#!/usr/bin/env bash
# newAccount.sh — scaffolds a new account (brand/client) in the dataMx vault.
#
# Creates, from the vault's own templates:
#   knowledge/brands/<Slug>/<Brand Name> Knowledge.md
#   meetings/client/<Slug>/<Brand Name> Meetings.md
# and appends the account to:
#   knowledge/brands/Brands.md
#   meetings/client/Clientes.md
#
# so a new account is fully connected in the reference graph from the moment
# it's created — no manual link-chasing, no risk of a floating note.
#
# Usage:
#   ./newAccount.sh "Brand Name" [path-to-vault]
#
# Defaults to ~/dataMx-vault if no vault path is given.
# Slug is derived by replacing spaces with "-" (e.g. "Brand Name" -> "Brand-Name").
# Refuses to run if the account already exists (won't overwrite).

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 \"Brand Name\" [path-to-vault]" >&2
    exit 2
fi

BRAND="$1"
VAULT="${2:-$HOME/dataMx-vault}"

if [ ! -d "$VAULT" ]; then
    echo "Vault not found: $VAULT" >&2
    exit 2
fi

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 2; }

python3 - "$VAULT" "$BRAND" <<'PYEOF'
import os, sys, re, datetime, json, colorsys

GOLDEN_ANGLE = 137.508  # maximally-spread sequential hue step, no manual color list to maintain

vault = os.path.abspath(sys.argv[1])
brand = sys.argv[2].strip()
slug = brand.replace(' ', '-')
today = datetime.date.today().isoformat()

# A brand name is user input that becomes a directory path — reject anything
# that could escape knowledge/brands/<slug> (path traversal, absolute paths,
# separators, leading dots). Keep it to plain account-name characters.
if not brand or brand in ('.', '..'):
    sys.exit(f"Invalid brand name: {brand!r}")
if any(c in brand for c in ('/', '\\')) or '..' in brand:
    sys.exit(f"Brand name can't contain path separators or '..': {brand!r}")
if slug.startswith('.') or os.path.isabs(slug):
    sys.exit(f"Invalid brand name (leading dot or absolute path): {brand!r}")

os.chdir(vault)

brand_tpl_path = os.path.join('templates', 'molds', 'Brand Knowledge.md')
meetings_tpl_path = os.path.join('templates', 'molds', 'Client Meetings Index.md')
reports_tpl_path = os.path.join('templates', 'molds', 'Account Reports Index.md')
brands_index_path = os.path.join('knowledge', 'brands', 'Brands.md')
clientes_index_path = os.path.join('meetings', 'client', 'Clientes.md')

for req in (brand_tpl_path, meetings_tpl_path, reports_tpl_path, brands_index_path, clientes_index_path):
    if not os.path.exists(req):
        sys.exit(f"Missing expected vault file: {req}")

knowledge_dir = os.path.join('knowledge', 'brands', slug)
meetings_dir = os.path.join('meetings', 'client', slug)
reports_dir = os.path.join(knowledge_dir, 'reportes')
knowledge_file = os.path.join(knowledge_dir, f'{brand} Knowledge.md')
meetings_file = os.path.join(meetings_dir, f'{brand} Meetings.md')
reports_file = os.path.join(reports_dir, f'{brand} Reportes.md')

if os.path.exists(knowledge_dir) or os.path.exists(meetings_dir):
    sys.exit(f"Account '{brand}' (slug '{slug}') already exists — aborting, nothing written.")

# --- Brand Knowledge note ---
with open(brand_tpl_path, encoding='utf-8') as fh:
    content = fh.read()
content = content.replace('[YYYY-MM-DD]', today).replace('[Brand-Name]', slug).replace('[Brand Name]', brand)
os.makedirs(knowledge_dir, exist_ok=True)
with open(knowledge_file, 'w', encoding='utf-8') as fh:
    fh.write(content)

# --- Client Meetings Index note ---
with open(meetings_tpl_path, encoding='utf-8') as fh:
    content = fh.read()
