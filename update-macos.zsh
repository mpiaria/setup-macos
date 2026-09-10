#!/usr/bin/env zsh
#
# update-macos.zsh — update macOS to the latest version.
#
# Standalone: run it on its own, independently from the rest of the setup process.
#
# Usage:
#   ./update-macos.zsh                      # update macOS in place + bump major version if behind
#   SKIP_FULL_UPGRADE=1 ./update-macos.zsh  # apply in-place updates only, leave current major version
#
# Design notes:
#   * Arch-aware (Apple Silicon vs Intel) — detected at runtime.
#   * Idempotent: safe to re-run; no-ops if there is nothing to install.
#   * sudo is required; run it with a local admin account.
#
set -euo pipefail

# -------------------------------------------------------------------------
# Globals
# -------------------------------------------------------------------------
ARCH="$(uname -m)"    # arm64 (Apple Silicon) or x86_64 (Intel)

say()  { printf '\n\033[1;34m== %s ==\033[0m\n' "$*"; }
ok()   { printf '   \033[1;32m%s\033[0m\n' "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '   \033[1;33m%s\033[0m\n' "$*"; }


# =========================================================================
# Update macOS to the latest version
# =========================================================================
# Two tiers:
#   a. Apply every pending *in-place* update (patches, security, point
#      releases) that Software Update currently offers. Safe: doesn't change
#      the major version, at worst auto-restarts if Apple flags one as
#      requiring it.
#   b. Major-version bump. "Latest" can mean a *newer major release* (e.g.
#      15 Sequoia -> 26 Tahoe). softwareupdate cannot do that in place; you
#      must download the full installer and boot into a fresh install. We
#      detect whether you're already on the newest release and only act when
#      you are behind. Set SKIP_FULL_UPGRADE=1 to never auto-bump.
# -------------------------------------------------------------------------
current_pretty()  { sw_vers -productVersion; }    # e.g. 26.6.2
current_build()   { sw_vers -buildVersion; }      # e.g. 25G83

# Newest full installer Apple offers for this Mac (first listed line = newest).
latest_full_installer() {
    softwareupdate --list-full-installers 2>/dev/null \
      | awk -F', ' '/Title:/ { v=$2; sub(/^Version: /,"",v); print v; exit }'
}

update_macos() {
    say "Update macOS (arch: $ARCH)"

    local cur build
    cur="$(current_pretty)"
    build="$(current_build)"
    info "Current macOS: $cur (build $build)"

    # ---- a: in-place updates ---------------------------------------------
    info "Scanning for pending updates..."
    local scan
    scan="$(softwareupdate -l 2>&1 || true)"

    if printf '%s' "$scan" | grep -q "No new software available"; then
        ok "No pending in-place updates."
    else
        info "Pending updates found:"
        printf '%s\n' "$scan" | sed '/^$/d' | sed 's/^/      /'
        info "Installing all pending updates (may take a while)..."
        # --ia      : install --all appropriate updates
        # --agree-to-license : no interactive license prompt
        # -R        : auto-restart if Apple marks an update as restart-required
        sudo softwareupdate --ia --agree-to-license -R
        ok "In-place updates installed."
    fi

    # Re-read current version (a may have bumped the point release).
    cur="$(current_pretty)"

    # ---- b: major-version bump --------------------------------------------
    if [ "${SKIP_FULL_UPGRADE:-0}" = "1" ]; then
        warn "SKIP_FULL_UPGRADE=1 set — leaving macOS at the current major version."
        ok "Done."
        return 0
    fi

    local latest
    latest="$(latest_full_installer)"
    if [ -z "$latest" ]; then
        warn "Could not determine latest full installer; skipping major bump."
        ok "Done."
        return 0
    fi

    info "Newest macOS available: $latest"
    # sort -V ascending: the first line is the OLDER of the two. If that older
    # one is $cur, we are strictly behind the latest release -> do the bump.
    if [ "$(printf '%s\n%s\n' "$cur" "$latest" | sort -V | head -n1)" = "$cur" ] && [ "$cur" != "$latest" ]; then
        info "This Mac is behind the latest release ($cur -> $latest)."
        info "Downloading full installer..."
        sudo softwareupdate --fetch-full-installer --full-installer-version "$latest"
        # Locate the freshly downloaded "Install macOS *.app".
        local app
        app="$(/usr/bin/find "/Applications" -maxdepth 1 -name 'Install macOS*.app' 2>/dev/null | head -n1)"
        if [ -z "$app" ]; then
            warn "Full installer download finished but no 'Install macOS*.app' in /Applications."
            ok "Done (please upgrade manually)."
            return 0
        fi
        info "Starting unattended install. The Mac will reboot and finish automatically."
        info "  installer: $app"
        sudo "$app/Contents/Resources/startosinstall" --agreetolicense --nointeraction --force
        ok "Full macOS upgrade installed."
    else
        ok "Already on the latest macOS ($cur)."
    fi

    info "macOS is now: $(current_pretty) ($(current_build))"
    ok "Done."
}


# =========================================================================
# Main
# =========================================================================
main() {
    say "macOS update on $ARCH (current: $(current_pretty))"
    command -v sudo >/dev/null || { echo "sudo is required" >&2; exit 1; }

    update_macos

    say "macOS update complete."
}

main "$@"
