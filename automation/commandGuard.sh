#!/usr/bin/env bash
# commandGuard.sh — PreToolUse(Bash) hook for Claude Code.
#
# Complements the permissions.deny prefix rules in .claude/settings.json.
# Those only match a command that STARTS with a pattern (e.g. "rm -rf *"),
# so a chained/composed command like `cd x && rm -rf y` or `ls; git push -f`
# slips past a prefix-only rule. This hook greps the FULL command string for
# the same destructive patterns anywhere in it, not just at the start, and
# actively denies the tool call if it matches.
#
# Wired into .claude/settings.json as a PreToolUse hook on the Bash matcher.
# Reads the standard Claude Code hook JSON on stdin, e.g.:
#   {"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"

[ -z "$CMD" ] && exit 0

# Recursive rm in ANY flag order/case: rm ... -rf / -fr / -Rf / -r -f / -f -r.
# We block the *recursive* flag (-r/-R) regardless of -f, since a recursive
# delete is the destructive part; a single-file rm is left to pass.
PATTERN='(^|[[:space:]])rm[[:space:]]+[^;&|]*-[A-Za-z]*[rR]([A-Za-z]*)?([[:space:]]|$)'
PATTERN="$PATTERN|(^|[[:space:]])-delete([[:space:]]|$)"
# Force push: --force / --force-with-lease / -f, and the "+ref" refspec form
# (git push origin +main) which force-updates a ref without the word "force".
PATTERN="$PATTERN|git[[:space:]]+push[[:space:]]+[^;&|]*(--force(-with-lease)?|-f)([[:space:]]|$)"
PATTERN="$PATTERN|git[[:space:]]+push[[:space:]]+[^;&|]*[[:space:]]\\+[A-Za-z0-9]"
PATTERN="$PATTERN|git[[:space:]]+reset[[:space:]]+[^;&|]*--hard"
PATTERN="$PATTERN|git[[:space:]]+clean[[:space:]]+-[A-Za-z]*f"
PATTERN="$PATTERN|git[[:space:]]+branch[[:space:]]+(-D|--delete[[:space:]]+--force)"
PATTERN="$PATTERN|git[[:space:]]+filter-branch"
PATTERN="$PATTERN|git[[:space:]]+gc[[:space:]]+[^;&|]*--prune"
PATTERN="$PATTERN|git[[:space:]]+reflog[[:space:]]+expire"
# Discard working-tree changes wholesale: checkout -- / restore / stash drop|clear.
PATTERN="$PATTERN|git[[:space:]]+checkout[[:space:]]+[^;&|]*--([[:space:]]|\$)"
PATTERN="$PATTERN|git[[:space:]]+restore([[:space:]]|\$)"
PATTERN="$PATTERN|git[[:space:]]+stash[[:space:]]+(drop|clear)"
# Truncate/overwrite a tracked note via shell redirection (> file), e.g. ': > x.md'.
PATTERN="$PATTERN|(^|[[:space:]])>[[:space:]]*[^;&|]*\\.md([[:space:]]|\$)"

if printf '%s' "$CMD" | grep -qE "$PATTERN"; then
    REASON="commandGuard: bloqueado por patrón destructivo en el comando: $CMD"
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}' \
        "$(printf '%s' "$REASON" | jq -Rs .)"
fi

exit 0
