#!/usr/bin/env bash
# install.sh — one-shot bootstrap for a new team member's machine.
#
# Automates everything Sync.md used to spell out as separate copy-paste
# steps: Homebrew, git, gh, a git identity (name+email — needed for commits
# to have an author, and easy to forget), gh auth, cloning the vault, cloning
# this repo, installing the vaultGuard pre-push hook ("el candado"), and
# pre-installing the six Obsidian community plugins the vault's buttons
# depend on (Obsidian Git, Kanban, Excalidraw, Templater, Buttons, Modal
# forms) with Obsidian Git already configured to auto-sync every 10 minutes.
#
# What stays manual on purpose: GitHub account signup + accepting the invite
# (steps 1-2 in Sync.md, need a browser before this script can even run),
# opening Obsidian and pointing it at the cloned folder, and the one-time
# "Turn on community plugins" toggle. That last one genuinely can't be
# scripted — Obsidian's restricted-mode flag lives in the app's own
# per-machine storage, not in any file inside the vault, precisely so a
# vault (or a script run against it) can't silently flip it on its own.
#
# Usage — bootstrap on a brand-new machine, nothing cloned yet:
#   curl -fsSL https://raw.githubusercontent.com/digodat/dataMx-vaultkeeper/main/automation/install.sh | bash
#
# Usage — already have this repo cloned:
#   ~/repos/vaultkeeping/automation/install.sh
#
# Idempotent: every step checks whether it's already done and skips if so,
# so re-running after a partial/failed setup is safe. Functions are pure
# enough to be sourced and called individually — see ../tests/test_install.sh,
# which mocks brew/git/gh/curl to exercise the skip-logic and JSON merging
# without touching the network or the real machine.

set -euo pipefail

# When piped through `curl | bash`, stdin is the script itself, not the
# terminal — reattach it so `read` and `gh auth login` can prompt normally.
# Best-effort: environments with no controlling terminal at all (CI, this
# script sourced by the test suite) fall through silently instead of dying.
if [ ! -t 0 ]; then
    { exec < /dev/tty; } 2>/dev/null || true
fi

VAULT="${VAULT:-$HOME/dataMx-vault}"
VAULTKEEPING="${VAULTKEEPING:-$HOME/repos/vaultkeeping}"
VAULT_REPO="${VAULT_REPO:-digodat/dataMx-vault}"
VAULTKEEPING_URL="${VAULTKEEPING_URL:-https://github.com/digodat/dataMx-vaultkeeper.git}"

# id:owner/repo — the six community plugins templates/Templates.md depends
# on. Verified against each repo's actual latest-release manifest.json `id`
# field, not guessed from the repo name (buttons and modalforms in
# particular don't match their repo names 1:1 in older forks).
PLUGIN_REPOS=(
    "templater-obsidian:SilentVoid13/Templater"
    "obsidian-git:Vinzent03/obsidian-git"
    "obsidian-kanban:mgmeyers/obsidian-kanban"
    "obsidian-excalidraw-plugin:zsviczian/obsidian-excalidraw-plugin"
    "buttons:shabegom/buttons"
    "modalforms:danielo515/obsidian-modal-form"
)

step() { echo; echo "== $1 =="; }

ensure_homebrew() {
    step "Homebrew"
    if command -v brew >/dev/null 2>&1; then
        echo "Already installed."
        return 0
    fi
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ -d /opt/homebrew/bin ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
}

ensure_git_and_gh() {
    step "git + gh"
    local pkg
    for pkg in git gh; do
        if command -v "$pkg" >/dev/null 2>&1; then
            echo "$pkg already installed."
        else
            brew install "$pkg"
        fi
    done
}

configure_git_identity() {
    step "git identity"
    if git config --global user.name >/dev/null 2>&1 && git config --global user.email >/dev/null 2>&1; then
        echo "Already set: $(git config --global user.name) <$(git config --global user.email)>"
        return 0
    fi
    local git_name git_email
    read -rp "Tu nombre (para firmar tus commits): " git_name
    read -rp "Tu correo (el mismo de tu cuenta de GitHub): " git_email
    git config --global user.name "$git_name"
    git config --global user.email "$git_email"
}

ensure_gh_auth() {
    step "GitHub CLI login"
    if gh auth status >/dev/null 2>&1; then
        echo "Already logged in."
        return 0
    fi
    gh auth login
}

clone_vault() {
    step "Vault clone"
    if [ -d "$VAULT/.git" ]; then
        echo "Already cloned at $VAULT."
        return 0
    fi
    gh repo clone "$VAULT_REPO" "$VAULT"
}

clone_vaultkeeping() {
    step "vaultkeeping clone"
    # If this script is itself running from inside a vaultkeeping clone (not
    # piped from curl), reuse that clone instead of making a second one.
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
    if [ -n "$script_dir" ] && [ -f "$script_dir/vaultGuard.sh" ]; then
        VAULTKEEPING="$(cd "$script_dir/.." && pwd)"
        echo "Running from an existing clone: $VAULTKEEPING"
    elif [ -d "$VAULTKEEPING/.git" ]; then
        echo "Already cloned at $VAULTKEEPING."
    else
        git clone "$VAULTKEEPING_URL" "$VAULTKEEPING"
    fi
}

install_candado() {
    step "Candado (vaultGuard pre-push hook)"
    "$VAULTKEEPING/automation/vaultGuard.sh" --install "$VAULT"
}

