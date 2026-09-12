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
#       * sets the Pro profile's font to MesloLGS NF at 12pt
#     Both go through Terminal's AppleScript API. The default profile in
#     particular is NOT just a plist string: a running Terminal keeps
#     "Default Window Settings" in memory, where an external 'defaults
#     write' is ignored (and the app rewrites the plist on exit), so the
#     default is set in-app and read back for verification. macOS 26
#     (Tahoe) also renamed the AppleScript property from "default
#     settings set" to "default settings" (and 'set' became a reserved
#     word), so the script tries the new spelling and falls back to the
#     old one. The API launches Terminal when it is closed; the script
#     NEVER quits it: the user runs it from a terminal, and process
#     detection is unreliable (e.g. 'pgrep -x Terminal' can miss a
#     running Terminal on recent macOS), so quitting is not worth the
#     risk of closing a window the user had open.
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
# The font can only be written through Terminal's AppleScript API, which
# LAUNCHES Terminal if it is closed. That is acceptable, but the script
# NEVER quits Terminal afterwards: the user runs it from a terminal, and
# launch-state detection is unreliable (e.g. 'pgrep -x Terminal' can miss
# a running Terminal on recent macOS), so quitting risks closing a window
# the user had open.

# Face name read back from the API for a MesloLGS NF font, e.g.
# "MesloLGS-NF-Regular". (Calling this launches Terminal when it is
# closed — that is fine; see the note atop this step.)
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

# --- default profile helpers ---------------------------------------------
# A RUNNING Terminal keeps "Default Window Settings" as a live in-memory
# value: an external 'defaults write' changes the plist but NOT what the
# launch app uses (and it writes its value back over the plist on exit).
# So the default must be read and written through the app itself.
#
# The AppleScript property was renamed in macOS 26 (Tahoe): "default
# settings set" (older) -> "default settings". "set" has become a reserved
# word there, so the OLD name is a hard syntax error on new systems and
# the NEW name is unknown to older ones — try new first, fall back to old.
# The font calls above keep 'settings set "Pro"' because THAT spelling is
# still valid on both.
_terminal_default_profile() {
    local v
    if v="$(osascript -e 'tell application "Terminal" to get name of default settings' 2>/dev/null)"; then
        printf '%s' "$v"
        return
    fi
    osascript -e 'tell application "Terminal" to get name of default settings set' 2>/dev/null || true
}
# Writes in-app; falls back to the plist when Terminal cannot be reached
# at all (e.g. launchd is wedged). Returns 1 on failure.
_terminal_set_default_profile() {
    local name="$1"
    osascript -e "tell application \"Terminal\" to set name of default settings to \"${name}\"" \
        || osascript -e "tell application \"Terminal\" to set name of default settings set to \"${name}\"" \
        || {
            local before
            before="$(defaults read "$TERMINAL_DOMAIN" "Default Window Settings" 2>/dev/null || true)"
            [ "${before:-}" = "$name" ] && return 0
            defaults write "$TERMINAL_DOMAIN" "Default Window Settings" -string "$name"
        }
}

configure_terminal() {
    say "Configure Terminal.app (default profile ${TERMINAL_PROFILE}, font ${TERMINAL_FONT_FAMILY} ${TERMINAL_FONT_SIZE}pt)"

    # --- part 1: default profile — set through the APP (in app memory and
    # on disk). An external 'defaults write' is not picked up by a running
    # Terminal, so it is only the last resort (see note above).
    local current
    current="$(_terminal_default_profile)"
    # Unreachable / not yet answered ("") -> treat as "not Pro", but skip a
    # write we cannot verify instead of claiming success we cannot prove.
    if [ -n "$current" ] && [ "$current" = "$TERMINAL_PROFILE" ]; then
        ok "Default profile is already ${TERMINAL_PROFILE}."
    else
        info "Default profile was '${current:-<unknown>}' — switching to ${TERMINAL_PROFILE}."
        if ! _terminal_set_default_profile "$TERMINAL_PROFILE"; then
            warn "Could not set the ${TERMINAL_PROFILE} profile as Terminal's default."
        else
            local verified
            verified="$(_terminal_default_profile)"
            if [ "$verified" = "$TERMINAL_PROFILE" ]; then
                ok "Default profile is now ${TERMINAL_PROFILE}."
            else
                warn "Wrote the ${TERMINAL_PROFILE} profile, but the read-back reported '${verified:-<none>}'."
            fi
        fi
    fi

    # --- part 2: the Pro profile's font — AppleScript API only, which
    # launches Terminal when it is closed. The script never quits it
    # afterwards (see the note atop this step).
    local face size
    face="$(_terminal_font_face)"
    if [[ "$face" != *"$TERMINAL_FONT_MARKER"* ]]; then
        info "Setting ${TERMINAL_PROFILE} font to ${TERMINAL_FONT_FAMILY} ${TERMINAL_FONT_SIZE}pt (was: ${face:-none})..."
        if ! _terminal_set_font; then
            error "Terminal refused the font change (is there a ${TERMINAL_PROFILE} profile?)."
            return 1
        fi
        if ! _terminal_set_font_size; then
            error "Terminal refused the font-size change."
            return 1
        fi
        ok "${TERMINAL_PROFILE} font is now ${TERMINAL_FONT_FAMILY} ${TERMINAL_FONT_SIZE}pt."
    else
        size="$(_terminal_font_size)"
        if [ "${size:-0}" != "$TERMINAL_FONT_SIZE" ]; then
            if ! _terminal_set_font_size; then
                error "Terminal refused the font-size change."
                return 1
            fi
            ok "${TERMINAL_PROFILE} font size adjusted to ${TERMINAL_FONT_SIZE}pt (was ${size:-unknown})."
        else
            ok "${TERMINAL_PROFILE} font is already ${TERMINAL_FONT_FAMILY} ${TERMINAL_FONT_SIZE}pt."
        fi
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
