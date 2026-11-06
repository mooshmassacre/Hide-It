import AppKit

guard CommandLine.arguments.count == 3,
      let logo = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fatalError("Não foi possível carregar o logo do Hide-It.")
}

// A área transparente ao redor do logo cria margens dentro do instalador.
let canvas = NSImage(size: NSSize(width: 176, height: 176), flipped: false) { _ in
    logo.draw(in: NSRect(x: 24, y: 24, width: 128, height: 128))
    return true
}
guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Não foi possível preparar a imagem do instalador.")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
