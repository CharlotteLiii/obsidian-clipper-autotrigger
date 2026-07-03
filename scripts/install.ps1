<#
Obsidian-Clipper-AutoTrigger — Windows installer.

Modes:
  Interactive (default, when a console is attached): asks any missing values.
  Non-interactive (-Unattended, or when no console is attached): uses only
    what you pass on the command line, no prompts. Missing optional fields
    fall back to defaults; missing -VaultPath aborts.

What it does:
  1. Detects PowerShell 7+ and offers to install it via winget if missing.
  2. Seeds config/clipper.win.conf from clipper.win.conf.example and fills
     in VAULT_PATH / CLIP_OUTPUT_DIR / CLIP_SHORTCUT / TRIGGER_DRIVER.
  3. Optionally installs AutoHotkey v2 when the user picks that driver.
  4. Detects agent skills directories (OpenClaw / Claude Code / Codex) and
     creates a symlink or junction into each detected one (or a single
     directory when -TargetRoot is given).
  5. Prints a machine-parseable summary block at the end (matches
     AGENT_INSTALL.md format).

Parameters:
  -VaultPath        Absolute path to the Obsidian vault (REQUIRED unattended).
  -ClipOutputDir    Relative save-to folder inside the vault; blank = whole vault.
  -Shortcut         Key combo bound in Chrome (default: Shift+Alt+S).
  -TriggerDriver    ahk | sendkeys (default: sendkeys — zero install).
  -TargetRoot       Link the skill ONLY into this directory.
  -AllHosts         Link into every detected agent skills dir (default when
                    -TargetRoot is not set).
  -NoAllHosts       Only link into the first detected host dir.
  -Unattended       Never prompt; fall back to defaults for optional fields.
#>

[CmdletBinding()]
param(
    [switch]$Unattended,
    [ValidateSet('ahk','sendkeys')][string]$TriggerDriver,
    [string]$VaultPath,
    [string]$ClipOutputDir,
    [string]$Shortcut,
    [string]$TargetRoot,
    [switch]$AllHosts,
    [switch]$NoAllHosts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── PowerShell 7 check ───────────────────────────────────────────

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host '[install] PowerShell 7+ is required.' -ForegroundColor Red
    Write-Host '[install] Install with: winget install --id Microsoft.PowerShell -e --accept-package-agreements --accept-source-agreements'
    Write-Host '[install] Then rerun this script with: pwsh -NoProfile -File scripts\install.ps1 <args>'
    exit 2
}

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillDir   = Split-Path -Parent $ScriptDir
$SkillName  = 'Obsidian-Clipper-AutoTrigger'
$ConfigDir  = Join-Path $SkillDir 'config'
$ConfigExample = Join-Path $ConfigDir 'clipper.win.conf.example'
$ConfigFile    = Join-Path $ConfigDir 'clipper.win.conf'

# Decide interactive mode
$Interactive = -not $Unattended
if ($Interactive -and -not [Environment]::UserInteractive) {
    $Interactive = $false
}

function Write-Info { param($m) Write-Host "[install] $m" -ForegroundColor Cyan }
function Write-Warn { param($m) Write-Host "[install] $m" -ForegroundColor Yellow }
function Die        { param($m) Write-Host "[install] ERROR: $m" -ForegroundColor Red; exit 1 }

function Prompt-With-Default {
    param([string]$Question, [string]$Default = '')
    if (-not $Interactive) { return $Default }
    $suffix = if ($Default) { " [$Default]" } else { '' }
    $ans = Read-Host "$Question$suffix"
    if (-not $ans) { return $Default } else { return $ans }
}

function Prompt-Choice {
    param([string]$Question, [string[]]$Options, [int]$DefaultIndex = 0)
    if (-not $Interactive) { return $DefaultIndex }
    Write-Host ''
    Write-Host $Question -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $marker = if ($i -eq $DefaultIndex) { '*' } else { ' ' }
        Write-Host ("  [{0}]{1} {2}" -f ($i + 1), $marker, $Options[$i])
    }
    while ($true) {
        $ans = Read-Host "Enter 1-$($Options.Count) (default $($DefaultIndex + 1))"
        if (-not $ans) { return $DefaultIndex }
        if (($ans -as [int]) -and [int]$ans -ge 1 -and [int]$ans -le $Options.Count) {
            return ([int]$ans - 1)
        }
        Write-Host 'Invalid choice, try again.' -ForegroundColor Yellow
    }
}

function Test-AhkAvailable { return [bool](Get-Command 'AutoHotkey64.exe' -ErrorAction SilentlyContinue) }

function Install-AhkViaWinget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warn 'winget not available; install AutoHotkey v2 manually from https://www.autohotkey.com/ and rerun.'
        return $false
    }
    Write-Info 'Installing AutoHotkey v2 via winget...'
    & winget install --id AutoHotkey.AutoHotkey -e --accept-package-agreements --accept-source-agreements | Out-Null
    return (Test-AhkAvailable)
}

# ── Trigger driver ───────────────────────────────────────────────

