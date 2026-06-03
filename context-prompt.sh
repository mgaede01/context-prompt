#!/usr/bin/env bash
# context-prompt: right-side shell context display for bash and zsh
# Source this file from ~/.bashrc or ~/.zshrc

# Locate this script's directory regardless of how it was sourced
if [[ -n "${ZSH_VERSION:-}" ]]; then
    CTXP_DIR="${${(%):-%x}:h}"
elif [[ -n "${BASH_VERSION:-}" ]]; then
    CTXP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    return 0
fi

# Color constants — cleared if NO_COLOR is set
if [[ -z "${NO_COLOR:-}" ]]; then
    __CTXP_YELLOW=$'\033[33m'
    __CTXP_BLUE=$'\033[34m'
    __CTXP_GREEN=$'\033[32m'
    __CTXP_MAGENTA=$'\033[35m'
    __CTXP_RESET=$'\033[0m'
else
    __CTXP_YELLOW=""
    __CTXP_BLUE=""
    __CTXP_GREEN=""
    __CTXP_MAGENTA=""
    __CTXP_RESET=""
fi

# Default color names for built-in providers (updated by ctxp color)
CTXP_AWS_COLOR_NAME="yellow"
CTXP_K8S_COLOR_NAME="blue"
CTXP_GIT_COLOR_NAME="green"
CTXP_VENV_COLOR_NAME="magenta"

# Active providers (rendered in prompt) — shrinks/grows via enable/disable/order
CTXP_PROVIDERS=()
# All known providers (sourced at any point) — never shrinks; used by list/enable
CTXP_KNOWN_PROVIDERS=()

# Called by provider files to self-register into both arrays.
# Optional second arg: command string to eval as the function body (one-liner shorthand).
ctxp_register() {
    local name="${1:-}"
    [[ -z "$name" ]] && return
    if [[ -n "${2:-}" ]]; then
        eval "ctxp_provider_${name}() { ${2}; }"
    fi
    CTXP_PROVIDERS+=("$name")
    CTXP_KNOWN_PROVIDERS+=("$name")
}

# --- Internal CLI helpers ---

__ctxp_in_array() {
    local target="$1"; shift
    local item
    for item in "$@"; do
        [[ "$item" == "$target" ]] && return 0
    done
    return 1
}

# Maps a friendly color name to its ANSI escape code.
# Prints the code; prints nothing for "none".
__ctxp_color_code() {
    case "$1" in
        red)           printf '%s' $'\033[31m' ;;
        green)         printf '%s' $'\033[32m' ;;
        yellow)        printf '%s' $'\033[33m' ;;
        blue)          printf '%s' $'\033[34m' ;;
        magenta)       printf '%s' $'\033[35m' ;;
        cyan)          printf '%s' $'\033[36m' ;;
        white)         printf '%s' $'\033[37m' ;;
        gray|grey)     printf '%s' $'\033[90m' ;;
        orange)        printf '%s' $'\033[38;5;208m' ;;
        brightred)     printf '%s' $'\033[91m' ;;
        brightgreen)   printf '%s' $'\033[92m' ;;
        brightyellow)  printf '%s' $'\033[93m' ;;
        brightblue)    printf '%s' $'\033[94m' ;;
        brightmagenta) printf '%s' $'\033[95m' ;;
        brightcyan)    printf '%s' $'\033[96m' ;;
        brightwhite)   printf '%s' $'\033[97m' ;;
        none)          printf '' ;;
        *)             return 1 ;;
    esac
}

__ctxp_enable() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        echo "Usage: ctxp enable <provider>" >&2; return 1
    fi
    if __ctxp_in_array "$name" "${CTXP_PROVIDERS[@]+"${CTXP_PROVIDERS[@]}"}"; then
        echo "ctxp: '$name' is already enabled"
        return 0
    fi
    if __ctxp_in_array "$name" "${CTXP_KNOWN_PROVIDERS[@]+"${CTXP_KNOWN_PROVIDERS[@]}"}"; then
        CTXP_PROVIDERS+=("$name")
        echo "ctxp: enabled '$name'"
        return 0
    fi
    local provider_file="${CTXP_DIR}/providers/${name}.sh"
    if [[ -f "$provider_file" ]]; then
        # shellcheck source=/dev/null
        source "$provider_file"
        echo "ctxp: enabled '$name'"
    else
        echo "ctxp: unknown provider '$name' (no file at ${provider_file})" >&2
        return 1
    fi
}

__ctxp_disable() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        echo "Usage: ctxp disable <provider>" >&2; return 1
    fi
    if ! __ctxp_in_array "$name" "${CTXP_PROVIDERS[@]+"${CTXP_PROVIDERS[@]}"}"; then
        echo "ctxp: '$name' is not currently enabled"
        return 0
    fi
    local new_providers=() p
    for p in "${CTXP_PROVIDERS[@]}"; do
        [[ "$p" != "$name" ]] && new_providers+=("$p")
    done
    CTXP_PROVIDERS=("${new_providers[@]+"${new_providers[@]}"}")
    echo "ctxp: disabled '$name'"
}

