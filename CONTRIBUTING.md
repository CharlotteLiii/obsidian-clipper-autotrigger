# Contributing

Thanks for looking! This project is small enough that most contributions
can be a single PR against `main`. Please read the sections below before
opening one.

## Ground rules

- **macOS and Windows are equal citizens.** If you change the CLI
  contract on one platform, mirror the change on the other. The two
  installers and entrypoints must accept the same conceptual flags.
- **Never commit generated config.** `config/clipper.conf` and
  `config/clipper.win.conf` are `.gitignore`d because they contain
  absolute vault paths. If a new tunable is needed, add it to the
  matching `*.example` file and patch it into the installer.
- **AI agents are first-class users.** If your change affects install,
  update, or troubleshooting, keep `AGENT_INSTALL.md` in sync. Agents
  parse the last block of installer output — do not break the
  `LINKED: / CONFIG: / SOURCE:` summary format without updating the
  contract.

## Dev loop

1. Fork and clone.
2. Do all real testing on your own vault; both installers accept
   `--target-root` (`sh`) or `-TargetRoot` (`ps1`) to install into a
   throwaway location so you do not clobber your real skills folder.
3. macOS smoke test (safe, uses a temp target and a fake vault):

   ```bash
   TMP="$(mktemp -d)"
   scripts/install.sh --non-interactive \
       --vault-path "$TMP/fake-vault" \
       --target-root "$TMP/skills"
   ls "$TMP/skills"
   ```

4. Windows smoke test (in `pwsh` 7+):

   ```powershell
   $tmp = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "oca-$(Get-Random)")
   pwsh -NoProfile -File scripts\install.ps1 -Unattended `
       -VaultPath "$tmp\fake-vault" `
       -TargetRoot "$tmp\skills"
   Get-ChildItem "$tmp\skills"
   ```

5. End-to-end clip test requires a real Obsidian vault and the Web
   Clipper Chrome extension. Note in your PR whether you ran it.

## Coding style

- Bash: `set -euo pipefail`, no external dependencies beyond `python3`
  (already required for config patching) and standard POSIX tools.
- PowerShell: target PS 7+, `Set-StrictMode -Version Latest`,
  `$ErrorActionPreference = 'Stop'`.
- Keep functions small and testable. If a helper grows past ~40 lines,
  split it.

## Commit / PR notes

- Reference the issue number in the PR body when applicable.
- Bump `SKILL.md` `version:` and add a `CHANGELOG.md` entry for
  user-visible changes.
- No need for a signed CLA. By contributing you agree your patch is
  licensed under the repo's MIT license.

## Reporting bugs

Please use the "Clip failed" issue template. It asks for the exact bits
the maintainers need to reproduce (config, OS, Chrome version, agent
version, last 30 lines of the clip command's output).
