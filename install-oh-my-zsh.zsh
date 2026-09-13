#!/usr/bin/env zsh
#
# install-oh-my-zsh.zsh — install Oh My Zsh.
#
# Standalone: run it on its own, independently from the rest of the setup process.
#
# Usage:
#   ./install-oh-my-zsh.zsh        # install; no-ops whatever is already in place
#
# What it does (in order; every step is attempted and idempotent):
#   1. If ~/.oh-my-zsh is missing, runs the official Oh My Zsh installer:
#         ZSH= curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh \
#           | ZSH= sh -s -- --unattended
#      (no interactive prompts). Two deliberate details:
#       * ZSH is unset for the call — in an Oh My Zsh shell $ZSH is
#         exported and the installer aborts with '$ZSH folder already
#         exists' unless it is.
#       * On a machine with an EXISTING ~/.zshrc, the official installer
#         renames it to ~/.zshrc.pre-oh-my-zsh and writes its default
#         template — that is standard Oh My Zsh behavior, not something
#         this script adds.
#   2. Configures plugins in ~/.zshrc and drops redundant activation
#      lines:
#       * rewrites the plugins block to contain exactly the plugins
#         in $ZSH_PLUGINS (default: aws brew cdk gh git mise node
#         podman — alphabetical, one per line, the OMZ style),
#         replacing any existing block in place, or appending one if
#         none exists;
#       * removes the standalone activation lines the installers append
#         — `eval "$(/opt/homebrew/bin/brew shellenv ...)"` (from the
#         Homebrew installer) and `eval "$($HOME/.local/bin/mise activate
#         zsh)" ...` (from the mise installer) — from ~/.zshrc and
#         ~/.zprofile; each file is checked and a line may be absent.
#         The OMZ brew and mise plugins put Homebrew on PATH and
#         activate mise themselves, so those lines are redundant.
#
# Design notes:
#   * Arch-aware (Apple Silicon vs Intel) — detected at runtime.
#   * Idempotent: safe to re-run; each step no-ops if already done, and a
#     re-run never rewrites ~/.zshrc / ~/.zprofile unless the plugins
#     block or an activation line actually differs.
#   * The network installer is the only external call; no sudo.
#   * After installation, open a NEW terminal (or 'source ~/.zshrc').
#   * See install-powerlevel10k.zsh for the matching theme setup (fonts,
#     Terminal.app profile, p10k clone, ZSH_THEME) — run this script
#     first so ~/.oh-my-zsh/custom exists.
#
source "${0:A:h}/common.zsh"

# -------------------------------------------------------------------------
# Globals
# -------------------------------------------------------------------------
OMZ_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
ZSHRC="${HOME}/.zshrc"


# =========================================================================
# Step 1 — Oh My Zsh
# =========================================================================
omz_installed() {
    [ -d "${HOME}/.oh-my-zsh" ]
}

install_oh_my_zsh() {
    say "Install Oh My Zsh"
    if omz_installed; then
        ok "Oh My Zsh already installed: ${HOME}/.oh-my-zsh"
        return 0
    fi
    info "Running the official installer (unattended):"
    info "  ZSH= curl -fsSL \"$OMZ_INSTALL_URL\" | ZSH= sh -s -- --unattended"
    # ZSH must be unset: an Oh My Zsh shell exports it, and the installer
    # treats a non-empty $ZSH as 'already installed elsewhere' and aborts.
    ZSH= curl -fsSL "$OMZ_INSTALL_URL" | ZSH= sh -s -- --unattended
    if ! omz_installed; then
        warn "Installer ran but ~/.oh-my-zsh is still missing. Check its output above."
        return 1
    fi
    ok "Oh My Zsh installed."
}


# =========================================================================
# Step 2 — plugins in $ZSHRC; drop the redundant brew/mise activation lines
# =========================================================================
# The OMZ brew and mise plugins put Homebrew on PATH and activate mise
# themselves, so the standalone activation lines the installers append
# are redundant once the plugins load. This step:
#   * makes the plugins block exactly the list in $ZSH_PLUGINS
#     (unquoted, 4-space indent, one per line — the OMZ style). Any
#     existing block is replaced in place — both the single-line form
#     `plugins=(git)` and the multi-line form; if none exists, one is
#     appended at EOF. A file whose block already is this is left
#     byte-identical (idempotent re-run).
#   * removes the brew and mise activation lines from $ZSHRC and
#     $PROFILE_FILE — the installer may have put each in either file.
#     Either line may be absent; that is not an error.

