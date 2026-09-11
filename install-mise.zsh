#!/usr/bin/env zsh
#
# install-mise.zsh — install mise, pin core tools, enable automatic updates.
#
# Standalone: run it on its own, independently from the rest of the setup process.
#
# Usage:
#   ./install-mise.zsh        # install; no-ops the mise install if already present
#
# What it does (in order):
#   1. Installs mise if not present, via the official shell-aware command:
#         curl -fsSL https://mise.run/zsh | sh
#      It puts the binary at ~/.local/bin/mise and adds the zsh activation
#      line to ~/.zshrc (idempotent — it greps for its own
#      '# added by https://mise.run/zsh' marker), so mise works in every
#      new shell.
#   2. Pins the core toolchain GLOBALLY (runs whether or not step 1
#      installed anything; idempotent — no-op if the pins are already
#      at these versions):
#         mise use -g python@3        # latest python (3.x)
#         mise use -g node@lts        # latest Node LTS
#         mise use -g java@lts        # latest Java LTS
#      These land in the global config (~/.config/mise/config.toml) rather
#      than a per-directory mise.toml, so they apply everywhere.
#   3. Enables automatic updates globally:
#         mise settings auto_update=true
#
# Design notes:
#   * 'python@3' is pinned to the major version: mise tracks 3.x forwards.
#     'lts' is a real mise label (verified resolving to the current LTS).
#   * Arch-aware (Apple Silicon vs Intel) — detected at runtime.
#   * Idempotent: safe to re-run; each step no-ops if already done.
#   * No sudo required — mise is a per-user install under ~/.local/bin.
#
source "${0:A:h}/common.zsh"

# -------------------------------------------------------------------------
# Globals
# -------------------------------------------------------------------------
MISE_INSTALL_URL="https://mise.run/zsh"
MISE_BIN="${HOME}/.local/bin/mise"

# Tool pins, in the order mise installs them. 'lts' tracks the latest
# long-term-support release; '3' tracks the latest 3.x python.
MISE_TOOLS=(python@3 node@lts java@lts)


# =========================================================================
# Mise binary helpers
# =========================================================================
# True if the mise binary exists (on PATH or in its canonical location).
mise_installed() {
    if command -v mise >/dev/null 2>&1; then
        return 0
    fi
    [ -x "$MISE_BIN" ]
}

# Resolve the mise binary to run, regardless of this shell's PATH.
# Always succeeds (falls back to the canonical location) so callers may
# use it in assignments under 'set -e' — the caller gates on
# mise_installed() to know whether it actually exists.
mise_bin_path() {
    command -v mise 2>/dev/null || printf '%s' "$MISE_BIN"
}

ensure_mise() {
    say "Install mise (arch: $ARCH)"
    if mise_installed; then
        ok "mise already installed: $("$(mise_bin_path)" --version)"
        return 0
    fi
    info "Running the official install command: curl -fsSL $MISE_INSTALL_URL | sh"
    info "(installs mise to ~/.local/bin and adds zsh activation to ~/.zshrc)"
    curl -fsSL $MISE_INSTALL_URL | sh
    if ! mise_installed; then
        warn "Install ran but mise is still not found. Check the installer output above."
        return 1
    fi
    ok "Installed: $("$(mise_bin_path)" --version)"
}

# =========================================================================
# Core toolchain (python / node / java) — global, idempotent
# =========================================================================
install_tools() {
    say "Install core toolchain: ${MISE_TOOLS[*]}"
    local mise_bin
    mise_bin="$(mise_bin_path)"
    info "Running: mise use -g ${MISE_TOOLS[*]}"
    # '-g' targets the global config, so the pins apply in every directory.
    # mise only downloads what isn't installed yet and re-pinning a tool
    # that's already at this version is a no-op, making the whole step
    # idempotent. It does not touch tools already in the config.
    "$mise_bin" use -g "${MISE_TOOLS[@]}"
    ok "Active versions:"
    "$mise_bin" ls | sed 's/^/      /'
}

# =========================================================================
# Automatic updates
# =========================================================================
enable_auto_updates() {
    local mise_bin
    mise_bin="$(mise_bin_path)"
    info "Enabling automatic updates globally (mise settings auto_update=true)..."
    "$mise_bin" settings auto_update=true
    ok "auto_update is now: $("${mise_bin}" settings get auto_update)"
}


# =========================================================================
# Main
# =========================================================================
main() {
    ensure_mise
    install_tools
    enable_auto_updates
    say "mise setup complete."
}

main "$@"
