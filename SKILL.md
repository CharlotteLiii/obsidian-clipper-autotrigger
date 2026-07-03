---
name: obsidian-clipper-autotrigger
description: Clip one or more webpages into an Obsidian vault by driving Google Chrome and the installed Obsidian Web Clipper extension. Works on macOS (AppleScript + Shortcuts) and Windows (CDP + AutoHotkey/SendKeys). Use when the user asks to clip/save/archive/capture webpages or URLs into Obsidian, especially prompts like "Clip this webpage", "Clip these webpages", "save this article to Obsidian", or "use Obsidian Web Clipper".
version: 0.3.0
homepage: https://github.com/CharlotteLiii/obsidian-clipper-autotrigger
license: MIT
---

# Obsidian-Clipper-AutoTrigger

Use this skill to clip HTTP/HTTPS webpages into an Obsidian vault through
the user's working Obsidian Web Clipper Chrome extension.

## ⚠️ Preflight — confirm with the user before the first run

On any machine where this skill has not run successfully before, remind
the user of the three requirements below and get explicit confirmation on
each one. If any is unverified, walk the user through it *before* invoking
the script — do not just run and let it fail.

1. **Chrome extension installed.** The "Obsidian Web Clipper" extension
   must be installed inside the Chrome instance this skill will drive.
   On Windows the skill launches a dedicated `--user-data-dir` profile
   the first time it runs; the extension must be installed *inside that
   profile* (see Operational Notes below).
2. **Shortcut is bound and works in Chrome.** Ask the user to open any
   page in that Chrome profile and press the clip keystroke manually,
   confirming the Web Clipper popup opens. If nothing happens, the
   extension shortcut is not bound — direct the user to
   `chrome://extensions/shortcuts` to bind it.
3. **Configured shortcut must match Chrome.** The value of
   `CLIP_SHORTCUT` in `config/clipper.conf` (macOS) or `CLIP_SHORTCUT` in
   `config/clipper.win.conf` (Windows) must equal the key combo actually
   bound at `chrome://extensions/shortcuts` for Obsidian Web Clipper.
   Defaults: `Shift+Option+S` (macOS) / `Shift+Alt+S` (Windows). If the
   user customized the shortcut, update the config accordingly before
   running.

A short verification script you can offer the user:

> "Before I clip anything, please open Chrome, load any page, and press
> your Web Clipper shortcut manually. Does the clipper popup appear? If
> yes, tell me the exact key combo you pressed — I'll make sure the
> config matches."

## Platform entrypoints

Pick the entrypoint that matches the host OS. Both scripts share the same
CLI contract: a config file, an optional `--dry-run`, and one or more URLs.

- **macOS**: `scripts/clip_webpages.sh URL [URL ...]`
- **Windows**: `pwsh -NoProfile -File scripts/clip_webpages.ps1 URL [URL ...]`

On macOS the skill drives Chrome via AppleScript and triggers the clipper
through the `ObsidianClip` macOS Shortcut (with `Shift+Option+S` as a
fallback). On Windows the skill drives Chrome via the DevTools Protocol
and triggers the clipper via AutoHotkey v2 or `SendKeys`. Windows requires
PowerShell 7+; if unavailable, install with `winget install Microsoft.PowerShell`.

## Installation

**AI agents installing this skill from GitHub**: read
[`AGENT_INSTALL.md`](AGENT_INSTALL.md) — it is the machine-readable
contract for clone → configure → link → verify.

**Humans installing manually**: read the top of [`README.md`](README.md).

Quick reference for both installers:

- macOS: `scripts/install.sh [--vault-path <path>] [--non-interactive] [--target-root <dir>]`
- Windows: `pwsh -NoProfile -File scripts/install.ps1 [-VaultPath <path>] [-Unattended] [-TargetRoot <dir>]`

Both installers now auto-detect OpenClaw / Claude Code / Codex skills
directories and link into every host that exists. Pass `--target-root` /
`-TargetRoot` to pin a single location.

## Workflow (both platforms)

1. Validate each URL before doing anything else. Only `http://` and `https://` URLs are accepted.
2. Run the platform entrypoint with the requested URL list. It:
   - Loads the platform config (`config/clipper.conf` on macOS,
     `config/clipper.win.conf` on Windows).
   - Ensures Chrome is running (Windows: with `--remote-debugging-port`).
   - Opens the first URL as a new tab and reuses the same window/session
     for subsequent URLs.
   - Waits for the page to finish loading, with a short render grace
     period for JavaScript-heavy pages.
   - Triggers the Obsidian Web Clipper via the platform driver.
   - Compares Markdown files under `VAULT_PATH` (or `CLIP_OUTPUT_DIR`
     subdirectory) before and after clipping.
   - Cleans up stray root-level `Untitled*.md` files produced by failed
     attempts when `CLIP_OUTPUT_DIR` is configured.
   - Retries per URL up to `MAX_RETRIES`.
   - Closes only the tab it opened after a successful clip or final
     failure, prints detailed progress logs, exits non-zero on failure.