# no real bitácoras yet — drop the placeholder Línea/Periodo block, same
# convention used when the first meetings indexes were created by hand.
content = re.sub(
    r'## \[Línea\]\n- \[\[Archivo\|Periodo\]\]',
    '(Sin bitácoras registradas todavía.)',
    content,
)
content = content.replace('[YYYY-MM-DD]', today).replace('[Cliente-Slug]', slug).replace('[Cliente]', brand)
os.makedirs(meetings_dir, exist_ok=True)
with open(meetings_file, 'w', encoding='utf-8') as fh:
    fh.write(content)

# --- Account Reports Index note ---
with open(reports_tpl_path, encoding='utf-8') as fh:
    content = fh.read()
content = content.replace('[YYYY-MM-DD]', today).replace('[Brand-Name]', slug).replace('[Brand Name]', brand)
os.makedirs(reports_dir, exist_ok=True)
with open(reports_file, 'w', encoding='utf-8') as fh:
    fh.write(content)

# --- Wire into Brands.md ---
knowledge_link = f'[[knowledge/brands/{slug}/{brand} Knowledge|{brand}]]'
with open(brands_index_path, encoding='utf-8') as fh:
    brands_content = fh.read()
if knowledge_link not in brands_content:
    sep = '' if brands_content.endswith('\n') else '\n'
    brands_content = f"{brands_content}{sep}- {knowledge_link}\n"
    with open(brands_index_path, 'w', encoding='utf-8') as fh:
        fh.write(brands_content)

# --- Wire into Clientes.md ---
meetings_link = f'[[meetings/client/{slug}/{brand} Meetings|{brand}]]'
with open(clientes_index_path, encoding='utf-8') as fh:
    clientes_content = fh.read()
if meetings_link not in clientes_content:
    sep = '' if clientes_content.endswith('\n') else '\n'
    clientes_content = f"{clientes_content}{sep}- {meetings_link}\n"
    with open(clientes_index_path, 'w', encoding='utf-8') as fh:
        fh.write(clientes_content)

# --- Assign this account its own Graph view color, automatically ---
# One color group per account would normally mean remembering to hand-add a
# new entry every time — instead, count how many account-shaped groups
# already exist (query mentions both trees) and pick the next hue via the
# golden angle, so every new account gets a distinct color with zero
# maintenance, forever.
graph_path = os.path.join('.obsidian', 'graph.json')
color_note = "(sin .obsidian/graph.json todavía — se puede correr Obsidian una vez y volver a intentar)"
if os.path.exists(graph_path):
    with open(graph_path, encoding='utf-8') as fh:
        graph = json.load(fh)
    groups = graph.setdefault('colorGroups', [])
    account_group_count = sum(
        1 for g in groups
        if 'knowledge/brands/' in g.get('query', '') and 'meetings/client/' in g.get('query', '')
    )
    hue = (account_group_count * GOLDEN_ANGLE) % 360
    # neon (S=95%, L=55%) -- must match the palette rule in
    # onBoarding/graph.md and vaultkeeping/automation/rebuildGraphColors.sh: categories
    # are pastel, accounts are neon, nothing in between.
    r, g_, b = colorsys.hls_to_rgb(hue / 360, 0.55, 0.95)
    rgb_int = round(r * 255) * 65536 + round(g_ * 255) * 256 + round(b * 255)
    groups.append({
        'query': f'path:knowledge/brands/{slug} OR path:meetings/client/{slug}',
        'color': {'a': 1, 'rgb': rgb_int},
    })
    with open(graph_path, 'w', encoding='utf-8') as fh:
        json.dump(graph, fh, indent=2)
        fh.write('\n')
    color_note = f"#{rgb_int:06X}"

print(f"Created account: {brand} (slug: {slug})")
print(f"  - {knowledge_file}")
print(f"  - {meetings_file}")
print(f"  - {reports_file}")
print(f"  - linked from {brands_index_path}")
print(f"  - linked from {clientes_index_path}")
print(f"  - graph color: {color_note}")
PYEOF
