# Obsidian-Clipper-AutoTrigger — Windows usage

> 🤖 If you are an AI agent installing this skill, read
> [`../AGENT_INSTALL.md`](../AGENT_INSTALL.md) first. This file assumes a
> human is running the commands.

Windows entrypoint: `scripts/clip_webpages.ps1`. It mirrors the macOS `.sh`
contract but drives Chrome through the DevTools Protocol (CDP) instead of
AppleScript, and triggers the Web Clipper extension via AutoHotkey v2 or
`SendKeys`.

## Prerequisites

1. **Windows 10/11**.
2. **PowerShell 7+** (`pwsh`). Install with `winget install Microsoft.PowerShell` or from https://aka.ms/powershell.
3. **Google Chrome** with the **Obsidian Web Clipper** extension installed and configured to save into your vault. Set the extension's "Save to" folder to match `CLIP_OUTPUT_DIR`.
4. **Trigger driver** (choose one during install):
   - `ahk` — install **AutoHotkey v2** (`winget install AutoHotkey.AutoHotkey`). Recommended: more reliable, tolerates focus changes better.
   - `sendkeys` — no extra install; uses `System.Windows.Forms.SendKeys`. Works, but sensitive to focus and modifier state.
5. The Web Clipper's clip shortcut is left at its default `Shift+Alt+S`. Both drivers send this chord.

## First-time setup

```powershell
pwsh -NoProfile -File "scripts\install.ps1"
```

The installer asks:
- Which trigger driver to use (with a one-line description of each).
- If AHK is selected but missing, whether to install it via `winget`.
- Absolute path to your Obsidian vault.
- Relative "Save to" folder inside the vault.

It writes `config/clipper.win.conf` and links the skill into every
detected agent skills directory it finds (OpenClaw at
`%USERPROFILE%\.openclaw\workspace\skills`, Claude Code at
`%USERPROFILE%\.claude\skills`, and Codex at `%USERPROFILE%\.codex\skills`).
Pass `-TargetRoot <dir>` to pin a single location. It falls back from
symlink to directory junction to copy depending on Windows Developer Mode
/ Admin state.

> **UTF-8 note.** The generated `config/clipper.win.conf` is UTF-8 without
> BOM. Windows PowerShell 5.1's default `Get-Content` and legacy `notepad`
> misrender it as mojibake, but the file itself is correct — open it in
> `pwsh` 7, VS Code, or Notepad++ and non-ASCII paths (Chinese, spaces,
> etc.) will display fine. The skill's own scripts always read it as UTF-8.

To rerun non-interactively:

```powershell
pwsh -NoProfile -File "scripts\install.ps1" `
    -Unattended `
    -TriggerDriver ahk `
    -VaultPath "C:\Users\me\Obsidian\Vault" `
    -ClipOutputDir "Inbox\Clippings"
```

## Clipping

```powershell
pwsh -NoProfile -File "scripts\clip_webpages.ps1" "https://example.com/article"
pwsh -NoProfile -File "scripts\clip_webpages.ps1" "https://a.com" "https://b.com"
pwsh -NoProfile -File "scripts\clip_webpages.ps1" -DryRun "https://example.com"
pwsh -NoProfile -File "scripts\clip_webpages.ps1" -Config "D:\my.conf" "https://x.com"
```

What happens per URL:
1. If Chrome is not already listening on `CHROME_DEBUG_PORT`, the script
   starts Chrome with `--remote-debugging-port=9222` and a dedicated
   profile under `%LOCALAPPDATA%\Obsidian-Clipper-AutoTrigger\chrome-profile`.
2. A new tab is opened via CDP; the script waits for `Page.loadEventFired`
   plus a small render grace period.
3. The tab is brought to the foreground; the configured trigger driver
   sends `Shift+Alt+S` to Chrome to run the clipper.
4. The vault's Markdown files are diffed against the pre-clip snapshot;
   the newest changed file is reported as the result.
5. On failure, root-level `Untitled*.md` artefacts created during the
   attempt are cleaned up (only when `CLIP_OUTPUT_DIR` is set).
6. The tab opened by the script is closed. Pre-existing tabs are left
   alone.

## Chrome profile note

CDP requires Chrome to be launched with `--remote-debugging-port`. If your
normal Chrome is already running without that flag, the script starts a
second instance with a separate `--user-data-dir` so it does not conflict.
You will need to install the Obsidian Web Clipper extension inside this
managed profile the first time, or set `CHROME_USER_DATA_DIR` to point at
an existing profile that has the extension and is not currently open.

## Troubleshooting

- **"AutoHotkey executable not found on PATH"** — install AutoHotkey v2 or
  set `TRIGGER_DRIVER=sendkeys` in `config/clipper.win.conf`.
- **"Chrome did not expose DevTools on port 9222"** — another Chrome
  instance may be holding the profile. Close all Chrome windows or point
  `CHROME_USER_DATA_DIR` to a fresh folder.
- **Clipper opens but nothing saves** — the extension's "Save to" folder
  does not match `CLIP_OUTPUT_DIR`, or Obsidian is not running with the
  vault open. Fix the extension setting and rerun.
- **SendKeys fires but no popup** — another window stole focus between
  `bringToFront` and the keystroke. Switch to the `ahk` driver.
- **Symlink refused during install** — enable Windows Developer Mode
  (Settings → Privacy & security → For developers), or run the installer
  from an elevated PowerShell. A directory junction or copy is used as a
  fallback either way.
- **`ERROR: SUSPECTED_LOGIN_WALL: ...`** — the post-load probe detected a
  login form, paywall node, auth-style URL, or a known "please sign in /
  请登录后阅读" phrase, and aborted before triggering the clipper. Open
  the same URL in the Chrome profile the skill drives (the one with
  `--user-data-dir=...\Obsidian-Clipper-AutoTrigger\chrome-profile`),
  sign in, then rerun. To disable the check, set `LOGIN_WALL_CHECK=0`
  in `config/clipper.win.conf`; the false-positive threshold for
  "short body text" is tunable via `LOGIN_WALL_MIN_TEXT`.