if (-not $TriggerDriver) {
    if ($Interactive) {
        $idx = Prompt-Choice `
            -Question 'Which trigger driver should launch the Obsidian Web Clipper?' `
            -Options @(
                'sendkeys       (zero install, works out of the box, focus-sensitive)',
                'AutoHotkey v2  (more stable, requires AutoHotkey install)'
            ) `
            -DefaultIndex 0
        $TriggerDriver = @('sendkeys','ahk')[$idx]
    } else {
        $TriggerDriver = 'sendkeys'
    }
}

if ($TriggerDriver -eq 'ahk' -and -not (Test-AhkAvailable)) {
    if (-not $Interactive) {
        Write-Warn 'AutoHotkey v2 not found and running unattended; falling back to SendKeys.'
        $TriggerDriver = 'sendkeys'
    } else {
        $ans = Read-Host 'AutoHotkey v2 not found. Install now via winget? [Y/n]'
        if (-not $ans -or $ans -match '^(y|yes)$') {
            if (-not (Install-AhkViaWinget)) {
                Write-Warn 'AutoHotkey install failed; falling back to SendKeys driver.'
                $TriggerDriver = 'sendkeys'
            }
        } else {
            Write-Warn 'Falling back to SendKeys driver.'
            $TriggerDriver = 'sendkeys'
        }
    }
}

# ── Vault path ───────────────────────────────────────────────────

if (-not $VaultPath) {
    if ($Interactive) {
        while (-not $VaultPath) {
            $VaultPath = Read-Host 'Absolute path to your Obsidian vault (e.g. D:\Vault)'
            if ($VaultPath -and -not (Test-Path -LiteralPath $VaultPath -PathType Container)) {
                Write-Warn "Path does not exist: $VaultPath"
                $VaultPath = $null
            }
        }
    } else {
        Die '-VaultPath is required in unattended mode.'
    }
} elseif (-not (Test-Path -LiteralPath $VaultPath -PathType Container)) {
    Write-Warn "Vault path does not exist yet: $VaultPath (continuing anyway)"
}

if (-not $PSBoundParameters.ContainsKey('ClipOutputDir')) {
    $ClipOutputDir = Prompt-With-Default 'Relative folder inside the vault (blank = whole vault)' ''
}
if (-not $Shortcut) {
    $Shortcut = Prompt-With-Default 'Clip shortcut bound in Chrome' 'Shift+Alt+S'
}

# ── Seed / patch config/clipper.win.conf ─────────────────────────

if (-not (Test-Path -LiteralPath $ConfigExample)) {
    Die "Missing $ConfigExample — corrupt checkout?"
}

New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
if (-not (Test-Path -LiteralPath $ConfigFile)) {
    Copy-Item -LiteralPath $ConfigExample -Destination $ConfigFile
    Write-Info "Seeded $ConfigFile from example."
} else {
    Write-Info "Updating fields in existing $ConfigFile"
}

# Patch known fields in place (preserves user comments and any extra keys)
$script:text = Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8
function Update-ConfKey {
    param([string]$Key, [string]$Value, [switch]$Quote)
    if ($Quote) {
        $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
        $repl = ('{0}="{1}"' -f $Key, $escaped)
    } else {
        $repl = ('{0}={1}' -f $Key, $Value)
    }
    $pattern = "(?m)^$([regex]::Escape($Key))=.*$"
    if ([regex]::IsMatch($script:text, $pattern)) {
        # MatchEvaluator prevents backreference expansion inside $repl.
        $captured = $repl
        $script:text = [regex]::Replace($script:text, $pattern, { param($m) $captured })
    } else {
        $script:text += "`r`n$repl`r`n"
    }
}
Update-ConfKey -Key 'VAULT_PATH'      -Value $VaultPath      -Quote
Update-ConfKey -Key 'CLIP_OUTPUT_DIR' -Value $ClipOutputDir  -Quote
Update-ConfKey -Key 'CLIP_SHORTCUT'   -Value $Shortcut       -Quote
Update-ConfKey -Key 'TRIGGER_DRIVER'  -Value $TriggerDriver
Set-Content -LiteralPath $ConfigFile -Value $script:text -Encoding UTF8 -NoNewline
Write-Info "Config written: $ConfigFile"

# ── Detect host skills directories ───────────────────────────────

function Get-HostSkillDirs {
    $openclawHome = if ($env:OPENCLAW_HOME) { $env:OPENCLAW_HOME } else { Join-Path $HOME '.openclaw' }
    $codexHome    = if ($env:CODEX_HOME)    { $env:CODEX_HOME }    else { Join-Path $HOME '.codex' }
    $entries = @(
        @{ label='OpenClaw';    path=(Join-Path $openclawHome 'workspace\skills') },
        @{ label='OpenClaw';    path=(Join-Path $HOME '.openclaw\skills') },
        @{ label='Claude Code'; path=(Join-Path $HOME '.claude\skills') },
        @{ label='Codex';       path=(Join-Path $codexHome 'skills') },
        @{ label='Codex';       path=(Join-Path $HOME '.codex\skills') }
    )
    $seen = @{}
    $out = @()
    foreach ($e in $entries) {
        if (-not (Test-Path -LiteralPath $e.path -PathType Container)) { continue }
        if ($seen.ContainsKey($e.path)) { continue }
        $seen[$e.path] = $true
        $out += [pscustomobject]@{ Label=$e.label; Path=$e.path }
    }
    return $out
}

$linkTargets = @()
if ($TargetRoot) {
    $linkTargets = @([pscustomobject]@{ Label='custom'; Path=$TargetRoot })
} else {
    $detected = Get-HostSkillDirs
    if ($detected.Count -eq 0) {
        # Nothing detected — default to OpenClaw workspace path
        $fallback = Join-Path $HOME '.openclaw\workspace\skills'
        $linkTargets = @([pscustomobject]@{ Label='OpenClaw (created)'; Path=$fallback })
    } elseif ($NoAllHosts) {
        $linkTargets = @($detected[0])
    } else {
        $linkTargets = $detected
    }
}

# ── Perform linking ──────────────────────────────────────────────

$linkReport = @()

function Link-SkillInto {
    param([string]$Root, [string]$Label)
    $target = Join-Path $Root $SkillName
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    if (Test-Path -LiteralPath $target) {
        $item = Get-Item -LiteralPath $target -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            # Existing symlink/junction — refresh
            Remove-Item -LiteralPath $target -Force -Recurse
        } else {
            $script:linkReport += [pscustomobject]@{
                Target=$target; Kind='SKIPPED (not a link; move it aside)'; Label=$Label
            }
            return
        }
    }
    $linked = $false
    $kind = ''
    try {
        New-Item -ItemType SymbolicLink -Path $target -Target $SkillDir -ErrorAction Stop | Out-Null
        $linked = $true; $kind = 'symlink'
    } catch {
        try {
            & cmd.exe /c mklink /J "`"$target`"" "`"$SkillDir`"" | Out-Null
            $linked = $true; $kind = 'junction'
        } catch {
            Write-Warn 'Symlink and junction both failed; falling back to copy (will not auto-update).'
            Copy-Item -Recurse -LiteralPath $SkillDir -Destination $target
            $linked = $true; $kind = 'COPY (one-shot; rerun to update)'
        }
    }
    if ($linked) {
        $script:linkReport += [pscustomobject]@{ Target=$target; Kind=$kind; Label=$Label }
    }
}

