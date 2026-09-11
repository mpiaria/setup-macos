#!/usr/bin/env zsh
#
# install-homebrew.zsh — install Homebrew.
#
# Standalone: run it on its own, independently from the rest of the setup process.
#
# Usage:
#   ./install-homebrew.zsh        # install; no-ops if already installed
#
# How it works:
#   * Runs the official Homebrew install script (the one from brew.sh):
#       /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
#     The installer is interactive: it pauses at the 'Press RETURN to
#     continue' prompt and may ask for your sudo password — both are yours
#     to answer in the terminal.
#   * After a fresh install, adds 'brew shellenv' to ~/.zprofile (idempotent),
#     so brew is on PATH in every new zsh session. On Apple Silicon this is
#     what the installer itself recommends.
#
# Design notes:
#   * Arch-aware (Apple Silicon vs Intel) — detected at runtime.
#   * Idempotent: safe to re-run; no-ops if brew is already installed.
#   * sudo may be requested by the installer; run it with a local admin account.
#
# Shared helpers (say/ok/info/warn), strict mode, and ARCH live in
# common.zsh in this directory — sourced below.
#
source "${0:A:h}/common.zsh"

# -------------------------------------------------------------------------
# Globals
# -------------------------------------------------------------------------
INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
ZPROFILE="${HOME}/.zprofile"


# =========================================================================
# Install Homebrew
# =========================================================================
brew_installed() {
    # Check PATH first, then the two canonical install locations, so the
    # no-op detection works even before shellenv is sourced in this shell.
    if command -v brew >/dev/null 2>&1; then return 0; fi
    [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ]
}

# Make sure 'brew shellenv' is in ~/.zprofile so brew is on PATH in new
# shells. Idempotent: never adds a duplicate line.
ensure_shellenv() {
    local brew_bin
    brew_bin="$(command -v brew 2>/dev/null || { [ -x /opt/homebrew/bin/brew ] && printf '%s' /opt/homebrew/bin/brew; } || true)"
    if [ -z "$brew_bin" ]; then
        warn "brew not found on PATH after install; skipping shellenv setup."
        return 0
    fi
    local line
    line="eval \"\$(${brew_bin} shellenv zsh)\""

    if [ -f "$ZPROFILE" ] && grep -qF "${brew_bin} shellenv" "$ZPROFILE"; then
        ok "brew shellenv already present in $ZPROFILE."
        return 0
    fi
    printf '\n%s\n' "$line" >> "$ZPROFILE"
    ok "Added brew shellenv to $ZPROFILE. Open a new terminal (or 'source $ZPROFILE') to use brew."
}

install_homebrew() {
    say "Install Homebrew (arch: $ARCH)"

    if brew_installed; then
        ok "Homebrew already installed: $(brew --version | head -n1)"
        ensure_shellenv
        return 0
    fi

    info "Running the official Homebrew installer..."
    info "It will pause at the 'Press RETURN to continue' prompt — press Return."
    info "It may also ask for your sudo password."
    /bin/bash -c "$(curl -fsSL $INSTALL_URL)"

    if ! brew_installed; then
        warn "Install ran but brew is still not found. Check the installer output above."
        return 1
    fi
    info "Installed: $(brew --version | head -n1)"
    ensure_shellenv
}


# =========================================================================
# Main
# =========================================================================
main() {
    say "Install Homebrew on $ARCH"
    install_homebrew
    say "Homebrew install complete."
}

main "$@"
