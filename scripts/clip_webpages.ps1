<#
Windows entrypoint for the Obsidian-Clipper-AutoTrigger skill.

Contract mirrors scripts/clip_webpages.sh:
  clip_webpages.ps1 [-Config PATH] [-DryRun] URL [URL ...]

Behaviour:
  * Loads config/clipper.win.conf (falls back to clipper.conf).
  * Ensures Chrome is running with --remote-debugging-port; starts it if not.
  * Opens each URL as a new tab via CDP, waits for Page.loadEventFired.
  * Focuses the tab, triggers the Obsidian Web Clipper via the configured
    trigger driver (AutoHotkey v2 or SendKeys), and diffs the vault's
    Markdown files to detect the newly clipped note.
  * Retries up to $MaxRetries, closes the tab it opened, prints a summary.

Requires: PowerShell 7+. Optional: AutoHotkey v2 (if TRIGGER_DRIVER=ahk).
#>

[CmdletBinding()]
param(
    [string]$Config,
    [switch]$DryRun,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Urls
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillDir  = Split-Path -Parent $ScriptDir
$LibDir    = Join-Path $ScriptDir 'lib'
$TrigDir   = Join-Path $ScriptDir 'trigger'

Import-Module (Join-Path $LibDir 'Cdp.psm1') -Force

function Write-Log {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts] $($Message -join ' ')"
}

function Write-Fail {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Message)
    Write-Log "ERROR: $($Message -join ' ')"
}

# ── Config loading ─────────────────────────────────────────────────

function Read-ConfigFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path"
    }
    $cfg = [ordered]@{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -notmatch '^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)$') { continue }
        $key = $Matches[1]
        $val = $Matches[2].Trim()
        if ($val.Length -ge 2 -and (($val[0] -eq '"' -and $val[-1] -eq '"') -or ($val[0] -eq "'" -and $val[-1] -eq "'"))) {
            $val = $val.Substring(1, $val.Length - 2)
        }
        $cfg[$key] = $val
    }
    return $cfg
}

if (-not $Config) {
    $winCfg = Join-Path $SkillDir 'config/clipper.win.conf'
    $unixCfg = Join-Path $SkillDir 'config/clipper.conf'
    if (Test-Path -LiteralPath $winCfg) {
        $Config = $winCfg
    } else {
        $Config = $unixCfg
    }
}

try {
    $cfg = Read-ConfigFile -Path $Config
} catch {
    Write-Fail $_.Exception.Message
    exit 2
}

function Get-Cfg {
    param([string]$Key, $Default = $null)
    if ($cfg.Contains($Key) -and $cfg[$Key] -ne '') { return $cfg[$Key] }
    return $Default
}

$VaultPath        = Get-Cfg 'VAULT_PATH'
$ClipOutputDir    = Get-Cfg 'CLIP_OUTPUT_DIR' ''
$PageLoadTimeout  = [int](Get-Cfg 'PAGE_LOAD_TIMEOUT' 45)
$RenderGraceSec   = [double](Get-Cfg 'RENDER_GRACE_SECONDS' 3)
$ClipTimeout      = [int](Get-Cfg 'CLIP_TIMEOUT' 30)
$MaxRetries       = [int](Get-Cfg 'MAX_RETRIES' 3)
$PollInterval     = [double](Get-Cfg 'POLL_INTERVAL' 1)
$TriggerDriver    = (Get-Cfg 'TRIGGER_DRIVER' 'sendkeys').ToLowerInvariant()
$AhkExe           = Get-Cfg 'AHK_EXE' 'AutoHotkey64.exe'
$ChromeExe        = Get-Cfg 'CHROME_EXE' ''
$DebugPort        = [int](Get-Cfg 'CHROME_DEBUG_PORT' 9222)
$UserDataDir      = Get-Cfg 'CHROME_USER_DATA_DIR' ''
$ClipShortcut     = Get-Cfg 'CLIP_SHORTCUT' 'Shift+Alt+S'

# ── Shortcut parsing ──────────────────────────────────────

