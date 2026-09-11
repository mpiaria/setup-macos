#!/usr/bin/env zsh
#
# install-mise.zsh — install mise and enable automatic updates.
#
# Standalone: run it on its own, independently from the rest of the setup process.
#
# Usage:
#   ./install-mise.zsh        # install; no-ops the install if mise already present
#
# How it works:
#   * Runs the official shell-aware install command:
#       curl -fsSL https://mise.run/zsh | sh
#     It installs the binary to ~/.local/bin/mise and adds the zsh
#     activation line to ~/.zshrc (idempotent — it greps for its own
#     '# added by https://mise.run/zsh' marker). Shell activation itself
#     is left to whatever already provides it (e.g. the oh-my-zsh mise
#     plugin); the line the installer appends is harmless and not
#     managed by this script.
#   * Enables automatic updates globally:
#       mise settings auto_update=true
#     (safe to re-run; just re-asserts the setting)
#   * On a no-op run (mise already installed) it still re-asserts
#     auto_update=true.
#
# Design notes:
#   * Arch-aware (Apple Silicon vs Intel) — detected at runtime.
#   * Idempotent: safe to re-run; no-ops the install if mise is present.
#   * No sudo required — mise is a per-user install under ~/.local/bin.
#
source "${0:A:h}/common.zsh"

# -------------------------------------------------------------------------
# Globals
# -------------------------------------------------------------------------
MISE_INSTALL_URL="https://mise.run/zsh"
MISE_BIN="${HOME}/.local/bin/mise"


# =========================================================================
# Install mise
# =========================================================================
mise_installed() {
    # PATH first, then the canonical install location (a shell that hasn't
    # sourced the new .zshrc line won't have ~/.local/bin on PATH yet).
    if command -v mise >/dev/null 2>&1; then
        return 0
    fi
    [ -x "$MISE_BIN" ]
}

# Resolve the mise binary to run, regardless of this shell's PATH.
mise_bin_path() {
    command -v mise 2>/dev/null || { [ -x "$MISE_BIN" ] && printf '%s' "$MISE_BIN"; }
}

enable_auto_updates() {
    local mise_bin
    mise_bin="$(mise_bin_path)"
    info "Enabling automatic updates globally (mise settings auto_update=true)..."
    "$mise_bin" settings auto_update=true
    ok "auto_update is now: $("${mise_bin}" settings get auto_update)"
}

install_mise() {
    say "Install mise (arch: $ARCH)"
    local mise_bin
    mise_bin="$(mise_bin_path)"

    if mise_installed; then
        ok "mise already installed: $("${mise_bin}" --version)"
        # No-op run still re-asserts the global setting.
        enable_auto_updates
        return 0
    fi

    info "Running the official install command: curl -fsSL $MISE_INSTALL_URL | sh"
    info "(installs mise to ~/.local/bin and adds zsh activation to ~/.zshrc)"
    curl -fsSL $MISE_INSTALL_URL | sh

    if ! mise_installed; then
        warn "Install ran but mise is still not found. Check the installer output above."
        return 1
    fi
    mise_bin="$(mise_bin_path)"
    ok "Installed: $("${mise_bin}" --version)"
    enable_auto_updates
}


# =========================================================================
# Main
# =========================================================================
main() {
    say "Install mise on $ARCH"
    install_mise
    say "mise install complete."
}

main "$@"
