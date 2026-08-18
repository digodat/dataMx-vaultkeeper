#!/usr/bin/env bash
# test_install.sh — exercises ../automation/install.sh without touching the
# network, Homebrew, git's real global config, or any real GitHub account.
#
# Each test runs in its own throwaway `bash -c` process: it sources
# install.sh (which, thanks to install.sh's own sourcing guard, only defines
# functions — main() does not run), points VAULT/VAULTKEEPING/HOME at a
# fresh temp dir, replaces curl/git/gh/brew with mock shell functions that
# record what they were called with, and then calls one install.sh function
# directly. Full isolation between tests: no shared state, no real side
# effects, safe to run offline and as many times as you like.
#
# Usage: ./test_install.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SH="$TESTS_DIR/../automation/install.sh"

if [ ! -f "$INSTALL_SH" ]; then
    echo "Can't find install.sh at $INSTALL_SH" >&2
    exit 2
fi

PASS=0
FAIL=0

# Runs the named test function in a clean bash subprocess. The function body
# is serialized with `declare -f` so the child process gets an exact copy —
# no eval'd string-building, no quoting hazards.
run_test() {
    local name="$1"
    local output
    local tmp_home
    tmp_home="$(mktemp -d)"
    if output="$(
        HOME="$tmp_home" \
        INSTALL_SH="$INSTALL_SH" \
        bash -c "
            set -uo pipefail
            $(declare -f assert_eq assert_file_exists assert_file_missing)
            $(declare -f "$name")
            $name
        " 2>&1
    )"; then
        PASS=$((PASS + 1))
        echo "ok   - $name"
    else
        FAIL=$((FAIL + 1))
        echo "FAIL - $name"
        echo "$output" | sed 's/^/       /'
    fi
    rm -rf "$tmp_home"
}

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [ "$expected" != "$actual" ]; then
        echo "assert_eq failed $msg: expected [$expected], got [$actual]" >&2
        return 1
    fi
}

assert_file_exists() {
    if [ ! -f "$1" ]; then
        echo "assert_file_exists failed: $1 does not exist" >&2
        return 1
    fi
}

assert_file_missing() {
    if [ -f "$1" ]; then
        echo "assert_file_missing failed: $1 exists" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------

test_syntax_is_valid() {
    bash -n "$INSTALL_SH"
}

test_sourcing_does_not_run_main() {
    # If main() ran on source, this would try to `brew install` etc. and
    # fail loudly (no brew mock defined) — reaching the echo means it didn't.
    source "$INSTALL_SH" </dev/null
    echo "sourced without running main"
}

test_git_identity_skips_prompt_when_already_set() {
    source "$INSTALL_SH" </dev/null
    git() {
        case "$1 $2 $3" in
            "config --global user.name") echo "Ya Existe"; return 0 ;;
            "config --global user.email") echo "ya@existe.com"; return 0 ;;
        esac
        echo "unexpected git call: $*" >&2; return 1
    }
    read() { echo "read() should not have been called: $*" >&2; return 1; }
    configure_git_identity
}

test_git_identity_prompts_when_unset() {
    source "$INSTALL_SH" </dev/null
    git() {
        # Reads are 3 args (config --global user.name); writes add a 4th
        # (the value) — same $1-$3 for both, so arg count is what tells
        # them apart.
        if [ "$1 $2" = "config --global" ] && [ "$#" -eq 3 ]; then
            return 1
        fi
        if [ "$1 $2" = "config --global" ] && [ "$#" -eq 4 ]; then
            echo "SET: $3=$4"
            return 0
        fi
        echo "unexpected git call: $*" >&2; return 1
    }
    read() {
        # -rp "prompt" varname
        local varname="${*: -1}"
        printf -v "$varname" "%s" "mock-value"
    }
    configure_git_identity
}

test_gh_auth_skips_login_when_already_logged_in() {
    source "$INSTALL_SH" </dev/null
    gh() {
        if [ "$1 $2" = "auth status" ]; then return 0; fi
        echo "gh should not have been called with: $*" >&2; return 1
    }
    ensure_gh_auth
}

test_clone_vault_skips_when_already_cloned() {
    source "$INSTALL_SH" </dev/null
    export VAULT="$(mktemp -d)/vault"
    mkdir -p "$VAULT/.git"
    gh() { echo "gh should not have been called: $*" >&2; return 1; }
    clone_vault
}

test_clone_vault_clones_when_missing() {
    source "$INSTALL_SH" </dev/null
    export VAULT="$(mktemp -d)/vault"
    gh() {
        if [ "$1 $2" = "repo clone" ]; then
            echo "cloned: $3 -> $4"
            return 0
        fi
        echo "unexpected gh call: $*" >&2; return 1
    }
    clone_vault
}