# The exact plugin list $ZSHRC must contain (kept alphabetical).
ZSH_PLUGINS=(aws brew cdk gh git mise node podman)
PROFILE_FILE="${HOME}/.zprofile"
# Only ACTIVE lines are matched (a line the user commented out is left
# alone). Matches the Homebrew installer line, any brew path:
#     eval "$(/opt/homebrew/bin/brew shellenv zsh)"
BREW_ACTIVATE_RE='^[[:space:]]*eval[[:space:]]+"\$\(/[^)]*brew shellenv[^)]*\)".*$'
# Matches the mise installer line, any mise path, trailing comment
# allowed:
#     eval "$($HOME/.local/bin/mise activate zsh)" # added by https://mise.run/zsh
MISE_ACTIVATE_RE='^[[:space:]]*eval[[:space:]]+"\$\([^)]*mise activate[^)]*\)".*$'

# Print the plugins block of $1 verbatim, from the opening
# plugins=(... line through the line that closes it. Returns 1 when the
# file has no plugins block at all.
plugin_block_text() {
    local file="$1" line found=0
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$found" -eq 0 ]; then
            [[ "$line" =~ ^[[:space:]]*plugins[[:space:]]*= ]] || continue
            found=1
            printf '%s\n' "$line"
            [[ "$line" == *")"* ]] && return 0
            continue
        fi
        printf '%s\n' "$line"
        [[ "$line" == *")"* ]] && return 0
    done < "$file"
    return 1
}

# Remove every line of $2 matching the ERE in $1 (only if present).
strip_lines_matching() {
    local re="$1" file="$2"
    [ -f "$file" ] || return 0
    if ! grep -qE "$re" "$file"; then
        return 0
    fi
    local tmp="${file}.tmp"
    grep -vE "$re" "$file" > "$tmp" || true
    mv "$tmp" "$file"
}

set_zsh_plugins() {
    say "Configure plugins in $ZSHRC: ${ZSH_PLUGINS[*]}"
    if [ ! -f "$ZSHRC" ]; then
        error "$ZSHRC not found — cannot configure plugins (Oh My Zsh should have created it)."
        return 1
    fi

    local cur want
    cur="$(plugin_block_text "$ZSHRC")" || cur="__no_block__"
    want="$(
        printf 'plugins=('
        for p in "${ZSH_PLUGINS[@]}"; do
            printf '\n    %s' "$p"
        done
        printf '\n)'
    )"
    if [ "$cur" = "$want" ]; then
        ok "Plugins already ${ZSH_PLUGINS[*]}."
        return 0
    fi

# $want (above) holds the exact block to write (OMZ style:
# multi-line, 4-space indent).

    if grep -qE '^[[:space:]]*plugins[[:space:]]*=' "$ZSHRC"; then
        # Replace the existing block in place (single- or multi-line form).
        local line out
        out="$(
            local inblk=0
            while IFS= read -r line || [ -n "$line" ]; do
                if [ "$inblk" -eq 0 ]; then
                    if [[ "$line" =~ ^[[:space:]]*plugins[[:space:]]*= ]]; then
                        inblk=1
                        printf '%s\n' "$want"
                        [[ "$line" == *")"* ]] && inblk=2
                    else
                        printf '%s\n' "$line"
                    fi
                    continue
                fi
                if [ "$inblk" -eq 1 ]; then
                    # inside the old block — skip until its close line
                    [[ "$line" == *")"* ]] && inblk=2
                    continue
                fi
                printf '%s\n' "$line"
            done < "$ZSHRC"
        )"
        printf '%s\n' "$out" > "$ZSHRC"
        ok "Plugins were ${cur//\$'\n'/ /} — now: ${ZSH_PLUGINS[*]}."
    else
        # No plugins block — append one.
        printf '\n%s\n' "$want" >> "$ZSHRC"
        ok "No plugins block found — appended plugins: ${ZSH_PLUGINS[*]}."
    fi
}

set_zsh_plugins_step() {
    set_zsh_plugins || return 1

    say "Remove the brew/mise activation lines (the OMZ plugins handle PATH/activation now)"
    local f re
    local total=0
    for f in "$ZSHRC" "$PROFILE_FILE"; do
        [ -f "$f" ] || continue
        for re in "$BREW_ACTIVATE_RE" "$MISE_ACTIVATE_RE"; do
            if grep -qE "$re" "$f"; then
                strip_lines_matching "$re" "$f"
                total=$((total+1))
                info "Removed the matching activation line from ${f#~/}."
            fi
        done
    done
    if [ "$total" -eq 0 ]; then
        ok "No brew/mise activation lines found — nothing to remove."
    fi
    return 0
}

# =========================================================================
# Main
# =========================================================================
main() {
    install_oh_my_zsh
    set_zsh_plugins_step
    say "Oh My Zsh setup complete."
    info "Open a new terminal (or 'source $ZSHRC') to load the theme."
}

main "$@"
