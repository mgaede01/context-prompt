#!/usr/bin/env bash
# Kubernetes provider: shows current context from kubeconfig (no kubectl call)

ctxp_provider_k8s() {
    local kubeconfig="${KUBECONFIG:-${HOME}/.kube/config}"
    [[ ! -f "$kubeconfig" ]] && return

    local ctx
    ctx=$(grep 'current-context:' "$kubeconfig" 2>/dev/null | awk '{print $2}' | head -1)
    [[ -z "$ctx" ]] && return

    local color="${CTXP_K8S_COLOR:-${__CTXP_BLUE:-}}"
    local reset="${__CTXP_RESET:-}"
    printf "%s<k8s:%s>%s" "$color" "$ctx" "$reset"
}

ctxp_register k8s
