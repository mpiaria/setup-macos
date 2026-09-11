#!/usr/bin/env zsh
#
# common.zsh — shared bits for the setup-macos scripts.
#
# Sourced (not executed) by every install/update script in this repo.
# Each script begins with:
#
#   source "${0:A:h}/common.zsh"
#
# which resolves to the directory the script itself lives in, so the
# scripts work no matter where you run them from.

# Strict mode for every script in this repo.
set -euo pipefail

# -------------------------------------------------------------------------
# Globals
# -------------------------------------------------------------------------
ARCH="$(uname -m)"    # arm64 (Apple Silicon) or x86_64 (Intel)

# -------------------------------------------------------------------------
# Console helpers
# -------------------------------------------------------------------------
say()  { printf '\n\033[1;34m== %s ==\033[0m\n' "$*"; }
ok()   { printf '   \033[1;32m%s\033[0m\n' "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '   \033[1;33m%s\033[0m\n' "$*"; }
# Hard failure: red text on stderr. It does NOT exit by itself — callers
# follow it with `return 1`, which 'set -euo pipefail' turns into an abort
# of the whole script.
error() { printf '   \033[1;31mERROR: %s\033[0m\n' "$*" >&2; }
