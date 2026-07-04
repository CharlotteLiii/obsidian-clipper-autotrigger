#!/usr/bin/env bash
#
# Obsidian-Clipper-AutoTrigger — macOS / Linux installer.
#
# Modes:
#   Interactive (default when stdin is a TTY): asks any missing values.
#   Non-interactive (--non-interactive, or when stdin is not a TTY): uses
#     only what you pass on the command line, no prompts. Missing optional
#     fields fall back to sensible defaults. Missing REQUIRED fields (only
#     --vault-path is required) cause a hard error.
#
# What it does:
#   1. Seeds config/clipper.conf from clipper.conf.example when missing.
#   2. Fills in VAULT_PATH / CLIP_OUTPUT_DIR / CLIP_SHORTCUT / SHORTCUT_NAME
#      from CLI flags or prompts.
#   3. Detects agent skills directories (OpenClaw / Claude / Codex) and
#      creates a symlink into each detected one (unless --target-root
#      pins a single location).
#   4. Prints a machine-parseable summary block at the end (see
#      AGENT_INSTALL.md for the format).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_NAME="Obsidian-Clipper-AutoTrigger"
CFG_EXAMPLE="$SKILL_DIR/config/clipper.conf.example"
CFG_ACTIVE="$SKILL_DIR/config/clipper.conf"

# ── Defaults ──────────────────────────────────────────────────────

INTERACTIVE="auto"      # auto | yes | no
VAULT_PATH=""
CLIP_OUTPUT_DIR=""
CLIP_SHORTCUT=""
SHORTCUT_NAME=""
USE_SHORTCUT=0          # 1 = user opted into the Shortcut path
ENABLE_APPLE_EVENTS=1   # 1 = flip Chrome's Allow-JS-from-Apple-Events on
TARGET_ROOT=""          # if set, link ONLY here (single-host mode)
ALL_HOSTS=1             # 1 = link into every detected host dir (default)

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --vault-path <path>        Absolute path to the Obsidian vault (REQUIRED
                             in non-interactive mode).
  --clip-output-dir <path>   Relative folder inside the vault where the
                             Web Clipper saves notes. Empty = whole vault.
  --shortcut <combo>         Key combo bound to the Web Clipper in Chrome
                             (e.g. "Shift+Option+S").
  --shortcut-name <name>     Name of an existing macOS Shortcut that
                             triggers the clipper. When omitted, direct
                             AppleScript keystroke is used (no manual
                             Shortcut creation required).
  --use-shortcut             Enable the macOS Shortcut path. Requires the
                             Shortcut to already exist (default name:
                             ObsidianClip).
  --no-enable-apple-events   Skip flipping Chrome's "Allow JavaScript from
                             Apple Events" preference on. The login-wall
                             probe will be a no-op until enabled manually.
  --target-root <path>       Link the skill ONLY into this directory
                             (skips multi-host autodetect).
  --all-hosts                Link into every detected agent skills dir
                             (default when --target-root is not set).
  --no-all-hosts             Only link into the first detected host dir.
  --non-interactive          Never prompt. Missing values fall back to
                             defaults; missing --vault-path aborts.
  -h, --help                 Show this help.

Environment:
  CODEX_HOME, OPENCLAW_HOME  Override the corresponding agent's home dir.

Examples:
  # Interactive install (macOS user, first time):
  $0

  # Fully non-interactive (called by an AI agent):
  $0 --non-interactive \\
     --vault-path "\$HOME/Obsidian Vault" \\
     --clip-output-dir "Inbox/Clippings" \\
     --shortcut "Shift+Option+S"

  # Only link into OpenClaw, not other agents:
  $0 --target-root "\$HOME/.openclaw/workspace/skills"
EOF
}

# ── Parse args ────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --vault-path)       VAULT_PATH="$2"; shift 2 ;;
        --clip-output-dir)  CLIP_OUTPUT_DIR="$2"; shift 2 ;;
        --shortcut)         CLIP_SHORTCUT="$2"; shift 2 ;;
        --shortcut-name)    SHORTCUT_NAME="$2"; USE_SHORTCUT=1; shift 2 ;;
        --use-shortcut)     USE_SHORTCUT=1; shift ;;
        --no-enable-apple-events) ENABLE_APPLE_EVENTS=0; shift ;;
        --target-root)      TARGET_ROOT="$2"; ALL_HOSTS=0; shift 2 ;;
        --all-hosts)        ALL_HOSTS=1; shift ;;
        --no-all-hosts)     ALL_HOSTS=0; shift ;;
        --non-interactive)  INTERACTIVE="no"; shift ;;
        -h|--help)          usage; exit 0 ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# Auto-detect interactive mode
if [[ "$INTERACTIVE" == "auto" ]]; then
    if [[ -t 0 && -t 1 ]]; then
        INTERACTIVE="yes"
    else
        INTERACTIVE="no"
    fi
fi

# ── Small helpers ────────────────────────────────────────────────

