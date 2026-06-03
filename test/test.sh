#!/usr/bin/env bash
# Smoke tests for context-prompt providers and ctxp CLI.
# Run directly: bash test/test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  PASS  $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL  $desc"
        echo "        expected: $(printf '%q' "$expected")"
        echo "        actual:   $(printf '%q' "$actual")"
        (( FAIL++ )) || true
    fi
}

check_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS  $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL  $desc"
        echo "        expected to contain: $(printf '%q' "$needle")"
        echo "        actual:              $(printf '%q' "$haystack")"
        (( FAIL++ )) || true
    fi
}

check_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "  PASS  $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL  $desc"
        echo "        expected NOT to contain: $(printf '%q' "$needle")"
        echo "        actual:                  $(printf '%q' "$haystack")"
        (( FAIL++ )) || true
    fi
}

# Load core (NO_COLOR for clean string comparisons)
NO_COLOR=1 source "${SCRIPT_DIR}/context-prompt.sh"

echo "--- AWS provider ---"
unset AWS_PROFILE
check "no output when AWS_PROFILE unset" "" "$(ctxp_provider_aws)"

AWS_PROFILE="company-west"
check "shows profile name" "<aws:company-west>" "$(ctxp_provider_aws)"

AWS_PROFILE="prod"
check "shows different profile" "<aws:prod>" "$(ctxp_provider_aws)"

echo ""
echo "--- K8s provider ---"
KUBECONFIG="/tmp/ctxp_test_kube_$$.yaml"
cat > "$KUBECONFIG" <<'EOF'
apiVersion: v1
kind: Config
current-context: prod-cluster
contexts:
- context: {}
  name: prod-cluster
EOF

check "shows current context" "<k8s:prod-cluster>" "$(ctxp_provider_k8s)"

KUBECONFIG="/tmp/ctxp_nonexistent_$$.yaml"
check "no output when kubeconfig missing" "" "$(ctxp_provider_k8s)"
rm -f "/tmp/ctxp_test_kube_$$.yaml"
unset KUBECONFIG

echo ""
echo "--- Git provider ---"
TMP_REPO="/tmp/ctxp_test_repo_$$"
mkdir "$TMP_REPO"
git -C "$TMP_REPO" init -q
git -C "$TMP_REPO" commit --allow-empty -m "init" -q

actual=$(cd "$TMP_REPO" && NO_COLOR=1 source "${SCRIPT_DIR}/context-prompt.sh" 2>/dev/null && ctxp_provider_git)
check_contains "shows branch name" "<git:" "$actual"

rm -rf "$TMP_REPO"

echo ""
echo "--- Venv provider ---"
unset VIRTUAL_ENV
check "no output when no venv" "" "$(ctxp_provider_venv)"

VIRTUAL_ENV="/home/user/.venv/myproject"
check "shows venv basename" "<venv:myproject>" "$(ctxp_provider_venv)"

echo ""
echo "--- ctxp disable ---"
unset AWS_PROFILE; AWS_PROFILE="test-profile"
check_contains "aws enabled before disable" "<aws:test-profile>" "$(NO_COLOR=1 __ctxp_build_prompt)"

ctxp disable aws > /dev/null
check_not_contains "aws gone after disable" "<aws:" "$(NO_COLOR=1 __ctxp_build_prompt)"
check_contains "aws shows disabled in list" "disabled" "$(ctxp list | grep aws)"

echo ""
echo "--- ctxp enable ---"
ctxp enable aws > /dev/null
check_contains "aws back after enable" "<aws:test-profile>" "$(NO_COLOR=1 __ctxp_build_prompt)"
check_contains "aws shows enabled in list" "enabled" "$(ctxp list | grep aws)"

echo ""
echo "--- ctxp list ---"
list_output="$(ctxp list)"
check_contains "list shows aws"  "aws"  "$list_output"
check_contains "list shows k8s"  "k8s"  "$list_output"
check_contains "list shows git"  "git"  "$list_output"
check_contains "list shows venv" "venv" "$list_output"

echo ""
echo "--- ctxp add ---"
ctxp add testctx '[ -n "${_TESTCTX:-}" ] && printf "<testctx:%s>" "$_TESTCTX"' > /dev/null
_TESTCTX="hello"
check "custom add provider renders" "<testctx:hello>" "$(ctxp_provider_testctx)"
check_contains "add shows in list" "testctx" "$(ctxp list)"
unset _TESTCTX

echo ""
echo "--- ctxp status ---"
unset AWS_PROFILE; AWS_PROFILE="status-test"
status_out="$(ctxp status)"
check_contains "status shows aws segment" "<aws:status-test>" "$status_out"

echo ""
echo "--- ctxp color ---"
ctxp color aws red > /dev/null
check_contains "color command sets CTXP_AWS_COLOR" $'\033[31m' "${CTXP_AWS_COLOR:-}"
check "color name tracked as red" "red" "$CTXP_AWS_COLOR_NAME"

ctxp color aws yellow > /dev/null
check "color name reset to yellow" "yellow" "$CTXP_AWS_COLOR_NAME"

ctxp color aws none > /dev/null
check "color name set to none" "none" "$CTXP_AWS_COLOR_NAME"
check "color none clears ANSI code" "" "${CTXP_AWS_COLOR:-}"

color_show="$(ctxp color aws)"
check_contains "color show reports current name" "none" "$color_show"

# Restore default
ctxp color aws yellow > /dev/null

color_err="$(ctxp color aws bogus 2>&1)" || true
check_contains "unknown color shows error" "unknown color" "$color_err"

echo ""
echo "--- ctxp order ---"
# Reset to known state
CTXP_PROVIDERS=(aws k8s git venv)

ctxp order venv git k8s aws > /dev/null
check "order: first provider" "venv" "${CTXP_PROVIDERS[0]}"
check "order: last provider"  "aws"  "${CTXP_PROVIDERS[3]}"

# Omitted provider gets appended with warning
ctxp disable venv > /dev/null
ctxp order k8s aws > /dev/null  # git is enabled but not listed
check "order: unlisted provider appended" "git" "${CTXP_PROVIDERS[2]}"
ctxp enable venv > /dev/null

# Disabled provider in order list is skipped (not re-enabled)
ctxp disable k8s > /dev/null
order_out="$(ctxp order aws k8s git venv)"
check_contains "order: skips disabled provider" "disabled" "$order_out"
if ! __ctxp_in_array "k8s" "${CTXP_PROVIDERS[@]}"; then
    echo "  PASS  order: disabled provider not re-enabled"
    (( PASS++ )) || true
else
    echo "  FAIL  order: disabled provider was incorrectly re-enabled"
    (( FAIL++ )) || true
fi
ctxp enable k8s > /dev/null

echo ""
echo "--- ctxp list with color column ---"
list_out="$(ctxp list)"
check_contains "list shows COLOR header" "COLOR" "$list_out"
check_contains "list shows yellow for aws" "yellow" "$list_out"

echo ""
echo "================================"
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
