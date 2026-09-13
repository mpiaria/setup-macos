#!/usr/bin/env zsh
#
# install-omlx.zsh — install the oMLX macOS app from the official DMG.
#
# Standalone: run it on its own, independently from the rest of the setup
# process.
#
# Usage:
#   ./install-omlx.zsh                             # install; no-ops if already installed
#   FORCE_OMLX=1 ./install-omlx.zsh                # replace the app even if already installed
#   OMLX_INSTALL_DIR=~/Apps ./install-omlx.zsh     # install somewhere other than /Applications
#
# What it does (in order):
#   1. Fetches the latest release of jundot/omlx from the GitHub API
#      (releases/latest — prereleases excluded) and derives:
#       * the download URL of the DMG for the current macOS line. The
#         release publishes exactly one DMG per supported macOS line
#         (one for 15, one for 26/27); this always picks the newest
#         (oMLX-<version>-macos26-27.dmg).
#       * the sha256 checksum the release publishes for that asset.
#   2. Downloads the DMG with curl and verifies its sha256 against the
#      published value (a mismatch aborts the install).
#   3. Mounts the image with hdiutil (the image integrity is verified
#      during mount), copies the app with ditto, unmounts, and verifies
#      the installed app's code signature with codesign --verify --strict.
#
# Design notes:
#   * Deliberately NOT a Homebrew install: the official DMG ships the
#     precompiled native custom kernels, which the brew / from-source
#     builds can only make with full Xcode. Upgrades happen in-app
#     (in-app auto-update), so this script only ever needs to run once.
#   * Apple Silicon only (aborts on Intel). Assumes the current macOS
#     (26.x today); on an older release grab the matching DMG from
#     https://github.com/jundot/omlx/releases.
#   * Idempotent: if oMLX.app is already in $OMLX_INSTALL_DIR the script
#     reports it and exits without downloading anything.
#   * No sudo required: /Applications is writable for admin users.
#   * The app installs a lightweight ~/.omlx/bin/omlx CLI shim on its
#     first launch, so terminal commands exist only after running
#     oMLX.app at least once.
#
source "${0:A:h}/common.zsh"

# -------------------------------------------------------------------------
# Globals
# -------------------------------------------------------------------------
OMLX_REPO="jundot/omlx"
OMLX_APP="oMLX"
OMLX_INSTALL_DIR="${OMLX_INSTALL_DIR:-/Applications}"

TMP_DIR=""          # scratch dir (mktemp -d), removed by the EXIT trap
RELEASE_TAG=""      # e.g. v0.6.4
RELEASE_NAME=""     # asset name, e.g. oMLX-0.6.4-macos26-27.dmg
RELEASE_URL=""      # direct download URL
RELEASE_SHA256=""   # published sha256 of the DMG ("" if unfindable)


# =========================================================================
# Cleanup
# =========================================================================
# Detach a mount that is still attached and drop the scratch dir. Runs on
# EVERY exit (success, failure, interrupt) — a leaked DMG mount would
# otherwise linger in /Volumes.
cleanup() {
    if [ -n "$TMP_DIR" ]; then
        hdiutil detach "$TMP_DIR/mount" >/dev/null 2>&1 || true
        rm -rf "$TMP_DIR" 2>/dev/null || true
    fi
}

# =========================================================================
# Installed-state checks
# =========================================================================
omlx_installed() {
    [ -d "$OMLX_INSTALL_DIR/$OMLX_APP.app" ]
}

# Version of the installed app ("" when unreadable) — always exits 0 so it
# is safe inside messages under 'set -e'.
installed_version() {
    defaults read "$OMLX_INSTALL_DIR/$OMLX_APP.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || true
}