function Parse-ClipShortcut {
    <#
    Splits a human shortcut like 'Shift+Alt+S' or 'Ctrl+Shift+O' into a
    normalized modifier set + a single main key. Returns a hashtable:
        @{ Modifiers = @('Shift','Alt'); Key = 'S'; Raw = 'Shift+Alt+S' }
    Modifiers accepted (aliases collapsed):
        Shift            -> Shift
        Ctrl / Control   -> Ctrl
        Alt / Option     -> Alt
        Cmd / Meta / Win -> Meta   (rarely bindable on Windows Chrome)
    #>
    param([Parameter(Mandatory)][string]$Shortcut)
    $tokens = ($Shortcut -split '\+') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if (-not $tokens) { throw "CLIP_SHORTCUT is empty." }
    $modifiers = New-Object System.Collections.Generic.List[string]
    $mainKey = $null
    foreach ($tok in $tokens) {
        switch -Regex ($tok.ToLowerInvariant()) {
            '^shift$'          { $modifiers.Add('Shift');   break }
            '^(ctrl|control)$' { $modifiers.Add('Ctrl');    break }
            '^(alt|option)$'   { $modifiers.Add('Alt');     break }
            '^(cmd|meta|win|command)$' { $modifiers.Add('Meta'); break }
            default {
                if ($mainKey) {
                    throw "CLIP_SHORTCUT '$Shortcut' has multiple non-modifier keys: '$mainKey' and '$tok'."
                }
                $mainKey = $tok.ToUpperInvariant()
            }
        }
    }
    if (-not $mainKey) { throw "CLIP_SHORTCUT '$Shortcut' has no main key." }
    return @{ Modifiers = @($modifiers | Sort-Object -Unique); Key = $mainKey; Raw = $Shortcut }
}

function ConvertTo-AhkShortcut {
    <# Converts parsed shortcut into AHK Send syntax, e.g. '+!s' for Shift+Alt+S. #>
    param([Parameter(Mandatory)][hashtable]$Parsed)
    $map = @{ 'Shift' = '+'; 'Ctrl' = '^'; 'Alt' = '!'; 'Meta' = '#' }
    $prefix = ''
    foreach ($m in $Parsed.Modifiers) { $prefix += $map[$m] }
    # AHK sends the literal key; for letters lowercase is conventional.
    $key = $Parsed.Key
    if ($key.Length -eq 1) { $key = $key.ToLowerInvariant() }
    return $prefix + $key
}

function ConvertTo-SendKeysShortcut {
    <# Converts parsed shortcut into System.Windows.Forms.SendKeys syntax. #>
    param([Parameter(Mandatory)][hashtable]$Parsed)
    $map = @{ 'Shift' = '+'; 'Ctrl' = '^'; 'Alt' = '%'; 'Meta' = '^' } # Meta unsupported, degrade to Ctrl-ish
    $prefix = ''
    foreach ($m in $Parsed.Modifiers) { $prefix += $map[$m] }
    $key = $Parsed.Key
    if ($key.Length -eq 1) { $key = $key.ToLowerInvariant() }
    return $prefix + $key
}

function Test-Config {
    if (-not $VaultPath)                                                 { Write-Fail 'VAULT_PATH is empty';                              return $false }
    if (-not (Test-Path -LiteralPath $VaultPath -PathType Container))    { Write-Fail "VAULT_PATH does not exist: $VaultPath";           return $false }
    if ($ClipOutputDir) {
        $sub = Join-Path $VaultPath $ClipOutputDir
        if (-not (Test-Path -LiteralPath $sub -PathType Container))      { Write-Fail "CLIP_OUTPUT_DIR does not exist: $sub";            return $false }
    }
    if ($MaxRetries -lt 1)                                                { Write-Fail 'MAX_RETRIES must be >= 1';                        return $false }
    if ($TriggerDriver -notin @('ahk','sendkeys'))                        { Write-Fail "TRIGGER_DRIVER must be 'ahk' or 'sendkeys'";      return $false }
    if ($TriggerDriver -eq 'ahk' -and -not (Get-Command $AhkExe -ErrorAction SilentlyContinue)) {
        Write-Fail "AutoHotkey executable not found on PATH: $AhkExe. Install AutoHotkey v2 or set TRIGGER_DRIVER=sendkeys."
        return $false
    }
    try { $script:ClipShortcutParsed = Parse-ClipShortcut $ClipShortcut } catch {
        Write-Fail $_.Exception.Message
        return $false
    }
    return $true
}

function Test-Url {
    param([string]$Url)
    return $Url -match '^(?i)https?://[^\s/?#]+([^\s]*)?$'
}

# ── Chrome bootstrap ───────────────────────────────────────────────

