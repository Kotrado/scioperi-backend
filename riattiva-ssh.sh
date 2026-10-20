#!/bin/bash
#
# Riattiva l'agente SSH con la chiave usata per GitHub, cosi' non devi
# ricordarti i singoli comandi ogni volta che apri un nuovo terminale.
#
# Uso:
#   ./riattiva-ssh.sh

set -e

CHIAVE="$HOME/.ssh/id_ed25519_nuova"

if [ ! -f "$CHIAVE" ]; then
    echo "Chiave non trovata in $CHIAVE"
    echo "Controlla il percorso, o rigenerala con: ssh-keygen -t ed25519 -C \"tua-email@example.com\""
    exit 1
fi

echo "Avvio ssh-agent..."
eval "$(ssh-agent -s)" > /dev/null

echo "Carico la chiave nel Keychain di macOS..."
ssh-add --apple-use-keychain "$CHIAVE"

echo ""
echo "Verifica connessione a GitHub..."
ssh -T git@github.com 2>&1 || true

echo ""
echo "Fatto. Puoi usare git push/pull normalmente adesso."
