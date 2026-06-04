#!/usr/bin/env bash
# Runs the test suite under every available shell so the bash and zsh code
# paths are both exercised. bash always runs; zsh runs if it's installed.
#
#   bash test/run.sh
#
set -u
here="$(cd "$(dirname "$0")" && pwd)"
rc=0

echo "######## bash ########"
bash "$here/test.sh" || rc=1

echo ""
if command -v zsh >/dev/null 2>&1; then
    echo "######## zsh ########"
    zsh "$here/test.sh" || rc=1
else
    echo "######## zsh not installed — skipping ########"
fi

echo ""
if [ "$rc" -eq 0 ]; then
    echo "ALL SHELLS PASSED"
else
    echo "SOME SHELLS FAILED"
fi
exit "$rc"