# Sets the display order of active providers.
# Enabled providers not listed are appended at the end with a warning.
# Disabled providers in the list are skipped with a notice.
__ctxp_order() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: ctxp order <provider> [provider ...]" >&2
        echo "       Specify the left-to-right display order of active providers." >&2
        return 1
    fi

    local new_order=() skipped=() name
    for name in "$@"; do
        if __ctxp_in_array "$name" "${CTXP_PROVIDERS[@]+"${CTXP_PROVIDERS[@]}"}"; then
            new_order+=("$name")
        elif __ctxp_in_array "$name" "${CTXP_KNOWN_PROVIDERS[@]+"${CTXP_KNOWN_PROVIDERS[@]}"}"; then
            echo "ctxp: '$name' is disabled — skipping (enable it first with: ctxp enable $name)"
        else
            echo "ctxp: unknown provider '$name' — skipping" >&2
        fi
    done

    # Append any enabled providers that weren't mentioned
    local p
    for p in "${CTXP_PROVIDERS[@]+"${CTXP_PROVIDERS[@]}"}"; do
        if ! __ctxp_in_array "$p" "${new_order[@]+"${new_order[@]}"}"; then
            new_order+=("$p")
            skipped+=("$p")
        fi
    done

    CTXP_PROVIDERS=("${new_order[@]+"${new_order[@]}"}")

    if [[ ${#skipped[@]} -gt 0 ]]; then
        echo "ctxp: order updated (note: ${skipped[*]} not listed — appended at end)"
    else
        echo "ctxp: order updated"
    fi
}

# Sets or shows the color for a provider.
__ctxp_set_color() {
    local name="${1:-}" color_name="${2:-}"
    if [[ -z "$name" ]]; then
        echo "Usage: ctxp color <provider> [color]" >&2
        echo "       Colors: red green yellow blue magenta cyan white none" >&2
        return 1
    fi

    local upper
    upper=$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')

    # No color arg — show current color for this provider
    if [[ -z "$color_name" ]]; then
        local name_var="CTXP_${upper}_COLOR_NAME"
        local current_name
        if [[ -n "${BASH_VERSION:-}" ]]; then
            current_name="${!name_var:-none}"
        elif [[ -n "${ZSH_VERSION:-}" ]]; then
            current_name="${(P)name_var:-none}"
        fi
        echo "ctxp: $name color is '$current_name'"
        return 0
    fi

    # Validate and resolve the color
    local code
    if ! code="$(__ctxp_color_code "$color_name")"; then
        echo "ctxp: unknown color '$color_name'" >&2
        echo "      Available: red green yellow blue magenta cyan white none" >&2
        return 1
    fi

    # Set CTXP_<NAME>_COLOR and CTXP_<NAME>_COLOR_NAME
    local color_var="CTXP_${upper}_COLOR"
    local name_var="CTXP_${upper}_COLOR_NAME"
    printf -v "$color_var" '%s' "$code"
    printf -v "$name_var" '%s' "$color_name"

    echo "ctxp: set $name color to '$color_name'"
}

__ctxp_list() {
    # Show enabled providers in prompt order, then disabled ones
    printf "%-12s %-10s %s\n" "PROVIDER" "STATUS" "COLOR"

    local p upper name_var color_name
    for p in "${CTXP_PROVIDERS[@]+"${CTXP_PROVIDERS[@]}"}"; do
        [[ -z "$p" ]] && continue
        upper=$(printf '%s' "$p" | tr '[:lower:]' '[:upper:]')
        name_var="CTXP_${upper}_COLOR_NAME"
        if [[ -n "${BASH_VERSION:-}" ]]; then
            color_name="${!name_var:-—}"
        elif [[ -n "${ZSH_VERSION:-}" ]]; then
            color_name="${(P)name_var:-—}"
        fi
        printf "%-12s %-10s %s\n" "$p" "enabled" "$color_name"
    done

    for p in "${CTXP_KNOWN_PROVIDERS[@]+"${CTXP_KNOWN_PROVIDERS[@]}"}"; do
        [[ -z "$p" ]] && continue
        __ctxp_in_array "$p" "${CTXP_PROVIDERS[@]+"${CTXP_PROVIDERS[@]}"}" && continue
        upper=$(printf '%s' "$p" | tr '[:lower:]' '[:upper:]')
        name_var="CTXP_${upper}_COLOR_NAME"
        if [[ -n "${BASH_VERSION:-}" ]]; then
            color_name="${!name_var:-—}"
        elif [[ -n "${ZSH_VERSION:-}" ]]; then
            color_name="${(P)name_var:-—}"
        fi
        printf "%-12s %-10s %s\n" "$p" "disabled" "$color_name"
    done
}

__ctxp_add() {
    local name="${1:-}" cmd="${2:-}"
    if [[ -z "$name" || -z "$cmd" ]]; then
        echo "Usage: ctxp add <name> '<command>'" >&2; return 1
    fi
    eval "ctxp_provider_${name}() { ${cmd}; }"
    CTXP_PROVIDERS+=("$name")
    CTXP_KNOWN_PROVIDERS+=("$name")
    echo "ctxp: added provider '$name'"
}

__ctxp_help() {
    cat <<'EOF'
ctxp — context-prompt CLI

  ctxp enable  <provider>           re-enable a disabled provider
  ctxp disable <provider>           hide a provider from the prompt
  ctxp order   <provider> ...       set the left-to-right display order
  ctxp color   <provider> [color]   show or set a provider's color
  ctxp list                         show all providers, status, and color
  ctxp status                       print what the right prompt currently shows
  ctxp add     <name> '<cmd>'       register a custom one-liner provider
  ctxp help                         show this message

Colors: red  green  yellow  blue  magenta  cyan  white  gray  orange  none
        bright variants: brightred  brightgreen  brightyellow  brightblue
                         brightmagenta  brightcyan  brightwhite

Examples:
  ctxp disable k8s
  ctxp enable  k8s
  ctxp order   k8s aws git venv
  ctxp color   aws red
  ctxp color   k8s
  ctxp add myapp '[ -n "$MYAPP_ENV" ] && printf "<myapp:%s>" "$MYAPP_ENV"'
EOF
}

# --- User-facing CLI ---

ctxp() {
    local cmd="${1:-help}"
    case "$cmd" in
        enable)  __ctxp_enable    "${2:-}" ;;
        disable) __ctxp_disable   "${2:-}" ;;
        order)   shift; __ctxp_order "$@" ;;
        color)   __ctxp_set_color "${2:-}" "${3:-}" ;;
        list)    __ctxp_list ;;
        status)  NO_COLOR=1 __ctxp_build_prompt; echo ;;
        add)     __ctxp_add       "${2:-}" "${3:-}" ;;
        help|*)  __ctxp_help ;;
    esac
}

