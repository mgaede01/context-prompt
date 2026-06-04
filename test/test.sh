#!/usr/bin/env bash
# Smoke tests for context-prompt providers and ctxp CLI.
# Runs under both shells:  bash test/test.sh   OR   zsh test/test.sh
# (Run it under zsh to exercise the zsh-only RPROMPT / persistence paths.)

set -euo pipefail

# Locate the repo root. The test is executed (not sourced), so $0 is the
# script path under both bash and zsh — no shell-specific detection needed.
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

# Space-joined list of enabled providers in order — works in bash and zsh
# (avoids shell-specific numeric array indexing).
enabled_order() { printf '%s' "${CTXP_PROVIDERS[*]}"; }

# Isolate persisted config so tests never touch the real ~/.config and each
# run starts from a clean slate.
export XDG_CONFIG_HOME="$(mktemp -d)"
trap 'rm -rf "$XDG_CONFIG_HOME"' EXIT

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
echo "--- ctxp color list ---"
color_list="$(ctxp color list)"
check_contains "color list shows header"        "Available colors" "$color_list"
check_contains "color list shows a standard color" "magenta"        "$color_list"
check_contains "color list shows a bright color"   "brightcyan"     "$color_list"
check_contains "color list shows none"             "none"           "$color_list"
# NO_COLOR output must contain no ANSI escapes
nc_list="$(NO_COLOR=1 ctxp color list)"
check_not_contains "color list honors NO_COLOR" $'\033' "$nc_list"

echo ""
echo "--- ctxp order ---"
# Reset to known state
CTXP_PROVIDERS=(aws k8s git venv)

ctxp order venv git k8s aws > /dev/null
check "order: full sequence applied" "venv git k8s aws" "$(enabled_order)"

# Omitted provider gets appended with warning
ctxp disable venv > /dev/null
ctxp order k8s aws > /dev/null  # git is enabled but not listed
check "order: unlisted provider appended at end" "k8s aws git" "$(enabled_order)"
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
echo "--- zsh RPROMPT escape wrapping ---"
# __ctxp_precmd wraps ANSI escapes in %{...%} so zsh counts them as
# zero-width. Hardcode the escapes in the provider (the suite runs with
# NO_COLOR=1, which blanks the shared color constants).
esc=$'\033'
ctxp add wraptest "printf '${esc}[31m<wraptest:%s>${esc}[0m' z" > /dev/null
__ctxp_precmd
check_contains "RPROMPT wraps opening escape in %{...%}" "%{${esc}[31m%}" "$RPROMPT"
check_contains "RPROMPT wraps reset escape in %{...%}"   "%{${esc}[0m%}"  "$RPROMPT"
check_contains "RPROMPT keeps visible text unwrapped"    "<wraptest:z>"   "$RPROMPT"
ctxp disable wraptest > /dev/null

echo ""
echo "--- __ctxp_visible_len (ANSI-stripped width) ---"
# Directly guards the macOS off-by-one (BSD sed's trailing newline inflating
# the count): the visible width must exclude ANSI escape sequences.
check "visible_len of plain text"        "5"  "$(__ctxp_visible_len "hello")"
check "visible_len ignores color codes"  "5"  "$(__ctxp_visible_len "${esc}[31mhello${esc}[0m")"
check "visible_len of a colored segment" "10" "$(__ctxp_visible_len "${esc}[33m<aws:prod>${esc}[0m")"

echo ""
echo "--- __ctxp_bash_prompt (right-prompt rendering) ---"
# TERM is forced so tput has a valid terminfo entry in a non-interactive run.
bp_empty="$(CTXP_PROVIDERS=(); TERM=xterm __ctxp_bash_prompt)"
check "bash prompt is empty when no segments" "" "$bp_empty"
bp_out="$(ctxp add bptest "printf '<bptest:%s>' y" >/dev/null 2>&1; TERM=xterm __ctxp_bash_prompt)"
check_contains "bash prompt renders the active segment" "<bptest:y>" "$bp_out"

echo ""
echo "--- ctxp help ---"
help_out="$(ctxp help)"
check_contains "help shows the CLI title"   "context-prompt CLI" "$help_out"
check_contains "help lists the enable verb" "ctxp enable"        "$help_out"
check_contains "help notes persistence"     "saved automatically" "$help_out"

echo ""
echo "--- zsh-specific behavior ---"
if [ -n "${ZSH_VERSION:-}" ]; then
    check "zsh reclaims the RPROMPT indent" "0" "${ZLE_RPROMPT_INDENT:-unset}"
    ctxp add zt "printf '<zt:%s>' q" > /dev/null
    __ctxp_precmd
    check_contains "zsh precmd populates RPROMPT" "<zt:q>" "$RPROMPT"
    ctxp disable zt > /dev/null
else
    echo "  SKIP  zsh-only checks (run 'zsh test/test.sh' to exercise them)"
fi

echo ""
echo "--- config persistence ---"
# Drive changes in one subshell, then verify a fresh subshell restores them.
# Both share the isolated XDG_CONFIG_HOME exported at the top of this file.
PERSIST_HOME="$(mktemp -d)"
(
    export XDG_CONFIG_HOME="$PERSIST_HOME"
    NO_COLOR=1 source "${SCRIPT_DIR}/context-prompt.sh"
    ctxp disable k8s        >/dev/null
    ctxp order venv git aws >/dev/null
    ctxp color aws red      >/dev/null
    ctxp add tf 'printf "<tf:%s>" "prod"' >/dev/null
) >/dev/null 2>&1

cfg="$PERSIST_HOME/context-prompt/config"
check "config file is written" "yes" "$([[ -f "$cfg" ]] && echo yes || echo no)"

restored="$(
    export XDG_CONFIG_HOME="$PERSIST_HOME"
    NO_COLOR=1 source "${SCRIPT_DIR}/context-prompt.sh"
    ctxp list
)"
check_contains "restores disabled state" "k8s          disabled" "$restored"
check_contains "restores custom color"   "aws          enabled    red" "$restored"
check_contains "restores custom provider" "tf           enabled" "$restored"

# Order is restored: venv before git before aws in the enabled section
order_line="$(
    export XDG_CONFIG_HOME="$PERSIST_HOME"
    NO_COLOR=1 source "${SCRIPT_DIR}/context-prompt.sh"
    ctxp list | awk '$2=="enabled"{print $1}' | tr '\n' ' '
)"
check_contains "restores display order" "venv git aws" "$order_line"

# Custom provider actually renders after restore
tf_out="$(
    export XDG_CONFIG_HOME="$PERSIST_HOME"
    NO_COLOR=1 source "${SCRIPT_DIR}/context-prompt.sh"
    ctxp_provider_tf
)"
check "restored custom provider renders" "<tf:prod>" "$tf_out"

rm -rf "$PERSIST_HOME"

echo ""
echo "================================"
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
