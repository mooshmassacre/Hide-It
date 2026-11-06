import AppKit
import ApplicationServices
import Darwin
import Carbon

// Copyright (c) 2026 Moosh Massacre. MIT License.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controlWidth: CGFloat = 14
    private let dividerWidth: CGFloat = 8.5
    private let menuSymbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
    private var control: NSStatusItem!
    private var divider: NSStatusItem!
    private var timer: Timer?
    private var hidden = false
    private let preferences = UserDefaults.standard
    private var visibilityAssertion: NSObject?
    private var visibilityGeneration = 0
    private var isHiding = false
    private var recoveryHotKey: EventHotKeyRef?
    private var recoveryHandler: EventHandlerRef?
    private var modifierMonitor: Any?
    private var localModifierMonitor: Any?
    private var commandHoldTimer: Timer?
    private var commandHeld = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        preferences.register(defaults: ["autoHide": true])
        if let iconURL = Bundle.main.url(forResource: "HideIt", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        control = NSStatusBar.system.statusItem(withLength: controlWidth)
        control.autosaveName = "HideItControl"
        control.button?.target = self
        control.button?.action = #selector(clicked)
        control.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        divider = NSStatusBar.system.statusItem(withLength: dividerWidth)
        divider.autosaveName = "HideItDivider"
        updateDividerAppearance(visible: true)
        divider.button?.toolTip = "Segure Command e arraste os ícones que deseja ocultar para a esquerda deste divisor."
        divider.button?.target = self
        divider.button?.action = #selector(showInstructions)
        updateAppearance()
        installRecoveryShortcut()
        modifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            DispatchQueue.main.async { self?.commandChanged(event.modifierFlags.contains(.command)) }
        }
        localModifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.commandChanged(event.modifierFlags.contains(.command))
            return event
        }
        if !AXIsProcessTrusted() { showAccessibilityNotice() }
        if !preferences.bool(forKey: "instructionsShown") {
            showInstructions()
            preferences.set(true, forKey: "instructionsShown")
        }
        scheduleAutoHide()
    }

    private func commandChanged(_ pressed: Bool) {
        guard pressed != commandHeld else { return }
        commandHeld = pressed
        commandHoldTimer?.invalidate()
        commandHoldTimer = nil
        guard pressed else { return }
        let holdTimer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            guard let self = self, self.commandHeld else { return }
            self.setHidden(!self.hidden)
        }
        commandHoldTimer = holdTimer
        RunLoop.main.add(holdTimer, forMode: .common)
    }

    private func scheduleAutoHide() {
        timer?.invalidate()
        timer = nil
        guard preferences.bool(forKey: "autoHide") else { return }
        if #available(macOS 27, *), !AXIsProcessTrusted() { return }
        let hideTimer = Timer(timeInterval: 10, repeats: false) { [weak self] _ in
            guard let self = self, !self.hidden else { return }
            self.setHidden(true)
        }
        timer = hideTimer
        RunLoop.main.add(hideTimer, forMode: .common)
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            openMenu()
        } else {
            setHidden(!hidden)
        }
    }

    private func setHidden(_ value: Bool) {
        timer?.invalidate()
        timer = nil
        if #available(macOS 27, *) {
            if value { hideWithNativeVisibility() } else { showWithNativeVisibility() }
            return
        }
        hidden = value
        let totalWidth = NSScreen.screens.reduce(CGFloat(0)) { $0 + $1.frame.width }
        divider.length = value ? max(10000, totalWidth * 2) : dividerWidth
        updateDividerAppearance(visible: !value)
        updateAppearance()
        if !value { scheduleAutoHide() }
    }

    private func showAccessibilityNotice() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Permissão de Acessibilidade necessária"
        alert.informativeText = "O Hide-It precisa de acesso à Acessibilidade para identificar os ícones à esquerda do divisor. Ative o Hide-It em Ajustes do Sistema para usar a ocultação no macOS 27."
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Agora não")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func hideWithNativeVisibility() {
        guard !hidden, !isHiding else { return }
        let applicationFolder = Bundle.main.bundleURL.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath()
        let expectedFolder = URL(fileURLWithPath: "/Applications").standardizedFileURL.resolvingSymlinksInPath()
        guard applicationFolder == expectedFolder else {
            message("Mova o Hide-It para Aplicativos", "Para manter a seta acessível no macOS 27, feche este exemplar, mova o Hide-It para a pasta Aplicativos e abra-o de lá.")
            return
        }
        guard recoveryHotKey != nil else {
            message("Atalho de recuperação indisponível", "Não foi possível registrar ⌃⌥⌘H. Libere esse atalho e abra o Hide-It novamente antes de ocultar os ícones.")
            return
        }
        guard AXIsProcessTrusted() else {
            showAccessibilityNotice()
            return
        }
        guard let boundary = divider.button?.window?.frame, boundary.width > 0,
              dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW | RTLD_LOCAL) != nil,
              let configClass = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
              let assertionClass = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type else {
            message("Não foi possível ocultar os ícones", "O macOS não disponibilizou os recursos necessários ou a posição do divisor. Tente novamente.")
            return
        }
        visibilityGeneration += 1
        let generation = visibilityGeneration
        isHiding = true
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.pathExtension == "app" && $0.bundleIdentifier != nil }
            .map { (pid: $0.processIdentifier, id: $0.bundleIdentifier!) }
        let own = Bundle.main.bundleIdentifier ?? ""
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var left = Set<String>()
            var right = Set<String>()
            for app in apps where app.id != own {
                let element = AXUIElementCreateApplication(app.pid)
                AXUIElementSetMessagingTimeout(element, 0.1)
                var bar: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &bar) == .success,
                      let bar = bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
                var children: CFTypeRef?
                guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
                      let elements = children as? [AXUIElement] else { continue }
                for item in elements {
                    var pos: CFTypeRef?
                    var size: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &pos) == .success,
                          AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size) == .success,
                          let pos = pos, let size = size,
                          CFGetTypeID(pos) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { continue }
                    var point = CGPoint.zero
                    var dimensions = CGSize.zero
                    guard AXValueGetValue(pos as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions), dimensions.width > 0 else { continue }
                    if point.x + dimensions.width / 2 < boundary.midX { left.insert(app.id) } else { right.insert(app.id) }
                }
            }
            let hiddenApps = left.subtracting(right)
            let allowed = Set(apps.map(\.id)).subtracting(hiddenApps).union([own]).sorted()
            DispatchQueue.main.async {
                guard let self = self, generation == self.visibilityGeneration else { return }
                guard !hiddenApps.isEmpty else {
                    self.isHiding = false
                    self.message("Nenhum ícone encontrado", "Arraste um ícone de aplicativo para a esquerda do divisor e tente novamente.")
                    return
                }
                let initSelector = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
                let activateSelector = NSSelectorFromString("activateWithConfiguration:completionHandler:")
                guard configClass.instancesRespond(to: initSelector), assertionClass.instancesRespond(to: activateSelector), assertionClass.instancesRespond(to: NSSelectorFromString("invalidate")),
                      let allocated = (configClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
                      let config = allocated.perform(initSelector, with: (0..<64).map { NSNumber(value: $0) } as NSArray, with: allowed as NSArray)?.takeUnretainedValue() else {
                    self.isHiding = false
                    self.message("Não foi possível ocultar os ícones", "O recurso de visibilidade do macOS está indisponível nesta versão.")
                    return
                }
                let assertion = assertionClass.init()
                let completion: @convention(block) (NSError?) -> Void = { [weak self] error in
                    DispatchQueue.main.async {
                        guard let self = self else { _ = assertion.perform(NSSelectorFromString("invalidate")); return }
                        guard generation == self.visibilityGeneration else { _ = assertion.perform(NSSelectorFromString("invalidate")); return }
                        self.isHiding = false
                        if let error = error {
                            _ = assertion.perform(NSSelectorFromString("invalidate"))
                            self.message("Não foi possível ocultar os ícones", error.localizedDescription)
                        } else {
                            self.visibilityAssertion = assertion
                            self.hidden = true
                            self.divider.isVisible = false
                            self.updateAppearance()
                        }
                    }
                }
                _ = assertion.perform(activateSelector, with: config, with: completion)
            }
        }
    }

    private func showWithNativeVisibility() {
        visibilityGeneration += 1
        isHiding = false
        _ = visibilityAssertion?.perform(NSSelectorFromString("invalidate"))
        visibilityAssertion = nil
        divider.isVisible = true
        hidden = false
        updateAppearance()
        scheduleAutoHide()
    }

    private func installRecoveryShortcut() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let handler: EventHandlerUPP = { _, event, context in
            guard let event = event, let context = context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == OSType(0x48494445), identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            if app.hidden { app.setHidden(false) }
            return noErr
        }
        guard InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, context, &recoveryHandler) == noErr else { return }
        let id = EventHotKeyID(signature: OSType(0x48494445), id: 1)
        if RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &recoveryHotKey) != noErr {
            if let recoveryHandler = recoveryHandler { RemoveEventHandler(recoveryHandler) }
            recoveryHandler = nil
        }
    }

    private func updateAppearance() {
        control.button?.image = NSImage(systemSymbolName: hidden ? "chevron.left" : "chevron.right", accessibilityDescription: hidden ? "Mostrar ícones" : "Ocultar ícones")?.withSymbolConfiguration(menuSymbolConfiguration)
        control.button?.toolTip = "Hide-It · Clique para \(hidden ? "mostrar" : "ocultar"). Clique direito para opções."
    }

    private func updateDividerAppearance(visible: Bool) {
        let image = NSImage(size: NSSize(width: 13, height: 13), flipped: false) { _ in
            NSColor.black.setStroke()
            let line = NSBezierPath()
            line.lineWidth = 1.5
            line.lineCapStyle = .round
            line.move(to: NSPoint(x: 6.5, y: 2))
            line.line(to: NSPoint(x: 6.5, y: 11))
            line.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Divisor de ícones"
        divider.button?.image = visible ? image : nil
        divider.button?.title = ""
    }

    private func openMenu() {
        let menu = NSMenu()
        let auto = menu.addItem(withTitle: "Recolher após 10s", action: #selector(toggleAutoHide), keyEquivalent: "")
        auto.state = preferences.bool(forKey: "autoHide") ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Como usar…", action: #selector(showInstructions), keyEquivalent: "")
        menu.addItem(withTitle: "Sobre", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Fechar", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        control.menu = menu
        control.button?.performClick(nil)
        control.menu = nil
    }

    @objc private func toggleAutoHide() {
        preferences.set(!preferences.bool(forKey: "autoHide"), forKey: "autoHide")
        if hidden {
            timer?.invalidate()
            timer = nil
        } else {
            scheduleAutoHide()
        }
    }
    @objc private func showInstructions() {
        setHidden(false)
        // Keep icons visible while the user reads and arranges them.
        timer?.invalidate()
        timer = nil
        message("Como usar o Hide-It", "Segure ⌘ e arraste os ícones que deseja ocultar para a esquerda do divisor │.\n\nClique na seta para alternar a visibilidade.\n\nAo segurar ⌘ por 3s, a visibilidade é alternada.")
        scheduleAutoHide()
    }
    @objc private func showAbout() {
        message("Hide-It 1.0", "Por Moosh Massacre\n\nOrganize a barra de menus do seu Mac.\nGratuito e de código aberto · Licença MIT\n\nCopyright © 2026 Moosh Massacre")
    }
    private func message(_ title: String, _ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    @objc private func quit() {
        setHidden(false)
        NSApp.terminate(nil)
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        commandHoldTimer?.invalidate()
        if let recoveryHotKey = recoveryHotKey { UnregisterEventHotKey(recoveryHotKey) }
        if let recoveryHandler = recoveryHandler { RemoveEventHandler(recoveryHandler) }
        if let modifierMonitor = modifierMonitor { NSEvent.removeMonitor(modifierMonitor) }
        if let localModifierMonitor = localModifierMonitor { NSEvent.removeMonitor(localModifierMonitor) }
        _ = visibilityAssertion?.perform(NSSelectorFromString("invalidate"))
        if divider != nil { NSStatusBar.system.removeStatusItem(divider) }
        if control != nil { NSStatusBar.system.removeStatusItem(control) }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
