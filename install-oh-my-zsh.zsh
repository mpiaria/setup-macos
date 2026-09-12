#!/usr/bin/env zsh
#
# install-oh-my-zsh.zsh — install Oh My Zsh and the powerlevel10k theme.
#
# Standalone: run it on its own, independently from the rest of the setup process.
#
# Usage:
#   ./install-oh-my-zsh.zsh        # install both; no-ops whatever is already in place
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
#   2. Installs the MesloLGS NF fonts powerlevel10k needs (all four
#      styles), which the p10k docs list as a requirement:
#        brew install --cask font-meslo-for-powerlevel10k
#      Homebrew's cask ships exactly the files from the p10k "Meslo Nerd
#      Font patched for powerlevel10k" section:
#        MesloLGS NF Regular.ttf / Bold.ttf / Italic.ttf / Bold Italic.ttf
#      Installed into ~/Library/Fonts. This is a HARD dependency: if
#      Homebrew is missing or the install fails, the script fails.
#   3. Configures Terminal.app, right after the fonts are in place by
#      setting three things, each applied on every run and read back to
#      verify:
#       * the default profile for future windows:
#           tell application "Terminal" to set default settings to settings set "Pro"
#       * the profile of window 1 (the window the script runs in):
#           tell application "Terminal" to set current settings of window 1 to settings set "Pro"
#       * the Pro profile's font to MesloLGS NF at 12pt (a binary NSFont
#         blob only the AppleScript API can write).
#     The profile writes ASSIGN the Pro profile object — never
#     `set name of default settings to "Pro"`, which would RENAME the
#     current default profile to "Pro" instead of switching to it. The
#     user runs the script from Terminal.app, so Terminal is assumed to
#     be open (and never quit); the macOS 26 (Tahoe) spellings ("default
#     settings") are tried first, with the older "default settings set"
#     as fallback.
#   4. Clones the powerlevel10k theme if not already there, exactly per
#      the official instructions:
#         git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
#           "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
#   5. Finds the ZSH_THEME line in ~/.zshrc and sets its value to
#      "powerlevel10k/powerlevel10k" (appends the line if none exists).
#   6. Configures plugins in ~/.zshrc and drops redundant activation
#      lines:
#       * rewrites the plugins block to contain exactly brew, git, mise
#         (alphabetical, one per line, the OMZ style), replacing any
#         existing block in place, or appending one if none exists;
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
#     re-run never rewrites ~/.zshrc / ~/.zprofile unless the ZSH_THEME
#     value, the plugins block, or an activation line actually differs.
#   * git is required (from the Command Line Tools); no sudo.
#   * Homebrew is REQUIRED: the script fails without it after the fonts
#     step (unless all four fonts are already installed).
#   * After installation, open a NEW terminal (or 'source ~/.zshrc').
#     p10k will run its configuration prompt on first load — or add
#     POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true to skip it.
#
source "${0:A:h}/common.zsh"

# -------------------------------------------------------------------------
# Globals
# -------------------------------------------------------------------------
OMZ_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
P10K_REPO="https://github.com/romkatv/powerlevel10k.git"
ZSHRC="${HOME}/.zshrc"
P10K_THEME='powerlevel10k/powerlevel10k'
MESLO_FONTS_CASK="font-meslo-for-powerlevel10k"
MESLO_FONTS_DIR="${HOME}/Library/Fonts"
MESLO_FONTS=(
    "MesloLGS NF Regular.ttf"
    "MesloLGS NF Bold.ttf"
    "MesloLGS NF Italic.ttf"
    "MesloLGS NF Bold Italic.ttf"
)
TERMINAL_DOMAIN="com.apple.Terminal"
TERMINAL_PROFILE="Pro"
# The family name Terminal's AppleScript API wants for `set font`.
# Read back, the profile's font face is spelled e.g. "MesloLGS-NF-Regular".
TERMINAL_FONT_FAMILY="MesloLGS NF"
TERMINAL_FONT_MARKER="MesloLGS-NF"
TERMINAL_FONT_SIZE=12


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
# Step 2 — MesloLGS NF fonts (powerlevel10k requirement)
# =========================================================================
# True only if ALL four font files are present in ~/Library/Fonts.
# Checking the files (not 'brew list --cask') means this also succeeds on
# machines where the fonts were installed without Homebrew.
fonts_installed() {
    local f
    for f in "${MESLO_FONTS[@]}"; do
        [ -f "${MESLO_FONTS_DIR}/${f}" ] || return 1
    done
    return 0
}