3. Report the result from the script output, including the detected
   Markdown filename when present and the final success/failure counts.

## Configuration

Edit the platform config before first use if the defaults do not match
the environment. Keep values shell-quoted when they contain spaces.

Shared keys (semantics identical on both platforms):

- `VAULT_PATH`: absolute path to the Obsidian vault to monitor.
- `CLIP_OUTPUT_DIR`: relative "Save to" folder inside the vault. Leave
  empty to scan the whole vault.
- `CLIP_SHORTCUT`: the key combo bound to Obsidian Web Clipper in Chrome
  (`chrome://extensions/shortcuts`). Defaults: `Shift+Option+S` on macOS,
  `Shift+Alt+S` on Windows. Must match Chrome exactly or clipping will
  silently do nothing. See [Shortcut format](#shortcut-format) below.
- `PAGE_LOAD_TIMEOUT`, `RENDER_GRACE_SECONDS`, `CLIP_TIMEOUT`,
  `MAX_RETRIES`, `POLL_INTERVAL`: timing knobs.

### Shortcut format

`CLIP_SHORTCUT` uses a human-readable form with `+` between modifiers and
the key. Modifiers accepted: `Shift`, `Ctrl`/`Control`, `Alt`/`Option`,
`Cmd`/`Meta`/`Win`. Order does not matter, case-insensitive. Examples:

- `Shift+Alt+S` (Windows default)
- `Shift+Option+S` (macOS default; `Option` is an alias for `Alt`)
- `Ctrl+Shift+O` (a common user override)

macOS-only keys:

- `SHORTCUT_NAME`: name of the macOS Shortcut that runs the clipper
  (default `ObsidianClip`).
- `CHECK_SHORTCUT_EXISTS`: refuse to start if the Shortcut is missing.

Windows-only keys:

- `TRIGGER_DRIVER`: `ahk` (AutoHotkey v2) or `sendkeys`.
- `AHK_EXE`: path or name of the AutoHotkey executable.
- `CHROME_EXE`: Chrome binary path; empty means auto-detect.
- `CHROME_DEBUG_PORT`: DevTools Protocol port (default `9222`).
- `CHROME_USER_DATA_DIR`: profile for the CDP-controlled Chrome
  instance; empty means a per-user folder under `%LOCALAPPDATA%`.

## Usage Examples

macOS:

```bash
scripts/clip_webpages.sh "https://example.com/article"
scripts/clip_webpages.sh "https://a.com" "https://b.com" "https://c.com"
scripts/clip_webpages.sh --config /absolute/path/to/clipper.conf "https://example.com"
scripts/clip_webpages.sh --dry-run "https://example.com"
```

Windows:

```powershell
pwsh -NoProfile -File scripts\clip_webpages.ps1 "https://example.com/article"
pwsh -NoProfile -File scripts\clip_webpages.ps1 "https://a.com" "https://b.com"
pwsh -NoProfile -File scripts\clip_webpages.ps1 -DryRun "https://example.com"
pwsh -NoProfile -File scripts\clip_webpages.ps1 -Config "D:\my.conf" "https://x.com"
```

For macOS setup details, Shortcut creation, and troubleshooting, read
[references/usage.md](references/usage.md). For Windows setup and
troubleshooting, read [references/usage-windows.md](references/usage-windows.md).

## Operational Notes (macOS)

- The Shortcut approach is primary; `Shift+Option+S` is a Chrome
  extension shortcut, not a global macOS shortcut, so the Shortcut
  must activate Google Chrome before sending the keystroke. Use
  `applescripts/shortcut_obsidian_clip_template.applescript` as the
  template.
- Requires macOS Automation permission for Terminal/Codex to control
  Google Chrome via `osascript`, and Accessibility permission if the
  Shortcut sends keystrokes.
- On failed attempts with `CLIP_OUTPUT_DIR` set, the script only removes
  `Untitled*.md` files directly under `VAULT_PATH` that were created or
  modified during the failed attempt.

## Operational Notes (Windows)

- The script starts Chrome with `--remote-debugging-port` and a dedicated
  profile if no CDP endpoint is already listening. The Obsidian Web
  Clipper extension must be installed inside that profile (or
  `CHROME_USER_DATA_DIR` set to an existing profile that has it).
- AutoHotkey v2 is the recommended trigger driver; SendKeys works but is
  sensitive to focus changes. The installer lets the user choose and
  offers to install AHK via `winget`.
- Symlink creation into `%CODEX_HOME%\skills` requires Developer Mode or
  Administrator; the installer falls back to a directory junction and
  then a copy.