function Resolve-ChromeExe {
    if ($ChromeExe -and (Test-Path -LiteralPath $ChromeExe)) { return $ChromeExe }
    $candidates = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Ensure-ChromeWithDebugging {
    if (Wait-CdpReady -Port $DebugPort -TimeoutSec 1) {
        Write-Log "Chrome DevTools already listening on port $DebugPort."
        return $true
    }

    $exe = Resolve-ChromeExe
    if (-not $exe) {
        Write-Fail 'Could not locate chrome.exe. Set CHROME_EXE in config.'
        return $false
    }

    $profileDir = $UserDataDir
    if (-not $profileDir) {
        $profileDir = Join-Path $env:LOCALAPPDATA 'Obsidian-Clipper-AutoTrigger\chrome-profile'
    }
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

    Write-Log "Starting Chrome with remote debugging on port $DebugPort (profile: $profileDir)..."
    $chromeArgs = @(
        "--remote-debugging-port=$DebugPort",
        "--user-data-dir=$profileDir",
        'about:blank'
    )
    Start-Process -FilePath $exe -ArgumentList $chromeArgs | Out-Null

    if (-not (Wait-CdpReady -Port $DebugPort -TimeoutSec 20)) {
        Write-Fail "Chrome did not expose DevTools on port $DebugPort within 20s."
        return $false
    }
    return $true
}

# ── Markdown detection ─────────────────────────────────────────────

function Get-ScanDir {
    if ($ClipOutputDir) { return (Join-Path $VaultPath $ClipOutputDir) }
    return $VaultPath
}

function Get-MarkdownSnapshot {
    $dir = Get-ScanDir
    $map = @{}
    Get-ChildItem -LiteralPath $dir -Recurse -Filter *.md -File -ErrorAction SilentlyContinue |
        ForEach-Object { $map[$_.FullName] = $_.LastWriteTimeUtc.Ticks }
    return $map
}

function Find-NewestChangedMarkdown {
    param([Parameter(Mandatory)][hashtable]$Before)
    $after = Get-MarkdownSnapshot
    $changed = @()
    foreach ($k in $after.Keys) {
        if (-not $Before.ContainsKey($k) -or $Before[$k] -ne $after[$k]) {
            $changed += [PSCustomObject]@{ Path = $k; Ticks = $after[$k] }
        }
    }
    if (-not $changed) { return $null }
    return ($changed | Sort-Object -Property Ticks -Descending | Select-Object -First 1).Path
}

function Remove-FailedUntitledClips {
    param([Parameter(Mandatory)][DateTime]$SinceUtc)
    if (-not $ClipOutputDir) { return }
    Get-ChildItem -LiteralPath $VaultPath -Filter 'Untitled*.md' -File -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.Name -eq 'Untitled.md' -or $_.Name -match '^Untitled \d+\.md$') -and
            ($_.LastWriteTimeUtc -ge $SinceUtc -or $_.CreationTimeUtc -ge $SinceUtc)
        } |
        ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Force
                Write-Log "Cleaned failed clip artefact: $($_.Name)"
            } catch {
                Write-Log "Could not remove $($_.FullName): $_"
            }
        }
}

# ── Trigger drivers ────────────────────────────────────────────────

function Invoke-ClipTrigger {
    switch ($TriggerDriver) {
        'ahk' {
            $ahk = Join-Path $TrigDir 'send_clip_ahk.ahk'
            $keys = ConvertTo-AhkShortcut $script:ClipShortcutParsed
            $p = Start-Process -FilePath $AhkExe -ArgumentList @($ahk, $keys) -NoNewWindow -PassThru -Wait
            return ($p.ExitCode -eq 0)
        }
        'sendkeys' {
            $ps1 = Join-Path $TrigDir 'send_clip_sendkeys.ps1'
            $keys = ConvertTo-SendKeysShortcut $script:ClipShortcutParsed
            $p = Start-Process -FilePath 'pwsh' `
                               -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$ps1,'-Keys',$keys) `
                               -NoNewWindow -PassThru -Wait
            return ($p.ExitCode -eq 0)
        }
        default { return $false }
    }
}

# ── Per-URL clip ───────────────────────────────────────────────────