# =========================================================================
# Step 1 — latest release info
# =========================================================================
# Fills RELEASE_TAG / RELEASE_NAME / RELEASE_URL / RELEASE_SHA256 from the
# GitHub releases API. The DMG asset name is derived from the tag (the
# release names its assets oMLX-<version>-macos<line>.dmg), and the
# published sha256 is taken from the asset's "digest" JSON field — which
# is guaranteed to follow its "name" field within the asset object, so a
# single pass over the field lines pairs them correctly.
fetch_release() {
    say "Fetch the latest oMLX release (GitHub: $OMLX_REPO)"
    local json
    if ! json="$(curl -fsSL --retry 3 "https://api.github.com/repos/$OMLX_REPO/releases/latest")"; then
        error "Could not fetch the latest release from the GitHub API — check the network and re-run."
        return 1
    fi
    RELEASE_TAG="$(printf '%s\n' "$json" | grep -oE '"tag_name": *"[^"]+"' | head -n 1 | sed -E 's/^ *"tag_name" *: *"([^"]*)".*$/\1/')"
    if [ -z "$RELEASE_TAG" ]; then
        error "The GitHub API response had no tag_name — cannot locate the DMG."
        return 1
    fi
    # Always the newest supported macOS line (macos26-27); the script
    # assumes a current macOS — older releases are fetched manually.
    RELEASE_NAME="oMLX-${RELEASE_TAG#v}-macos26-27.dmg"
    RELEASE_URL="https://github.com/$OMLX_REPO/releases/download/$RELEASE_TAG/$RELEASE_NAME"
    RELEASE_SHA256="$(printf '%s\n' "$json" | awk -v target="$RELEASE_NAME" '
        /"name"/ {
            name = $0
            sub(/^ *"name" *: *"/, "", name)
            sub(/".*$/, "", name)
            current = name
        }
        current == target && /"digest": *"sha256:/ {
            sha = $0
            sub(/^ *"digest" *: *"sha256:/, "", sha)
            sub(/".*$/, "", sha)
            print sha
            exit
        }
    ')"
    info "Release:  $RELEASE_TAG"
    info "DMG:      $RELEASE_NAME"
    if [ -n "$RELEASE_SHA256" ]; then
        info "sha256:   ${RELEASE_SHA256:0:16}…"
    else
        warn "No sha256 for $RELEASE_NAME in the API response — skipping checksum verification."
    fi
}

# =========================================================================
# Step 2 — download (and verify) the DMG
# =========================================================================
download_dmg() {
    say "Download $RELEASE_NAME"
    local dmg="$TMP_DIR/omlx.dmg"
    info "$RELEASE_URL"
    if ! curl -fsSL --retry 3 -o "$dmg" "$RELEASE_URL"; then
        error "Download failed (404?). The release layout may have changed — check:"
        error "  $RELEASE_URL"
        return 1
    fi
    if [ -n "$RELEASE_SHA256" ]; then
        info "Verifying sha256…"
        local actual
        actual="$(shasum -a 256 "$dmg" | awk '{print $1}')"
        if [ "$actual" != "$RELEASE_SHA256" ]; then
            error "Checksum mismatch — aborting (expected $RELEASE_SHA256, got $actual)."
            return 1
        fi
        ok "Checksum verified."
    fi
}

# =========================================================================
# Step 3 — mount, copy, verify, unmount
# =========================================================================
install_from_dmg() {
    say "Install $OMLX_APP.app to $OMLX_INSTALL_DIR"
    local dmg="$TMP_DIR/omlx.dmg"
    mkdir -p "$TMP_DIR/mount"
    # hdiutil verifies the image integrity (CRC32) during the attach.
    if ! hdiutil attach -nobrowse -noautoopen -mountpoint "$TMP_DIR/mount" "$dmg" >/dev/null; then
        error "Could not mount the DMG (corrupt image?) — re-run the script to download it again."
        return 1
    fi
    if ! ditto "$TMP_DIR/mount/$OMLX_APP.app" "$OMLX_INSTALL_DIR/$OMLX_APP.app"; then
        error "Copying into $OMLX_INSTALL_DIR failed — check that the path exists and is writable."
        return 1
    fi
    hdiutil detach "$TMP_DIR/mount" >/dev/null 2>&1 || true
    ok "Installed. Verifying the code signature…"
    if ! codesign --verify --strict "$OMLX_INSTALL_DIR/$OMLX_APP.app"; then
        rm -rf "$OMLX_INSTALL_DIR/$OMLX_APP.app" 2>/dev/null || true
        error "The installed app failed 'codesign --verify --strict' — removed and aborting."
        return 1
    fi
    ok "Signature OK."
}


# =========================================================================
# Main
# =========================================================================
main() {
    say "Install oMLX — $OMLX_APP.app (Apple Silicon, arch: $ARCH)"

    if [ "$ARCH" != "arm64" ]; then
        error "oMLX requires Apple Silicon; this machine is $ARCH. Nothing done."
        return 1
    fi

    trap cleanup EXIT

    if [ "${FORCE_OMLX:-0}" != "1" ] && omlx_installed; then
        ok "$OMLX_APP.app is already installed in $OMLX_INSTALL_DIR (version $(installed_version))."
        info "Upgrades happen inside the app (auto-update) — nothing to do."
        say "oMLX is ready."
        return 0
    fi

    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/omlx-install.XXXXXX")"

    fetch_release
    download_dmg
    if [ "${FORCE_OMLX:-0}" = "1" ] && omlx_installed; then
        info "FORCE_OMLX=1 — replacing the existing $OMLX_APP.app…"
        rm -rf "$OMLX_INSTALL_DIR/$OMLX_APP.app"
    fi
    install_from_dmg

    say "oMLX installed: $OMLX_INSTALL_DIR/$OMLX_APP.app"
    info "Open the app to finish the first-run welcome screen. It installs a lightweight CLI shim at ~/.omlx/bin/omlx."
    info "The app auto-updates itself — this script only needs to run once (FORCE_OMLX=1 to reinstall)."
}

main "$@"