test_install_plugin_skips_when_manifest_present() {
    source "$INSTALL_SH" </dev/null
    export VAULT="$(mktemp -d)/vault"
    mkdir -p "$VAULT/.obsidian/plugins/templater-obsidian"
    echo '{"id":"templater-obsidian"}' > "$VAULT/.obsidian/plugins/templater-obsidian/manifest.json"
    curl() { echo "curl should not have been called: $*" >&2; return 1; }
    install_plugin templater-obsidian "SilentVoid13/Templater"
}

test_install_plugin_downloads_all_assets() {
    source "$INSTALL_SH" </dev/null
    export VAULT="$(mktemp -d)/vault"
    curl() {
        local out="" url=""
        while [ "$#" -gt 0 ]; do
            case "$1" in
                -o) out="$2"; shift 2 ;;
                -fsSL) shift ;;
                http*) url="$1"; shift ;;
                *) shift ;;
            esac
        done
        case "$url" in
            */releases/latest)
                cat <<'JSON'
{"assets":[
  {"name":"manifest.json","browser_download_url":"https://x/manifest.json"},
  {"name":"main.js","browser_download_url":"https://x/main.js"},
  {"name":"styles.css","browser_download_url":"https://x/styles.css"}
]}
JSON
                ;;
            https://x/manifest.json) echo '{"id":"fake-plugin"}' > "$out" ;;
            https://x/main.js) echo '// js' > "$out" ;;
            https://x/styles.css) echo '/* css */' > "$out" ;;
            *) return 1 ;;
        esac
    }
    install_plugin fake-plugin "someone/fake-plugin"
    assert_file_exists "$VAULT/.obsidian/plugins/fake-plugin/manifest.json"
    assert_file_exists "$VAULT/.obsidian/plugins/fake-plugin/main.js"
    assert_file_exists "$VAULT/.obsidian/plugins/fake-plugin/styles.css"
}

test_install_plugin_handles_missing_optional_styles_css() {
    source "$INSTALL_SH" </dev/null
    export VAULT="$(mktemp -d)/vault"
    curl() {
        local out="" url=""
        while [ "$#" -gt 0 ]; do
            case "$1" in
                -o) out="$2"; shift 2 ;;
                -fsSL) shift ;;
                http*) url="$1"; shift ;;
                *) shift ;;
            esac
        done
        case "$url" in
            */releases/latest)
                cat <<'JSON'
{"assets":[
  {"name":"manifest.json","browser_download_url":"https://x/manifest.json"},
  {"name":"main.js","browser_download_url":"https://x/main.js"}
]}
JSON
                ;;
            https://x/manifest.json) echo '{"id":"no-css-plugin"}' > "$out" ;;
            https://x/main.js) echo '// js' > "$out" ;;
            *) return 1 ;;
        esac
    }
    install_plugin no-css-plugin "someone/no-css-plugin"
    assert_file_exists "$VAULT/.obsidian/plugins/no-css-plugin/manifest.json"
    assert_file_missing "$VAULT/.obsidian/plugins/no-css-plugin/styles.css"
}

test_install_plugin_fails_cleanly_on_network_error() {
    source "$INSTALL_SH" </dev/null
    export VAULT="$(mktemp -d)/vault"
    curl() { return 22; }
    if install_plugin broken-plugin "someone/broken-plugin"; then
        echo "expected install_plugin to fail" >&2
        return 1
    fi
    assert_file_missing "$VAULT/.obsidian/plugins/broken-plugin/manifest.json"
}

test_install_plugin_discards_partial_download_on_asset_failure() {
    source "$INSTALL_SH" </dev/null
    export VAULT="$(mktemp -d)/vault"
    curl() {
        local out="" url=""
        while [ "$#" -gt 0 ]; do
            case "$1" in
                -o) out="$2"; shift 2 ;;
                -fsSL) shift ;;
                http*) url="$1"; shift ;;
                *) shift ;;
            esac
        done
        case "$url" in
            */releases/latest)
                cat <<'JSON'
{"assets":[
  {"name":"manifest.json","browser_download_url":"https://x/manifest.json"},
  {"name":"main.js","browser_download_url":"https://x/main.js"}
]}
JSON
                ;;
            https://x/manifest.json) echo '{"id":"half-plugin"}' > "$out" ;;
            https://x/main.js) return 1 ;;  # main.js download fails
            *) return 1 ;;
        esac
    }
    if install_plugin half-plugin "someone/half-plugin"; then
        echo "expected install_plugin to fail" >&2
        return 1
    fi
    assert_file_missing "$VAULT/.obsidian/plugins/half-plugin/manifest.json"
}

