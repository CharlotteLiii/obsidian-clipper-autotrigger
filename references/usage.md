# Obsidian-Clipper-AutoTrigger — macOS usage

## Install

Run `scripts/install.sh` — it seeds `config/clipper.conf` and links the
skill into every detected agent skills directory (OpenClaw / Claude Code
/ Codex). See [`../AGENT_INSTALL.md`](../AGENT_INSTALL.md) for the full
contract.

Manual placement is still supported. Pick the location of the agent
you use (or all of them if you use several):

   ```text
   ~/.openclaw/workspace/skills/Obsidian-Clipper-AutoTrigger
   ~/.claude/skills/Obsidian-Clipper-AutoTrigger
   ~/.codex/skills/Obsidian-Clipper-AutoTrigger
   ```

   Copy or symlink the whole `Obsidian-Clipper-AutoTrigger` directory in.

2. Confirm the main script is executable (installer does this for you):

   ```bash
   chmod +x path/to/Obsidian-Clipper-AutoTrigger/scripts/clip_webpages.sh
   ```

3. Edit `config/clipper.conf` and confirm `VAULT_PATH` points to the target Obsidian vault.

4. (Recommended) Set `CLIP_OUTPUT_DIR` to the subfolder where the Obsidian Web Clipper extension saves Markdown files. This avoids scanning the entire vault on every clip and significantly speeds up large vaults.

5. Ensure a macOS Shortcut named `ObsidianClip` exists. The Chrome extension shortcut `Shift+Option+S` only works while Chrome is focused, so the Shortcut must activate Google Chrome before sending the keystroke.

   In the Shortcuts app, create a Shortcut named `ObsidianClip`, add a "Run AppleScript" action, and use:

   ```applescript
   on run {input, parameters}
     tell application "Google Chrome"
       activate
     end tell

     delay 0.3

     tell application "System Events"
       keystroke "s" using {shift down, option down}
     end tell

     return input
   end run
   ```

   The same template is bundled at `applescripts/shortcut_obsidian_clip_template.applescript`.

6. Grant permissions when macOS prompts:
   - Terminal/Codex may need Automation permission to control Google Chrome.
   - The Shortcut may need Accessibility permission if it sends keyboard shortcuts.
   - The direct keystroke fallback (`chrome_send_clip_shortcut.scpt`) also requires Accessibility permission for the process running the script.

7. Restart your agent (OpenClaw / Claude Code / Codex) so the skill is discoverable.

## Commands

Below examples use `$SKILL` as a shorthand for wherever you installed the
skill (e.g. `~/.openclaw/workspace/skills/Obsidian-Clipper-AutoTrigger`).

Clip one URL:

```bash
"$SKILL/scripts/clip_webpages.sh" "https://example.com/article"
```

Clip several URLs (same Chrome window, one tab per URL):

```bash
"$SKILL/scripts/clip_webpages.sh" \
  "https://a.com" \
  "https://b.com" \
  "https://c.com"
```

Validate configuration and URLs without opening Chrome:

```bash
"$SKILL/scripts/clip_webpages.sh" --dry-run "https://example.com"
```

Use an alternate config:

```bash
"$SKILL/scripts/clip_webpages.sh" \
  --config "/absolute/path/to/clipper.conf" \
  "https://example.com"
```

## Expected Logs

The script prints progress logs for each major step:

```text
Opening Chrome...
Waiting for page...
Page loaded.
Running Shortcut...
Waiting for Markdown...
Markdown detected.
Finished.
```

When the Shortcut produces no Markdown, a fallback step appears:

```text
No Markdown file generated via Shortcut on attempt 1.
Trying direct Shift+Option+S fallback...
Markdown detected via fallback: /path/to/note.md
```

When successful, it emits a tab-separated result line:

```text
SUCCESS https://example.com/article /path/to/generated-note.md
```

## Failure Modes

- `Invalid URL`: the URL is not HTTP or HTTPS.
- `Chrome could not open URL`: Google Chrome did not accept AppleScript control or failed to create a tab.
- `Page never finished loading`: Chrome kept reporting the target tab as loading until `PAGE_LOAD_TIMEOUT`.
- `SUSPECTED_LOGIN_WALL: <reason>`: after the page loaded, the login-wall
  probe detected a login form, paywall node, auth-style URL, or a known
  "please sign in / 请登录后阅读" phrase, and aborted before triggering the
  clipper. Open the same URL in Google Chrome, sign in, then rerun. To
  disable this check, set `LOGIN_WALL_CHECK=0` in `config/clipper.conf`;
  the false-positive threshold for "short body text" is tunable via
  `LOGIN_WALL_MIN_TEXT`.
- `Login-wall probe error`: the probe could not execute JavaScript in
  Chrome. Enable it once in Chrome > View > Developer > **Allow
  JavaScript from Apple Events**. The script logs the error and
  continues (does not abort the clip), so leaving this off just means
  you lose the safety net.
- `Shortcut failed`: `shortcuts run "$SHORTCUT_NAME"` exited nonzero.
- `Direct shortcut keystroke failed`: the `Shift+Option+S` fallback also failed. Check Accessibility permissions.
- `No Markdown file was generated`: no new or modified `.md` file was detected in the vault (or `CLIP_OUTPUT_DIR`) within `CLIP_TIMEOUT` after all retry attempts.

## Login-wall probe (macOS)

Mirrors the Windows CDP probe. After `wait_for_page_load` and before
triggering the clipper, the script runs
`applescripts/chrome_login_wall_probe.scpt` via `osascript`, which
calls Chrome's `execute javascript` command in the target tab. The JS
heuristic checks the final URL path, the DOM (`input[type=password]`,
paywall / login-wall class/id/data attributes), and body text against
a list of EN and zh-CN login / paywall phrases. Any strong signal, or
a short body plus a weak signal, aborts the URL with
`SUSPECTED_LOGIN_WALL: <reason>` and no keystroke is sent.

One-time setup: in Google Chrome, open **View → Developer → Allow
JavaScript from Apple Events** (the menu entry is a toggle). Without
it, the probe cannot inspect the page — it logs a hint and lets the
clip proceed, matching the pre-probe behaviour.

Config knobs in `config/clipper.conf`:

- `LOGIN_WALL_CHECK` (default `1`): `1` runs the probe, `0` skips it.
- `LOGIN_WALL_MIN_TEXT` (default `300`): body-text length below which
  the probe treats an accompanying weak signal as suspicious. Raise if
  you clip many legitimately short pages that get false-flagged.


## Design Notes

- The script opens the first URL in a new Chrome window and reuses that window for subsequent URLs by opening new tabs. This reduces visual disruption and speeds up batch clipping.
- The script intentionally does not send keyboard events as the primary clip method. It runs the configured macOS Shortcut, and only falls back to direct keystroke when the Shortcut succeeds but produces no Markdown.
- The `Shift+Option+S` Chrome extension shortcut is not global. The Shortcut (and the fallback) must activate Chrome first, otherwise the keystroke may be sent to Terminal, Codex, or another foreground app.
- The script tracks the Chrome window id and tab id returned when it opens the URL, then closes only that tab after a successful clip (or after final failure, so no tabs accumulate).
- Markdown detection compares file paths and modification timestamps under the vault (or `CLIP_OUTPUT_DIR`) before and after each clipping attempt, so both new files and changed files count as success.
- Adaptive polling uses 0.5-second intervals for the first 5 seconds, the configured `POLL_INTERVAL` for seconds 5-15, and 2-second intervals thereafter. This keeps detection responsive for fast clips while reducing overhead for slow pages.
