#!/usr/bin/env bash
# Python venv provider: shows active virtualenv name from $VIRTUAL_ENV

ctxp_provider_venv() {
    [[ -z "${VIRTUAL_ENV:-}" ]] && return

    local color="${CTXP_VENV_COLOR:-${__CTXP_MAGENTA:-}}"
    local reset="${__CTXP_RESET:-}"
    printf "%s<venv: %s>%s" "$color" "$(basename "$VIRTUAL_ENV")" "$reset"
}

ctxp_register venv
