#!/usr/bin/env zsh
#
# install-hermes.zsh — install the Hermes Agent (CLI + Desktop) on macOS
# using the hermes-desktop Homebrew cask.
#
# Standalone: run it on its own, independently from the rest of the setup process.
#
# Usage:
#   ./install-hermes.zsh        # install; no-ops if the hermes CLI is already set up
#   FORCE=1 ./install-hermes.zsh
#                               # re-run the installer even if hermes is present
#
# Environment options:
#   WAIT_SECONDS   how long to wait for the setup bundle to finish before
#                  giving up (default 1800 = 30 min; the first install
#                  downloads Python, Node, ripgrep, ffmpeg and more)
#   SKIP_LAUNCH=1  do not launch the setup bundle — test hook that exercises
#                  everything up to the GUI install (fresh-CLI verification
#                  is then driven by whatever CLI state exists already)
#   APPS_DIR_OVERRIDE
#                  directory to look in for Hermes.app — test hook only; the
#                  real install always lives in /Applications
#
# How it works:
#   1. Installs the setup bundle with
#        brew install --cask hermes-desktop
#      Homebrew handles the download, verifies the cask's declared sha256,
#      and tracks the latest build (cask version = app version + build
#      hash of the Hermes-Setup.dmg served at the same clean URL the docs
#      link). Re-runs are a Homebrew no-op unless FORCE=1 (reinstall).
#      The cask's artifact is /Applications/Hermes.app — which is the
#      SETUP bundle, not the desktop app the user ends up with.
#   2. Installs by launching that setup bundle (GUI — the user may need to
#      approve macOS security prompts for an app downloaded from the
#      internet). The setup bundle is a Tauri app that runs the official
#      install script: uv, Python, Node.js, ripgrep, ffmpeg, the repo
#      clone, the venv, the ~/.local/bin/hermes launcher, then it builds
#      and launches the desktop app. The installer is interactive and has
#      no non-interactive flags, so the script prints what it is waiting
#      for and polls.
#   3. Polls until the hermes CLI works headlessly (~/.local/bin/hermes is
#      present and its venv answers --version), with a heartbeat every 30s
#      and a WAIT_SECONDS bound.
#   4. Verifies: CLI version, setup bundle at /Applications/Hermes.app,
#      and the CLI source checkout at ~/.hermes/hermes-agent.
#
# Design notes:
#   * Homebrew is required (run ./install-homebrew.zsh first).
#   * Idempotent: on a machine where the hermes CLI is already installed
#     the script no-ops (it does not touch /Applications/Hermes.app).
#     FORCE=1 re-runs the Desktop installer via 'brew reinstall --cask' —
#     use that to update through it. NOTE: the CLI also updates itself
#     ('hermes update' / the desktop app), so re-running this script is
#     NOT required for ordinary updates.
#   * The setup bundle is a GUI app with no headless mode (verified: its
#     binary takes no CLI flags), so the script drives it the way this
#     repo drives xcode-select: print what to click/approve, launch it,
#     poll until the state change is observable, with a bounded wait.
#   * Arch-aware via common.zsh's ARCH. The current DMG ships an arm64
#     setup bundle; the script warns (with a confirm prompt) on
#     non-Apple-Silicon machines.
#   * Desktop-installer quirks (verified on macOS 26.6.2, DMG build
#     b9271bcb34e1): /Applications/Hermes.app holds the *setup* bundle
#     (bundle id com.nousresearch.hermes.setup, ~12MB) — it is NOT the
#     desktop app the user ends up with. After a successful install, the
#     CLI source lives at ~/.hermes/hermes-agent, the launcher at
#     ~/.local/bin/hermes, and the built desktop app is managed by the
#     installer (build stamp at ~/.hermes/desktop-build-stamp.json).
#   * No sudo required: both the cask install (/Applications is
#     group-writable) and the setup bundle run as the user.
#
# Shared helpers (say/ok/info/warn/error), strict mode, and ARCH live in
# common.zsh in this directory — sourced below.
#
source "${0:A:h}/common.zsh"

