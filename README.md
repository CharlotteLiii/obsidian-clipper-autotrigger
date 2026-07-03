# Obsidian-Clipper-AutoTrigger

> Automate the Obsidian Web Clipper Chrome extension from the command line.
> One URL, a list of URLs, or an entire reading queue → parsed to Markdown
> inside your Obsidian vault, hands-free.

Runs on **macOS** (AppleScript + Shortcuts) and **Windows** (Chrome DevTools
Protocol + AutoHotkey/SendKeys). Same CLI contract on both platforms.

> 🤖 **Are you an AI agent installing this skill?** Read
> **[`AGENT_INSTALL.md`](AGENT_INSTALL.md)** — that file is the contract.
> The rest of this README is for humans.

---

## 🤖 Agent install (one line)

Ask your AI agent (OpenClaw / Codex / Claude / etc.):

> "Install the skill at https://github.com/CharlotteLiii/obsidian-clipper-autotrigger"

…and have it run **one** of the following:

### macOS / Linux

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/CharlotteLiii/obsidian-clipper-autotrigger/main/bootstrap.sh)
```

### Windows (PowerShell 7+)

```powershell
iwr -useb https://raw.githubusercontent.com/CharlotteLiii/obsidian-clipper-autotrigger/main/bootstrap.ps1 | iex
```

The bootstrap will:
1. Detect your agent's skills directory (OpenClaw → Claude → Codex, in that order).
2. `git clone` this repo into it.
3. Run the platform installer (`scripts/install.sh` or `scripts/install.ps1`)
   to seed the config file and register the skill.
4. Print a short checklist of the two or three fields you still need to fill
   in (vault path, save-to folder, macOS Shortcut name).

Restart your agent after install so it re-scans the skills directory.

> ⚠️ Before trusting a `curl | bash` / `iwr | iex` one-liner, feel free to
> inspect the script first — it's short and does nothing sneakier than
> `git clone` + running the shipped installer.

---

## 🧑 Manual Install

```bash
git clone https://github.com/CharlotteLiii/obsidian-clipper-autotrigger.git \
    ~/.openclaw/workspace/skills/Obsidian-Clipper-AutoTrigger
cd ~/.openclaw/workspace/skills/Obsidian-Clipper-AutoTrigger
cp config/clipper.conf.example config/clipper.conf   # macOS
# then edit VAULT_PATH etc., and:
scripts/install.sh
```

Windows equivalent:

```powershell
git clone https://github.com/CharlotteLiii/obsidian-clipper-autotrigger.git `
    "$HOME\.openclaw\workspace\skills\Obsidian-Clipper-AutoTrigger"
cd "$HOME\.openclaw\workspace\skills\Obsidian-Clipper-AutoTrigger"
pwsh -NoProfile -File scripts\install.ps1
```

---

## 🚀 First Real Clip

### ⚠️ Three things to confirm before the first clip

1. **Extension installed** in the Chrome profile this skill will drive
   (on Windows, that's a fresh dedicated profile created on first run).
2. **Shortcut works when pressed manually** in that Chrome — open any
   page and press the shortcut yourself; the Web Clipper popup should
   appear. If not, bind it at `chrome://extensions/shortcuts`.
3. **Config matches Chrome.** `CLIP_SHORTCUT` in your `config/clipper.conf`
   or `config/clipper.win.conf` must equal the key combo bound in Chrome.
   Defaults: `Shift+Option+S` (macOS) / `Shift+Alt+S` (Windows).

### First-run bootstrap on a clean machine

The **first** time you clip on a fresh machine, the script will spin up a
brand-new Chrome profile with **no extension installed** — attempts will
fail three times and stop. That is expected. Do not close that Chrome
window; instead:

1. Install the **Obsidian Web Clipper** Chrome extension inside the new profile.
2. Open its settings → set the "Save to" folder to match your `CLIP_OUTPUT_DIR`.
3. Rerun the clip. It should succeed on attempt 1.

See [`references/usage.md`](references/usage.md) and
[`references/usage-windows.md`](references/usage-windows.md) for full setup,
including the macOS Shortcut template.

---

## 🎯 Usage

```bash
# macOS
scripts/clip_webpages.sh "https://example.com/article"
scripts/clip_webpages.sh --dry-run "https://a.com" "https://b.com"

# Windows
pwsh -NoProfile -File scripts\clip_webpages.ps1 "https://example.com"
pwsh -NoProfile -File scripts\clip_webpages.ps1 -DryRun "https://a.com" "https://b.com"
```

Or just tell your AI agent: *"Use Obsidian-Clipper-AutoTrigger to save
&lt;URL&gt; to Obsidian."*

---

## 📁 Repository Layout

```
Obsidian-Clipper-AutoTrigger/
├── SKILL.md                          # Skill entry point (loaded by AI agents)
├── README.md                         # This file
├── bootstrap.sh / bootstrap.ps1      # One-line agent installer
├── config/
│   ├── clipper.conf.example          # macOS config template
│   ├── clipper.win.conf.example      # Windows config template
│   └── clipper.conf                  # (generated locally, git-ignored)
├── scripts/
│   ├── clip_webpages.sh              # macOS entrypoint
│   ├── clip_webpages.ps1             # Windows entrypoint
│   ├── install.sh / install.ps1      # Platform installers
│   ├── lib/Cdp.psm1                  # Windows CDP client
│   └── trigger/                      # Windows keystroke drivers
├── applescripts/                     # macOS Chrome/Shortcut glue
├── references/                       # Detailed usage docs
└── agents/                           # Agent-specific metadata
```

---

## 🔒 Privacy

`config/clipper.conf` and `config/clipper.win.conf` are **git-ignored** —
they carry absolute paths to your vault and must never be committed. Only
the `*.example` files are versioned.

---

## 📝 License

TBD (add before making the repo public).
