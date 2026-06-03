#!/usr/bin/env bash
# AWS provider: shows current $AWS_PROFILE

ctxp_provider_aws() {
    local profile="${AWS_PROFILE:-}"
    [[ -z "$profile" ]] && return

    local color="${CTXP_AWS_COLOR:-${__CTXP_YELLOW:-}}"
    local reset="${__CTXP_RESET:-}"
    printf "%s<aws:%s>%s" "$color" "$profile" "$reset"
}

ctxp_register aws
