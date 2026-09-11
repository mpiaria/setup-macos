#!/usr/bin/env zsh
#
# install-command-line-tools.zsh — install the Xcode Command Line Tools.
#
# Standalone: run it on its own, independently from the rest of the setup process.
#
# Usage:
#   ./install-command-line-tools.zsh                  # install; no-ops if already installed
#   FORCE_CLT=1 ./install-command-line-tools.zsh      # re-launch the install dialog anyway
#   WAIT_SECONDS=3600 ./install-command-line-tools.zsh   # wait longer for the GUI install
#
# How it works:
#   * Runs 'xcode-select --install', which shows the system GUI prompt.
#     YOU must click "Install" in the dialog (and agree to the terms if
#     asked) — the script cannot and will not do that part for you.
#   * The script then polls until the tools appear on disk, so you know it
#     actually finished instead of it silently walking away.
#
# Design notes:
#   * Arch-aware (Apple Silicon vs Intel) — detected at runtime.
#   * Idempotent: safe to re-run; no-ops if the tools are already present.
#   * sudo is NOT required — xcode-select handles authorization itself.
#
# Shared helpers (say/ok/info/warn), strict mode, and ARCH live in
# common.zsh in this directory — sourced below.
#
source "${0:A:h}/common.zsh"

# -------------------------------------------------------------------------
# Globals
# -------------------------------------------------------------------------
CLT_PREFIX="/Library/Developer/CommandLineTools"
WAIT_SECONDS="${WAIT_SECONDS:-1800}"   # default: 30 minutes for the GUI install
POLL_SECONDS=5


# =========================================================================
# Install the Xcode Command Line Tools
# =========================================================================
# Count as installed only when the active developer directory IS the
# Command Line Tools — Xcode.app alone doesn't count.
clt_installed() {
    xcode-select -p 2>/dev/null | grep -q "$CLT_PREFIX"
}

install_clt() {
    say "Install Xcode Command Line Tools (arch: $ARCH)"

    if [ "${FORCE_CLT:-0}" != "1" ] && clt_installed; then
        ok "Command Line Tools already installed: $(xcode-select -p)"
        return 0
    fi
    if clt_installed; then
        info "FORCE_CLT=1 set — they are already present, but re-launching the dialog."
    fi

    info "Launching 'xcode-select --install' — a system dialog will appear."
    info "Click 'Install' in the dialog and agree to the license when asked."
    # Non-zero exit here is expected and harmless: it can mean the tools were
    # already installed, or a previous install is still in progress.
    xcode-select --install 2>/dev/null || true

    if (( WAIT_SECONDS < 60 )); then local wait_label="$WAIT_SECONDS sec"; else local wait_label="$((WAIT_SECONDS / 60)) min"; fi
    info "Waiting for the install to finish (up to $wait_label)..."
    local elapsed=0
    while (( elapsed < WAIT_SECONDS )); do
        if clt_installed; then
            ok "Command Line Tools installed: $(xcode-select -p)"
            info "git is now: $(git --version 2>/dev/null || echo 'NOT AVAILABLE')"
            return 0
        fi
        sleep "$POLL_SECONDS"
        (( elapsed += POLL_SECONDS ))
        # Heartbeat every minute so a long wait doesn't look frozen.
        if (( elapsed % 60 == 0 )); then
            info "  ...still waiting ($((elapsed / 60)) min elapsed) — is the dialog open?"
        fi
    done

    warn "Timed out after $wait_label: the tools are still not present."
    warn "Check the dialog / Software Update, or retry with a larger WAIT_SECONDS."
    return 1
}


# =========================================================================
# Main
# =========================================================================
main() {
    say "Install Xcode Command Line Tools on $ARCH"
    install_clt
    say "Command Line Tools install complete."
}

main "$@"