test_configure_obsidian_continues_after_one_plugin_fails() {
    # One repo 404s; the other five must still install, and only the
    # successful ones must end up in community-plugins.json.
    source "$INSTALL_SH" </dev/null
    export VAULT="$(mktemp -d)/vault"
    PLUGIN_REPOS=(
        "good-plugin:someone/good-plugin"
        "bad-plugin:someone/bad-plugin"
    )
    curl() {
        local out="" url=""
        while [ "$#" -gt 0 ]; do
            case "$1" in
                -o) out="$2"; shift 2 ;;
                -fsSL) shift ;;
                http*) url="$1"; shift ;;
                *) shift ;;
            esac
        done
        case "$url" in
            *bad-plugin/releases/latest) return 22 ;;
            */releases/latest)
                cat <<'JSON'
{"assets":[
  {"name":"manifest.json","browser_download_url":"https://x/manifest.json"},
  {"name":"main.js","browser_download_url":"https://x/main.js"}
]}
JSON
                ;;
            https://x/manifest.json) echo '{"id":"good-plugin"}' > "$out" ;;
            https://x/main.js) echo '// js' > "$out" ;;
            *) return 1 ;;
        esac
    }
    configure_obsidian
    assert_file_exists "$VAULT/.obsidian/plugins/good-plugin/manifest.json"
    assert_file_missing "$VAULT/.obsidian/plugins/bad-plugin/manifest.json"
    local content
    content="$(cat "$VAULT/.obsidian/community-plugins.json")"
    case "$content" in
        *good-plugin*) ;;
        *) echo "good-plugin missing from community-plugins.json: $content" >&2; return 1 ;;
    esac
    case "$content" in
        *bad-plugin*) echo "bad-plugin should not be in community-plugins.json: $content" >&2; return 1 ;;
    esac
}

test_merge_json_array_unions_and_dedupes_existing_file() {
    source "$INSTALL_SH" </dev/null
    local dir; dir="$(mktemp -d)"
    local path="$dir/community-plugins.json"
    echo '["already-here", "obsidian-git"]' > "$path"
    merge_json_array "$path" "obsidian-git" "newly-added"
    python3 -c "
import json
got = json.load(open('$path'))
expected = ['already-here', 'obsidian-git', 'newly-added']
assert got == expected, f'{got} != {expected}'
"
}

test_merge_json_array_creates_file_when_missing() {
    source "$INSTALL_SH" </dev/null
    local dir; dir="$(mktemp -d)"
    local path="$dir/community-plugins.json"
    merge_json_array "$path" "a" "b"
    python3 -c "
import json
got = json.load(open('$path'))
assert got == ['a', 'b'], got
"
}

test_obsidian_git_sync_settings_preserve_other_keys() {
    source "$INSTALL_SH" </dev/null
    export VAULT="$(mktemp -d)/vault"
    mkdir -p "$VAULT/.obsidian/plugins/obsidian-git"
    echo '{"showStatusBar": false, "autoSaveInterval": 0}' \
        > "$VAULT/.obsidian/plugins/obsidian-git/data.json"
    configure_obsidian_git_sync
    python3 -c "
import json
got = json.load(open('$VAULT/.obsidian/plugins/obsidian-git/data.json'))
assert got['showStatusBar'] is False, got
assert got['autoSaveInterval'] == 10, got
assert got['autoPullInterval'] == 10, got
assert got['autoPullOnBoot'] is True, got
assert got['disablePush'] is False, got
"
}

test_obsidian_git_sync_settings_create_file_when_missing() {
    source "$INSTALL_SH" </dev/null
    export VAULT="$(mktemp -d)/vault"
    configure_obsidian_git_sync
    python3 -c "
import json
got = json.load(open('$VAULT/.obsidian/plugins/obsidian-git/data.json'))
assert got['autoSaveInterval'] == 10, got
assert got['autoPullOnBoot'] is True, got
"
}

test_candado_install_targets_correct_vault_path() {
    source "$INSTALL_SH" </dev/null
    export VAULT="/fake/vault/path"
    export VAULTKEEPING="$(mktemp -d)"
    mkdir -p "$VAULTKEEPING/automation"
    cat > "$VAULTKEEPING/automation/vaultGuard.sh" <<'HOOK'
#!/usr/bin/env bash
echo "called with: $*"
if [ "$1" != "--install" ] || [ "$2" != "/fake/vault/path" ]; then
    exit 1
fi
HOOK
    chmod +x "$VAULTKEEPING/automation/vaultGuard.sh"
    install_candado
}

test_ensure_homebrew_skips_when_present() {
    source "$INSTALL_SH" </dev/null
    brew() { echo "brew should not be invoked for install: $*" >&2; return 1; }
    command() {
        if [ "$1" = "-v" ] && [ "$2" = "brew" ]; then return 0; fi
        builtin command "$@"
    }
    ensure_homebrew
}

test_ensure_git_and_gh_skips_already_installed_tools() {
    source "$INSTALL_SH" </dev/null
    brew() { echo "brew install should not run when tools are present: $*" >&2; return 1; }
    command() {
        if [ "$1" = "-v" ]; then return 0; fi
        builtin command "$@"
    }
    ensure_git_and_gh
}

# ---------------------------------------------------------------------------

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$t"
done

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
