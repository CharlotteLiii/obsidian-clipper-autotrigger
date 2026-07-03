<#
Obsidian-Clipper-AutoTrigger — preflight self-check (Windows).

Runs the checks a human can do manually but that an AI agent cannot
reliably drive. Exits 0 if the skill is safe to run, non-zero otherwise.

Checks:
  1. config/clipper.win.conf exists and parses.
  2. VAULT_PATH exists and contains a `.obsidian` folder.
  3. CLIP_OUTPUT_DIR (if set) exists under VAULT_PATH.
  4. Google Chrome is installed at a known path.
  5. Obsidian is installed and (informationally) running.
  6. If CHROME_DEBUG_PORT is already listening, probe it and list the
     extensions loaded in the profile. Looks specifically for the
     Obsidian Web Clipper extension by manifest name.
  7. TRIGGER_DRIVER dependencies: AutoHotkey v2 if driver=ahk.

Usage:
  pwsh -NoProfile -File scripts\preflight.ps1 [-Config <path>]
#>

[CmdletBinding()]
param([string]$Config)

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host 'PowerShell 7+ is required. Install with:'
    Write-Host '  winget install --id Microsoft.PowerShell -e --accept-package-agreements --accept-source-agreements'
    exit 2
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillDir  = Split-Path -Parent $ScriptDir
if (-not $Config) { $Config = Join-Path $SkillDir 'config\clipper.win.conf' }

$script:Failed = $false
function Pass  { param($m) Write-Host "  " -NoNewline; Write-Host "OK   " -ForegroundColor Green -NoNewline; Write-Host $m }
function Fail  { param($m) Write-Host "  " -NoNewline; Write-Host "FAIL " -ForegroundColor Red   -NoNewline; Write-Host $m; $script:Failed = $true }
function Warn  { param($m) Write-Host "  " -NoNewline; Write-Host "WARN " -ForegroundColor Yellow -NoNewline; Write-Host $m }
function Info  { param($m) Write-Host ''; Write-Host $m -ForegroundColor Cyan }

# ── 1. Config ────────────────────────────────────────────────────

Info 'Config'
if (-not (Test-Path -LiteralPath $Config)) {
    Fail "Missing $Config - run scripts\install.ps1 first."
    exit 1
}
Pass "Config found: $Config"

$conf = @{}
foreach ($line in Get-Content -LiteralPath $Config -Encoding UTF8) {
    $trim = $line.Trim()
    if (-not $trim -or $trim.StartsWith('#')) { continue }
    if ($trim -match '^\s*([A-Z_][A-Z_0-9]*)\s*=\s*(.*)$') {
        $k = $matches[1]
        $v = $matches[2].Trim()
        if ($v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Substring(1, $v.Length - 2) }
        $conf[$k] = $v
    }
}

$Vault    = $conf['VAULT_PATH']
$OutDir   = $conf['CLIP_OUTPUT_DIR']
$Shortcut = if ($conf['CLIP_SHORTCUT']) { $conf['CLIP_SHORTCUT'] } else { 'Shift+Alt+S' }
$Driver   = if ($conf['TRIGGER_DRIVER']) { $conf['TRIGGER_DRIVER'] } else { 'sendkeys' }
$Port     = if ($conf['CHROME_DEBUG_PORT']) { $conf['CHROME_DEBUG_PORT'] } else { '9222' }

# ── 2. Vault ─────────────────────────────────────────────────────

Info 'Obsidian vault'
if (-not $Vault) {
    Fail 'VAULT_PATH is empty in the config'
} elseif (-not (Test-Path -LiteralPath $Vault -PathType Container)) {
    Fail "VAULT_PATH does not exist: $Vault"
} else {
    Pass "VAULT_PATH exists: $Vault"
    if (Test-Path -LiteralPath (Join-Path $Vault '.obsidian')) {
        Pass 'Looks like an Obsidian vault (.obsidian\ present)'
    } else {
        Warn 'No .obsidian\ folder inside - is this really an Obsidian vault?'
    }
    if ($OutDir) {
        if (Test-Path -LiteralPath (Join-Path $Vault $OutDir)) {
            Pass "CLIP_OUTPUT_DIR exists: $OutDir"
        } else {
            Warn "CLIP_OUTPUT_DIR does not exist yet: $OutDir (Web Clipper will create it on first clip)"
        }
    } else {
        Pass 'CLIP_OUTPUT_DIR empty - will scan the whole vault'
    }
}

