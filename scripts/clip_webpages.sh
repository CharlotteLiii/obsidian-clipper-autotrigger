#!/usr/bin/env bash
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_CONFIG="$SKILL_DIR/config/clipper.conf"
APPLE_DIR="$SKILL_DIR/applescripts"

CONFIG_FILE="$DEFAULT_CONFIG"
DRY_RUN=0
declare -a URLS=()

usage() {
  cat <<'EOF'
Usage:
  clip_webpages.sh [--config PATH] [--dry-run] URL [URL ...]

Options:
  --config PATH  Use a custom config file instead of config/clipper.conf.
  --dry-run      Validate config and URLs without opening Chrome or clipping.
  -h, --help     Show this help.
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  log "ERROR: $*"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      if [[ $# -lt 2 ]]; then
        fail "--config requires a path"
        exit 2
      fi
      CONFIG_FILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        URLS+=("$1")
        shift
      done
      ;;
    -*)
      fail "Unknown option: $1"
      usage
      exit 2
      ;;
    *)
      URLS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#URLS[@]} -eq 0 ]]; then
  fail "No URLs provided."
  usage
  exit 2
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  fail "Config file not found: $CONFIG_FILE"
  exit 2
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

VAULT_PATH="${VAULT_PATH:-}"
SHORTCUT_NAME="${SHORTCUT_NAME-}"
CLIP_OUTPUT_DIR="${CLIP_OUTPUT_DIR:-}"
CLIP_SHORTCUT="${CLIP_SHORTCUT:-Shift+Option+S}"
PAGE_LOAD_TIMEOUT="${PAGE_LOAD_TIMEOUT:-45}"
RENDER_GRACE_SECONDS="${RENDER_GRACE_SECONDS:-3}"
CLIP_TIMEOUT="${CLIP_TIMEOUT:-30}"
MAX_RETRIES="${MAX_RETRIES:-3}"
POLL_INTERVAL="${POLL_INTERVAL:-1}"
CHECK_SHORTCUT_EXISTS="${CHECK_SHORTCUT_EXISTS:-1}"
LOGIN_WALL_CHECK="${LOGIN_WALL_CHECK:-1}"
LOGIN_WALL_MIN_TEXT="${LOGIN_WALL_MIN_TEXT:-300}"

validate_config() {
  local numeric_re='^[0-9]+([.][0-9]+)?$'
  local integer_re='^[0-9]+$'

  if [[ -z "$VAULT_PATH" ]]; then
    fail "VAULT_PATH is empty in $CONFIG_FILE"
    return 1
  fi
  if [[ ! -d "$VAULT_PATH" ]]; then
    fail "VAULT_PATH does not exist or is not a directory: $VAULT_PATH"
    return 1
  fi
  if [[ -n "$CLIP_OUTPUT_DIR" && ! -d "${VAULT_PATH}/${CLIP_OUTPUT_DIR}" ]]; then
    fail "CLIP_OUTPUT_DIR does not exist inside vault: ${VAULT_PATH}/${CLIP_OUTPUT_DIR}"
    return 1
  fi
  if [[ -z "$SHORTCUT_NAME" ]]; then
    :  # Direct-keystroke mode: no Shortcut required.
  fi
  if [[ ! "$PAGE_LOAD_TIMEOUT" =~ $integer_re ]]; then
    fail "PAGE_LOAD_TIMEOUT must be an integer"
    return 1
  fi
  if [[ ! "$RENDER_GRACE_SECONDS" =~ $numeric_re ]]; then
    fail "RENDER_GRACE_SECONDS must be a number"
    return 1
  fi
  if [[ ! "$CLIP_TIMEOUT" =~ $integer_re ]]; then
    fail "CLIP_TIMEOUT must be an integer"
    return 1
  fi
  if [[ ! "$POLL_INTERVAL" =~ $numeric_re ]]; then
    fail "POLL_INTERVAL must be a number"
    return 1
  fi
  if [[ ! "$MAX_RETRIES" =~ $integer_re ]] || [[ "$MAX_RETRIES" -lt 1 ]]; then
    fail "MAX_RETRIES must be an integer >= 1"
    return 1
  fi
  if [[ "$CHECK_SHORTCUT_EXISTS" != "0" && "$CHECK_SHORTCUT_EXISTS" != "1" ]]; then
    fail "CHECK_SHORTCUT_EXISTS must be 0 or 1"
    return 1
  fi
  if [[ "$LOGIN_WALL_CHECK" != "0" && "$LOGIN_WALL_CHECK" != "1" ]]; then
    fail "LOGIN_WALL_CHECK must be 0 or 1"
    return 1
  fi
  if [[ ! "$LOGIN_WALL_MIN_TEXT" =~ $integer_re ]]; then
    fail "LOGIN_WALL_MIN_TEXT must be an integer"
    return 1
  fi
  if ! validate_clip_shortcut "$CLIP_SHORTCUT"; then
    return 1
  fi
  if ! command -v osascript >/dev/null 2>&1; then
    fail "osascript is not available on this system"
    return 1
  fi
  if ! command -v shortcuts >/dev/null 2>&1; then
    fail "shortcuts CLI is not available on this system"
    return 1
  fi
  if [[ -n "$SHORTCUT_NAME" && "$CHECK_SHORTCUT_EXISTS" == "1" ]] && ! shortcut_exists; then
    fail "Shortcut not found: $SHORTCUT_NAME"
    fail "Open the Shortcuts app and create/rename the Shortcut, or clear SHORTCUT_NAME in $CONFIG_FILE to use direct keystroke mode."
    return 1
  fi
}

shortcut_exists() {
  local shortcut_list

  if ! shortcut_list="$(shortcuts list 2>/dev/null)"; then
    fail "Could not list macOS Shortcuts. Try running 'shortcuts list' in Terminal to grant/confirm Shortcuts permissions."
    return 1
  fi

  printf '%s\n' "$shortcut_list" | awk -v target="$SHORTCUT_NAME" '$0 == target { found = 1 } END { exit found ? 0 : 1 }'
}

validate_clip_shortcut() {
  local raw="$1"
  if [[ -z "$raw" ]]; then
    fail "CLIP_SHORTCUT is empty in $CONFIG_FILE"
    return 1
  fi
  local IFS='+' token found_key=0
  # shellcheck disable=SC2206
  local -a parts=($raw)
  for token in "${parts[@]}"; do
    token="${token## }"
    token="${token%% }"
    if [[ -z "$token" ]]; then
      fail "CLIP_SHORTCUT has empty component: '$raw'"
      return 1
    fi
    local lower
    lower="$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
      shift|ctrl|control|alt|option|cmd|command|meta|win) ;;
      *)
        if (( found_key )); then
          fail "CLIP_SHORTCUT '$raw' has more than one non-modifier key."
          return 1
        fi
        found_key=1
        ;;
    esac
  done
  if (( ! found_key )); then
    fail "CLIP_SHORTCUT '$raw' has no main key."
    return 1
  fi
  return 0
}

