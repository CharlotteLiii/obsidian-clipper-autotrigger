#!/usr/bin/env bash
#
# Obsidian-Clipper-AutoTrigger — one-line bootstrap installer (macOS/Linux).
#
# Typical usage from an AI agent (OpenClaw / Codex / Claude / etc.):
#   bash <(curl -fsSL https://raw.githubusercontent.com/CharlotteLiii/obsidian-clipper-autotrigger/main/bootstrap.sh)
#
# What it does:
#   1. Detects git, bash, and the target agent's skills directory.
#   2. git clones (or pulls) this repo into the skills directory.
#   3. Copies config/clipper.conf.example -> config/clipper.conf if missing.
#   4. Invokes scripts/install.sh to finish setup (symlink + chmod).
#   5. Prints a checklist of the interactive fields the user still needs to
#      fill in inside config/clipper.conf (VAULT_PATH, CLIP_OUTPUT_DIR, ...).
#
# Env vars (all optional):
#   OCA_REPO_URL       Git URL to clone. Defaults to the canonical repo below.
#   OCA_INSTALL_DIR    Absolute path to place the skill. Autodetected if unset.
#   OCA_BRANCH         Branch/tag to check out. Defaults to main.
#   OCA_UNATTENDED     If set to 1, skip interactive prompts (agent mode).

set -euo pipefail

REPO_URL_DEFAULT="https://github.com/CharlotteLiii/obsidian-clipper-autotrigger.git"
SKILL_NAME="Obsidian-Clipper-AutoTrigger"

REPO_URL="${OCA_REPO_URL:-$REPO_URL_DEFAULT}"
BRANCH="${OCA_BRANCH:-main}"
UNATTENDED="${OCA_UNATTENDED:-0}"

log()  { printf '\033[36m[oca]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[oca]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m[oca] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git is required. Install it (e.g. 'xcode-select --install') and rerun."

# ── Pick a skills directory ────────────────────────────────────────
#
# The bootstrap just needs ONE stable place to keep the git clone. The
# platform installer (scripts/install.sh) then links the skill into every
# detected agent host (OpenClaw / Claude Code / Codex). So the choice
# below is only about where the SOURCE tree lives, not which agents get
# the skill.

detect_source_dir() {
  local candidates=(
    "$HOME/.local/share/skills-src"
    "$HOME/.openclaw/workspace/skills-src"
  )
  for d in "${candidates[@]}"; do
    if [[ -d "$d" ]]; then
      printf '%s\n' "$d"
      return 0
    fi
  done
  printf '%s\n' "$HOME/.local/share/skills-src"
}

TARGET_ROOT="${OCA_INSTALL_DIR:-$(detect_source_dir)}"
TARGET_DIR="$TARGET_ROOT/obsidian-clipper-autotrigger"

log "Skill target: $TARGET_DIR"
mkdir -p "$TARGET_ROOT"

# ── Clone or update ─────────────────────────────────────────────────

if [[ -d "$TARGET_DIR/.git" ]]; then
  log "Existing checkout found; updating..."
  git -C "$TARGET_DIR" fetch --quiet origin "$BRANCH"
  git -C "$TARGET_DIR" checkout --quiet "$BRANCH"
  git -C "$TARGET_DIR" pull --ff-only --quiet
elif [[ -e "$TARGET_DIR" ]]; then
  die "Target exists and is not a git checkout: $TARGET_DIR
Move it aside (e.g. mv \"$TARGET_DIR\" \"$TARGET_DIR.bak\") and rerun."
else
  log "Cloning $REPO_URL (branch $BRANCH)..."
  git clone --quiet --branch "$BRANCH" --depth 1 "$REPO_URL" "$TARGET_DIR"
fi

# ── Seed config ─────────────────────────────────────────────────────

CFG_EXAMPLE="$TARGET_DIR/config/clipper.conf.example"
CFG_ACTIVE="$TARGET_DIR/config/clipper.conf"
if [[ -f "$CFG_EXAMPLE" && ! -f "$CFG_ACTIVE" ]]; then
  cp "$CFG_EXAMPLE" "$CFG_ACTIVE"
  log "Seeded $CFG_ACTIVE from example."
fi

# ── Wire the skill into the agent ──────────────────────────────────

if [[ -x "$TARGET_DIR/scripts/install.sh" ]]; then
  log "Running scripts/install.sh..."
  "$TARGET_DIR/scripts/install.sh" || warn "install.sh returned non-zero; check messages above."
else
  chmod +x "$TARGET_DIR/scripts/clip_webpages.sh" 2>/dev/null || true
fi

# ── Post-install checklist ──────────────────────────────────────────

cat <<EOF

✅ $SKILL_NAME installed at:
   $TARGET_DIR

Next steps (edit these fields in $CFG_ACTIVE):
   • VAULT_PATH        → absolute path to your Obsidian vault
   • CLIP_OUTPUT_DIR   → relative folder inside the vault (must match the
                          "Save to" folder in the Web Clipper extension)
   • SHORTCUT_NAME     → the macOS Shortcut that triggers the clipper
                          (default: ObsidianClip; see references/usage.md
                          for how to create it)

Then dry-run:
   "$TARGET_DIR/scripts/clip_webpages.sh" --dry-run "https://example.com"

Restart your agent (OpenClaw / Codex) so it re-scans skills.
EOF
