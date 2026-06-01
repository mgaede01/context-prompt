#!/usr/bin/env bash
# Git provider: shows current branch (or short SHA when detached HEAD)

ctxp_provider_git() {
    local branch
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return

    if [[ "$branch" == "HEAD" ]]; then
        branch=$(git rev-parse --short HEAD 2>/dev/null) || return
    fi

    local color="${CTXP_GIT_COLOR:-${__CTXP_GREEN:-}}"
    local reset="${__CTXP_RESET:-}"
    printf "%s<git: %s>%s" "$color" "$branch" "$reset"
}

ctxp_register git
