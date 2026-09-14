#!/usr/bin/env zsh
#
# install-hermes.zsh — install the Hermes Agent (CLI + Desktop app) on macOS
# using the official Hermes Desktop installer.
#
# Standalone: run it on its own, independently from the rest of the setup process.
#
# Usage:
#   ./install-hermes.zsh        # install; no-ops if the hermes CLI is already set up
#   FORCE=1 ./install-hermes.zsh
#                               # re-run the installer even if hermes is present
#
# Environment options:
#   WAIT_SECONDS   how long to wait for the installer to finish before giving
#                  up (default 1800 = 30 min; the first install downloads
#                  Python, Node, ripgrep, ffmpeg and more)
#   MIN_SIZE_MB    sanity floor for the downloaded DMG (default 3)
#   SKIP_LAUNCH=1  do not launch the setup bundle — test hook that exercises
#                  everything up to the GUI install (fresh-CLI verification
#                  is then driven by whatever CLI state exists already)
#   APPS_DIR_OVERRIDE
#                  directory to look in for /Applications/Hermes.app — test
#                  hook only; the real install always uses /Applications
#
# How it works:
#   1. Downloads the official Desktop installer DMG:
#        https://hermes-assets.nousresearch.com/Hermes-Setup.dmg
#      This is the recommended install path per the docs
#      (docs/getting-started/installation) — it installs both the desktop
#      app and the CLI. The clean URL always serves the latest build (the
#      verified-identical bytes of the ?build=<hash> link on the website),
#      so the URL is stable across releases and needs no scraping.
#   2. Verifies the DMG: a minimum-size floor after download, then hdiutil
#      CRC verification at attach; the mounted Hermes.app must be the setup
#      bundle (com.nousresearch.hermes.setup), carry a matching-arch main
#      executable, and pass codesign --verify --strict. There is no
#      published sha256 for this asset; the computed sha256 is printed for
#      the record.
#   3. Installs by launching the Hermes.app setup bundle from the mounted
#      DMG (GUI — the user may need to approve macOS security prompts for
#      an app downloaded from the internet). The setup bundle is a Tauri
#      app that runs the official install script: uv, Python, Node.js,
#      ripgrep, ffmpeg, the repo clone, the venv, the ~/.local/bin/hermes
#      launcher, then it builds and launches the desktop app. The installer
#      is interactive and has no non-interactive flags, so the script
#      prints what it is waiting for and polls.
#   4. Polls until the hermes CLI works headlessly (~/.local/bin/hermes is
#      present and its venv answers --version), with a heartbeat every 30s
#      and a WAIT_SECONDS bound.
#   5. Verifies: CLI version, setup bundle at /Applications/Hermes.app,
#      and the CLI source checkout at ~/.hermes/hermes-agent.
#
# Design notes:
#   * Idempotent: on a machine where the hermes CLI is already installed
#     the script no-ops (it does not touch /Applications/Hermes.app).
#     FORCE=1 re-runs the Desktop installer — use that to update through
#     it. NOTE: the CLI also updates itself ('hermes update' / the desktop
#     app), so re-running this script is NOT required for ordinary updates.
#   * The Desktop installer is a GUI app with no headless mode (verified:
#     its binary takes no CLI flags), so the script drives it the way this
#     repo drives xcode-select: print what to click/approve, launch it,
#     poll until the state change is observable, with a bounded wait.
#   * Arch-aware via common.zsh's ARCH. The current DMG ships an arm64
#     setup bundle; the script refuses to launch a bundle that does not
#     contain a slice for this mach, and warns (with a confirm prompt) on
#     non-Apple-Silicon machines.
#   * Desktop-installer quirks (verified on macOS 26.6.2, DMG build
#     b9271bcb34e1): the DMG's Hermes.app is itself the *setup* bundle
#     (bundle id com.nousresearch.hermes.setup, ~12MB) — it is NOT the
#     desktop app the user ends up with. After a successful install,
#     /Applications/Hermes.app holds the setup bundle, the CLI source
#     lives at ~/.hermes/hermes-agent, the launcher at
#     ~/.local/bin/hermes, and the built desktop app is managed by the
#     installer (build stamp at ~/.hermes/desktop-build-stamp.json).
#   * No sudo required.
#
# Shared helpers (say/ok/info/warn), strict mode, and ARCH live in
# common.zsh in this directory — sourced below.
#
source "${0:A:h}/common.zsh"