# ── 3. Chrome ────────────────────────────────────────────────────

Info 'Google Chrome'
$chromeCandidates = @(
    'C:\Program Files\Google\Chrome\Application\chrome.exe',
    'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
)
if ($conf['CHROME_EXE']) { $chromeCandidates = @($conf['CHROME_EXE']) + $chromeCandidates }
$chromeFound = $chromeCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if ($chromeFound) {
    Pass "Chrome found at $chromeFound"
} else {
    Fail 'Chrome not found - install from https://www.google.com/chrome/'
}

# ── 4. Obsidian ──────────────────────────────────────────────────

Info 'Obsidian'
$obsidianCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Obsidian\Obsidian.exe'),
    'C:\Program Files\Obsidian\Obsidian.exe'
)
$obsidianFound = $obsidianCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($obsidianFound) {
    Pass "Obsidian installed: $obsidianFound"
    if (Get-Process -Name Obsidian -ErrorAction SilentlyContinue) {
        Pass 'Obsidian is currently running'
    } else {
        Warn 'Obsidian is not running - start it before your first clip so files appear'
    }
} else {
    Fail 'Obsidian not found in %LOCALAPPDATA%\Obsidian or C:\Program Files\Obsidian'
}

# ── 5. Chrome CDP (if already listening) ─────────────────────────

Info "Chrome DevTools Protocol probe (port $Port)"
$cdpReachable = $false
try {
    $conn = Test-NetConnection -ComputerName 'localhost' -Port ([int]$Port) -InformationLevel Quiet -WarningAction SilentlyContinue
    $cdpReachable = [bool]$conn
} catch {
    $cdpReachable = $false
}

if (-not $cdpReachable) {
    Warn "No Chrome listening on port $Port yet - that's normal; the skill will start Chrome on first clip."
} else {
    Pass "Something is listening on port $Port"
    try {
        $targets = Invoke-RestMethod -Uri "http://localhost:$Port/json/list" -TimeoutSec 3
        Pass ("CDP responded with {0} target(s)" -f ($targets | Measure-Object).Count)
        $extTargets = $targets | Where-Object { $_.type -in 'background_page','service_worker' -and $_.url -match '^chrome-extension://' }
        if ($extTargets) {
            $clipperHit = $extTargets | Where-Object { $_.title -match 'Obsidian Web Clipper' -or $_.url -match 'obsidian' }
            if ($clipperHit) {
                Pass ("Obsidian Web Clipper extension detected in profile: {0}" -f $clipperHit[0].url)
            } else {
                Warn 'CDP profile has extensions but Obsidian Web Clipper is not among them - install it in this Chrome profile.'
                $extTargets | ForEach-Object { Write-Host "        - $($_.title)" }
            }
        } else {
            Warn 'CDP profile has no extension targets - the Obsidian Web Clipper is probably not installed in this profile.'
        }
    } catch {
        Warn "Port $Port is open but not speaking DevTools Protocol: $($_.Exception.Message)"
    }
}

# ── 6. Trigger driver deps ───────────────────────────────────────

Info "Trigger driver ($Driver)"
if ($Driver -eq 'ahk') {
    if (Get-Command 'AutoHotkey64.exe' -ErrorAction SilentlyContinue) {
        Pass 'AutoHotkey v2 found on PATH'
    } else {
        Fail 'TRIGGER_DRIVER=ahk but AutoHotkey64.exe is not on PATH - install with: winget install AutoHotkey.AutoHotkey'
    }
} else {
    Pass 'SendKeys driver has no external dependencies'
}

# ── 7. Human preflight reminder ──────────────────────────────────

Info 'Manual verification (agent-facing)'
Write-Host '  Ask the user to confirm:'
Write-Host "    1. Chrome has the `"Obsidian Web Clipper`" extension installed in the CDP profile."
Write-Host "    2. Pressing $Shortcut in Chrome opens the Web Clipper popup."
Write-Host '    3. Obsidian is open with the correct vault loaded.'

# ── Result ───────────────────────────────────────────────────────

Write-Host ''
if ($script:Failed) {
    Write-Host 'PREFLIGHT FAILED - fix the FAIL items above before clipping.' -ForegroundColor Red
    exit 1
} else {
    Write-Host 'PREFLIGHT OK - you can attempt a clip.' -ForegroundColor Green
    exit 0
}
