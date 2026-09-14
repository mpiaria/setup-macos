#!/usr/bin/env zsh
#
# install-vscode.zsh — install Visual Studio Code via the Homebrew cask.
#
# Standalone: run it on its own, independently from the rest of the setup
# process. REQUIRES Homebrew: run ./install-homebrew.zsh first if brew is
# not installed yet (this script checks and fails with a pointer).
#
# Usage:
#   ./install-vscode.zsh                  # install; no-ops if already installed
#   FORCE=1 ./install-vscode.zsh          # reinstall from the cask even if present
#
# How it works:
#   * Installs the 'visual-studio-code' cask:
#       brew install --cask visual-studio-code
#     The cask is arch-aware: on Apple Silicon it fetches the pure arm64
#     build ('darwin-arm64'), on Intel the x86_64 build ('darwin') — never
#     a universal binary. That is how this script "prefers Apple Silicon
#     over universal": the right single-arch build is chosen by
#     construction, and verified afterwards (see below).
#   * The cask also links the 'code' and 'code-tunnel' CLI shims into
#     Homebrew's bin (e.g. /opt/homebrew/bin/code), so 'code' works from
#     a shell once brew is on PATH.
#   * Verifies the result: the app is present, its version (read from the
#     Info.plist), and the architecture of the main executable matches
#     this machine (arm64 on Apple Silicon, x86_64 on Intel) — a universal
#     binary would be flagged, since a native build is expected.
#
# Design notes:
#   * Idempotent: safe to re-run; no-ops if /Applications/Visual Studio
#     Code.app already exists (the check is by app presence, so it also
#     recognizes an install done outside brew).
#   * FORCE=1 forces a reinstall from the cask (brew reinstall --cask),
#     which repairs a broken install. VS Code auto-updates itself (the
#     cask is marked auto_updates), so a plain re-run is NOT how you
#     upgrade it — upgrades happen in the app.
#   * No sudo required by this script.
#
# Shared helpers (say/ok/info/warn), strict mode, and ARCH live in
# common.zsh in this directory — sourced below.
#
source "${0:A:h}/common.zsh"

# -------------------------------------------------------------------------
# Globals
# -------------------------------------------------------------------------
CASK="visual-studio-code"
APP_NAME="Visual Studio Code"
APP_PATH="/Applications/${APP_NAME}.app"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"


# =========================================================================
# Helpers
# =========================================================================
# Resolve the brew binary regardless of this shell's PATH. Always succeeds
# (empty string if brew is absent) so it is safe in assignments under
# 'set -e'; callers gate on brew_installed().
brew_bin() {
    command -v brew 2>/dev/null \
        || { [ -x /opt/homebrew/bin/brew ] && printf '%s' /opt/homebrew/bin/brew; } \
        || { [ -x /usr/local/bin/brew ] && printf '%s' /usr/local/bin/brew; } \
        || true
}

brew_installed() {
    [ -n "$(brew_bin)" ]
}

# By app presence: true if VS Code is installed, whether or not via brew.
vscode_installed() {
    [ -d "$APP_PATH" ]
}

app_version() {
    defaults read "$INFO_PLIST" CFBundleShortVersionString 2>/dev/null || printf 'unknown'
}

# The app's main executable (the only file in Contents/MacOS), as a full
# path. Never fails, so it is safe in assignments under 'set -e'.
main_executable() {
    local name
    name="$(ls "$APP_PATH/Contents/MacOS" 2>/dev/null | head -n1 || true)"
    [ -n "$name" ] && printf '%s' "$APP_PATH/Contents/MacOS/$name" || true
}


# =========================================================================
# Install (idempotent)
# =========================================================================
ensure_vscode() {
    say "Install VS Code (arch: $ARCH)"

    local brew
    brew="$(brew_bin)"

    if vscode_installed && [ "${FORCE:-0}" != "1" ]; then
        ok "VS Code already installed: $(app_version) at $APP_PATH — nothing to do."
        return 0
    fi

    if vscode_installed; then
        info "FORCE=1 set — reinstalling from the cask: brew reinstall --cask $CASK"
        "$brew" reinstall --cask "$CASK"
    else
        info "Running: brew install --cask $CASK"
        "$brew" install --cask "$CASK"
    fi

    if ! vscode_installed; then
        warn "Install ran but '$APP_PATH' is still missing. Check the brew output above."
        return 1
    fi
}

# =========================================================================
# Verify: app present, version, architecture, 'code' shim
# =========================================================================
verify_install() {
    say "Verify VS Code"

    if ! vscode_installed; then
        error "'$APP_PATH' not found."
        return 1
    fi
    ok "App:     $APP_PATH"
    ok "Version: $(app_version)"

    local exe arch_desc
    exe="$(main_executable)"
    if [ -n "$exe" ]; then
        if file -b "$exe" | grep -q 'universal'; then
            warn "Arch:    universal binary — the cask should have picked the native $ARCH build."
        elif file -b "$exe" | grep -q "$ARCH"; then
            arch_desc="native $ARCH build — preferred over universal"
            ok "Arch:    native $ARCH ($arch_desc)"
        else
            warn "Arch:    could not confirm an $ARCH slice in: $exe"
        fi
    fi

    if command -v code >/dev/null 2>&1; then
        ok "CLI:     $(command -v code)"
    else
        info "'code' is not on PATH in this shell yet — the cask links it into"
        info "Homebrew's bin; open a new shell (or 'source ~/.zprofile') to use it."
    fi
}


# =========================================================================
# Main
# =========================================================================
main() {
    if ! brew_installed; then
        error "Homebrew not found."
        error "Run ./install-homebrew.zsh first, then re-run this script."
        return 1
    fi
    ensure_vscode
    verify_install
    say "VS Code setup complete."
}

main "$@"
