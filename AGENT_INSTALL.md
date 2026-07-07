# For AI agents: how to install this skill

**You are reading this because a human asked you to install
`Obsidian-Clipper-AutoTrigger` from its GitHub repo.**
This file is the contract. Follow it verbatim. Do not improvise.

The end goal: the user says *"clip this URL to Obsidian"* to their
agent, the skill runs, and a Markdown file lands in their vault.

---

## Supported hosts

The installer auto-detects and links the skill into whichever of these
directories already exist on the user's machine:

| Host        | Skills directory (macOS/Linux)        | Skills directory (Windows)              |
|-------------|---------------------------------------|-----------------------------------------|
| OpenClaw    | `~/.openclaw/workspace/skills`        | `%USERPROFILE%\.openclaw\workspace\skills` |
| Claude Code | `~/.claude/skills`                    | `%USERPROFILE%\.claude\skills`          |
| Codex       | `~/.codex/skills`                     | `%USERPROFILE%\.codex\skills`           |

If more than one is present, the installer links into **all** of them by
default (`--all-hosts` is on). If none are present, it creates the
OpenClaw path and links there.

Override with `--target-root <absolute path>` when the user asks for a
specific location.

---

## Step 1 — Clone to a stable location

Pick this path (do NOT use `/tmp`, `%TEMP%`, or the user's Downloads):

- **macOS / Linux**: `~/.local/share/skills-src/obsidian-clipper-autotrigger`
- **Windows**: `%LOCALAPPDATA%\skills-src\obsidian-clipper-autotrigger`

If the directory already exists and is a git checkout, `git pull` instead
of re-cloning. If it exists and is not a checkout, ask the user before
touching it.

```bash
# macOS/Linux
mkdir -p ~/.local/share/skills-src
git clone https://github.com/CharlotteLiii/obsidian-clipper-autotrigger.git \
    ~/.local/share/skills-src/obsidian-clipper-autotrigger
cd ~/.local/share/skills-src/obsidian-clipper-autotrigger
```

```powershell
# Windows
$src = "$env:LOCALAPPDATA\skills-src\obsidian-clipper-autotrigger"
New-Item -ItemType Directory -Force -Path (Split-Path $src) | Out-Null
git clone https://github.com/CharlotteLiii/obsidian-clipper-autotrigger.git $src
Set-Location $src
```

---

## Step 2 — Ask the user for the required inputs

Before running the installer, collect these values from the user. Do NOT
guess.

| Input                | Required? | Example                                       |
|----------------------|-----------|-----------------------------------------------|
| Obsidian vault path  | Optional* | `/Users/me/Obsidian Vault` or `D:\Vault`      |
| Clip output subdir   | Optional  | `Inbox/Clippings` (leave blank = whole vault) |
| Clip shortcut        | REQUIRED  | `Shift+Alt+O` (Win), `Shift+Option+O` (mac)   |
| Use macOS Shortcut   | Optional  | `--use-shortcut` (default is direct keystroke)|
| Trigger driver (Win) | Optional  | `ahk` or `sendkeys` (default: `sendkeys`)     |

\* macOS: the installer auto-reads the currently-open vault from
`~/Library/Application Support/obsidian/obsidian.json` if you omit
`--vault-path`. In non-interactive mode it uses that value directly and
logs it. Pass `--vault-path` explicitly to override.

If the user has an existing `obsidian.json` you can peek at it for the
vault path, but **confirm the path with the user before writing it into
the config file**.

**The clip shortcut is required and cannot be auto-detected.** It must
match the combo the user bound for **"Quick clip"** under Obsidian Web
Clipper at `chrome://extensions/shortcuts`, exactly as shown in Chrome.
Always ask the user for it; never guess a default. If you omit
`--shortcut`, the installer aborts in non-interactive mode.

---

## Step 3 — Run the installer non-interactively

Pass everything the user gave you on the command line. `--vault-path`
(macOS can auto-detect) and `--shortcut` are required; other missing
values fall back to sensible defaults without prompting.

### macOS / Linux

```bash
scripts/install.sh \
  --non-interactive \
  --vault-path "$USER_VAULT_PATH" \
  --clip-output-dir "$USER_CLIP_DIR" \
  --shortcut "$USER_SHORTCUT" \
  --all-hosts
```

On macOS the installer defaults to **direct AppleScript keystroke** as
the clip trigger — no `ObsidianClip` Shortcut needs to be created by
hand. It also flips `com.google.Chrome AppleScriptEnabled` on so the
login-wall probe works out of the box. Pass `--use-shortcut` to keep the
old Shortcut-based trigger (requires the user to have built the Shortcut
first), or `--no-enable-apple-events` to skip the Chrome preference
write.

### Windows (PowerShell 7+)

```powershell
pwsh -NoProfile -File scripts\install.ps1 `
  -Unattended `
  -VaultPath "$UserVaultPath" `
  -ClipOutputDir "$UserClipDir" `
  -Shortcut "$UserShortcut" `
  -TriggerDriver sendkeys `
  -AllHosts
```

> **Windows note**: if PowerShell 7 is missing, the installer refuses to
> run. Bootstrap it first with:
> `winget install --id Microsoft.PowerShell -e --accept-package-agreements --accept-source-agreements`
> then rerun the installer with `pwsh`. Do NOT try Windows PowerShell 5.1.

The installer prints exactly which agent skills directories it linked
into, and where the generated config file lives. Parse the last block of
its output — it looks like:

```
LINKED:
  ~/.openclaw/workspace/skills/Obsidian-Clipper-AutoTrigger  (symlink)
  ~/.claude/skills/Obsidian-Clipper-AutoTrigger              (skipped: not detected)
CONFIG:
  <skill>/config/clipper.conf
```

---

## Step 4 — Human preflight (unavoidable)

Things the installer physically cannot verify. Ask the user each one, in
order, and STOP if any answer is "no".

1. **"Is the Obsidian Web Clipper Chrome extension installed?"**
   The installer probes for this automatically (see step 5 of its output
   summary) and warns loudly if the extension is missing. If it is
   missing, point the user at
   `https://chromewebstore.google.com/detail/obsidian-web-clipper/cnjifjpddelmedmihgijeibhnjfabmlf`.
2. **"Open Chrome, load any page, press the shortcut. Did the Clipper popup appear?"**
   If no → ask them to bind the shortcut at `chrome://extensions/shortcuts`,
   then tell you what combo they set. Rerun the installer with
   `--shortcut "<their combo>"`.
3. **"Is Obsidian open with your vault loaded?"**
   The clipper writes into the currently open vault. If Obsidian is
   closed the extension will still capture, but the file will not appear
   until Obsidian starts.
4. **macOS first-run permissions (direct-keystroke mode).**
   On the first clip macOS will prompt for two things:
   - **Accessibility** for Terminal / the agent binary that runs
     `osascript` (System Settings > Privacy & Security > Accessibility).
   - **Automation → Google Chrome** (also under Privacy & Security).
   Tell the user to expect the prompts and approve them. If they miss
   the prompt, they can toggle the permissions on manually later.
   *If the user opted into `--use-shortcut`, additionally verify a macOS
   Shortcut named `ObsidianClip` (or the value passed via
   `--shortcut-name`) exists in Shortcuts.app.*
5. **Save-to folder must match `CLIP_OUTPUT_DIR`.**
   The installer reads the Web Clipper's clip history (LevelDB in the
   detected Chrome profile) and warns when its recent save-to paths do
   not match your `CLIP_OUTPUT_DIR`. If you see that warning, open the
   Web Clipper's *Vaults* settings inside Chrome and update the path
   before the first clip — otherwise the file lands in the wrong folder
   and the skill will not detect it.