log()  { printf '\033[36m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m[install] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

prompt() {
    # $1 = question, $2 = default value (may be empty)
    local q="$1" default="${2:-}" ans=""
    if [[ "$INTERACTIVE" != "yes" ]]; then
        printf '%s' "$default"
        return
    fi
    if [[ -n "$default" ]]; then
        read -r -p "$q [$default]: " ans
    else
        read -r -p "$q: " ans
    fi
    printf '%s' "${ans:-$default}"
}

# ── Vault auto-detection ─────────────────────────────────────────

detect_vault_from_obsidian() {
    # Emit the path of the currently-open vault from Obsidian's registry.
    # Prints nothing if unavailable.
    local registry="$HOME/Library/Application Support/obsidian/obsidian.json"
    [[ -f "$registry" ]] || return 0
    if ! command -v python3 >/dev/null 2>&1; then
        return 0
    fi
    python3 - "$registry" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
vaults = data.get('vaults') or {}
# Prefer the one marked open=true, then the most recent by ts.
open_vaults = [v for v in vaults.values() if v.get('open')]
candidates = open_vaults if open_vaults else list(vaults.values())
candidates.sort(key=lambda v: v.get('ts', 0), reverse=True)
for v in candidates:
    path = v.get('path')
    if path:
        print(path)
        break
PY
}

# ── Collect required values ──────────────────────────────────────

DETECTED_VAULT="$(detect_vault_from_obsidian)"

if [[ -z "$VAULT_PATH" ]]; then
    if [[ "$INTERACTIVE" == "yes" ]]; then
        while [[ -z "$VAULT_PATH" || ! -d "$VAULT_PATH" ]]; do
            VAULT_PATH="$(prompt 'Absolute path to your Obsidian vault' "$DETECTED_VAULT")"
            if [[ -z "$VAULT_PATH" ]]; then
                warn 'Vault path is required.'
            elif [[ ! -d "$VAULT_PATH" ]]; then
                warn "Directory not found: $VAULT_PATH"
                VAULT_PATH=""
            fi
        done
    elif [[ -n "$DETECTED_VAULT" && -d "$DETECTED_VAULT" ]]; then
        VAULT_PATH="$DETECTED_VAULT"
        log "Auto-detected vault from Obsidian registry: $VAULT_PATH"
    else
        die '--vault-path is required in non-interactive mode (could not auto-detect from Obsidian).'
    fi
elif [[ ! -d "$VAULT_PATH" ]]; then
    warn "Vault path does not exist yet: $VAULT_PATH (continuing anyway)"
fi

CLIP_OUTPUT_DIR="${CLIP_OUTPUT_DIR:-$(prompt 'Relative save-to folder inside the vault (blank = whole vault)' '')}"
CLIP_SHORTCUT="${CLIP_SHORTCUT:-$(prompt 'Clip shortcut bound in Chrome' 'Shift+Option+S')}"

# Only prompt for a Shortcut name when the user opted into that path.
if [[ "$USE_SHORTCUT" -eq 1 ]]; then
    SHORTCUT_NAME="${SHORTCUT_NAME:-$(prompt 'macOS Shortcut name that triggers the clipper' 'ObsidianClip')}"
    [[ -z "$SHORTCUT_NAME" ]] && SHORTCUT_NAME="ObsidianClip"
fi

# Fill remaining defaults
[[ -z "$CLIP_SHORTCUT" ]] && CLIP_SHORTCUT="Shift+Option+S"

# ── Seed / update config/clipper.conf ────────────────────────────

if [[ ! -f "$CFG_EXAMPLE" ]]; then
    die "Missing $CFG_EXAMPLE — is this a corrupt checkout?"
fi

if [[ -f "$CFG_ACTIVE" ]]; then
    log "Existing $CFG_ACTIVE detected — updating fields in place."
else
    cp "$CFG_EXAMPLE" "$CFG_ACTIVE"
    log "Seeded $CFG_ACTIVE from example."
fi

# In-place replace VAULT_PATH / CLIP_OUTPUT_DIR / CLIP_SHORTCUT / SHORTCUT_NAME
python3 - "$CFG_ACTIVE" \
    "$VAULT_PATH" "$CLIP_OUTPUT_DIR" "$CLIP_SHORTCUT" "$SHORTCUT_NAME" <<'PY'
import re, sys
path, vault, outdir, shortcut, shortcut_name = sys.argv[1:6]
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()
def sub(key, value):
    global text
    pattern = re.compile(rf'^{re.escape(key)}=.*$', re.MULTILINE)
    escaped = value.replace('\\', '\\\\').replace('"', '\\"')
    replacement = f'{key}="{escaped}"'
    if pattern.search(text):
        text = pattern.sub(replacement, text)
    else:
        text += f'\n{replacement}\n'
sub('VAULT_PATH',      vault)
sub('CLIP_OUTPUT_DIR', outdir)
sub('CLIP_SHORTCUT',   shortcut)
sub('SHORTCUT_NAME',   shortcut_name)
with open(path, 'w', encoding='utf-8') as f:
    f.write(text)
PY

log "Config written: $CFG_ACTIVE"

# Ensure entrypoint is executable
chmod +x "$SKILL_DIR/scripts/clip_webpages.sh" 2>/dev/null || true

# ── Enable Chrome's AppleScript / JS-from-Apple-Events bridge ────

APPLE_EVENTS_STATUS="skipped (--no-enable-apple-events)"
if [[ "$ENABLE_APPLE_EVENTS" -eq 1 ]]; then
    if command -v defaults >/dev/null 2>&1; then
        if defaults write com.google.Chrome AppleScriptEnabled -bool true 2>/dev/null; then
            APPLE_EVENTS_STATUS="enabled (com.google.Chrome AppleScriptEnabled=true)"
            log "Chrome AppleScript / JS-from-Apple-Events preference set. Restart Chrome for it to take effect."
        else
            APPLE_EVENTS_STATUS="failed to write defaults; enable manually via Chrome > View > Developer > Allow JavaScript from Apple Events"
            warn "Could not set com.google.Chrome AppleScriptEnabled via 'defaults'. Enable it once by hand from Chrome's View > Developer menu."
        fi
    else
        APPLE_EVENTS_STATUS="skipped (no 'defaults' command)"
    fi
fi

# ── Detect host skills directories ───────────────────────────────

detect_hosts() {
    # Emits "label|path" lines for every detected host skills dir.
    local -a labels paths
    labels=("OpenClaw" "OpenClaw"    "Claude Code" "Codex" "Codex")
    paths=(
        "${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/skills"
        "$HOME/.openclaw/skills"
        "$HOME/.claude/skills"
        "${CODEX_HOME:-$HOME/.codex}/skills"
        "$HOME/.codex/skills"
    )
    local seen=""
    local i
    for i in "${!paths[@]}"; do
        local p="${paths[$i]}"
        local l="${labels[$i]}"
        [[ -d "$p" ]] || continue
        case "$seen" in
            *"|$p|"*) continue ;;
        esac
        seen="$seen|$p|"
        printf '%s|%s\n' "$l" "$p"
    done
}

