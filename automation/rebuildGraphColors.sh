#!/usr/bin/env bash
# rebuildGraphColors.sh — rebuilds the Graph view color scheme from scratch.
#
# .obsidian/graph.json is NOT tracked by git by default (only graph.json itself
# is whitelisted in .gitignore, but that only helps once the vault actually
# lives in a git repo with commits). Obsidian can also reset colorGroups on its
# own (plugin update, "reset view" click, etc). When that happens, this script
# regenerates the exact same scheme every time — no manual re-entry, no drift.
#
# Palette rule (see onBoarding/graph.md for the full explanation):
#   - Folder categories -> PASTEL (soft, calm, S=50% L=82%), one fixed hue per
#     folder, evenly spaced. Never changes.
#   - Client/brand accounts -> NEON (vivid, S=95% L=55%), one hue per account
#     picked via the golden angle so every new account (scanned live from
#     knowledge/brands/*) gets a distinct color with zero maintenance.
#   - Root note (README.md) -> gold, marks the center of the graph.
#
# Usage:
#   ./rebuildGraphColors.sh [path-to-vault]
#
# Defaults to ~/dataMx-vault. Overwrites colorGroups in .obsidian/graph.json;
# leaves every other graph.json setting (scale, forces, etc.) untouched.

set -euo pipefail

VAULT="${1:-$HOME/dataMx-vault}"

if [ ! -d "$VAULT" ]; then
    echo "Vault not found: $VAULT" >&2
    exit 2
fi

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 2; }

python3 - "$VAULT" <<'PYEOF'
import os, sys, json, colorsys

GOLDEN_ANGLE = 137.508

vault = os.path.abspath(sys.argv[1])
graph_path = os.path.join(vault, '.obsidian', 'graph.json')

if not os.path.exists(graph_path):
    sys.exit(f"Not found: {graph_path} (open the vault in Obsidian at least once first)")

# name, path query(ies) -- fixed set, fixed order, fixed hues. Do not reorder
# or insert entries in the middle: that would reshuffle every existing hue.
CATEGORIES = [
    ("Inbox", "path:inbox"),
    ("Decisions", "path:decisions"),
    ("Knowledge", "path:knowledge"),
    ("Meetings", "path:meetings"),
    ("Daybook", "path:daybook"),
    ("Onboarding", "path:onBoarding OR path:Excalidraw"),
    ("Active Projects", "path:activeProjects"),
    ("Index", "path:index"),
    ("Templates", "path:templates"),
    ("To Learn", "path:toLearn"),
    ("Archive", "path:archive"),
    ("Trash", "path:trash"),
]

def pastel(i, total):
    hue = (360 / total) * i
    r, g, b = colorsys.hls_to_rgb(hue / 360, 0.82, 0.50)
    return round(r * 255) * 65536 + round(g * 255) * 256 + round(b * 255)

def neon(i):
    hue = (i * GOLDEN_ANGLE) % 360
    r, g, b = colorsys.hls_to_rgb(hue / 360, 0.55, 0.95)
    return round(r * 255) * 65536 + round(g * 255) * 256 + round(b * 255)

groups = []
for i, (name, query) in enumerate(CATEGORIES):
    groups.append({"query": query, "color": {"a": 1, "rgb": pastel(i, len(CATEGORIES))}})

brands_dir = os.path.join(vault, 'knowledge', 'brands')
accounts = sorted(
    d for d in os.listdir(brands_dir)
    if os.path.isdir(os.path.join(brands_dir, d))
) if os.path.isdir(brands_dir) else []

for i, slug in enumerate(accounts):
    groups.append({
        "query": f"path:knowledge/brands/{slug} OR path:meetings/client/{slug}",
        "color": {"a": 1, "rgb": neon(i)},
    })

groups.append({"query": "path:README.md", "color": {"a": 1, "rgb": 0xFFD700}})

with open(graph_path, encoding='utf-8') as fh:
    graph = json.load(fh)
graph['colorGroups'] = groups
with open(graph_path, 'w', encoding='utf-8') as fh:
    json.dump(graph, fh, indent=2)
    fh.write('\n')

print(f"Rebuilt {len(groups)} color groups in {graph_path}")
print(f"  - {len(CATEGORIES)} category (pastel)")
print(f"  - {len(accounts)} account (neon): {', '.join(accounts) if accounts else '(none found)'}")
print("  - 1 root marker (gold)")
print("Close and reopen the Graph view in Obsidian (or toggle it) to see the refresh.")
PYEOF
