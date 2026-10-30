#!/usr/bin/env bash
# Install git-profile on this machine. Safe to re-run.
#
#   ./setup.sh                      install; asks for a first profile when no config exists
#   ./setup.sh --config <file>      install with an existing profiles.gitconfig (copied in place)
#   ./setup.sh --no-shell           do not touch shell rc files (then put bin/ first on PATH yourself)
#   ./setup.sh --uninstall          remove the links, the ~/.gitconfig include and the rc block (keeps your config)
#
# Bash 3.2 compatible (macOS default); needs only git.

set -euo pipefail

SKILL_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CANONICAL="$HOME/.agents/skills/git-profile"
BIN_DIR="$HOME/.local/bin"
CONFIG="${GIT_PROFILE_CONFIG:-$HOME/.config/git-profile/profiles.gitconfig}"
GENERATED="$(dirname "$CONFIG")/generated.gitconfig"
# Harness skill dirs that get a link to the canonical copy, when the harness is installed.
HARNESS_SKILL_DIRS="$HOME/.claude/skills $HOME/.codex/skills"
# The gh wrapper dir must come before the real gh on PATH, in login and interactive shells alike
# (agent harnesses often run `zsh -lc`, which reads .zprofile but not .zshrc).
WRAPPER_DIR="$CANONICAL/bin"
RC_BEGIN="# >>> git-profile >>>"
RC_END="# <<< git-profile <<<"

rc_files() {
    case "$(basename "${SHELL:-bash}")" in
        zsh) echo "$HOME/.zprofile $HOME/.zshrc" ;;
        *) echo "$HOME/.bash_profile $HOME/.bashrc" ;;
    esac
}

strip_rc_block() {
    local f="$1" tmp
    [[ -f "$f" ]] && grep -qxF "$RC_BEGIN" "$f" || return 0
    tmp=$(mktemp)
    awk -v b="$RC_BEGIN" -v e="$RC_END" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$f" > "$tmp"
    cat "$tmp" > "$f" && rm -f "$tmp"
}

install_rc_block() {
    local f
    for f in $(rc_files); do
        strip_rc_block "$f"
        # Re-prepend even when already on PATH, so it stays ahead of anything (brew shellenv) added earlier.
        printf '\n%s\n_gp_bin="%s"\nexport PATH="$_gp_bin:${PATH//$_gp_bin:/}"\nunset _gp_bin\n%s\n' \
            "$RC_BEGIN" "$WRAPPER_DIR" "$RC_END" >> "$f"
        say "PATH block (gh wrapper first) in $f"
    done
}

say() { printf '  %s\n' "$*"; }
die() { echo "setup: $*" >&2; exit 1; }

link() {
    local target="$1" name="$2"
    if [[ -e "$name" && ! -L "$name" ]]; then
        say "skip $name (exists and is not a link)"
        return
    fi
    ln -sfn "$target" "$name"
    say "link $name -> $target"
}

uninstall() {
    local d
    rm -f "$BIN_DIR/git-profile" && say "removed $BIN_DIR/git-profile"
    for d in $HARNESS_SKILL_DIRS; do
        [[ -L "$d/git-profile" ]] && rm -f "$d/git-profile" && say "removed $d/git-profile"
    done
    if git config --global --get-all include.path 2>/dev/null | grep -qxF "$GENERATED"; then
        git config --global --fixed-value --unset include.path "$GENERATED"
        git config --global --get-all include.path >/dev/null 2>&1 || git config --global --remove-section include 2>/dev/null || true
        local tmp
        tmp=$(mktemp)
        grep -vxF '# git-profile: keep this include LAST' "$HOME/.gitconfig" > "$tmp" || true
        cat "$tmp" > "$HOME/.gitconfig" && rm -f "$tmp"
        say "removed the include from ~/.gitconfig"
    fi
    # Keep commits working: write the active profile back as the plain global identity.
    if [[ -f "$CONFIG" ]]; then
        local act k v
        act=$(git config -f "$CONFIG" git-profile.active 2>/dev/null || true)
        if [[ -n "$act" ]]; then
            for k in name email signingkey; do
                v=$(git config -f "$CONFIG" "profile.$act.$k" 2>/dev/null || true)
                [[ -n "$v" ]] && git config --global "user.$k" "$v"
            done
            say "set the global identity to profile '$act'"
        fi
    fi
    local f
    for f in $HOME/.zprofile $HOME/.zshrc $HOME/.bash_profile $HOME/.bashrc; do
        grep -qxF "$RC_BEGIN" "$f" 2>/dev/null && strip_rc_block "$f" && say "removed the PATH block from $f"
    done
    say "kept $CONFIG"
}