declare -a LINK_TARGETS
declare -a LINK_LABELS

if [[ -n "$TARGET_ROOT" ]]; then
    LINK_TARGETS=("$TARGET_ROOT")
    LINK_LABELS=("custom")
else
    while IFS='|' read -r label path; do
        [[ -z "$path" ]] && continue
        LINK_LABELS+=("$label")
        LINK_TARGETS+=("$path")
    done < <(detect_hosts)

    if [[ ${#LINK_TARGETS[@]} -eq 0 ]]; then
        # Nothing detected — default to OpenClaw workspace path
        LINK_TARGETS=("$HOME/.openclaw/workspace/skills")
        LINK_LABELS=("OpenClaw (created)")
    elif [[ "$ALL_HOSTS" -eq 0 ]]; then
        LINK_TARGETS=("${LINK_TARGETS[0]}")
        LINK_LABELS=("${LINK_LABELS[0]}")
    fi
fi

# ── Perform the linking ──────────────────────────────────────────

declare -a LINK_REPORT

link_skill_into() {
    local root="$1" label="$2"
    local target="$root/$SKILL_NAME"
    mkdir -p "$root"
    if [[ -L "$target" ]]; then
        # Existing symlink: refresh it.
        ln -sfn "$SKILL_DIR" "$target"
        LINK_REPORT+=("$target|symlink (refreshed)|$label")
    elif [[ -e "$target" ]]; then
        LINK_REPORT+=("$target|SKIPPED (not a symlink; move it aside)|$label")
    else
        ln -s "$SKILL_DIR" "$target"
        LINK_REPORT+=("$target|symlink|$label")
    fi
}

for i in "${!LINK_TARGETS[@]}"; do
    link_skill_into "${LINK_TARGETS[$i]}" "${LINK_LABELS[$i]}"
done

# ── Summary (agent-parseable) ────────────────────────────────────

printf '\n'
log "Setup complete."
printf '\n'
printf 'LINKED:\n'
for entry in "${LINK_REPORT[@]}"; do
    IFS='|' read -r target kind label <<< "$entry"
    printf '  %s  (%s, %s)\n' "$target" "$kind" "$label"
done
printf 'CONFIG:\n'
printf '  %s\n' "$CFG_ACTIVE"
printf 'SOURCE:\n'
printf '  %s\n' "$SKILL_DIR"
printf '\n'
printf 'Before your first clip, verify these things:\n'
printf '  1. Chrome has the "Obsidian Web Clipper" extension installed and configured.\n'
printf '  2. Press %s manually in Chrome to confirm the popup opens.\n' "$CLIP_SHORTCUT"
if [[ -n "$SHORTCUT_NAME" ]]; then
    printf '  3. macOS Shortcut named "%s" exists (see references/usage.md).\n' "$SHORTCUT_NAME"
else
    printf '  3. On the first clip, grant Terminal / your agent Accessibility\n'
    printf '     permission (System Settings > Privacy & Security > Accessibility)\n'
    printf '     and Automation permission for Google Chrome. macOS will prompt once.\n'
fi
printf '  4. Chrome AppleScript bridge: %s\n' "$APPLE_EVENTS_STATUS"
printf '\n'
printf 'Restart your agent (OpenClaw / Claude Code / Codex) to load the skill.\n'