# -------------------------------------------------------------------------
# Globals
# -------------------------------------------------------------------------
CASK_NAME="hermes-desktop"
SETUP_APP_NAME="Hermes"                        # app bundle the cask installs
SETUP_BUNDLE_ID="com.nousresearch.hermes.setup"
HERMES_LAUNCHER="${HOME}/.local/bin/hermes"
HERMES_SRC_DIR="${HOME}/.hermes/hermes-agent"
APPS_DIR="${APPS_DIR_OVERRIDE:-/Applications}" # test hook
WAIT_SECONDS="${WAIT_SECONDS:-1800}"


# =========================================================================
# Helpers
# =========================================================================
# True if the hermes CLI is already installed (launcher on PATH or in its
# canonical location). Used only in conditional contexts.
hermes_installed() {
    command -v hermes >/dev/null 2>&1 || [ -x "${HERMES_LAUNCHER}" ]
}

# Headless version probe of the installed CLI. Always exits 0 and prints
# an empty string when the CLI is not there, so it is safe in assignments
# under 'set -e'.
hermes_version() {
    local py="${HERMES_SRC_DIR}/venv/bin/python" entry="${HERMES_SRC_DIR}/hermes"
    local raw=""
    if [ -x "${py}" ] && [ -f "${entry}" ]; then
        raw="$( "${py}" "${entry}" --version 2>/dev/null | head -n1 \
            | sed -n 's/^Hermes Agent \(v[0-9][0-9.]*\).*/\1/p' || true )"
    fi
    # Keep a semver, otherwise nothing: an empty result is what callers
    # mean by "CLI not ready yet".
    [[ "${raw}" =~ ^v[0-9]+\.[0-9]+ ]] && printf '%s' "${raw}" || true
}

# The setup bundle is what this script installs, and what it leaves at
# ${APPS_DIR}/Hermes.app after a run.
setup_bundle_present() {
    [ -d "${APPS_DIR}/${SETUP_APP_NAME}.app" ] &&
    [ -f "${APPS_DIR}/${SETUP_APP_NAME}.app/Contents/Info.plist" ]
}


# =========================================================================
# Step 0 — preconditions
# =========================================================================
check_prerequisites() {
    say "Check prerequisites (arch: ${ARCH})"
    if ! command -v git >/dev/null 2>&1; then
        error "git is not installed. Run ./install-command-line-tools.zsh first,"
        error "or run: xcode-select --install"
        return 1
    fi
    ok "git $(git --version | awk '{print $3}')"
    # HARD dependency: the cask is the install mechanism; no brew, no app.
    if ! command -v brew >/dev/null 2>&1; then
        error "Homebrew is required to install the ${CASK_NAME} cask, but brew was not found."
        error "Install it first (./install-homebrew.zsh) and re-run this script."
        return 1
    fi
    if [ "${ARCH}" != "arm64" ]; then
        warn "This machine is ${ARCH}. The Desktop installer currently ships"
        warn "an arm64 bundle; the install may not be supported here."
        echo "Press Enter to continue, or Ctrl-C to abort..."
        read -r
    fi
}


# =========================================================================
# Step 1 — install the setup bundle via Homebrew
# =========================================================================
install_cask() {
    say "Install the ${CASK_NAME} cask (setup bundle)"

    if [ "${FORCE:-0}" = "1" ] && brew list --cask "${CASK_NAME}" >/dev/null 2>&1; then
        info "FORCE=1 — reinstalling ${CASK_NAME} (fresh download + sha256 check)."
        brew reinstall --cask "${CASK_NAME}"
    else
        brew install --cask "${CASK_NAME}"
    fi

    # Check the artifact, not just 'brew list': Homebrew's job is done once
    # the bundle actually exists with a readable Info.plist.
    local app="${APPS_DIR}/${SETUP_APP_NAME}.app"
    if ! setup_bundle_present; then
        error "brew reported success but ${app} was not found."
        error "Re-run with FORCE=1 to force a reinstall."
        return 1
    fi

    # Identity: it must be the setup bundle, not some other app.
    local bundle_id
    bundle_id="$(defaults read "${app}/Contents/Info" CFBundleIdentifier 2>/dev/null || true)"
    if [ -n "${bundle_id}" ] && [ "${bundle_id}" != "${SETUP_BUNDLE_ID}" ]; then
        warn "Setup bundle id is ${bundle_id} (expected ${SETUP_BUNDLE_ID})."
    else
        ok "Setup bundle: ${app} (${bundle_id:-id unknown})"
    fi
}