# Downloads one plugin's manifest.json + main.js (+ styles.css if the release
# ships one) straight from its latest GitHub release into
# $VAULT/.obsidian/plugins/<id>/ — the same three files Obsidian's own
# community-plugin browser would place there. Skips if already present.
# Never raises: a single plugin failing (network hiccup, renamed repo) must
# not take down the rest of the install, so callers check the return code.
install_plugin() {
    local id="$1" repo="$2"
    local dir="$VAULT/.obsidian/plugins/$id"

    if [ -f "$dir/manifest.json" ]; then
        echo "$id already installed."
        return 0
    fi

    local release_json
    if ! release_json="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest")"; then
        echo "WARN: no se pudo consultar la release de $id ($repo)."
        return 1
    fi

    mkdir -p "$dir"
    local asset url ok=1
    for asset in manifest.json main.js styles.css; do
        url="$(printf '%s' "$release_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data.get('assets', []):
    if a['name'] == sys.argv[1]:
        print(a['browser_download_url'])
        break
" "$asset")"
        if [ -n "$url" ]; then
            curl -fsSL -o "$dir/$asset" "$url" || ok=0
        elif [ "$asset" != "styles.css" ]; then
            # manifest.json and main.js are mandatory; styles.css isn't
            # every plugin ships one.
            ok=0
        fi
    done

    if [ "$ok" -eq 1 ]; then
        echo "$id installed."
        return 0
    fi
    echo "WARN: instalación incompleta de $id — se descarta."
    rm -rf "$dir"
    return 1
}

# Merges `ids` (space-separated) into a JSON array file at `path`, union'd
# with whatever's already there (so plugins the user already installed by
# hand aren't dropped), de-duplicated, order preserved.
merge_json_array() {
    local path="$1"
    shift
    python3 - "$path" "$@" <<'PYEOF'
import json, sys, os

path = sys.argv[1]
wanted = sys.argv[2:]
existing = []
if os.path.exists(path):
    try:
        with open(path) as f:
            existing = json.load(f)
    except Exception:
        existing = []

merged = list(dict.fromkeys(existing + wanted))
with open(path, "w") as f:
    json.dump(merged, f, indent=2)
    f.write("\n")
PYEOF
}

# Merges the auto-sync settings (10 min backup, 10 min pull, pull on boot,
# push enabled) into obsidian-git's own data.json, preserving any other
# key already there. Keys verified against DEFAULT_SETTINGS /
# src/setting/settings.ts in Vinzent03/obsidian-git — not the older
# "push on backup" toggle name from earlier plugin versions.
configure_obsidian_git_sync() {
    local path="$VAULT/.obsidian/plugins/obsidian-git/data.json"
    mkdir -p "$(dirname "$path")"
    python3 - "$path" <<'PYEOF'
import json, sys, os

path = sys.argv[1]
data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        data = {}

data.update({
    "autoSaveInterval": 10,
    "autoPullInterval": 10,
    "autoPullOnBoot": True,
    "disablePush": False,
})

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
}

configure_obsidian() {
    step "Plugins de Obsidian"
    mkdir -p "$VAULT/.obsidian/plugins"

    local entry id repo
    local success_ids=() failed_ids=()
    for entry in "${PLUGIN_REPOS[@]}"; do
        id="${entry%%:*}"
        repo="${entry#*:}"
        if install_plugin "$id" "$repo"; then
            success_ids+=("$id")
        else
            failed_ids+=("$id")
        fi
    done

    if [ "${#success_ids[@]}" -gt 0 ]; then
        merge_json_array "$VAULT/.obsidian/community-plugins.json" "${success_ids[@]}"
    fi

    for id in "${success_ids[@]}"; do
        if [ "$id" = "obsidian-git" ]; then
            configure_obsidian_git_sync
        fi
    done

    if [ "${#failed_ids[@]}" -gt 0 ]; then
        echo
        echo "No se instalaron solos: ${failed_ids[*]} — instálalos a mano desde" \
             "Settings > Community plugins > Browse una vez que abras el vault."
    fi
}

print_next_steps() {
    step "Listo"
    cat <<EOF
Falta solo lo que no se puede automatizar desde terminal:
  1. Instala Obsidian (https://obsidian.md) y abre $VAULT como vault
     (Open folder as vault).
  2. La primera vez, Obsidian va a avisar que hay community plugins y los
     tiene apagados por seguridad ("Restricted mode") — un solo clic en
     Settings > Community plugins para prenderlos. Eso Obsidian no deja
     automatizar desde ningún archivo, a propósito.

Los 6 plugins (Obsidian Git, Kanban, Excalidraw, Templater, Buttons, Modal
forms) y el auto-sync de Obsidian Git (cada 10 min) ya están instalados y
configurados — no hay que buscarlos ni tocar sus settings.

De ahí en adelante tu guía es onBoarding/Onboarding Kanban.md.
EOF
}

main() {
    ensure_homebrew
    ensure_git_and_gh
    configure_git_identity
    ensure_gh_auth
    clone_vault
    clone_vaultkeeping
    install_candado
    configure_obsidian
    print_next_steps
}

# Only run when executed directly or piped into bash — sourcing this file
# (as the test suite does) loads the functions above without side effects.
# `$0` is unreliable here: piped through `curl | bash` it's just "bash", not
# a path, so BASH_SOURCE[0]=="$0" would misfire and skip main() entirely.
# `return` only succeeds when sourced, so this detects it directly.
if ! (return 0 2>/dev/null); then
    main "$@"
fi