---

## Step 5 — Tell the user to restart their agent

Skills are scanned at agent startup. Say something like:

> "Setup done. Restart OpenClaw / Codex / Claude Code so it re-scans
> the skills directory, then ask me to clip a page."

---

## First-clip note (important — do not skip)

On a Windows machine, the very first clip launches Chrome with a **fresh
dedicated profile** that has no extensions. The first three clip
attempts will fail. That is expected. Tell the user:

> "A new Chrome window will open — install the Obsidian Web Clipper in
> it, sign in / configure the 'Save to' folder, then ask me to clip
> again."

macOS uses the user's existing Chrome, so this only bites Windows users.

---

## Troubleshooting decision tree (agent-facing)

If a clip fails, ask the user these five questions in order. The answer
to #1 or #2 usually solves it.

1. Is Chrome running on the CDP profile the skill created?
   (Windows only. macOS uses default Chrome.)
2. When you press the clip shortcut manually in that Chrome, does the
   popup open?
3. Is Obsidian open with the correct vault loaded?
4. What is the `VAULT_PATH` and `CLIP_OUTPUT_DIR` in the config file?
   Does the Clipper extension's "Save to" setting match `CLIP_OUTPUT_DIR`?
5. Paste the last 30 lines of the clip command's output.

---

## Update

To pull upstream changes without touching user config:

```bash
cd ~/.local/share/skills-src/obsidian-clipper-autotrigger && git pull
```

The user's `config/clipper.conf` / `clipper.win.conf` is `.gitignore`d,
so `git pull` will not clobber it. If new config keys were added
upstream, tell the user to diff `config/*.example` against their live
config and merge missing keys manually. Do NOT overwrite their config.

---

## Uninstall

```bash
# Remove links (installer created these):
rm ~/.openclaw/workspace/skills/Obsidian-Clipper-AutoTrigger 2>/dev/null || true
rm ~/.claude/skills/Obsidian-Clipper-AutoTrigger 2>/dev/null || true
rm ~/.codex/skills/Obsidian-Clipper-AutoTrigger 2>/dev/null || true
# Remove source checkout:
rm -rf ~/.local/share/skills-src/obsidian-clipper-autotrigger
```

Windows equivalent uses `Remove-Item -Recurse -Force` on each junction
and the source directory.
