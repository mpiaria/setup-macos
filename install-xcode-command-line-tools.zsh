#!/usr/bin/env zsh
#
# install-xcode-command-line-tools.zsh — install the Xcode Command Line Tools.
#
# Standalone: run it on its own, independently from the rest of the setup process.
#
# Usage:
#   ./install-xcode-command-line-tools.zsh      # install (no-op if already installed)
#   FORCE_CLT=1 ./install-xcode-command-line-tools.zsh   # reinstall even if present
#
# How it works:
#   * Detection: CLT count as installed when xcode-select -p resolves to
#     /Library/Developer/CommandLineTools.
#   * Install: the classic 'xcode-select --install' shows a GUI dialog the user
#     must click — no good for an unattended script. Instead we create the
#     System/SoftwareUpdate progress marker, then let 'softwareupdate' install
#     the Command Line Tools label headlessly (no dialog, sudo only).
#
# Design notes:
#   * Arch-aware (Apple Silicon vs Intel) — detected at runtime.
#   * Idempotent: safe to re-run; no-ops if the tools are already present.
#   * sudo is required; run it with a local admin account.
#
set -euo pipefail

# -------------------------------------------------------------------------
# Globals
# -------------------------------------------------------------------------
ARCH="$(uname -m)"    # arm64 (Apple Silicon) or x86_64 (Intel)
PROGRESS_MARKER="/var/db/.com.apple.dt.CommandLineTools.installondemand.in-progress"

say()  { printf '\n\033[1;34m== %s ==\033[0m\n' "$*"; }
ok()   { printf '   \033[1;32m%s\033[0m\n' "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '   \033[1;33m%s\033[0m\n' "$*"; }


# =========================================================================
# Install the Xcode Command Line Tools
# =========================================================================
clt_installed() {
    xcode-select -p 2>/dev/null | grep -q '/Library/Developer/CommandLineTools'
}

install_clt() {
    say "Install Xcode Command Line Tools (arch: $ARCH)"

    if [ "${FORCE_CLT:-0}" != "1" ] && clt_installed; then
        ok "Command Line Tools already installed: $(xcode-select -p)"
        return 0
    fi

    if clt_installed; then
        info "FORCE_CLT=1 set — triggering a fresh install anyway."
    fi

    info "Triggering headless install via softwareupdate..."
    # 1. Create the progress marker so the CLI tools label becomes available.
    sudo touch "$PROGRESS_MARKER"
    # 2. Find the Command Line Tools update label. The label after "Label: "
    #    includes qualifiers, e.g. "Command Line Tools for Xcode 16.4", so the
    #    full field must be captured up to the first comma.
    local label
    label="$(sudo softwareupdate -l 2>&1 \
      | grep -E 'Label: .*Command Line Tools[^,]*' \
      | head -n1 | sed -E 's/^[[:space:]]*\*[[:space:]]+Label: [[:space:]]*//' | cut -d',' -f1 | sed 's/[[:space:]]*$//')"
    if [ -z "$label" ]; then
        sudo rm -f "$PROGRESS_MARKER"
        warn "No Command Line Tools label found after progress marker — the GUI " \
             "path may be the only option (rare; try 'xcode-select --install')."
        return 0
    fi
    info "Installing label: $label (may take a while)..."
    # 3. Install headlessly.
    sudo softwareupdate --install "$label"
    # 4. Remove the marker so future scans don't re-offer it.
    sudo rm -f "$PROGRESS_MARKER"

    if clt_installed; then
        ok "Command Line Tools installed: $(xcode-select -p)"
        info "git is now: $(git --version 2>/dev/null || echo 'NOT AVAILABLE')"
    else
        warn "Install reported success but xcode-select -p still doesn't resolve. " \
             "Try 'xcode-select --install' manually."
        return 1
    fi
}


# =========================================================================
# Main
# =========================================================================
main() {
    say "Install Xcode Command Line Tools on $ARCH"
    command -v sudo >/dev/null || { echo "sudo is required" >&2; exit 1; }

    install_clt

    say "Command Line Tools install complete."
}

main "$@"