foreach ($t in $linkTargets) {
    Link-SkillInto -Root $t.Path -Label $t.Label
}

# ── Summary ──────────────────────────────────────────────────────

Write-Host ''
Write-Info 'Setup complete.'
Write-Host ''
Write-Host 'LINKED:'
foreach ($r in $linkReport) {
    Write-Host ("  {0}  ({1}, {2})" -f $r.Target, $r.Kind, $r.Label)
}
Write-Host 'CONFIG:'
Write-Host "  $ConfigFile"
Write-Host 'SOURCE:'
Write-Host "  $SkillDir"
Write-Host ''
Write-Host 'Before your first clip, verify these three things:' -ForegroundColor Cyan
Write-Host '  1. Chrome has the "Obsidian Web Clipper" extension installed inside the'
Write-Host '     dedicated profile the skill creates on first run.'
Write-Host "  2. Press $Shortcut manually in that Chrome to confirm the popup opens."
Write-Host '  3. Set CLIP_SHORTCUT in config\clipper.win.conf to match Chrome exactly.'
Write-Host ''
Write-Host 'Restart your agent (OpenClaw / Claude Code / Codex) to load the skill.'

# ── Optional: open the Chrome Web Store install page for the Web Clipper ─────

if ($Interactive) {
    Write-Host ''
    $ans = Read-Host 'Open the Chrome Web Store page for the Obsidian Web Clipper extension now? [Y/n]'
    if (-not $ans -or $ans -match '^(y|yes)$') {
        $extUrl = 'https://chromewebstore.google.com/detail/obsidian-web-clipper/cnjifjpddelmedmihgijeibhnjfabmlf'
        $chromeExe = @(
            'C:\Program Files\Google\Chrome\Application\chrome.exe',
            'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
        ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        $profileDir = Join-Path $env:LOCALAPPDATA 'Obsidian-Clipper-AutoTrigger\chrome-profile'
        New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
        if ($chromeExe) {
            Write-Info 'Launching the Chrome CDP profile with the extension install page...'
            Start-Process -FilePath $chromeExe -ArgumentList @("--user-data-dir=$profileDir", $extUrl) | Out-Null
            Write-Host '  A Chrome window should open. Click "Add to Chrome" and finish extension setup.'
            Write-Host '  Set the extension''s "Save to" folder to match CLIP_OUTPUT_DIR in the config file.'
        } else {
            Write-Warn 'Chrome not found; open this URL manually inside the profile the skill creates:'
            Write-Host "    $extUrl"
        }
    }
}