# --- Prompt rendering ---

__ctxp_build_prompt() {
    local output="" segment p
    for p in "${CTXP_PROVIDERS[@]+"${CTXP_PROVIDERS[@]}"}"; do
        segment=$(ctxp_provider_${p} 2>/dev/null) || continue
        [[ -n "$segment" ]] && output="${output}${segment}"
    done
    printf "%s" "$output"
}

__ctxp_visible_len() {
    local esc=$'\033'
    local stripped
    # Command substitution strips any trailing newline that BSD sed adds,
    # so ${#stripped} is an accurate visible width (unlike `wc -m`, which
    # would count sed's extra trailing newline on macOS).
    stripped=$(printf "%s" "$1" | sed "s/${esc}\[[0-9;]*m//g")
    printf "%s" "${#stripped}"
}

# Bash: render right prompt via cursor positioning.
__ctxp_bash_prompt() {
    local right
    right="$(__ctxp_build_prompt)"
    [[ -z "$right" ]] && return

    local visible_len cols
    visible_len="$(__ctxp_visible_len "$right")"
    cols="$(tput cols 2>/dev/null)" || cols=80

    # Reserve the final column. Printing into the last column triggers the
    # terminal's auto-wrap on the next character on many terminals, which
    # pushes the right prompt down/over the left PS1 and causes overlap.
    local usable=$(( cols - 1 ))
    [[ $usable -lt 0 ]] && usable=0

    local offset=$(( usable - visible_len ))
    [[ $offset -lt 0 ]] && offset=0

    tput sc
    # `tput cuf 0` is a no-op at best and prints stray output on some
    # terminals, so only move the cursor when there's a real offset.
    [[ $offset -gt 0 ]] && tput cuf "$offset" 2>/dev/null
    printf "%s" "$right"
    tput rc
}

# Zsh: set RPROMPT before each prompt.
__ctxp_precmd() {
    RPROMPT="$(__ctxp_build_prompt)"
}

# --- Shell hooks ---

if [[ -n "${ZSH_VERSION:-}" ]]; then
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd __ctxp_precmd
    # zsh reserves one blank column to the right of RPROMPT by default
    # (ZLE_RPROMPT_INDENT defaults to 1). Reclaim it so the context segments
    # sit flush against the terminal's right edge.
    ZLE_RPROMPT_INDENT=0
elif [[ -n "${BASH_VERSION:-}" ]]; then
    if [[ -z "${PROMPT_COMMAND:-}" ]]; then
        PROMPT_COMMAND="__ctxp_bash_prompt"
    else
        PROMPT_COMMAND="__ctxp_bash_prompt; ${PROMPT_COMMAND}"
    fi
fi

# --- Source built-in providers ---

for __ctxp_p in aws k8s git venv; do
    # shellcheck source=/dev/null
    [[ -f "${CTXP_DIR}/providers/${__ctxp_p}.sh" ]] && source "${CTXP_DIR}/providers/${__ctxp_p}.sh"
done
unset __ctxp_p