ask() {
    local prompt="$1" var
    read -r -p "  $prompt: " var
    [[ -n "$var" ]] || die "$prompt is required"
    printf '%s' "$var"
}

write_first_config() {
    mkdir -p "$(dirname "$CONFIG")"
    if [[ -t 0 ]]; then
        echo "No config at $CONFIG. Create the first (default) profile:"
        local name email
        name=$(ask "git user.name")
        email=$(ask "git user.email")
        cp "$SKILL_SRC/profiles.example.gitconfig" "$CONFIG"
        # Keep the example's comments; replace its placeholder profiles with the real one.
        git config -f "$CONFIG" --remove-section 'profile.default' 2>/dev/null || true
        git config -f "$CONFIG" --remove-section 'profile.work' 2>/dev/null || true
        git config -f "$CONFIG" git-profile.active default
        git config -f "$CONFIG" profile.default.name "$name"
        git config -f "$CONFIG" profile.default.email "$email"
        say "wrote $CONFIG; add more with: git-profile add <name> --name N --email E"
    else
        cp "$SKILL_SRC/profiles.example.gitconfig" "$CONFIG"
        say "wrote the example config to $CONFIG"
        say "edit it, then run: git-profile init"
        return 1
    fi
}

main() {
    local src_config="" shell_rc=1
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --uninstall) uninstall; exit 0 ;;
            --no-shell) shell_rc=0; shift ;;
            --config) src_config="${2:-}"; [[ -f "$src_config" ]] || die "--config needs a file"; shift 2 ;;
            -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
            *) die "unknown option $1" ;;
        esac
    done
    command -v git >/dev/null || die "git is not installed"

    echo "Installing git-profile from $SKILL_SRC"
    chmod +x "$SKILL_SRC/scripts/git-profile" "$SKILL_SRC/bin/gh"

    # One canonical copy under ~/.agents/skills, linked into each harness.
    if [[ "$SKILL_SRC" != "$(cd "$CANONICAL" 2>/dev/null && pwd -P)" ]]; then
        mkdir -p "$(dirname "$CANONICAL")"
        link "$SKILL_SRC" "$CANONICAL"
    fi
    local d
    for d in $HARNESS_SKILL_DIRS; do
        [[ -d "$(dirname "$d")" ]] || continue
        mkdir -p "$d"
        link "$CANONICAL" "$d/git-profile"
    done
    mkdir -p "$BIN_DIR"
    link "$CANONICAL/scripts/git-profile" "$BIN_DIR/git-profile"

    if [[ $shell_rc == 1 ]]; then
        install_rc_block
    else
        say "skipped shell rc; put $WRAPPER_DIR first on PATH for per-dir gh accounts"
    fi

    if [[ -n "$src_config" ]]; then
        mkdir -p "$(dirname "$CONFIG")"
        [[ -f "$CONFIG" ]] && cp -p "$CONFIG" "$CONFIG.bak" && say "backed up the old config to $CONFIG.bak"
        cp "$src_config" "$CONFIG"
        say "copied $src_config -> $CONFIG"
    elif [[ ! -f "$CONFIG" ]]; then
        write_first_config || exit 0
    else
        say "keeping existing $CONFIG"
    fi

    "$BIN_DIR/git-profile" init | sed 's/^/  /'

    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *) say "NOTE: $BIN_DIR is not on PATH; add to your shell rc: export PATH=\"\$PATH:$BIN_DIR\"" ;;
    esac
    command -v gh >/dev/null 2>&1 && say "gh accounts: add \`gh = <github-user>\` to a profile and log each in with \`gh auth login\`"
    echo "Done. Open a new shell, then try: git-profile list"
}

main "$@"