# =========================================================================
# Step 2 — install via the setup bundle (GUI, interactive)
# =========================================================================
run_installer() {
    say "Run the Hermes Desktop installer"
    info "Launching ${SETUP_APP_NAME}.app from ${APPS_DIR}. It is a GUI installer"
    info "that runs the official install script: it sets up uv, Python,"
    info "Node.js, ripgrep, ffmpeg, the repo clone, the venv, and the"
    info "'${HERMES_LAUNCHER}' launcher, then builds and launches the"
    info "desktop app. If macOS shows a security prompt, approve it."
    info "This can take several minutes — follow the installer window."
    info "Waiting up to ${WAIT_SECONDS}s for the hermes CLI to come up."
    echo

    if [ "${SKIP_LAUNCH:-0}" = "1" ]; then
        info "SKIP_LAUNCH=1 — NOT launching the installer (test mode)."
    elif ! open "${APPS_DIR}/${SETUP_APP_NAME}.app"; then
        error "Failed to launch ${APPS_DIR}/${SETUP_APP_NAME}.app."
        return 1
    fi

    # Poll until the CLI is up. The setup bundle may quit or self-replace
    # on completion; all this script cares about is the CLI's observable
    # state. Heartbeat at most every 30s so it never looks frozen.
    local deadline=$(( $(date +%s) + WAIT_SECONDS ))
    local next_beat=0 now v
    while :; do
        if hermes_installed; then
            v="$(hermes_version)"
            if [ -n "${v}" ]; then
                ok "Hermes CLI is up: ${v}"
                return 0
            fi
            # Launcher present but the venv isn't ready yet — keep waiting.
        fi
        if [ "$(date +%s)" -ge "${deadline}" ]; then
            error "Waited ${WAIT_SECONDS}s and the hermes CLI is still not ready."
            error "Check the installer window. If the install did succeed,"
            error "just re-run this script — it will detect the CLI and verify."
            return 1
        fi
        now="$(date +%s)"
        if [ "${now}" -ge "${next_beat}" ]; then
            info "Still waiting for the installer to finish..."
            next_beat=$(( now + 30 ))
        fi
        sleep 2
    done
}


# =========================================================================
# Step 3 — verify
# =========================================================================
verify_install() {
    say "Verify Hermes install"

    local v
    v="$(hermes_version)"
    if [ -z "${v}" ]; then
        error "Could not read the hermes CLI version (headless probe failed)."
        error "The CLI may not be fully installed yet — re-run this script."
        return 1
    fi
    ok "CLI: ${v}"

    if setup_bundle_present; then
        ok "Setup bundle: ${APPS_DIR}/${SETUP_APP_NAME}.app (re-runnable with FORCE=1)"
    else
        info "Setup bundle not at ${APPS_DIR}/${SETUP_APP_NAME}.app — fine if you"
        info "only need the CLI; the desktop app is launched with 'hermes desktop'."
    fi

    if [ -d "${HERMES_SRC_DIR}" ]; then
        ok "CLI source: ${HERMES_SRC_DIR}"
    else
        warn "Expected CLI source dir not found: ${HERMES_SRC_DIR}"
    fi

    echo
    info "Next steps:"
    info "  hermes setup      # interactive setup wizard (provider/model)"
    info "  hermes doctor     # verify everything is healthy"
    info "  hermes desktop    # launch the desktop app (if not already open)"
}


# =========================================================================
# Main
# =========================================================================
main() {
    say "Install the Hermes Agent (CLI + Desktop) on macOS"

    if hermes_installed && [ "${FORCE:-0}" != "1" ]; then
        local v
        v="$(hermes_version)"
        ok "Hermes CLI already installed${v:+: ${v}} — nothing to do."
        ok "Use 'hermes update' to update, or re-run with FORCE=1 to re-run"
        ok "the Desktop installer."
        verify_install
        say "Hermes setup complete (no-op)."
        return 0
    fi

    if [ "${FORCE:-0}" = "1" ]; then
        info "FORCE=1 set — ignoring the existing hermes CLI and re-running"
        info "the Desktop installer."
    fi

    check_prerequisites
    install_cask
    run_installer
    verify_install
    say "Hermes setup complete."
}

main "$@"
