#!/bin/bash
# Compila Secret Santa per Mac (app universale Intel + Apple Silicon), Windows (64 bit) e Linux (amd64, arm64).
# Uso: ./build.sh   → risultati in ../dist
# Per ridisegnare l'icona: ./build.sh --icone
set -euo pipefail
cd "$(dirname "$0")"

DIST="../dist"
APP="$DIST/mac/Secret Santa.app"

if [[ "${1:-}" == "--icone" || ! -f icona/SecretSanta.icns || ! -f rsrc_windows_amd64.syso ]]; then
  echo "→ Icone"
  (
    cd icona
    swift disegna.swift mac-1024.png 1024 0.098
    swift disegna.swift win-256.png 256 0.02
    for s in 48 32 16; do sips -z $s $s win-256.png --out win-$s.png >/dev/null; done
    rm -rf SecretSanta.iconset && mkdir SecretSanta.iconset
    for s in 16 32 128 256 512; do
      sips -z $s $s mac-1024.png --out SecretSanta.iconset/icon_${s}x${s}.png >/dev/null
      sips -z $((s * 2)) $((s * 2)) mac-1024.png --out SecretSanta.iconset/icon_${s}x${s}@2x.png >/dev/null
    done
    iconutil -c icns SecretSanta.iconset -o SecretSanta.icns
    rm -rf SecretSanta.iconset
    sips -z 64 64 mac-1024.png --out favicon-64.png >/dev/null
  )
  go run ./strumenti/winicon -o rsrc_windows_amd64.syso icona/win-16.png icona/win-32.png icona/win-48.png icona/win-256.png
fi

mkdir -p web
cp ../index.html web/index.html

# Cancello solo quello che crea la build: se qualcuno ha avviato l'app da dist/,
# accanto ci sono i dati della famiglia (secret-santa-dati*.json) e devono restare.
rm -rf "$APP" "$DIST/windows/SecretSanta.exe" \
  "$DIST/linux-amd64/Secret Santa/secret-santa" "$DIST/linux-arm64/Secret Santa/secret-santa" \
  "$DIST"/*.zip "$DIST"/*.tar.gz
if find "$DIST" -name 'secret-santa-dati*.json' 2>/dev/null | grep -q .; then
  echo "⚠️  In dist/ ci sono file di dati della famiglia: li lascio dove sono, ma è meglio tenere l'app altrove."
fi
mkdir -p "$DIST/windows" "$APP/Contents/MacOS" "$APP/Contents/Resources"

LDFLAGS="-s -w"
export CGO_ENABLED=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "→ Windows"
GOOS=windows GOARCH=amd64 go build -trimpath -ldflags "$LDFLAGS -H windowsgui" -o "$DIST/windows/SecretSanta.exe" .

echo "→ Linux"
for arch in amd64 arm64; do
  L="$DIST/linux-$arch/Secret Santa"
  mkdir -p "$L"
  GOOS=linux GOARCH=$arch go build -trimpath -ldflags "$LDFLAGS" -o "$L/secret-santa" .
  cp icona/win-256.png "$L/secret-santa.png"
  cp linux/installa.sh linux/LEGGIMI.txt "$L/"
  chmod +x "$L/secret-santa" "$L/installa.sh"
  # niente metadati macOS dentro l'archivio
  (cd "$DIST/linux-$arch" && COPYFILE_DISABLE=1 tar --no-mac-metadata --no-xattrs --no-acls --no-fflags --uid 0 --gid 0 -czf "../Secret Santa - Linux $arch.tar.gz" "Secret Santa")
done

echo "→ Mac: programma"
GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags "$LDFLAGS" -o "$TMP/server-arm64" .
GOOS=darwin GOARCH=amd64 go build -trimpath -ldflags "$LDFLAGS" -o "$TMP/server-amd64" .
lipo -create -output "$APP/Contents/MacOS/secret-santa-server" "$TMP/server-arm64" "$TMP/server-amd64"

echo "→ Mac: lanciatore"
swiftc -O -target arm64-apple-macos13 mac/Lanciatore.swift -o "$TMP/lanciatore-arm64"
swiftc -O -target x86_64-apple-macos13 mac/Lanciatore.swift -o "$TMP/lanciatore-x86_64"
lipo -create -output "$APP/Contents/MacOS/Secret Santa" "$TMP/lanciatore-arm64" "$TMP/lanciatore-x86_64"

cp icona/SecretSanta.icns "$APP/Contents/Resources/SecretSanta.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Secret Santa</string>
  <key>CFBundleDisplayName</key><string>Secret Santa</string>
  <key>CFBundleIdentifier</key><string>it.famiglia.secretsanta</string>
  <key>CFBundleExecutable</key><string>Secret Santa</string>
  <key>CFBundleIconFile</key><string>SecretSanta</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"
# fa rileggere l'icona al Finder se l'app era già stata vista
touch "$APP"

echo "→ Zip da condividere"
(cd "$DIST/mac" && ditto -c -k --keepParent "Secret Santa.app" "../Secret Santa - Mac.zip")
(cd "$DIST/windows" && zip -q -j "../Secret Santa - Windows.zip" SecretSanta.exe)

ls -lh "$DIST"