install_fonts() {
    say "Install the MesloLGS NF fonts (powerlevel10k requirement)"
    if fonts_installed; then
        ok "All four MesloLGS NF fonts already present in ${MESLO_FONTS_DIR}."
        return 0
    fi
    # HARD dependency: no brew, or a failed cask install, aborts the script.
    if ! command -v brew >/dev/null 2>&1; then
        error "Homebrew is required to install the fonts, but brew was not found. Install it first (./install-homebrew.zsh) and re-run this script."
        return 1
    fi
    info "Installing cask '$MESLO_FONTS_CASK' (installs all four styles)..."
    if ! brew install --cask "$MESLO_FONTS_CASK"; then
        error "brew install --cask $MESLO_FONTS_CASK failed — see the error above and re-run this script."
        return 1
    fi
    if ! fonts_installed; then
        error "Cask install succeeded but not all four fonts were found in ${MESLO_FONTS_DIR}."
        return 1
    fi
    ok "MesloLGS NF fonts installed."
}

# =========================================================================
# Step 3 — Terminal.app: default profile Pro, window 1 Pro, Pro font
# =========================================================================
# Assumes the user runs this from Terminal.app: Terminal is open and
# window 1 is the window the script runs in. Every setting is applied on
# EVERY run (each `set` is harmless when the value is already right) and
# read back afterwards, so success is verified, never assumed. The script
# NEVER quits Terminal.

# Face name read back from the API for a MesloLGS NF font, e.g.
# "MesloLGS-NF-Regular".
_terminal_font_face() {
    osascript -e "tell application \"Terminal\" to get (font of settings set \"${TERMINAL_PROFILE}\") as text" 2>/dev/null || true
}
_terminal_font_size() {
    osascript -e "tell application \"Terminal\" to get font size of settings set \"${TERMINAL_PROFILE}\"" 2>/dev/null || true
}

# Set the font family (family name in; Terminal serializes the NSFont
# blob into the plist itself — 'defaults' cannot write that value).
_terminal_set_font() {
    osascript -e "tell application \"Terminal\" to set font of settings set \"${TERMINAL_PROFILE}\" to \"${TERMINAL_FONT_FAMILY}\""
}
_terminal_set_font_size() {
    osascript -e "tell application \"Terminal\" to set font size of settings set \"${TERMINAL_PROFILE}\" to ${TERMINAL_FONT_SIZE}"
}

