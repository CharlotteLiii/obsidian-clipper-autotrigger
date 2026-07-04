# Changelog

All notable changes to this project will be documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **macOS: Web Clipper extension detection.** New
  `scripts/detect_extension.sh` probes every Chrome (stable) profile
  under `~/Library/Application Support/Google/Chrome/` for the Obsidian
  Web Clipper extension id `cnjifjpddelmedmihgijeibhnjfabmlf`. When
  installed, it also extracts the most recent "save-to" paths from the
  extension's LevelDB clip history.
- `scripts/install.sh` now calls the probe by default and:
  - Prints an `Extension: installed (profile: …)` line in the summary.
  - When the extension is missing, prints the Chrome Web Store link so
    the user can install it in one click.
  - When the recent save-to paths do not match `CLIP_OUTPUT_DIR`, warns
    loudly with the mismatch details so the user updates the Web
    Clipper's Vaults settings *before* the first clip.
  - Skippable via `--skip-extension-check` (useful in CI / headless).
- `AGENT_INSTALL.md` step 4 documents the extension probe and adds a
  new step 5 for the save-to consistency check.

## [0.5.0] - 2026-07-05

### Changed
- **macOS: default trigger is now direct AppleScript keystroke.**
  `SHORTCUT_NAME` now defaults to empty in `config/clipper.conf.example`
  and the installer no longer creates a Shortcut requirement. On empty
  `SHORTCUT_NAME`, `scripts/clip_webpages.sh` calls
  `applescripts/chrome_send_clip_shortcut.scpt` directly instead of
  going through Shortcuts.app. This removes the biggest manual setup
  step (building an `ObsidianClip` Shortcut by hand). The Shortcut path
  remains available as an opt-in via `--use-shortcut` /
  `--shortcut-name` or by editing `SHORTCUT_NAME` after install.
- **Installer auto-detects the Obsidian vault** on macOS by reading
  `~/Library/Application Support/obsidian/obsidian.json` when
  `--vault-path` is omitted. Non-interactive runs use the detected
  currently-open vault; interactive runs get it as the default prompt.
- **Installer flips Chrome's AppleScript / JS-from-Apple-Events
  preference on** via `defaults write com.google.Chrome
  AppleScriptEnabled -bool true` so the login-wall probe works without
  the user having to toggle the Chrome menu item manually. Disable with
  `--no-enable-apple-events`.

### Docs
- `SKILL.md`, `AGENT_INSTALL.md`, `README.md`, `README.zh-CN.md`, and
  `references/usage.md` updated to describe the direct-keystroke path,
  the vault auto-detection, and the Chrome AppleScript-enable step.
  First-clip permission prompts (Accessibility + Automation → Chrome)
  are called out in Step 4 of `AGENT_INSTALL.md`.

## [0.4.0] - 2026-07-04

### Added
- **macOS: post-load login-wall detection** (parity with Windows).
  `applescripts/chrome_login_wall_probe.scpt` runs the same URL /
  DOM / body-text heuristic in the active tab via Chrome's AppleScript
  `execute javascript` command. `scripts/clip_webpages.sh` calls it
  after `wait_for_page_load` and aborts the URL with
  `SUSPECTED_LOGIN_WALL: <reason>` before triggering the Shortcut.
  Requires enabling **Chrome → View → Developer → Allow JavaScript from
  Apple Events** once. If the toggle is off the probe logs a hint and
  the clip proceeds unguarded.
- **macOS config keys.** `LOGIN_WALL_CHECK` (default `1`) and
  `LOGIN_WALL_MIN_TEXT` (default `300`) mirror the Windows knobs,
  documented in `config/clipper.conf.example` and
  `references/usage.md`.
- **Windows: post-load login-wall detection.** `scripts/lib/Cdp.psm1`
  gains `Invoke-CdpEvaluate` and `Test-CdpLoginWall`; after
  `Page.loadEventFired` and before firing the clipper, the script runs a
  CDP `Runtime.evaluate` probe that inspects the final URL path, the
  DOM (`input[type=password]`, paywall / login-wall nodes), and the
  visible body text (EN + zh-CN phrases: `please sign in`, `subscribe
  to read`, `登录后阅读`, `会员专享`, `关注公众号后阅读`, …). On a hit,
  `clip_webpages.ps1` aborts the URL with
  `ERROR: SUSPECTED_LOGIN_WALL: <reason>` and does *not* trigger a
  keystroke, so login pages no longer produce empty "please sign in"
  Markdown notes.
