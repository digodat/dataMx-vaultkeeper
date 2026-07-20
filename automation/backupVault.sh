#!/usr/bin/env bash
# backupVault.sh — snapshots the vault repo into dated git bundles.
#
# Why: the vault's remote is a private repo on a plan without server-side
# branch protection, so a force-push (or a local disaster) could rewrite
# shared history. A bundle is a full, self-contained copy of every ref at a
# point in time — restoring is just `git clone vault-<fecha>.bundle carpeta`.
#
# Skips the snapshot when nothing changed since the last one, so the kept
# window covers real history instead of 30 identical copies.
#
# Usage:
#   ./backupVault.sh [path-to-vault] [backup-dir] [keep]
# Defaults: vault = ~/dataMx-vault, backup-dir = ~/dataMx-vault-backups, keep = 30
#
# Meant to run from cron, e.g. hourly:
#   0 * * * * $HOME/repos/vaultkeeping/automation/backupVault.sh >/dev/null 2>&1

set -euo pipefail

VAULT="${1:-$HOME/dataMx-vault}"
DEST="${2:-$HOME/dataMx-vault-backups}"
KEEP="${3:-30}"

if [ ! -d "$VAULT/.git" ]; then
    echo "No git repo at $VAULT" >&2
    exit 2
fi
mkdir -p "$DEST"

cd "$VAULT"
# include the remote's latest refs when there is one; offline is fine too
git fetch --all --quiet 2>/dev/null || true

CUR="$(git for-each-ref --format='%(objectname) %(refname)' | shasum | awk '{print $1}')"
STATE="$DEST/.last-refs"
if [ -f "$STATE" ] && [ "$(cat "$STATE")" = "$CUR" ]; then
    echo "No changes since last snapshot — nothing to do."
    exit 0
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BUNDLE="$DEST/vault-$STAMP.bundle"
git bundle create "$BUNDLE" --all >/dev/null 2>&1
git bundle verify "$BUNDLE" >/dev/null 2>&1

printf '%s' "$CUR" > "$STATE"

# rotation: keep only the newest $KEEP bundles
ls -1t "$DEST"/vault-*.bundle | tail -n +$((KEEP + 1)) | while IFS= read -r old; do
    rm -- "$old"
done

COUNT="$(ls -1 "$DEST"/vault-*.bundle | wc -l | tr -d ' ')"
echo "Backup OK: $BUNDLE ($COUNT snapshots, max $KEEP)"
