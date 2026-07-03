<#
Obsidian-Clipper-AutoTrigger — one-line bootstrap installer (Windows).

Typical usage from an AI agent (OpenClaw / Codex / Claude / etc.):
    iwr -useb https://raw.githubusercontent.com/CharlotteLiii/obsidian-clipper-autotrigger/main/bootstrap.ps1 | iex

What it does:
    1. Detects git and PowerShell 7+.
    2. git clones (or pulls) this repo into the target agent's skills dir.
    3. Runs scripts/install.ps1 to generate config/clipper.win.conf and
       link the skill into %CODEX_HOME%\skills.
    4. Prints a checklist of what to verify next.

Env vars (all optional):
    OCA_REPO_URL     Git URL to clone. Defaults to the canonical repo below.
    OCA_INSTALL_DIR  Absolute path to place the skill. Autodetected if unset.
    OCA_BRANCH       Branch/tag to check out. Defaults to main.
    OCA_UNATTENDED   Set to 1 to skip interactive prompts.
#>

param(
    [string]$RepoUrl,
    [string]$InstallDir,
    [string]$Branch,
    [switch]$Unattended
)

$ErrorActionPreference = 'Stop'

$RepoUrlDefault = 'https://github.com/CharlotteLiii/obsidian-clipper-autotrigger.git'
$SkillName      = 'Obsidian-Clipper-AutoTrigger'

if (-not $RepoUrl)    { $RepoUrl    = if ($env:OCA_REPO_URL) { $env:OCA_REPO_URL } else { $RepoUrlDefault } }
if (-not $Branch)     { $Branch     = if ($env:OCA_BRANCH)   { $env:OCA_BRANCH }   else { 'main' } }
if (-not $Unattended) { $Unattended = ($env:OCA_UNATTENDED -eq '1') }

function Write-Info { param($m) Write-Host "[oca] $m" -ForegroundColor Cyan }
function Write-Warn { param($m) Write-Host "[oca] $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "[oca] ERROR: $m" -ForegroundColor Red }

# ── Preflight ──────────────────────────────────────────────────────

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Warn 'PowerShell 7+ is required for the skill runtime (scripts/clip_webpages.ps1).'
    Write-Warn "Current version: $($PSVersionTable.PSVersion). Install with: winget install Microsoft.PowerShell"
    Write-Warn 'Continuing bootstrap, but clipping will fail until pwsh 7+ is available.'
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Err 'git is required. Install with: winget install Git.Git'
    exit 1
}

# ── Pick a skills directory ────────────────────────────────────────

function Detect-SourceDir {
    # The bootstrap just needs ONE stable place for the git clone. The
    # platform installer links the skill into every detected agent host
    # from there.
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'skills-src'),
        (Join-Path $HOME '.openclaw\workspace\skills-src')
    )
    foreach ($d in $candidates) {
        if (Test-Path -LiteralPath $d -PathType Container) { return $d }
    }
    return (Join-Path $env:LOCALAPPDATA 'skills-src')
}

if (-not $InstallDir) {
    $InstallDir = if ($env:OCA_INSTALL_DIR) { $env:OCA_INSTALL_DIR } else { Detect-SourceDir }
}
$TargetDir = Join-Path $InstallDir 'obsidian-clipper-autotrigger'

Write-Info "Skill target: $TargetDir"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# ── Clone or update ─────────────────────────────────────────────────

if (Test-Path -LiteralPath (Join-Path $TargetDir '.git') -PathType Container) {
    Write-Info 'Existing checkout found; updating...'
    git -C $TargetDir fetch --quiet origin $Branch
    git -C $TargetDir checkout --quiet $Branch
    git -C $TargetDir pull --ff-only --quiet
} elseif (Test-Path -LiteralPath $TargetDir) {
    Write-Err "Target exists and is not a git checkout: $TargetDir"
    Write-Err "Move it aside (e.g. Rename-Item '$TargetDir' '$TargetDir.bak') and rerun."
    exit 1
} else {
    Write-Info "Cloning $RepoUrl (branch $Branch)..."
    git clone --quiet --branch $Branch --depth 1 $RepoUrl $TargetDir
}

# ── Run the platform installer ─────────────────────────────────────

$InstallScript = Join-Path $TargetDir 'scripts\install.ps1'
if (Test-Path -LiteralPath $InstallScript) {
    Write-Info 'Running scripts\install.ps1...'
    $installArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $InstallScript)
    if ($Unattended) { $installArgs += '-Unattended' }
    $pwshExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
    & $pwshExe @installArgs
} else {
    Write-Warn 'scripts\install.ps1 not found; skipping platform install.'
}

# ── Post-install checklist ──────────────────────────────────────────

$configFile = Join-Path $TargetDir 'config\clipper.win.conf'
Write-Host ''
Write-Host "✅ $SkillName installed at:" -ForegroundColor Green
Write-Host "   $TargetDir"
Write-Host ''
Write-Host 'Verify next:' -ForegroundColor Cyan
Write-Host "  1. Config lives at: $configFile"
Write-Host '  2. Dry-run:'
Write-Host "       pwsh -NoProfile -File `"$TargetDir\scripts\clip_webpages.ps1`" -DryRun `"https://example.com`""
Write-Host '  3. First real clip will open a fresh Chrome profile with NO extension.'
Write-Host '     Install the Obsidian Web Clipper extension inside that Chrome'
Write-Host "     and set its `"Save to`" folder to match CLIP_OUTPUT_DIR."
Write-Host '  4. Restart your agent (OpenClaw / Codex) so it re-scans skills.'
