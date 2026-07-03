---
name: Clip failed
about: A clip attempt failed or nothing landed in the vault
labels: bug
---

## What happened
<!-- One or two sentences. -->

## Environment

- OS: <!-- macOS 15.x / Windows 11 22H2 / etc. -->
- Agent host: <!-- OpenClaw / Claude Code / Codex / manual CLI -->
- Chrome version: <!-- chrome://version -->
- Obsidian version:
- Obsidian Web Clipper extension version:
- Skill version: <!-- from SKILL.md front-matter, e.g. 0.3.0 -->
- Windows only — TRIGGER_DRIVER: <!-- ahk / sendkeys -->

## Config (redact vault path if needed)

```
# paste config/clipper.conf or config/clipper.win.conf
# with VAULT_PATH replaced by e.g. "/Users/me/Vault"
```

## Reproduction

Command you ran:
```
scripts/clip_webpages.sh "https://example.com"
# or
pwsh -NoProfile -File scripts\clip_webpages.ps1 "https://example.com"
```

Last 30 lines of output:
```
<paste here>
```

## Preflight checks

Please confirm each:

- [ ] Chrome had the "Obsidian Web Clipper" extension installed in the
      profile the skill was using
- [ ] Manually pressing the clip shortcut in that Chrome opens the popup
- [ ] Obsidian was running with the correct vault loaded
- [ ] `CLIP_OUTPUT_DIR` matches the extension's "Save to" folder

## Anything else?