validate_url() {
  local url="$1"
  [[ "$url" =~ ^https?://[^[:space:]/?#]+([^[:space:]]*)?$ ]]
}

# ── adaptive polling ────────────────────────────────────────────────

adaptive_sleep() {
  local elapsed="${1:-0}"
  if (( elapsed < 5 )); then
    sleep 0.5
  elif (( elapsed < 15 )); then
    sleep "${POLL_INTERVAL:-1}"
  else
    sleep 2
  fi
}

# ── markdown detection ──────────────────────────────────────────────

markdown_snapshot() {
  local scan_dir
  if [[ -n "$CLIP_OUTPUT_DIR" ]]; then
    scan_dir="${VAULT_PATH}/${CLIP_OUTPUT_DIR}"
  else
    scan_dir="$VAULT_PATH"
  fi

  find "$scan_dir" -type f -name '*.md' -print0 2>/dev/null |
    while IFS= read -r -d '' markdown_file; do
      stat -f '%N	%m' "$markdown_file" 2>/dev/null
    done |
    sort
}

newest_changed_markdown() {
  local before_snapshot="$1"
  local after_snapshot

  after_snapshot="$(mktemp "${TMPDIR:-/tmp}/obsidian-clip-after.XXXXXX")"
  markdown_snapshot >"$after_snapshot"

  awk -F '\t' '
    NR == FNR {
      before[$1] = $2
      next
    }
    !($1 in before) || before[$1] != $2 {
      print $2 "\t" $1
    }
  ' "$before_snapshot" "$after_snapshot" |
    sort -nr |
    head -n 1 |
    cut -f2-

  rm -f "$after_snapshot"
}


cleanup_failed_root_untitled_clips() {
  local since_epoch="$1"
  local markdown_file basename mtime birth deleted_with_trash

  # Only run this cleanup when the extension is expected to save into a
  # configured subdirectory. If scanning the whole vault, root-level Untitled
  # files may be legitimate detected output and must not be touched.
  if [[ -z "$CLIP_OUTPUT_DIR" ]]; then
    return 0
  fi

  local -a candidates=()
  shopt -s nullglob
  candidates=("$VAULT_PATH"/Untitled*.md)
  shopt -u nullglob

  for markdown_file in "${candidates[@]}"; do
    [[ -f "$markdown_file" ]] || continue

    basename="${markdown_file##*/}"
    if [[ "$basename" != "Untitled.md" && ! "$basename" =~ ^Untitled\ [0-9]+\.md$ ]]; then
      continue
    fi

    mtime="$(stat -f '%m' "$markdown_file" 2>/dev/null || printf '0')"
    birth="$(stat -f '%B' "$markdown_file" 2>/dev/null || printf '0')"

    # Clean only files created or modified during this failed clip attempt.
    # This avoids deleting old user files that merely happen to be named
    # Untitled.md / Untitled 1.md in the vault root.
    if (( mtime < since_epoch && birth < since_epoch )); then
      continue
    fi

    log "Cleaning failed root Untitled clip: $markdown_file"
    deleted_with_trash=0
    if command -v trash >/dev/null 2>&1; then
      if trash "$markdown_file" >/dev/null 2>&1; then
        deleted_with_trash=1
      fi
    fi

    if [[ "$deleted_with_trash" != "1" ]]; then
      rm -f "$markdown_file"
    fi
  done
}

# ── Chrome helpers ──────────────────────────────────────────────────

open_chrome_tab() {
  local url="$1"
  local window_id="${2:-}"

  if [[ -n "$window_id" ]]; then
    osascript "$APPLE_DIR/chrome_open_new_tab.scpt" "$url" "$window_id"
  else
    osascript "$APPLE_DIR/chrome_open_new_tab.scpt" "$url"
  fi
}

tab_status() {
  local window_id="$1"
  local tab_id="$2"
  osascript "$APPLE_DIR/chrome_tab_status.scpt" "$window_id" "$tab_id"
}

close_chrome_tab() {
  local window_id="$1"
  local tab_id="$2"
  osascript "$APPLE_DIR/chrome_close_tab.scpt" "$window_id" "$tab_id" >/dev/null
}

# ── login-wall probe ────────────────────────────────────────────────
#
# Post-load heuristic mirroring the Windows Test-CdpLoginWall. Runs a JS
# probe in the target tab via Chrome's AppleScript `execute javascript`
# and inspects final URL / DOM / body text for login or paywall signals.
#
# Requires Chrome > View > Developer > "Allow JavaScript from Apple Events"
# to be enabled once. If disabled, the probe errors out and this function
# logs the reason and returns 2 (caller: continue anyway).
#
# Args: window_id tab_id
# Return: 0 = clear, 1 = login wall detected, 2 = probe error
# Stdout on hit: SUSPECTED_LOGIN_WALL: <reason>|<finalUrl>|<title>
probe_login_wall() {
  local window_id="$1"
  local tab_id="$2"
  local raw is_wall reason final_url doc_title url_hit pwd_input paywall_node text_hit text_len

  if ! raw="$(osascript "$APPLE_DIR/chrome_login_wall_probe.scpt" "$window_id" "$tab_id" "$LOGIN_WALL_MIN_TEXT" 2>&1)"; then
    log "Login-wall probe failed (continuing anyway): $raw"
    return 2
  fi

  IFS=$'\t' read -r is_wall reason final_url doc_title url_hit pwd_input paywall_node text_hit text_len <<<"$raw"

  if [[ "$is_wall" == "error" ]]; then
    log "Login-wall probe error (continuing anyway): $reason"
    log "  hint: enable Chrome > View > Developer > Allow JavaScript from Apple Events, or set LOGIN_WALL_CHECK=0."
    return 2
  fi

  log "Login-wall probe: urlHit=${url_hit} pwd=${pwd_input} paywall=${paywall_node} phrase=${text_hit:--} textLen=${text_len}"

  if [[ "$is_wall" == "1" ]]; then
    printf 'SUSPECTED_LOGIN_WALL: %s|%s|%s\n' "$reason" "$final_url" "$doc_title"
    return 1
  fi
  return 0
}

# ── page load ───────────────────────────────────────────────────────

wait_for_page_load() {
  local window_id="$1"
  local tab_id="$2"
  local start now elapsed status loading title tab_url

  start="$(date +%s)"
  while true; do
    if ! status="$(tab_status "$window_id" "$tab_id" 2>&1)"; then
      fail "Could not read Chrome tab status: $status"
      return 1
    fi

    IFS=$'\t' read -r loading title tab_url <<<"$status"
    if [[ "$loading" == "false" ]]; then
      log "Page loaded: ${title:-$tab_url}"
      if [[ "$RENDER_GRACE_SECONDS" != "0" ]]; then
        log "Waiting ${RENDER_GRACE_SECONDS}s for rendered content..."
        sleep "$RENDER_GRACE_SECONDS"
      fi
      return 0
    fi

    if [[ "$loading" == "missing" ]]; then
      fail "Chrome tab disappeared before the page finished loading."
      return 1
    fi

    now="$(date +%s)"
    elapsed=$((now - start))
    if (( elapsed >= PAGE_LOAD_TIMEOUT )); then
      fail "Page never finished loading within ${PAGE_LOAD_TIMEOUT}s."
      return 1
    fi

    log "Waiting for page... (${elapsed}s elapsed)"
    adaptive_sleep "$elapsed"
  done
}

# ── clipping actions ────────────────────────────────────────────────

run_shortcut() {
  local output
  if ! output="$(shortcuts run "$SHORTCUT_NAME" 2>&1)"; then
    fail "Shortcut failed: $output"
    return 1
  fi
  return 0
}

send_clip_shortcut() {
  local output
  if ! output="$(OCA_CLIP_SHORTCUT="$CLIP_SHORTCUT" osascript "$APPLE_DIR/chrome_send_clip_shortcut.scpt" 2>&1)"; then
    fail "Direct shortcut keystroke failed: $output"
    return 1
  fi
  return 0
}

# Primary clip trigger: use the macOS Shortcut when SHORTCUT_NAME is
# configured, otherwise send the keystroke directly via AppleScript.
trigger_clip() {
  if [[ -n "$SHORTCUT_NAME" ]]; then
    run_shortcut
  else
    send_clip_shortcut
  fi
}

wait_for_markdown() {
  local before_snapshot="$1"
  local start now elapsed detected


  start="$(date +%s)"
  while true; do
    detected="$(newest_changed_markdown "$before_snapshot")"
    if [[ -n "$detected" ]]; then
      printf '%s\n' "$detected"
      return 0
    fi

    now="$(date +%s)"
    elapsed=$((now - start))
    if (( elapsed >= CLIP_TIMEOUT )); then
      return 1
    fi

    log "Waiting for Markdown... (${elapsed}s elapsed)"
    adaptive_sleep "$elapsed"
  done
}

# ── single URL clip ─────────────────────────────────────────────────

clip_one_url() {
  local url="$1"
  local shared_window_id="$2"
  local open_result window_id tab_id attempt before_snapshot detected_file attempt_started_at fallback_started_at

  log "Opening Chrome for: $url"
  if ! open_result="$(open_chrome_tab "$url" "$shared_window_id" 2>&1)"; then
    fail "Chrome could not open URL: $open_result"
    return 1
  fi

  IFS=$'\t' read -r window_id tab_id <<<"$open_result"
  if [[ -z "${window_id:-}" || -z "${tab_id:-}" ]]; then
    fail "Chrome did not return a usable tab id."
    return 1
  fi

  # Echo the window id back to the caller so the next URL can reuse it.
  printf 'WINDOW	%s\n' "$window_id"

  log "Waiting for page..."
  if ! wait_for_page_load "$window_id" "$tab_id"; then
    log "Closing tab after page load failure..."
    close_chrome_tab "$window_id" "$tab_id" || true
    return 1
  fi

  if [[ "$LOGIN_WALL_CHECK" == "1" ]]; then
    local probe_out probe_rc
    probe_out="$(probe_login_wall "$window_id" "$tab_id")"
    probe_rc=$?
    if (( probe_rc == 1 )); then
      fail "$probe_out"
      log "Aborting this URL before triggering clipper. Sign in inside the driven Chrome profile and retry."
      log "To disable this check, set LOGIN_WALL_CHECK=0 in the config."
      log "Closing tab after login-wall abort..."
      close_chrome_tab "$window_id" "$tab_id" || true
      return 1
    fi
  fi

  for ((attempt = 1; attempt <= MAX_RETRIES; attempt++)); do
    if [[ -n "$SHORTCUT_NAME" ]]; then
      log "Triggering clipper via Shortcut '$SHORTCUT_NAME' (attempt $attempt/$MAX_RETRIES)..."
    else
      log "Triggering clipper via direct keystroke '$CLIP_SHORTCUT' (attempt $attempt/$MAX_RETRIES)..."
    fi
    before_snapshot="$(mktemp "${TMPDIR:-/tmp}/obsidian-clip-before.XXXXXX")"
    markdown_snapshot >"$before_snapshot"
    attempt_started_at="$(date +%s)"

    if ! trigger_clip; then
      cleanup_failed_root_untitled_clips "$attempt_started_at"
      rm -f "$before_snapshot"
      if (( attempt == MAX_RETRIES )); then
        log "Closing tab after final trigger failure..."
        close_chrome_tab "$window_id" "$tab_id" || true
        return 1
      fi
      log "Retrying after trigger failure..."
      continue
    fi

    log "Waiting for Markdown..."
    if detected_file="$(wait_for_markdown "$before_snapshot")"; then
      rm -f "$before_snapshot"
      log "Markdown detected: $detected_file"
      log "Closing Chrome tab opened by this run..."
      close_chrome_tab "$window_id" "$tab_id" || true
      printf 'SUCCESS	%s	%s\n' "$url" "$detected_file"
      return 0
    fi

    rm -f "$before_snapshot"
    log "No Markdown file generated on attempt $attempt."
    cleanup_failed_root_untitled_clips "$attempt_started_at"

    # Fallback: when the primary trigger was the Shortcut, try direct keystroke
    # once before the next full retry. When the primary is already direct
    # keystroke, the outer retry loop will repeat it.
    if [[ -n "$SHORTCUT_NAME" ]] && (( attempt < MAX_RETRIES )); then
      log "Trying direct $CLIP_SHORTCUT fallback..."
      before_snapshot="$(mktemp "${TMPDIR:-/tmp}/obsidian-clip-before.XXXXXX")"
      markdown_snapshot >"$before_snapshot"
      fallback_started_at="$(date +%s)"

      if send_clip_shortcut; then
        if detected_file="$(wait_for_markdown "$before_snapshot")"; then
          rm -f "$before_snapshot"
          log "Markdown detected via fallback: $detected_file"
          log "Closing Chrome tab..."
          close_chrome_tab "$window_id" "$tab_id" || true
          printf 'SUCCESS	%s	%s\n' "$url" "$detected_file"
          return 0
        fi
        log "Direct keystroke also produced no Markdown."
      fi

      cleanup_failed_root_untitled_clips "$fallback_started_at"

      rm -f "$before_snapshot"
    fi
  done

  log "No Markdown file was generated after $MAX_RETRIES attempts."
  log "Closing tab..."
  close_chrome_tab "$window_id" "$tab_id" || true
  return 1
}

# ── main ────────────────────────────────────────────────────────────

main() {
  local url successes failures invalid_count shared_window_id
  declare -a failure_urls=()

  if ! validate_config; then
    exit 2
  fi

  log "Loaded config: $CONFIG_FILE"
  log "Vault path: $VAULT_PATH"
  if [[ -n "$CLIP_OUTPUT_DIR" ]]; then
    log "Clip output dir: ${VAULT_PATH}/${CLIP_OUTPUT_DIR}"
  else
    log "Clip output dir: (entire vault)"
  fi
  log "Shortcut: ${SHORTCUT_NAME:-<disabled — using direct keystroke>}"
  log "Clip keystroke: $CLIP_SHORTCUT"
  if [[ "$LOGIN_WALL_CHECK" == "1" ]]; then
    log "Login-wall check: on (min body text ${LOGIN_WALL_MIN_TEXT} chars)"
  else
    log "Login-wall check: off"
  fi

  invalid_count=0
  for url in "${URLS[@]}"; do
    if ! validate_url "$url"; then
      fail "Invalid URL: $url"
      failure_urls+=("$url")
      invalid_count=$((invalid_count + 1))
      continue
    fi
  done

  if [[ "$DRY_RUN" -eq 1 && "$invalid_count" -gt 0 ]]; then
    log "Dry run failed because one or more URLs are invalid."
    exit 2
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "Dry run complete. Config and HTTP/HTTPS URL validation passed for valid URLs."
    exit 0
  fi

  successes=0
  failures=0
  shared_window_id=""

  for url in "${URLS[@]}"; do
    log "-----"
    log "Starting clip: $url"

    if ! validate_url "$url"; then
      failures=$((failures + 1))
      log "Result: FAILED invalid URL"
      continue
    fi

    local clip_output
    clip_output="$(clip_one_url "$url" "$shared_window_id")" || true

    # Extract the new window id for reuse by the next URL.
    local extracted_window_id
    extracted_window_id="$(printf '%s\n' "$clip_output" | awk -F'\t' '$1 == "WINDOW" { print $2; exit }')"
    if [[ -n "$extracted_window_id" ]]; then
      shared_window_id="$extracted_window_id"
    fi

    if printf '%s\n' "$clip_output" | grep -q '^SUCCESS'; then
      successes=$((successes + 1))
      log "Result: SUCCEEDED"
    else
      failures=$((failures + 1))
      failure_urls+=("$url")
      log "Result: FAILED"
      # Reset window id on failure so the next URL starts fresh.
      shared_window_id=""
    fi
  done

  log "-----"
  log "Finished. Successful clips: $successes. Failures: $failures."
  if [[ ${#failure_urls[@]} -gt 0 ]]; then
    log "Failed URLs:"
    printf '  - %s\n' "${failure_urls[@]}"
  fi

  if (( failures > 0 )); then
    exit 1
  fi
}

main "$@"
