<#
Fallback trigger for Obsidian Web Clipper on Windows when AutoHotkey is not
installed. Uses System.Windows.Forms.SendKeys to send the configured chord.

Strategy:
  1. Trust the CDP-driven Page.bringToFront from the caller: if the current
     foreground window is already a Chrome window, send the keystroke
     straight to it. This is critical when multiple Chrome processes (e.g.
     the user's daily browser + the CDP-managed profile) coexist.
  2. Only fall back to AppActivate when no Chrome window has focus. Prefer
     the Chrome process whose main window was activated most recently.

Parameters:
  -Keys  SendKeys chord (e.g. '+%o' for Shift+Alt+O). Defaults to '+%o'.

Exit codes:
  0  success (keystroke sent)
  2  no Chrome window found / could not focus Chrome
#>

param(
    [string]$Keys = '+%o'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName Microsoft.VisualBasic | Out-Null

# Win32 helpers to inspect the active foreground window.
if (-not ([System.Management.Automation.PSTypeName]'ObsidianClipperWin32').Type) {
    Add-Type -Namespace '' -Name 'ObsidianClipperWin32' -MemberDefinition @'
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern System.IntPtr GetForegroundWindow();

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern int GetWindowThreadProcessId(System.IntPtr hWnd, out int lpdwProcessId);
'@
}

function Test-ForegroundIsChrome {
    $hwnd = [ObsidianClipperWin32]::GetForegroundWindow()
    if ($hwnd -eq [System.IntPtr]::Zero) { return $false }
    $pid_ = 0
    [void][ObsidianClipperWin32]::GetWindowThreadProcessId($hwnd, [ref]$pid_)
    if ($pid_ -le 0) { return $false }
    try {
        $proc = Get-Process -Id $pid_ -ErrorAction Stop
    } catch {
        return $false
    }
    return ($proc.ProcessName -ieq 'chrome')
}

if (-not (Test-ForegroundIsChrome)) {
    $chromeProc = Get-Process -Name 'chrome' -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Sort-Object -Property StartTime -Descending |
        Select-Object -First 1

    if (-not $chromeProc) {
        Write-Error 'No Chrome window found. Start Chrome via clip_webpages.ps1 first.'
        exit 2
    }

    try {
        [Microsoft.VisualBasic.Interaction]::AppActivate($chromeProc.Id)
    } catch {
        Write-Error "Could not activate Chrome window: $_"
        exit 2
    }
    Start-Sleep -Milliseconds 250
} else {
    # Small settle in case bringToFront just landed a moment ago.
    Start-Sleep -Milliseconds 100
}

[System.Windows.Forms.SendKeys]::SendWait($Keys)
exit 0
