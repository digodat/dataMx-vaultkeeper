#!/usr/bin/env bash
# check-vault-links.sh — audits an Obsidian vault's reference graph.
#
# Reports:
#   - broken markdown links:  [text](path)
#   - broken wikilinks:       [[path]] / [[path|alias]]
#   - notes with zero incoming links (orphans)
#
# Usage:
#   ./check-vault-links.sh [path-to-vault]
#
# Defaults to ~/dataMx-vault if no path is given.
# Exits 0 if the graph is clean, 1 if it finds broken links.
# Skips .git/, .obsidian/, and files inside templates/ (those hold
# intentional bracket placeholders like [Brand Name] and aren't meant
# to resolve or be linked to). Also skips symlinks (e.g. CLAUDE.md ->
# AGENTS.md) and doesn't flag AGENTS.md as an orphan — it's an
# agent-facing entry point, not part of the Obsidian graph. Doesn't flag
# files inside trash/ as orphans either — that folder is explicitly
# "deletion staging", nothing is ever meant to link there. Treats tmp/ the
# same as templates/ (skipped for both broken-link and orphan checks) --
# it's the scratch folder the Templater+Buttons forms use before moving
# content to its real destination, gitignored, never meant to resolve.

set -euo pipefail

VAULT="${1:-$HOME/dataMx-vault}"

if [ ! -d "$VAULT" ]; then
    echo "Vault not found: $VAULT" >&2
    exit 2
fi

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 2; }

python3 - "$VAULT" <<'PYEOF'
import re, os, sys, urllib.parse

vault = os.path.abspath(sys.argv[1])
os.chdir(vault)

ENTRY_POINT_FILES = {'AGENTS.md'}  # agent-facing pointers, intentionally outside the Obsidian graph

md_files = []
for root, dirs, files in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in ('.git', '.obsidian')]
    for f in files:
        if f.endswith('.md'):
            p = os.path.join(root, f)
            if os.path.islink(p):
                continue  # e.g. CLAUDE.md -> AGENTS.md: don't double-count the same content
            md_files.append(os.path.normpath(p))

md_link_re = re.compile(r'\[([^\]]*)\]\(([^)]+)\)')
wiki_link_re = re.compile(r'\[\[([^\]|]+)(\|[^\]]+)?\]\]')

def in_code_fence(content, pos):
    return content[:pos].count('```') % 2 == 1

broken = []
incoming = {p: 0 for p in md_files}

for p in sorted(md_files):
    is_template = p.startswith('templates' + os.sep) or p.startswith('tmp' + os.sep)
    with open(p, encoding='utf-8') as fh:
        content = fh.read()
    base_dir = os.path.dirname(p)

    for m in md_link_re.finditer(content):
        if in_code_fence(content, m.start()):
            continue
        text, target = m.groups()
        if target.startswith(('http://', 'https://', 'mailto:')):
            continue
        target_unq = urllib.parse.unquote(target.split('#')[0])
        if not target_unq:
            continue
        resolved = os.path.normpath(os.path.join(base_dir, target_unq))
        if os.path.exists(resolved):
            if resolved in incoming:
                incoming[resolved] += 1
        elif not is_template:
            broken.append(f"[MD]   {p} -> '{target}'")

    for m in wiki_link_re.finditer(content):
        if in_code_fence(content, m.start()):
            continue
        target = m.group(1).strip().split('#')[0]
        if not target:
            continue
        cand = target if target.endswith('.md') else target + '.md'
        matches = [mp for mp in md_files if mp == cand or mp.endswith(os.sep + cand)]
        if matches:
            for mp in matches:
                incoming[mp] += 1
        elif not is_template:
            broken.append(f"[WIKI] {p} -> '[[{target}]]'")

orphans = [p for p, c in sorted(incoming.items())
           if c == 0 and not p.startswith('templates' + os.sep)
           and not p.startswith('trash' + os.sep) and not p.startswith('tmp' + os.sep)
           and p not in ENTRY_POINT_FILES]

print(f"Vault: {vault}")
print(f"Notes scanned: {len(md_files)}\n")

if broken:
    print(f"Broken links ({len(broken)}):")
    for b in broken:
        print(" -", b)
else:
    print("Broken links: none")

print()
if orphans:
    print(f"Orphan notes, zero incoming links ({len(orphans)}):")
    for o in orphans:
        print(" -", o)
else:
    print("Orphan notes: none")

sys.exit(1 if broken else 0)
PYEOF
