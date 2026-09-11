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
#   3. Configures Terminal.app, right after the fonts are in place:
#       * sets the default profile to Pro
#         (com.apple.Terminal "Default Window Settings")
#       * sets the Pro profile's font to MesloLGS NF at 12pt
#     The font can only be written through Terminal's AppleScript API
#     (it's a binary blob inside the plist, not a settable string), which
#     means Terminal.app is momentarily LAUNCHED for reads/writes. It is
#     quit again when done if the script started it, leaving the machine
#     as it was found.
#   4. Clones the powerlevel10k theme if not already there, exactly per
#      the official instructions:
#         git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
#           "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
#   5. Finds the ZSH_THEME line in ~/.zshrc and sets its value to
#      "powerlevel10k/powerlevel10k" (appends the line if none exists).
#
# Design notes:
#   * Arch-aware (Apple Silicon vs Intel) — detected at runtime.
#   * Idempotent: safe to re-run; each step no-ops if already done and a
#     re-run never rewrites ~/.zshrc unless the ZSH_THEME value differs.
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
# Step 3 — Terminal.app: default profile Pro, Pro profile font MesloLGS NF
# =========================================================================
# Launch-state helpers: Terminal.app must be quit again if THIS STEP is
# what launched it — never an app the user had running.
_terminal_was_running() {
    pgrep -x Terminal >/dev/null 2>&1
}
_terminal_quit() {
    osascript -e 'tell application "Terminal" to quit' >/dev/null 2>&1 || true
}

# Face name read back from the API for a MesloLGS NF font, e.g.
# "MesloLGS-NF-Regular". (Calling this launches Terminal when it is
# closed — the caller accounts for that.)
_terminal_font_face() {
    osascript -e "tell application \"Terminal\" to get (font of settings set \"${TERMINAL_PROFILE}\") as text" 2>/dev/null || true
}
_terminal_font_already_set() {
    [[ "$(_terminal_font_face)" == *"$TERMINAL_FONT_MARKER"* ]]
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

terminal_default_profile() {
    defaults read "$TERMINAL_DOMAIN" "Default Window Settings" 2>/dev/null || true
}

configure_terminal() {
    say "Configure Terminal.app (default profile ${TERMINAL_PROFILE}, font ${TERMINAL_FONT_FAMILY} ${TERMINAL_FONT_SIZE}pt)"

    # --- part 1: default profile — plain string, set via 'defaults'
    # without launching Terminal at all.
    local current
    current="$(terminal_default_profile)"
    if [ "$current" = "$TERMINAL_PROFILE" ]; then
        ok "Default profile is already ${TERMINAL_PROFILE}."
    else
        info "Default profile was '${current:-<unset>}' — switching to ${TERMINAL_PROFILE}."
        defaults write "$TERMINAL_DOMAIN" "Default Window Settings" -string "$TERMINAL_PROFILE"
        ok "Default profile set to ${TERMINAL_PROFILE}."
    fi

    # --- part 2: the Pro profile's font — AppleScript API only, which
    # means Terminal launches for reads/writes; quit it afterwards if
    # this step is what launched it.
    local was_running=0
    if _terminal_was_running; then
        was_running=1
    fi

    local face size
    face="$(_terminal_font_face)"
    if [[ "$face" != *"$TERMINAL_FONT_MARKER"* ]]; then
        info "Setting ${TERMINAL_PROFILE} font to ${TERMINAL_FONT_FAMILY} ${TERMINAL_FONT_SIZE}pt (was: ${face:-none})..."
        if ! _terminal_set_font; then
            (( was_running )) || _terminal_quit
            error "Terminal refused the font change (is there a ${TERMINAL_PROFILE} profile?)."
            return 1
        fi
        if ! _terminal_set_font_size; then
            (( was_running )) || _terminal_quit
            error "Terminal refused the font-size change."
            return 1
        fi
        ok "${TERMINAL_PROFILE} font is now ${TERMINAL_FONT_FAMILY} ${TERMINAL_FONT_SIZE}pt."
    else
        size="$(_terminal_font_size)"
        if [ "${size:-0}" != "$TERMINAL_FONT_SIZE" ]; then
            if ! _terminal_set_font_size; then
                (( was_running )) || _terminal_quit
                error "Terminal refused the font-size change."
                return 1
            fi
            ok "${TERMINAL_PROFILE} font size adjusted to ${TERMINAL_FONT_SIZE}pt (was ${size:-unknown})."
        else
            ok "${TERMINAL_PROFILE} font is already ${TERMINAL_FONT_FAMILY} ${TERMINAL_FONT_SIZE}pt."
        fi
    fi

    # Leave the machine as found: if this step launched Terminal, close it.
    (( was_running )) || _terminal_quit
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
# Main
# =========================================================================
main() {
    install_oh_my_zsh
    install_fonts
    configure_terminal
    install_powerlevel10k
    set_zsh_theme
    say "Oh My Zsh setup complete."
    info "Open a new terminal (or 'source $ZSHRC') to load the theme."
}

main "$@"
