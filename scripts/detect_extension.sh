#!/usr/bin/env bash
#
# Detect whether the Obsidian Web Clipper Chrome extension is installed
# in a user's Chrome profile, and inspect its stored clip history to
# infer the "Save to" folder(s) it is actively writing into.
#
# Emits two machine-parseable lines on stdout:
#   EXT_INSTALLED <yes|no> <profile-path-or-empty>
#   SAVE_TO_HINT  <path1>|<path2>|...      (empty when unknown)
#
# On stderr: human-readable log lines when --verbose is passed.
#
# Exit codes:
#   0 = ran successfully (extension may or may not be installed)
#   2 = fatal environment error (no Chrome dir, no python3, etc.)
#
# Only macOS Chrome (stable) is covered. Chromium, Chrome Beta, Chrome
# Canary, Brave, and Windows paths are out of scope for this pass.

set -u
set -o pipefail

EXTENSION_ID="cnjifjpddelmedmihgijeibhnjfabmlf"
VERBOSE=0
HISTORY_LIMIT=10

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v) VERBOSE=1; shift ;;
        --limit)      HISTORY_LIMIT="$2"; shift 2 ;;
        -h|--help)
            cat <<EOF
Usage: $0 [--verbose] [--limit N]

Detects the Obsidian Web Clipper Chrome extension and its recent
save-to paths. Prints two lines: EXT_INSTALLED and SAVE_TO_HINT.
EOF
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            exit 2
            ;;
    esac
done

vlog() { [[ "$VERBOSE" -eq 1 ]] && printf '[detect] %s\n' "$*" >&2 || true; }

CHROME_ROOT="$HOME/Library/Application Support/Google/Chrome"
if [[ ! -d "$CHROME_ROOT" ]]; then
    vlog "Google Chrome user-data root not found: $CHROME_ROOT"
    printf 'EXT_INSTALLED\tno\t\n'
    printf 'SAVE_TO_HINT\t\n'
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    vlog "python3 not available; SAVE_TO_HINT will be empty."
fi

# Enumerate Chrome profile directories. Chrome names them "Default",
# "Profile 1", "Profile 2", ... skip everything else.
declare -a PROFILES=()
while IFS= read -r -d '' d; do
    base="${d##*/}"
    if [[ "$base" == "Default" || "$base" =~ ^Profile[[:space:]][0-9]+$ ]]; then
        PROFILES+=("$d")
    fi
done < <(find "$CHROME_ROOT" -maxdepth 1 -type d -print0 2>/dev/null)

if [[ ${#PROFILES[@]} -eq 0 ]]; then
    vlog "No Chrome profiles found under $CHROME_ROOT"
    printf 'EXT_INSTALLED\tno\t\n'
    printf 'SAVE_TO_HINT\t\n'
    exit 0
fi

# Look for the extension in each profile. First hit wins.
FOUND_PROFILE=""
for profile in "${PROFILES[@]}"; do
    ext_dir="$profile/Extensions/$EXTENSION_ID"
    if [[ -d "$ext_dir" ]]; then
        FOUND_PROFILE="$profile"
        vlog "Extension found in profile: $profile"
        break
    fi
done

if [[ -z "$FOUND_PROFILE" ]]; then
    vlog "Extension $EXTENSION_ID not installed in any Chrome profile."
    printf 'EXT_INSTALLED\tno\t\n'
    printf 'SAVE_TO_HINT\t\n'
    exit 0
fi

printf 'EXT_INSTALLED\tyes\t%s\n' "$FOUND_PROFILE"

# Parse recent clip paths from the LevelDB log. This is a heuristic:
# Web Clipper stores its history as a JSON array under a LevelDB key,
# and each entry has a "path" field with the save-to folder relative
# to the vault root. We grep the visible JSON out of the log file
# rather than decoding LevelDB.
SETTINGS_LOG_DIR="$FOUND_PROFILE/Local Extension Settings/$EXTENSION_ID"
if [[ ! -d "$SETTINGS_LOG_DIR" ]] || ! command -v python3 >/dev/null 2>&1; then
    printf 'SAVE_TO_HINT\t\n'
    exit 0
fi

python3 - "$SETTINGS_LOG_DIR" "$HISTORY_LIMIT" <<'PY'
import json, os, re, sys, glob

settings_dir = sys.argv[1]
limit = int(sys.argv[2])

# Read every log/ldb file in the extension settings dir. Small, safe.
buf = b""
for name in sorted(os.listdir(settings_dir)):
    if not (name.endswith(".log") or name.endswith(".ldb") or name == "MANIFEST-000001"):
        continue
    try:
        with open(os.path.join(settings_dir, name), "rb") as f:
            buf += f.read()
    except Exception:
        continue

# Web Clipper history entries look like:
#   {"action":"addToObsidian","datetime":"...","path":"Clippings","title":"...","url":"...","vault":""}
# Extract just the path fields, in order of appearance (later == newer).
pattern = re.compile(rb'"action":"addToObsidian"[^{}]*?"path":"([^"]*)"')
paths = []
for m in pattern.finditer(buf):
    p = m.group(1)
    try:
        s = p.decode("utf-8")
    except UnicodeDecodeError:
        continue
    paths.append(s)

# Deduplicate but keep insertion order of the LAST occurrences.
seen = {}
for i, p in enumerate(paths):
    seen[p] = i
ordered = sorted(seen.items(), key=lambda kv: kv[1], reverse=True)
top = [p for p, _ in ordered[:limit]]

# The extension writes "" when saving to the vault root. Preserve that
# so callers can distinguish "unset" from "root".
print("SAVE_TO_HINT\t" + "|".join(top))
PY
