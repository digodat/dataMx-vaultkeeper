#!/usr/bin/env bash
# vaultGuard.sh — local, no-cloud version of the GitHub Actions safety net
# described in github-actions-security.md §4-5. Runs the reference-graph
# check (via vaultChecker.sh) plus a mass-deletion guard, and can install
# itself as a git pre-push hook so nothing bad leaves the machine.
#
# Usage:
#   ./vaultGuard.sh [path-to-vault] [max-deleted-files]
#   ./vaultGuard.sh --install [path-to-vault]
#
# Defaults: vault = ~/dataMx-vault, max-deleted-files = 5
#
# Honest limitation: unlike the GitHub Action, this is a *local* gate — it
# can be skipped with `git push --no-verify` or by deleting the hook. Treat
# it as a fast first line of defense, not a replacement for server-side
# branch protection once there's a remote.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/vaultChecker.sh"

install_hook() {
    local vault="$1"
    if [ ! -d "$vault/.git" ]; then
        echo "No .git at $vault — run git init there first." >&2
        exit 2
    fi
    local hook_path="$vault/.git/hooks/pre-push"
    cat > "$hook_path" <<HOOK
#!/usr/bin/env bash
# Installed by vaultGuard.sh --install — do not edit by hand, re-run install instead.
exec "$SCRIPT_DIR/vaultGuard.sh" "$vault"
HOOK
    chmod +x "$hook_path"
    echo "Installed pre-push hook: $hook_path"
    echo "Every push from this clone now runs vaultGuard.sh first."
}

if [ "${1:-}" = "--install" ]; then
    install_hook "${2:-$HOME/dataMx-vault}"
    exit 0
fi

VAULT="${1:-$HOME/dataMx-vault}"
MAX_DELETED="${2:-5}"

if [ ! -d "$VAULT" ]; then
    echo "Vault not found: $VAULT" >&2
    exit 2
fi
if [ ! -x "$CHECKER" ]; then
    echo "vaultChecker.sh not found next to this script ($CHECKER)" >&2
    exit 2
fi

echo "== 1/2: reference graph =="
GRAPH_STATUS=0
"$CHECKER" "$VAULT" || GRAPH_STATUS=$?

echo
echo "== 2/2: mass-deletion guard =="
DELETE_STATUS=0
cd "$VAULT"

if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Not a git repo — skipping deletion guard."
else
    BASE=""
    # Called as a real pre-push hook: git feeds "<local ref> <local sha1> <remote ref> <remote sha1>" on stdin.
    if [ ! -t 0 ] && read -r LOCAL_REF LOCAL_SHA REMOTE_REF REMOTE_SHA; then
        if [ -n "${REMOTE_SHA:-}" ] && [ "$REMOTE_SHA" != "0000000000000000000000000000000000000000" ]; then
            BASE="$REMOTE_SHA"
        fi
    fi
    # Manual run (no hook stdin, or brand-new remote branch): fall back to the previous commit.
    if [ -z "$BASE" ] && git rev-parse HEAD~1 > /dev/null 2>&1; then
        BASE="HEAD~1"
        echo "(modo manual: comparando contra el commit anterior, no contra el remoto)"
    fi

    if [ -z "$BASE" ]; then
        echo "Nothing to compare against yet (first commit) — skipping."
    else
        DELETED=$(git diff --name-status "$BASE" HEAD -- '*.md' 2>/dev/null | awk '$1=="D"' | wc -l | tr -d ' ')
        echo "Notes deleted since $BASE: $DELETED"
        if [ "$DELETED" -gt "$MAX_DELETED" ]; then
            echo "BLOCKED: deletes $DELETED notes, over the limit of $MAX_DELETED. Looks like a mass deletion." >&2
            DELETE_STATUS=1
        fi
    fi
fi

if [ "$GRAPH_STATUS" -ne 0 ] || [ "$DELETE_STATUS" -ne 0 ]; then
    echo
    echo "vaultGuard: BLOCKED — fix the above before pushing." >&2
    exit 1
fi

echo
echo "vaultGuard: clean."
exit 0