- **Windows config keys.** `LOGIN_WALL_CHECK` (default `1`) toggles the
  probe; `LOGIN_WALL_MIN_TEXT` (default `300`) is the short-body
  threshold for the weak-signal branch. Both are documented in
  `config/clipper.win.conf.example` and
  `references/usage-windows.md`.
- `SKILL.md`: mandatory per-clip login check (`Workflow → Step 0`) that
  agents must run before invoking the platform entrypoint on every
  request, plus a `Workflow → Step 2` diagnosis rule that treats login
  walls as the #1 suspect when the script reports `Result: FAILED`
  (and on Windows tells the agent to short-circuit on
  `SUSPECTED_LOGIN_WALL`).
- `SKILL.md` preflight item 4 (login-wall warning): first-run coverage
  for the same issue, with an explicit two-layer statement — both
  platforms now have the in-script probe as a safety net (Windows via
  CDP, macOS via Chrome AppleScript), and agent-side Step 0 is
  required on top either way.

### Changed
- `README.md`: restructured for humans-first reading order (Features →
  First-run checklist → Requirements → Quick Start → Configuration →
  Usage → Troubleshooting), added console-output demo, Features /
  Requirements sections, Configuration table, Troubleshooting table,
  exit-code documentation, badges, and a Chinese translation
  (`README.zh-CN.md`).
- `README.md`: fixed License field (was `TBD`, now MIT) and made the
  macOS / Windows Manual Install steps symmetric (both start from the
  `.example` config template).

### Known limitations
- **Login-wall probe is heuristic.** Same-origin only (main frame), and
  a mix of URL path patterns, DOM checks, and phrase matching
  (EN + zh-CN). False positives can be worked around by raising
  `LOGIN_WALL_MIN_TEXT`, extending the phrase list, or turning the
  probe off with `LOGIN_WALL_CHECK=0`.
- **macOS probe requires an opt-in.** Chrome disables
  `execute javascript` by default; users must enable it once from the
  View → Developer menu. Without it the probe cannot inspect the page.

## [0.3.0] - 2026-07-04

### Added
- `AGENT_INSTALL.md` — machine-readable install contract for AI agents.
- Multi-host auto-detection in both installers: OpenClaw
  (`~/.openclaw/workspace/skills`, `~/.openclaw/skills`), Claude Code
  (`~/.claude/skills`), and Codex (`~/.codex/skills`). By default the
  skill is linked into every host directory that exists.
- Full non-interactive support in `scripts/install.sh` and
  `scripts/install.ps1`, driven by CLI flags. Missing optional values
  fall back to sensible defaults instead of prompting.
- `--target-root` / `-TargetRoot` to override multi-host auto-detection
  and pin a single install location.
- `scripts/preflight.sh` and `scripts/preflight.ps1` — self-check
  scripts that probe Chrome CDP, list the extensions in the CDP profile,
  and verify vault existence before the first clip.
- MIT `LICENSE`.
- `CHANGELOG.md`, `CONTRIBUTING.md`, and GitHub issue templates.

### Changed
- Windows installer defaults `TriggerDriver` to `sendkeys` in unattended
  mode (zero install) instead of failing when AutoHotkey is missing.
- `SKILL.md` front-matter now includes `version`, `homepage`, and
  `license`.
- `README.md` and per-platform docs now point AI agents to
  `AGENT_INSTALL.md` first.
- Windows installer opens the Chrome Web Store install page for the
  Obsidian Web Clipper extension (in the CDP profile) at the end of
  setup, so users do not have to hunt for the correct profile.

### Fixed
- Windows installer no longer hard-fails when PowerShell 7 is missing
  without telling the user how to fix it — it prints the exact winget
  command and the pwsh rerun command.
- `config/clipper.win.conf` is now correctly patched in place instead of
  being overwritten wholesale, preserving user comments and unknown
  keys.

## [0.2.0]

Initial public prerelease with macOS + Windows entrypoints, Chrome CDP
driver, and AHK / SendKeys trigger drivers. Installers linked into a
single host directory (`$CODEX_HOME/skills` fallback to `~/.codex/skills`).
