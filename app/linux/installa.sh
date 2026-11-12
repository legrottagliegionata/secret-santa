#!/bin/sh
# Aggiunge Secret Santa al menu delle applicazioni (solo per l'utente corrente).
# Lancialo una volta dalla cartella in cui hai messo l'app: i dati verranno salvati qui accanto.
# Per toglierlo dal menu: ./installa.sh --rimuovi
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DESKTOP="$APPS/secret-santa.desktop"

if [ "${1:-}" = "--rimuovi" ]; then
  rm -f "$DESKTOP"
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" || true
  echo "Secret Santa rimosso dal menu. I file in $DIR non sono stati toccati."
  exit 0
fi

chmod +x "$DIR/secret-santa"
mkdir -p "$APPS"
# i percorsi vanno tra virgolette perché possono contenere spazi
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Secret Santa
Comment=Secret Santa di famiglia: sorteggio dei regali di Natale
Exec="$DIR/secret-santa"
Icon=$DIR/secret-santa.png
Terminal=false
Categories=Utility;
StartupNotify=false
EOF
chmod +x "$DESKTOP"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" || true

echo "Fatto: trovi Secret Santa nel menu delle applicazioni."
echo "I dati verranno salvati in: $DIR/secret-santa-dati.json"
echo "Se sposti questa cartella, rilancia ./installa.sh."