# -------------------------------------------------------------------------
# Globals
# -------------------------------------------------------------------------
DMG_URL="https://hermes-assets.nousresearch.com/Hermes-Setup.dmg"
SITE_URL="https://hermes-agent.nousresearch.com/"
SETUP_APP_NAME="Hermes"                        # app bundle inside the DMG
SETUP_BUNDLE_ID="com.nousresearch.hermes.setup"
HERMES_LAUNCHER="${HOME}/.local/bin/hermes"
HERMES_SRC_DIR="${HOME}/.hermes/hermes-agent"
APPS_DIR="${APPS_DIR_OVERRIDE:-/Applications}" # test hook
DMG="Hermes-Setup.dmg"
WAIT_SECONDS="${WAIT_SECONDS:-1800}"
MIN_SIZE_MB="${MIN_SIZE_MB:-3}"

# Resolved at run time for logging (the clean DMG_URL is what we download —
# it tracks the latest build, so the hash is never pinned).
DMG_BUILD_HASH=""
MOUNT_POINT=""
WORK_DIR=""


# =========================================================================
# Lifecycle (cleanup trap)
# =========================================================================
CLEANED=0
cleanup() {
    # Can be reached from both the ERR and the EXIT trap; clean once.
    [ "${CLEANED}" = "1" ] && return 0
    CLEANED=1
    # Order matters: detach the volume BEFORE removing the work dir that
    # holds it, and make each step best-effort so one failure can't skip
    # the other (a still-mounted disk image would otherwise block the rm).
    if [ -n "${MOUNT_POINT}" ]; then
        hdiutil detach -quiet "${MOUNT_POINT}" >/dev/null 2>&1 || true
        ok "Detached the installer volume."
    fi
    if [ -n "${WORK_DIR}" ] && [ -d "${WORK_DIR}" ]; then
        rm -rf "${WORK_DIR}" 2>/dev/null || true
    fi
}
# The EXIT trap alone does NOT run when 'set -e' kills the shell from
# inside a function; the ERR trap covers that case (EXIT still runs for
# explicit exits and normal completion).
trap cleanup ERR
trap cleanup EXIT


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
    if [ "${ARCH}" != "arm64" ]; then
        warn "This machine is ${ARCH}. The Desktop installer currently ships"
        warn "an arm64 bundle; the install may not be supported here."
        echo "Press Enter to continue, or Ctrl-C to abort..."
        read -r
    fi
}