function Wait-ForMarkdown {
    param([Parameter(Mandatory)][hashtable]$BeforeSnapshot)
    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt $ClipTimeout) {
        $found = Find-NewestChangedMarkdown -Before $BeforeSnapshot
        if ($found) { return $found }
        $elapsed = ((Get-Date) - $start).TotalSeconds
        # Adaptive polling: match the macOS shell version.
        #   < 5s   : 0.5s
        #   < 15s  : POLL_INTERVAL (default 1s)
        #   >= 15s : 2s
        if ($elapsed -lt 5) {
            $sleepSec = 0.5
        } elseif ($elapsed -lt 15) {
            $sleepSec = [Math]::Max($PollInterval, 0.3)
        } else {
            $sleepSec = 2
        }
        Start-Sleep -Milliseconds ([int]($sleepSec * 1000))
    }
    return $null
}

function Clip-OneUrl {
    param([Parameter(Mandatory)][string]$Url)

    Write-Log "Opening tab for: $Url"
    try {
        $target = New-CdpTab -Port $DebugPort -Url $Url
    } catch {
        Write-Fail "Could not open Chrome tab via CDP: $_"
        return $false
    }
    $targetId = $target.id
    $wsUrl = $target.webSocketDebuggerUrl

    try {
        Write-Log 'Waiting for page load...'
        if (-not (Wait-CdpPageLoad -WebSocketUrl $wsUrl -TimeoutSec $PageLoadTimeout -RenderGraceSec $RenderGraceSec)) {
            Write-Fail "Page did not finish loading within ${PageLoadTimeout}s."
            return $false
        }

        for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
            Write-Log "Triggering clipper via '$TriggerDriver' (attempt $attempt/$MaxRetries)..."
            $before = Get-MarkdownSnapshot
            $attemptStart = (Get-Date).ToUniversalTime()

            try { Invoke-CdpBringToFront -WebSocketUrl $wsUrl } catch { Write-Log "bringToFront failed: $_" }

            if (-not (Invoke-ClipTrigger)) {
                Write-Log "Trigger driver reported failure on attempt $attempt."
                Remove-FailedUntitledClips -SinceUtc $attemptStart
                continue
            }

            Write-Log 'Waiting for Markdown...'
            $detected = Wait-ForMarkdown -BeforeSnapshot $before
            if ($detected) {
                Write-Log "Markdown detected: $detected"
                return $detected
            }

            Write-Log "No Markdown produced on attempt $attempt."
            Remove-FailedUntitledClips -SinceUtc $attemptStart
        }

        return $false
    } finally {
        Write-Log 'Closing tab opened by this run...'
        Close-CdpTab -Port $DebugPort -TargetId $targetId
    }
}

# ── Main ───────────────────────────────────────────────────────────

if (-not $Urls -or $Urls.Count -eq 0) {
    Write-Fail 'No URLs provided.'
    Write-Host 'Usage: clip_webpages.ps1 [-Config PATH] [-DryRun] URL [URL ...]'
    exit 2
}

if (-not (Test-Config)) { exit 2 }

Write-Log "Loaded config: $Config"
Write-Log "Vault path: $VaultPath"
if ($ClipOutputDir) {
    Write-Log "Clip output dir: $(Join-Path $VaultPath $ClipOutputDir)"
} else {
    Write-Log 'Clip output dir: (entire vault)'
}
Write-Log "Trigger driver: $TriggerDriver"
Write-Log "Clip shortcut: $ClipShortcut"

$invalid = @()
foreach ($u in $Urls) {
    if (-not (Test-Url $u)) { $invalid += $u; Write-Fail "Invalid URL: $u" }
}

if ($DryRun) {
    if ($invalid.Count -gt 0) { exit 2 }
    Write-Log 'Dry run complete. Config and URL validation passed.'
    exit 0
}

if (-not (Ensure-ChromeWithDebugging)) { exit 2 }

$successes = 0
$failures  = 0
$failureUrls = @()

foreach ($u in $Urls) {
    Write-Log '-----'
    Write-Log "Starting clip: $u"
    if (-not (Test-Url $u)) {
        $failures++; $failureUrls += $u
        Write-Log 'Result: FAILED invalid URL'
        continue
    }
    $result = Clip-OneUrl -Url $u
    if ($result) {
        $successes++; Write-Log 'Result: SUCCEEDED'
    } else {
        $failures++; $failureUrls += $u
        Write-Log 'Result: FAILED'
    }
}

Write-Log '-----'
Write-Log "Finished. Successful clips: $successes. Failures: $failures."
if ($failureUrls.Count -gt 0) {
    Write-Log 'Failed URLs:'
    foreach ($u in $failureUrls) { Write-Host "  - $u" }
}

if ($failures -gt 0) { exit 1 } else { exit 0 }
