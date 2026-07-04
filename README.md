# Obsidian-Clipper-AutoTrigger

[English](README.md) · [中文](README.zh-CN.md)

> Drive the Obsidian Web Clipper Chrome extension from the command line.
> One URL, a whole reading queue, or an AI agent request → parsed to
> Markdown inside your Obsidian vault, hands-free.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform: macOS · Windows](https://img.shields.io/badge/platform-macOS%20%7C%20Windows-blue)
![Requires: PowerShell 7+ on Windows](https://img.shields.io/badge/pwsh-7%2B-informational)

Runs on **macOS** (AppleScript + optional Shortcuts) and **Windows** (Chrome DevTools
Protocol + AutoHotkey / SendKeys). Same CLI contract on both platforms.
On macOS the default trigger is direct AppleScript keystroke — no manual
Shortcut needs to be built.

```console
$ scripts/clip_webpages.sh "https://example.com/article"
[2026-07-04 17:00:00] Loaded config: config/clipper.conf
[2026-07-04 17:00:00] Vault path: /Users/me/Obsidian Vault
[2026-07-04 17:00:01] Opening Chrome for: https://example.com/article
[2026-07-04 17:00:03] Page loaded: Example Article — example.com
[2026-07-04 17:00:04] Triggering clipper via direct keystroke 'Shift+Option+S' (attempt 1/3)...
[2026-07-04 17:00:06] Markdown detected: /Users/me/Obsidian Vault/Inbox/Clippings/Example Article.md
[2026-07-04 17:00:06] Result: SUCCEEDED
```

---

## Features

- One command, many URLs — batch-clip a reading queue instead of
  clicking the extension icon N times.
- Cross-platform (macOS + Windows) with a shared CLI contract.
- Reuses your existing Obsidian Web Clipper install — no re-parsing,
  no formatting drift.
- **Cross-platform login-wall detection.** After the page loads, the
  script probes the URL, DOM, and body text (EN + zh-CN) via Chrome
  DevTools (Windows) or Chrome AppleScript `execute javascript`
  (macOS). Suspected login / paywall pages are aborted with
  `SUSPECTED_LOGIN_WALL` before the clipper fires, so login pages no
  longer produce empty "please sign in" notes. Toggle with
  `LOGIN_WALL_CHECK=0`. See [Known limitations](#known-limitations)
  for the macOS opt-in.
- Auto-retries with adaptive polling; cleans up half-written
  `Untitled*.md` artefacts from failed attempts.
- Ships as an installable **AI-agent skill** (OpenClaw / Claude Code /
  Codex) so an agent can clip pages on your behalf.

---

## First-run checklist

Before your first successful clip on a machine, confirm **all four**:

1. **Extension installed** in the Chrome profile this skill drives.
   On Windows that is a fresh dedicated `--user-data-dir` profile created
   on first run — *not* your normal Chrome profile.
2. **Shortcut works manually.** Open any page in that Chrome, press the
   shortcut yourself, and confirm the Web Clipper popup appears. If
   nothing happens, bind it at `chrome://extensions/shortcuts`.
3. **Config matches Chrome.** `CLIP_SHORTCUT` in the config file must
   equal the key combo you actually bound in Chrome.
4. **You are logged in** to any site that requires it, *inside the driven
   Chrome profile*. Login-wall handling is now available on both
   platforms:
   - **Windows**: the script runs a CDP probe after page load and aborts
     with `SUSPECTED_LOGIN_WALL` on hit.
   - **macOS**: same behaviour via Chrome's AppleScript `execute
     javascript` command. Enable it once in *Chrome → View → Developer
     → Allow JavaScript from Apple Events*; without it the probe logs a
     hint and the clip proceeds without the safety net.

   Either way, sign in **inside the driven Chrome profile** *before*
   clipping known auth-gated URLs (Medium members-only posts, WeChat
   subscription articles, private Notion pages, Twitter/X timelines,
   corporate SSO, etc.).

### ⚠️ First run on a fresh machine is expected to fail

The first clip on a clean install spins up a brand-new Chrome profile
with **no extension** installed — all three retries will fail and the
script stops. That's normal. Do **not** close that Chrome window; instead:

1. Install [Obsidian Web Clipper][Obsidian Web Clipper] inside the new profile.
2. Open its settings → set the "Save to" folder to match your `CLIP_OUTPUT_DIR`.
3. Bind the extension shortcut at `chrome://extensions/shortcuts`.
4. Rerun the clip — it should succeed on attempt 1.

See [`references/usage.md`](references/usage.md) (macOS) and
[`references/usage-windows.md`](references/usage-windows.md) (Windows)
for the full walkthrough, including the optional macOS Shortcut path.

---

## Requirements

- **Google Chrome** with the [Obsidian Web Clipper] extension installed.
- **Obsidian vault** on the local filesystem.
- **macOS**: macOS 13+ with the Shortcuts app; command-line `shortcuts` CLI.
- **Windows**: PowerShell 7+ (`winget install Microsoft.PowerShell`) and
  optionally AutoHotkey v2 (`winget install AutoHotkey.AutoHotkey`).
  Without AutoHotkey the skill falls back to `SendKeys`.

[Obsidian Web Clipper]: https://chromewebstore.google.com/detail/obsidian-web-clipper/cnjifjpddelmedmihgijeibhnjfabmlf

---

## Quick Start

### macOS

```bash
git clone https://github.com/CharlotteLiii/obsidian-clipper-autotrigger.git
cd obsidian-clipper-autotrigger
cp config/clipper.conf.example config/clipper.conf
# Edit VAULT_PATH, CLIP_OUTPUT_DIR, CLIP_SHORTCUT to match your setup.
scripts/install.sh
scripts/clip_webpages.sh --dry-run "https://example.com"
```

### Windows (PowerShell 7+)

```powershell
git clone https://github.com/CharlotteLiii/obsidian-clipper-autotrigger.git
cd obsidian-clipper-autotrigger
Copy-Item config\clipper.win.conf.example config\clipper.win.conf
# Edit VAULT_PATH, CLIP_OUTPUT_DIR, CLIP_SHORTCUT to match your setup.
pwsh -NoProfile -File scripts\install.ps1
pwsh -NoProfile -File scripts\clip_webpages.ps1 -DryRun "https://example.com"
```

<details>
<summary><b>Prefer a one-line agent install?</b> (curl / iwr)</summary>

Ask your AI agent (OpenClaw / Codex / Claude / etc.):

> "Install the skill at https://github.com/CharlotteLiii/obsidian-clipper-autotrigger"

Or run one of these bootstraps yourself:

```bash
# macOS / Linux
bash <(curl -fsSL https://raw.githubusercontent.com/CharlotteLiii/obsidian-clipper-autotrigger/main/bootstrap.sh)
```

```powershell
# Windows
iwr -useb https://raw.githubusercontent.com/CharlotteLiii/obsidian-clipper-autotrigger/main/bootstrap.ps1 | iex
```

The bootstrap will detect your agent's skills directory
(OpenClaw → Claude Code → Codex), `git clone` this repo into it, run the
platform installer, and print a short checklist of fields to fill in.
Restart your agent afterwards so it re-scans the skills directory.

Inspect the bootstrap scripts before piping into your shell — both are
short and do nothing beyond `git clone` + running the shipped installer.

</details>

---

## Configuration

`config/clipper.conf` (macOS) and `config/clipper.win.conf` (Windows)
are **git-ignored**. Copy from the `*.example` templates and edit the
fields below. Everything else has safe defaults.

| Key                | What it does                                                                                                                                                | Default                        |
|--------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------|
| `VAULT_PATH`       | Absolute path to your Obsidian vault. Must exist.                                                                                                            | *(required)*                   |
| `CLIP_OUTPUT_DIR`  | Relative folder inside the vault where the Web Clipper saves notes. Match your extension's "Save to" folder. Leave empty to scan the whole vault.            | `""` (whole vault)             |
| `CLIP_SHORTCUT`    | The key combo you bound at `chrome://extensions/shortcuts` for Obsidian Web Clipper. Must match Chrome exactly.                                              | `Shift+Option+S` / `Shift+Alt+S` |
| `SHORTCUT_NAME`    | *(macOS only, optional)* Name of an existing macOS Shortcut that fronts the keystroke. Leave empty to use direct AppleScript keystroke (default). See `references/usage.md`.                    | *(empty)*                     |
| `TRIGGER_DRIVER`   | *(Windows only)* `ahk` (AutoHotkey v2) or `sendkeys`.                                                                                                        | `sendkeys`                     |
| `CHROME_USER_DATA_DIR` | *(Windows only)* Optional Chrome profile the skill drives. Empty → a dedicated per-user profile under `%LOCALAPPDATA%`.                                  | `""`                           |
| `LOGIN_WALL_CHECK` | `1` runs the post-load login-wall probe and aborts the URL on hit. `0` disables the probe (previous behaviour).                                                | `1`                            |
| `LOGIN_WALL_MIN_TEXT` | Body-text length below which the probe treats an accompanying weak signal as suspicious. Raise if you clip many legitimately short pages.                    | `300`                          |

Timing knobs — `PAGE_LOAD_TIMEOUT`, `RENDER_GRACE_SECONDS`,
`CLIP_TIMEOUT`, `MAX_RETRIES`, `POLL_INTERVAL` — usually don't need
tuning; see the `.example` files for details.

---

## Usage

```bash
# macOS
scripts/clip_webpages.sh "https://example.com/article"
scripts/clip_webpages.sh "https://a.com" "https://b.com" "https://c.com"
scripts/clip_webpages.sh --dry-run "https://example.com"
scripts/clip_webpages.sh --config /absolute/path/to/clipper.conf "https://example.com"
```

```powershell
# Windows
pwsh -NoProfile -File scripts\clip_webpages.ps1 "https://example.com"
pwsh -NoProfile -File scripts\clip_webpages.ps1 -DryRun "https://a.com" "https://b.com"
pwsh -NoProfile -File scripts\clip_webpages.ps1 -Config "D:\my.conf" "https://x.com"
```

Or just tell your AI agent: *"Use Obsidian-Clipper-AutoTrigger to save
&lt;URL&gt; to Obsidian."*

Exit codes: `0` all URLs clipped, `1` some failed (including
`SUSPECTED_LOGIN_WALL` aborts), `2` config or CLI error.

---

## Troubleshooting

> **When the script reports `Result: FAILED`, login wall is suspect #1.**
> Look for `ERROR: SUSPECTED_LOGIN_WALL: <reason>` in the log — the probe
> caught it explicitly on both platforms, no guessing needed. If the
> probe is disabled or the macOS Chrome permission is off, the script
> cannot tell a login redirect apart from any other failure — it only
> sees "no new Markdown after N retries". Before blaming the extension,
> the shortcut, or timing, open the failing URL manually in the *driven*
> Chrome profile and check whether the page actually renders. If you see
> a login form, a "please sign in / 请登录后阅读" banner, or a paywall,
> that's the cause. Log in inside that profile and rerun.

| Symptom                                            | Likely cause                                                                                                                                       |
|----------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| `ERROR: SUSPECTED_LOGIN_WALL: <reason>`            | The post-load probe hit a login / paywall signal. Sign into the site inside the driven Chrome profile and retry.                                   |
| macOS: `Login-wall probe error` in the log         | Chrome's *View → Developer → Allow JavaScript from Apple Events* is off. Enable it once. The clip still runs, just without the safety net.        |
| Every attempt fails, no Markdown appears           | **First check: does the URL need login?** (see callout above). Otherwise: extension not installed in the driven profile, or shortcut not bound.    |
| Clipper popup appears but no `.md` written         | `CLIP_OUTPUT_DIR` doesn't match the extension's "Save to" folder.                                                                                  |
| False-positive `SUSPECTED_LOGIN_WALL`              | Raise `LOGIN_WALL_MIN_TEXT`, or set `LOGIN_WALL_CHECK=0` in the platform config to disable the probe.                                              |
| Windows: `pwsh` not found                          | Install PowerShell 7: `winget install Microsoft.PowerShell`.                                                                                       |
| Windows: `SendKeys` sends to the wrong app         | Another window stole focus. Use `TRIGGER_DRIVER=ahk` and install AutoHotkey v2 for a more robust driver.                                            |
| macOS: `shortcuts list` shows nothing              | Grant Shortcuts access in *System Settings → Privacy & Security → Automation*.                                                                     |

For deeper debugging run `scripts/preflight.sh` / `scripts\preflight.ps1`
— it probes Chrome CDP, lists installed extensions in the driven
profile, and verifies the vault path.

---

## Known limitations

- **The login-wall probe is heuristic**, not perfect. It uses a mix of
  URL path patterns, DOM probes, and body-text phrase matches (EN +
  zh-CN). Legitimate short pages with an auth-styled URL can still
  trip it. If that happens, raise `LOGIN_WALL_MIN_TEXT`, extend the
  phrase list (`Test-CdpLoginWall` on Windows,
  `chrome_login_wall_probe.scpt` on macOS), or turn the probe off with
  `LOGIN_WALL_CHECK=0`.
- **macOS probe requires a Chrome opt-in.** Enable *View → Developer →
  Allow JavaScript from Apple Events* once. Without it the probe logs a
  hint and the clip proceeds without the safety net.
- **Same-origin only.** The probe runs in the target tab's main frame.
  Login walls served inside cross-origin iframes are not inspected.

---

## For AI agents

If an AI agent (OpenClaw / Claude Code / Codex) is installing or driving
this skill, read **[`AGENT_INSTALL.md`](AGENT_INSTALL.md)** — that file
is the machine-readable contract for clone → configure → link → verify.
The agent-facing entrypoint is [`SKILL.md`](SKILL.md), which is what the
agent loads at runtime. `SKILL.md` also defines a **mandatory per-clip
login check** (Step 0 in the Workflow) that agents run *before* the
platform entrypoint — the post-load probe is a safety net, not a
substitute for asking the user to sign in on known auth-gated hosts.

---

## Repository layout

```
Obsidian-Clipper-AutoTrigger/
├── SKILL.md                          # Agent entry point (loaded at runtime)
├── AGENT_INSTALL.md                  # Install contract for AI agents
├── README.md                         # This file
├── CHANGELOG.md · CONTRIBUTING.md · LICENSE
├── bootstrap.sh · bootstrap.ps1      # One-line agent installer
├── config/
│   ├── clipper.conf.example          # macOS config template (+ login-wall keys)
│   ├── clipper.win.conf.example      # Windows config template (+ login-wall keys)
│   └── clipper.conf                  # (generated locally, git-ignored)
├── scripts/
│   ├── clip_webpages.sh              # macOS entrypoint (with login-wall probe)
│   ├── clip_webpages.ps1             # Windows entrypoint (with login-wall probe)
│   ├── install.sh · install.ps1      # Platform installers
│   ├── preflight.sh · preflight.ps1  # Environment self-check
│   ├── lib/Cdp.psm1                  # Windows CDP client + Test-CdpLoginWall
│   └── trigger/                      # Windows keystroke drivers
├── applescripts/                     # macOS Chrome / Shortcut glue (+ login-wall probe)
├── references/                       # Detailed usage docs
└── agents/                           # Agent-specific metadata
```

---

## Privacy

`config/clipper.conf` and `config/clipper.win.conf` are **git-ignored**
— they carry absolute paths to your vault and must never be committed.
Only the `*.example` templates are versioned.

## Changelog & Contributing

- [`CHANGELOG.md`](CHANGELOG.md) — release notes, semver.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — how to propose changes.

## License

[MIT](LICENSE) © Charlotte Li
