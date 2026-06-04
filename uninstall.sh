#!/usr/bin/env bash
# Removes context-prompt from ~/.context-prompt/ and cleans up rc files.

set -e

INSTALL_DIR="${HOME}/.context-prompt"

echo "Uninstalling context-prompt..."

# Remove installed files
if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    echo "  Removed ${INSTALL_DIR}"
else
    echo "  ${INSTALL_DIR} not found — skipping"
fi

# Remove persisted configuration (XDG config dir)
CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/context-prompt"
if [[ -d "$CONFIG_DIR" ]]; then
    rm -rf "$CONFIG_DIR"
    echo "  Removed ${CONFIG_DIR}"
fi

# Remove source lines from all common rc files
remove_from_rc() {
    local rc_file="$1"
    [[ ! -f "$rc_file" ]] && return
    if grep -qF "context-prompt" "$rc_file" 2>/dev/null; then
        local tmpfile
        tmpfile=$(mktemp)
        grep -v "^# context-prompt$" "$rc_file" \
            | grep -v "^source \".*context-prompt" \
            > "$tmpfile"
        mv "$tmpfile" "$rc_file"
        echo "  Cleaned ${rc_file}"
    fi
}

remove_from_rc "${HOME}/.bashrc"
remove_from_rc "${HOME}/.zshrc"
remove_from_rc "${ZDOTDIR:-$HOME}/.zshrc"
remove_from_rc "${HOME}/.profile"

echo ""
echo "Done. Reload your shell to finish:"
echo "  exec \$SHELL"