# --- default profile helpers -------------------------------------------------
# Terminal keeps the current default profile in the RUNNING app: an
# external `defaults write` of "Default Window Settings" only touches the
# plist, which the app ignores (and rewrites from memory on quit). So the
# default must be set in-app — by assigning the Pro settings-set OBJECT
# (`set default settings to settings set "Pro"`), NEVER by
# `set name of default settings to "Pro"`: AppleScript sets the NAME
# property of whatever profile is the default, so it RENAMEs the current
# default profile (an early draft of this did exactly that on a fresh
# Mac, turning the stock "Basic" into a duplicate "Pro").
#
# macOS 26 (Tahoe) renamed the property "default settings set" (older) to
# "default settings" ("set" became a reserved word, so the old spelling
# is a hard -2740 syntax error there); try the new spelling, fall back to
# the old. The profile reference `settings set "Pro"` parses on both.
_terminal_profile_exists() {
    [ -n "$(osascript -e "tell application \"Terminal\" to get name of (settings set \"${TERMINAL_PROFILE}\")" 2>/dev/null)" ]
}
_terminal_default_profile() {
    local v
    if v="$(osascript -e 'tell application "Terminal" to get name of default settings' 2>/dev/null)"; then
        printf '%s' "$v"
        return
    fi
    osascript -e 'tell application "Terminal" to get name of default settings set' 2>/dev/null || true
}
# Profile in use by window 1 — the window this script runs in. "" when the
# app is unreachable or has no windows.
_terminal_window_profile() {
    osascript -e "tell application \"Terminal\" to get name of (current settings of window 1)" 2>/dev/null || true
}
# Make Pro the app-level default (new spelling, then old — see note at
# the top of this step). Refuses before writing if there is no Pro
# profile (otherwise the object assignment fails anyway).
_terminal_set_default_profile() {
    _terminal_profile_exists || return 1
    osascript -e "tell application \"Terminal\" to set default settings to settings set \"${TERMINAL_PROFILE}\"" \
        || osascript -e "tell application \"Terminal\" to set default settings set to settings set \"${TERMINAL_PROFILE}\""
}
# Switch window 1 (the script's own window) to Pro.
_terminal_set_window1_profile() {
    osascript -e "tell application \"Terminal\" to set current settings of window 1 to settings set \"${TERMINAL_PROFILE}\""
}

configure_terminal() {
    say "Configure Terminal.app (default ${TERMINAL_PROFILE}, window 1 ${TERMINAL_PROFILE}, font ${TERMINAL_FONT_FAMILY} ${TERMINAL_FONT_SIZE}pt)"

    # 1. Default profile for future windows — assign the Pro profile
    # OBJECT (never `set name of default settings ...`, which would
    # RENAME the current default instead of switching it).
    if ! _terminal_set_default_profile; then
        error "Could not make ${TERMINAL_PROFILE} the default profile (no ${TERMINAL_PROFILE} profile in Terminal's Preferences?)."
        return 1
    fi
    local checked
    checked="$(_terminal_default_profile)"
    if [ "$checked" = "$TERMINAL_PROFILE" ]; then
        ok "Default profile is ${TERMINAL_PROFILE}."
    else
        warn "Default profile set, but read-back reports '${checked:-<unknown>}'."
        return 1
    fi

    # 2. This window (window 1, where the script runs) -> Pro, so the new
    # settings apply without opening another window.
    if ! _terminal_set_window1_profile; then
        error "Could not set window 1's profile to ${TERMINAL_PROFILE}."
        return 1
    fi
    checked="$(_terminal_window_profile)"
    if [ "$checked" = "$TERMINAL_PROFILE" ]; then
        ok "Window 1 profile is ${TERMINAL_PROFILE}."
    else
        warn "Window 1 profile set, but read-back reports '${checked:-<unknown>}'. Open a new window to pick up the default."
    fi

    # 3. Font on the Pro profile — Terminal stores it as a binary NSFont
    # blob that only the AppleScript API can write, so go through it.
    local face size
    face="$(_terminal_font_face)"
    size="$(_terminal_font_size)"
    info "Setting ${TERMINAL_PROFILE} font to ${TERMINAL_FONT_FAMILY} ${TERMINAL_FONT_SIZE}pt (was: ${face:-unknown} / ${size:-unknown}pt)..."
    if ! _terminal_set_font; then
        error "Terminal refused the font change (is there a ${TERMINAL_PROFILE} profile?)."
        return 1
    fi
    if ! _terminal_set_font_size; then
        error "Terminal refused the font-size change."
        return 1
    fi
    face="$(_terminal_font_face)"
    size="$(_terminal_font_size)"
    if [[ "$face" == *"$TERMINAL_FONT_MARKER"* ]] && [ "$size" = "$TERMINAL_FONT_SIZE" ]; then
        ok "${TERMINAL_PROFILE} font is ${TERMINAL_FONT_FAMILY} ${TERMINAL_FONT_SIZE}pt."
    else
        warn "Font set, but read-back reports '${face:-<unknown>}' / ${size:-unknown}pt."
        return 1
    fi
}


