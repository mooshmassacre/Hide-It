#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Build the current app before packaging it.
bash build.command

stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/hide-it-installer.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
mkdir -p "$stage_dir/root/Applications"
ditto "dist/Hide-It.app" "$stage_dir/root/Applications/Hide-It.app"

pkgbuild --analyze --root "$stage_dir/root" "$stage_dir/components.plist"
python3 - "$stage_dir/components.plist" <<'PY'
import plistlib
import sys

path = sys.argv[1]
with open(path, 'rb') as stream:
    components = plistlib.load(stream)
if len(components) != 1 or components[0].get('RootRelativeBundlePath') != 'Applications/Hide-It.app':
    raise SystemExit('Não foi possível identificar o aplicativo no pacote.')
component = components[0]
component['BundleIsRelocatable'] = False
component['BundleIsVersionChecked'] = False
component['BundleOverwriteAction'] = 'upgrade'
with open(path, 'wb') as stream:
    plistlib.dump(components, stream)
PY

pkgbuild --root "$stage_dir/root" \
    --component-plist "$stage_dir/components.plist" \
    --scripts Installer/scripts \
    --identifier com.mooshmassacre.hideit.installer \
    --version "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)" \
    --install-location / \
    "$stage_dir/Hide-It-component.pkg"

mkdir -p "$stage_dir/resources"
sips -z 128 128 Resources/HideIt-icon.png --out "$stage_dir/resources/HideIt-logo.png" >/dev/null
swift Installer/prepare-background.swift "$stage_dir/resources/HideIt-logo.png" "$stage_dir/resources/Background.png"
python3 - "$stage_dir/resources/HideIt-logo.png" "$stage_dir/resources/Welcome.rtf" <<'PY'
import pathlib
import sys

logo, output = map(pathlib.Path, sys.argv[1:])
def rtf(text):
    result = []
    for char in text:
        code = ord(char)
        if char in '\\{}':
            result.append('\\' + char)
        elif code > 127:
            result.append(f'\\u{code if code < 32768 else code - 65536}?')
        else:
            result.append(char)
    return ''.join(result)

image = logo.read_bytes().hex()
parts = [r'{\rtf1\ansi\deff0{\fonttbl{\f0\fswiss Helvetica;}}\viewkind4\uc1\pard\ql\f0\fs26 ',
         r'{\pict\pngblip\picw128\pich128\picwgoal1280\pichgoal1280 ' + image + '}',
         r'\par\b\fs38 ' + rtf('Bem-vindo ao Hide-It') + r'\b0\fs26\par\par ',
         rtf('O Hide-It ajuda você a organizar a barra de menus do seu Mac.\nEscolha os ícones que deseja ocultar e mostre-os novamente quando precisar.').replace('\n', r'\line '),
         r'\par\par ',
         rtf('Este instalador adicionará o Hide-It à sua pasta de Aplicativos.\nSe já houver uma versão instalada, ela será atualizada.').replace('\n', r'\line '),
         r'\par\par\b\fs30 ' + rtf('Licença e créditos') + r'\b0\fs26\par\par ',
         rtf('Hide-It é gratuito e de código aberto, distribuído sob a licença MIT.'),
         r'\par\par ' + rtf('Criado por ') + r'\b ' + rtf('Moosh Massacre') + r'\b0 .\par}']
output.write_text(''.join(parts), encoding='ascii')
PY
productbuild --synthesize --package "$stage_dir/Hide-It-component.pkg" "$stage_dir/Distribution.xml"
python3 - "$stage_dir/Distribution.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
tree = ET.parse(path)
root = tree.getroot()
ET.SubElement(root, 'title').text = 'Hide-It'
ET.SubElement(root, 'welcome', {'file': 'Welcome.rtf', 'mime-type': 'text/rtf'})
for appearance in ('background', 'background-darkAqua'):
    ET.SubElement(root, appearance, {
        'file': 'Background.png', 'mime-type': 'image/png',
        'alignment': 'bottomleft', 'scaling': 'none',
    })
ET.SubElement(root, 'domains', {
    'enable_anywhere': 'false', 'enable_currentUserHome': 'false',
    'enable_localSystem': 'true',
})
tree.write(path, encoding='utf-8', xml_declaration=True)
PY
productbuild --distribution "$stage_dir/Distribution.xml" \
    --resources "$stage_dir/resources" \
    --package-path "$stage_dir" \
    dist/Hide-It-Instalador.pkg

echo "Instalador criado: $PWD/dist/Hide-It-Instalador.pkg"
