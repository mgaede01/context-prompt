#!/usr/bin/env bash
# Installs context-prompt to ~/.context-prompt/ and adds source line to shell rc file.

set -e

INSTALL_DIR="${HOME}/.context-prompt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing context-prompt..."

# Copy files
mkdir -p "${INSTALL_DIR}/providers"
cp "${SCRIPT_DIR}/context-prompt.sh" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/providers/"*.sh "${INSTALL_DIR}/providers/"

echo "  Copied files to ${INSTALL_DIR}"

# Detect rc file
detect_rc() {
    local shell_name
    shell_name="$(basename "${SHELL:-bash}")"
    case "$shell_name" in
        zsh)  echo "${ZDOTDIR:-$HOME}/.zshrc" ;;
        bash) echo "${HOME}/.bashrc" ;;
        *)    echo "${HOME}/.profile" ;;
    esac
}

RC_FILE="$(detect_rc)"
SOURCE_LINE="source \"${INSTALL_DIR}/context-prompt.sh\""

# Add source line idempotently
if grep -qF "$SOURCE_LINE" "$RC_FILE" 2>/dev/null; then
    echo "  ${RC_FILE} already configured, skipping"
else
    printf '\n# context-prompt\n%s\n' "$SOURCE_LINE" >> "$RC_FILE"
    echo "  Added source line to ${RC_FILE}"
fi

echo ""
echo "Done. Open a new terminal or run:"
echo "  source ${RC_FILE}"
echo ""
echo "Quick reference:"
echo "  ctxp list                 # show all providers and their status"
echo "  ctxp disable git          # hide git provider"
echo "  ctxp disable k8s          # hide k8s provider"
echo "  ctxp color aws red        # change a provider's color"
echo "  ctxp order k8s aws git    # set display order"
echo ""
echo "To uninstall:"
echo "  bash $(dirname "$0")/uninstall.sh"
