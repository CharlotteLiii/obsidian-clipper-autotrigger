# Changelog

All notable changes to this project will be documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