# =========================================================================
# Step 4 — powerlevel10k theme
# =========================================================================
p10k_installed() {
    [ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]
}

install_powerlevel10k() {
    say "Install the powerlevel10k theme"
    if p10k_installed; then
        ok "powerlevel10k already installed:"
        info "   ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
        return 0
    fi
    if ! command -v git >/dev/null 2>&1; then
        warn "git not found — install the Command Line Tools first (./install-command-line-tools.zsh)."
        return 1
    fi
    info "Cloning powerlevel10k (depth 1)..."
    git clone --depth=1 "$P10K_REPO" "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if ! p10k_installed; then
        warn "git clone finished but the theme directory is missing. Check its output above."
        return 1
    fi
    ok "powerlevel10k installed."
}

# =========================================================================
# Step 5 — point ZSH_THEME at powerlevel10k
# =========================================================================
# True if ~/.zshrc already sets ZSH_THEME to the powerlevel10k value,
# in either quote style — matching both keeps a re-run byte-clean even
# when the user quoted the line differently.
theme_already_set() {
    [ -f "$ZSHRC" ] && grep -qE "^[[:space:]]*ZSH_THEME[[:space:]]*=[\"']${P10K_THEME}[\"']" "$ZSHRC"
}

set_zsh_theme() {
    say "Configure ZSH_THEME in $ZSHRC"
    if theme_already_set; then
        ok "ZSH_THEME is already \"$P10K_THEME\"."
        return 0
    fi

    # A real ZSH_THEME line exists (any value) -> replace the first one.
    if [ -f "$ZSHRC" ] && grep -qE '^[[:space:]]*ZSH_THEME[[:space:]]*=' "$ZSHRC"; then
        local line out
        out="$(
            local replaced=0
            while IFS= read -r line || [ -n "$line" ]; do
                if (( !replaced )) && [[ "$line" =~ ^[[:space:]]*ZSH_THEME[[:space:]]*= ]]; then
                    printf 'ZSH_THEME="%s"\n' "$P10K_THEME"
                    replaced=1
                else
                    printf '%s\n' "$line"
                fi
            done < "$ZSHRC"
        )"
        printf '%s\n' "$out" > "$ZSHRC"
        ok "Replaced the existing ZSH_THEME line with \"$P10K_THEME\"."
    else
        # No ZSH_THEME line (or no ~/.zshrc) — append one.
        printf '\nZSH_THEME="%s"\n' "$P10K_THEME" >> "$ZSHRC"
        ok "No ZSH_THEME line found — appended ZSH_THEME=\"$P10K_THEME\"."
    fi
}


# =========================================================================
# Step 6 — plugins in $ZSHRC; drop the redundant brew/mise activation lines
# =========================================================================
# The OMZ brew and mise plugins put Homebrew on PATH and activate mise
# themselves, so the standalone activation lines the installers append
# are redundant once the plugins load. This step:
#   * makes the plugins block exactly:
#       plugins=(
#           brew
#           git
#           mise
#       )
#     (alphabetical, unquoted, 4-space indent — the OMZ style). Any
#     existing block is replaced in place — both the single-line form
#     `plugins=(git)` and the multi-line form; if none exists, one is
#     appended at EOF. A file whose block already is this is left
#     byte-identical (idempotent re-run).
#   * removes the brew and mise activation lines from $ZSHRC and
#     $PROFILE_FILE — the installer may have put each in either file.
#     Either line may be absent; that is not an error.

# The exact plugin list $ZSHRC must contain (kept alphabetical).
ZSH_PLUGINS=(brew git mise)
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
    install_fonts
    configure_terminal
    install_powerlevel10k
    set_zsh_theme
    set_zsh_plugins_step
    say "Oh My Zsh setup complete."
    info "Open a new terminal (or 'source $ZSHRC') to load the theme."
}

main "$@"