# =========================================================================
# Step 1 — download the DMG and verify it
# =========================================================================
download_dmg() {
    say "Download the Hermes Desktop installer DMG"

    # Record the currently published build hash from the website (the
    # landing page's download link) — logging only.
    DMG_BUILD_HASH="$(curl -fsSL --max-time 15 "${SITE_URL}" 2>/dev/null \
        | grep -oE 'Hermes-Setup\.dmg\?build=[a-zA-Z0-9]+' | head -n1 \
        | sed 's/.*build=//' || true)"
    if [ -n "${DMG_BUILD_HASH}" ]; then
        info "Current published build: ${DMG_BUILD_HASH}"
    fi

    local dmg_path="${WORK_DIR}/${DMG}"
    rm -f "${dmg_path}"
    info "Downloading: ${DMG_URL}"
    curl -fsSL --retry 3 --max-time 300 --progress-bar -o "${dmg_path}" "${DMG_URL}"

    # Sanity: it must be a plausible-size disk image. Real DMGs are ~6.7MB;
    # a tiny download is a broken transfer or an error page.
    local size_mb
    size_mb=$(( $(stat -f%z "${dmg_path}") / (1024 * 1024) ))
    if [ "${size_mb}" -lt "${MIN_SIZE_MB}" ]; then
        error "Downloaded file is only ${size_mb}MB (expected at least ${MIN_SIZE_MB}MB):"
        error "  $(head -c 120 "${dmg_path}" | tr '\n' ' ')"
        error "Aborting: refusing to mount a file too small to be the DMG."
        return 1
    fi
    local sha
    sha="$(shasum -a 256 "${dmg_path}" | awk '{print $1}')"
    ok "Downloaded ${DMG} (${size_mb}MB) — sha256 ${sha}"

    # Mount. hdiutil verifies the DMG's CRC during attach, so a corrupt
    # download fails here, not mid-install.
    MOUNT_POINT="$(mktemp -d "${WORK_DIR}/vol.XXXXXX")"
    info "Mounting (CRC verified during attach)..."
    hdiutil attach -nobrowse -noautoopen -mountpoint "${MOUNT_POINT}" "${dmg_path}" >/dev/null
    ok "Mounted at ${MOUNT_POINT}"

    local setup_app="${MOUNT_POINT}/${SETUP_APP_NAME}.app"
    if [ ! -d "${setup_app}" ]; then
        error "'${setup_app}' not found in the DMG: $(ls "${MOUNT_POINT}" | tr '\n' ' ')"
        error "The DMG layout may have changed. Aborting."
        return 1
    fi

    # Identity: it must be the setup bundle, not some other app.
    local bundle_id
    bundle_id="$(defaults read "${setup_app}/Contents/Info" CFBundleIdentifier 2>/dev/null || true)"
    if [ -n "${bundle_id}" ] && [ "${bundle_id}" != "${SETUP_BUNDLE_ID}" ]; then
        warn "Setup bundle id is ${bundle_id} (expected ${SETUP_BUNDLE_ID})."
    else
        ok "Contents: ${SETUP_APP_NAME}.app (setup bundle ${bundle_id:-unknown})"
    fi

    # Arch: the main executable must contain a slice for this mach.
    local main exe
    main="$(ls "${setup_app}/Contents/MacOS" | head -n1)"
    exe="${setup_app}/Contents/MacOS/${main}"
    if file -b "${exe}" | grep -q 'universal'; then
        ok "Setup executable arch: universal (contains ${ARCH})"
    elif file -b "${exe}" | grep -q "${ARCH}"; then
        ok "Setup executable arch: ${ARCH}"
    else
        error "Setup executable has no ${ARCH} slice: $(file -b "${exe}")"
        error "Refusing to launch a setup bundle for a different architecture."
        return 1
    fi

    # The bundle must carry a valid signature.
    if codesign --verify --strict "${setup_app}" 2>/dev/null; then
        ok "Code signature verified."
    else
        error "Code signature FAILED for ${setup_app}. Aborting."
        return 1
    fi
}


# =========================================================================
# Step 2 — install via the setup bundle (GUI, interactive)
# =========================================================================
run_installer() {
    say "Run the Hermes Desktop installer"
    info "Launching ${SETUP_APP_NAME}.app from the DMG. It is a GUI installer"
    info "that runs the official install script: it sets up uv, Python,"
    info "Node.js, ripgrep, ffmpeg, the repo clone, the venv, and the"
    info "'${HERMES_LAUNCHER}' launcher, then builds and launches the"
    info "desktop app. If macOS shows a security prompt, approve it."
    info "This can take several minutes — follow the installer window."
    info "Waiting up to ${WAIT_SECONDS}s for the hermes CLI to come up."
    echo

    local setup_app="${MOUNT_POINT}/${SETUP_APP_NAME}.app"
    if [ "${SKIP_LAUNCH:-0}" = "1" ]; then
        info "SKIP_LAUNCH=1 — NOT launching the installer (test mode)."
    elif ! open "${setup_app}"; then
        error "Failed to launch ${setup_app}."
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

    WORK_DIR="$(mktemp -d "${HERMES_TMP_DIR:-/tmp}/hermes-install.XXXXXX")"

    if [ "${FORCE:-0}" = "1" ]; then
        info "FORCE=1 set — ignoring the existing hermes CLI and re-running"
        info "the Desktop installer."
    fi

    check_prerequisites
    download_dmg
    run_installer
    verify_install
    say "Hermes setup complete."
}

main "$@"
