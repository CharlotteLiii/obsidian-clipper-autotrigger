#!/usr/bin/env bash
#
# Obsidian-Clipper-AutoTrigger — preflight self-check (macOS/Linux).
#
# Runs the checks a human can do manually but that an AI agent cannot
# reliably drive, then prints a pass/fail matrix and exits 0 if the skill
# is safe to run, non-zero otherwise.
#
# What it checks:
#   1. config/clipper.conf exists and parses.
#   2. VAULT_PATH exists and looks like an Obsidian vault (has `.obsidian`).
#   3. CLIP_OUTPUT_DIR (if set) exists under VAULT_PATH.
#   4. Chrome is installed at a known path.
#   5. Obsidian is installed.
#   6. macOS Shortcut with SHORTCUT_NAME exists (macOS only).
#
# Usage:
#   scripts/preflight.sh [--config <path>]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$SKILL_DIR/config/clipper.conf"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) CONFIG="$2"; shift 2 ;;
        -h|--help)
            printf 'Usage: %s [--config <path>]\n' "$0"
            exit 0 ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            exit 2 ;;
    esac
done

pass()  { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail()  { printf '  \033[31m✗\033[0m %s\n' "$*"; FAILED=1; }
warn()  { printf '  \033[33m!\033[0m %s\n' "$*"; }
info()  { printf '\n\033[36m%s\033[0m\n' "$*"; }

FAILED=0

# ── 1. Config ─────────────────────────────────────────────────────

info "Config"
if [[ ! -f "$CONFIG" ]]; then
    fail "Missing $CONFIG — run scripts/install.sh first."
    exit 1
fi
pass "Config found: $CONFIG"

VAULT_PATH=""; CLIP_OUTPUT_DIR=""; CLIP_SHORTCUT=""; SHORTCUT_NAME=""
# shellcheck disable=SC1090
source "$CONFIG"

# ── 2. Vault ──────────────────────────────────────────────────────

info "Obsidian vault"
if [[ -z "${VAULT_PATH:-}" ]]; then
    fail "VAULT_PATH is empty in $CONFIG"
elif [[ ! -d "$VAULT_PATH" ]]; then
    fail "VAULT_PATH does not exist: $VAULT_PATH"
else
    pass "VAULT_PATH exists: $VAULT_PATH"
    if [[ -d "$VAULT_PATH/.obsidian" ]]; then
        pass "Looks like an Obsidian vault (.obsidian/ present)"
    else
        warn "No .obsidian/ folder inside — is this really an Obsidian vault?"
    fi
    if [[ -n "${CLIP_OUTPUT_DIR:-}" ]]; then
        if [[ -d "$VAULT_PATH/$CLIP_OUTPUT_DIR" ]]; then
            pass "CLIP_OUTPUT_DIR exists: $CLIP_OUTPUT_DIR"
        else
            warn "CLIP_OUTPUT_DIR does not exist yet: $CLIP_OUTPUT_DIR (Web Clipper will create it on first clip)"
        fi
    else
        pass "CLIP_OUTPUT_DIR empty — will scan the whole vault"
    fi
fi

# ── 3. Chrome ─────────────────────────────────────────────────────

info "Google Chrome"
CHROME_APP="/Applications/Google Chrome.app"
if [[ -d "$CHROME_APP" ]]; then
    pass "Chrome installed at $CHROME_APP"
else
    fail "Chrome not found at $CHROME_APP — install from https://www.google.com/chrome/"
fi

# ── 4. Obsidian ───────────────────────────────────────────────────

info "Obsidian"
if [[ -d "/Applications/Obsidian.app" ]]; then
    pass "Obsidian installed"
    if pgrep -x Obsidian >/dev/null 2>&1; then
        pass "Obsidian is currently running"
    else
        warn "Obsidian is not running — start it before your first clip so files appear"
    fi
else
    fail "Obsidian not installed at /Applications/Obsidian.app"
fi

# ── 5. macOS Shortcut ─────────────────────────────────────────────

if [[ "$(uname -s)" == "Darwin" ]]; then
    info "macOS Shortcut"
    SHORTCUT_NAME="${SHORTCUT_NAME:-ObsidianClip}"
    if command -v shortcuts >/dev/null 2>&1; then
        if shortcuts list 2>/dev/null | grep -Fxq "$SHORTCUT_NAME"; then
            pass "Shortcut '$SHORTCUT_NAME' exists"
        else
            fail "Shortcut '$SHORTCUT_NAME' not found — see references/usage.md for the template"
        fi
    else
        warn "'shortcuts' CLI missing (unusual on macOS 12+); cannot verify Shortcut existence"
    fi
fi

# ── 6. Human preflight reminder ───────────────────────────────────

info "Manual verification (agent-facing)"
printf '  Ask the user to confirm:\n'
printf '    1. Chrome has the "Obsidian Web Clipper" extension installed and configured.\n'
printf '    2. Pressing %s in Chrome opens the Web Clipper popup.\n' "${CLIP_SHORTCUT:-Shift+Option+S}"
printf '    3. Obsidian is open with the correct vault loaded.\n'

# ── Result ────────────────────────────────────────────────────────

printf '\n'
if [[ "$FAILED" -eq 0 ]]; then
    printf '\033[32mPREFLIGHT OK\033[0m — you can attempt a clip.\n'
    exit 0
else
    printf '\033[31mPREFLIGHT FAILED\033[0m — fix the ✗ items above before clipping.\n'
    exit 1
fi
