# Minimal Chrome DevTools Protocol client for the Windows clipper.
# Depends only on PowerShell 7's built-in Invoke-RestMethod and
# System.Net.WebSockets.ClientWebSocket.

Set-StrictMode -Version Latest

function Get-CdpVersion {
    param([Parameter(Mandatory)][int]$Port)
    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 3
    } catch {
        return $null
    }
}

function Wait-CdpReady {
    param(
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutSec = 15
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Get-CdpVersion -Port $Port) { return $true }
        Start-Sleep -Milliseconds 300
    }
    return $false
}

function New-CdpTab {
    # Opens a new tab and returns the target metadata (id, webSocketDebuggerUrl, ...).
    param(
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][string]$Url
    )
    $encoded = [System.Uri]::EscapeDataString($Url)
    return Invoke-RestMethod -Method Put -Uri "http://127.0.0.1:$Port/json/new?$encoded" -TimeoutSec 10
}

function Close-CdpTab {
    param(
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][string]$TargetId
    )
    try {
        Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/close/$TargetId" -TimeoutSec 5 | Out-Null
    } catch {
        # Tab may already be gone; that is fine.
    }
}

function Get-CdpTargets {
    param([Parameter(Mandatory)][int]$Port)
    return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -TimeoutSec 5
}

function New-CdpSocket {
    param([Parameter(Mandatory)][string]$WebSocketUrl)
    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    $cts = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(10))
    $ws.ConnectAsync([Uri]$WebSocketUrl, $cts.Token).GetAwaiter().GetResult()
    return $ws
}

function Send-CdpCommand {
    param(
        [Parameter(Mandatory)][System.Net.WebSockets.ClientWebSocket]$Socket,
        [Parameter(Mandatory)][int]$Id,
        [Parameter(Mandatory)][string]$Method,
        [hashtable]$Params
    )
    $payload = @{ id = $Id; method = $Method }
    if ($Params) { $payload.params = $Params }
    $json = $payload | ConvertTo-Json -Compress -Depth 6
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $segment = [System.ArraySegment[byte]]::new($bytes)
    $cts = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(5))
    $Socket.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).GetAwaiter().GetResult()
}

function Receive-CdpMessage {
    param(
        [Parameter(Mandatory)][System.Net.WebSockets.ClientWebSocket]$Socket,
        [int]$TimeoutSec = 5
    )
    $buffer = [byte[]]::new(16384)
    $sb = [System.Text.StringBuilder]::new()
    $cts = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($TimeoutSec))
    try {
        do {
            $segment = [System.ArraySegment[byte]]::new($buffer)
            $result = $Socket.ReceiveAsync($segment, $cts.Token).GetAwaiter().GetResult()
            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                return $null
            }
            [void]$sb.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count))
        } while (-not $result.EndOfMessage)
    } catch [System.OperationCanceledException] {
        return $null
    }
    return $sb.ToString() | ConvertFrom-Json
}

function Wait-CdpPageLoad {
    <#
    Connects to the tab's WebSocket, enables Page domain, and waits for
    Page.loadEventFired. Returns $true on load, $false on timeout.

    Handles the race where a fast-loading page fires loadEventFired
    *before* the WebSocket subscription is established: after Page.enable
    we probe document.readyState via Runtime.evaluate and short-circuit
    when the page is already 'complete'.
    #>
    param(
        [Parameter(Mandatory)][string]$WebSocketUrl,
        [int]$TimeoutSec = 45,
        [double]$RenderGraceSec = 3
    )

    $ws = New-CdpSocket -WebSocketUrl $WebSocketUrl
    try {
        Send-CdpCommand -Socket $ws -Id 1 -Method 'Page.enable'

        # Fast path: page may already be fully loaded before we subscribed.
        Send-CdpCommand -Socket $ws -Id 2 -Method 'Runtime.evaluate' -Params @{
            expression    = 'document.readyState'
            returnByValue = $true
        }

        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        while ((Get-Date) -lt $deadline) {
            $remaining = [int][Math]::Max(1, ($deadline - (Get-Date)).TotalSeconds)
            $msg = Receive-CdpMessage -Socket $ws -TimeoutSec $remaining
            if ($null -eq $msg) { continue }

            # Fast path: Runtime.evaluate reply for id=2.
            if ($msg.PSObject.Properties.Name -contains 'id' -and $msg.id -eq 2) {
                $readyState = $null
                try { $readyState = $msg.result.result.value } catch { }
                if ($readyState -eq 'complete') {
                    if ($RenderGraceSec -gt 0) { Start-Sleep -Milliseconds ([int]($RenderGraceSec * 1000)) }
                    return $true
                }
                continue
            }

            if ($msg.PSObject.Properties.Name -contains 'method' -and $msg.method -eq 'Page.loadEventFired') {
                if ($RenderGraceSec -gt 0) { Start-Sleep -Milliseconds ([int]($RenderGraceSec * 1000)) }
                return $true
            }
        }
        return $false
    } finally {
        try {
            $cts = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(2))
            $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', $cts.Token).GetAwaiter().GetResult()
        } catch { }
        $ws.Dispose()
    }
}

function Invoke-CdpBringToFront {
    param([Parameter(Mandatory)][string]$WebSocketUrl)
    $ws = New-CdpSocket -WebSocketUrl $WebSocketUrl
    try {
        Send-CdpCommand -Socket $ws -Id 1 -Method 'Page.bringToFront'
        # Give the OS a moment to focus the window before any keystroke.
        Start-Sleep -Milliseconds 250
    } finally {
        try {
            $cts = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(2))
            $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', $cts.Token).GetAwaiter().GetResult()
        } catch { }
        $ws.Dispose()
    }
}

function Invoke-CdpEvaluate {
    <#
    Runs a JS expression in the target's main frame and returns the
    deserialized value (returnByValue = true). Returns $null on timeout
    or protocol error.
    #>
    param(
        [Parameter(Mandatory)][string]$WebSocketUrl,
        [Parameter(Mandatory)][string]$Expression,
        [int]$TimeoutSec = 5
    )
    $ws = New-CdpSocket -WebSocketUrl $WebSocketUrl
    try {
        Send-CdpCommand -Socket $ws -Id 1 -Method 'Runtime.evaluate' -Params @{
            expression    = $Expression
            returnByValue = $true
            awaitPromise  = $true
        }
        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        while ((Get-Date) -lt $deadline) {
            $remaining = [int][Math]::Max(1, ($deadline - (Get-Date)).TotalSeconds)
            $msg = Receive-CdpMessage -Socket $ws -TimeoutSec $remaining
            if ($null -eq $msg) { continue }
            if ($msg.PSObject.Properties.Name -contains 'id' -and $msg.id -eq 1) {
                try { return $msg.result.result.value } catch { return $null }
            }
        }
        return $null
    } finally {
        try {
            $cts = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(2))
            $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', $cts.Token).GetAwaiter().GetResult()
        } catch { }
        $ws.Dispose()
    }
}

function Test-CdpLoginWall {
    <#
    Post-load heuristic: after Page.loadEventFired, run a JS probe to
    decide whether the tab is likely showing a login / signup / paywall
    page instead of the real content the user wanted to clip.

    Returns a PSCustomObject:
      IsWall           [bool]
      Reason           [string]   short human-readable reason, empty if clear
      Signals          [hashtable] individual probe results (for logging)
      FinalUrl, Title  [string]   captured page metadata

    Heuristics (any single strong signal, or short-text + weak signal):
      * Final URL path contains login/signin/sso/auth/accounts/oauth/...
      * A visible <input type=password> is present.
      * A paywall / login-wall DOM node ([class*=paywall], [data-paywall]).
      * Body text matches known login/paywall phrases (EN + zh-CN).
      * Body visible text is unusually short (< MinTextLen) AND any of
        the weak signals above.
    #>
    param(
        [Parameter(Mandatory)][string]$WebSocketUrl,
        [int]$MinTextLen = 300,
        [int]$TimeoutSec = 5
    )

    $js = @'
(() => {
  try {
    const url = location.href;
    const loginPathRe = /\/(login|signin|sign_in|sign-in|sso|auth|authenticate|accounts|oauth|session|passport|register|signup|verify|captcha)(\/|\?|#|$)/i;
    const urlHit = loginPathRe.test(url);
    const passwordInput = !!document.querySelector('input[type=password]');
    const paywallNode = !!document.querySelector(
      '[class*="paywall" i], [id*="paywall" i], [data-paywall], ' +
      '[class*="login-wall" i], [class*="loginwall" i], [class*="regwall" i]'
    );
    const rawText = (document.body ? (document.body.innerText || '') : '');
    const bodyText = rawText.slice(0, 20000);
    const textLen = bodyText.replace(/\s+/g, ' ').trim().length;
    const patterns = [
      [/please\s+(sign|log)\s*in/i,        'en:please-sign-in'],
      [/you\s+must\s+be\s+signed\s+in/i,   'en:must-be-signed-in'],
      [/log\s*in\s+to\s+continue/i,        'en:log-in-to-continue'],
      [/sign\s*in\s+to\s+continue/i,       'en:sign-in-to-continue'],
      [/subscribe\s+to\s+(read|continue)/i,'en:subscribe-to-read'],
      [/this\s+content\s+is\s+for.*members/i, 'en:members-only'],
      [/become\s+a\s+(paid\s+)?member/i,   'en:become-member'],
      [/登[录陆]后.{0,12}(阅读|查看|继续|访问)/, 'zh:login-to-view'],
      [/请先?登[录陆]/,                    'zh:please-login'],
      [/需要登[录陆]/,                     'zh:need-login'],
      [/会员(专享|可见)/,                  'zh:members-only'],
      [/订阅后可(查看|阅读)/,              'zh:subscribe-to-read'],
      [/关注公众号后.{0,10}(阅读|查看)/,   'zh:wechat-follow'],
    ];
    let textHit = null;
    for (const [re, tag] of patterns) {
      if (re.test(bodyText)) { textHit = tag; break; }
    }
    return {
      url, title: (document.title || '').slice(0, 200),
      urlHit, passwordInput, paywallNode, textHit, textLen
    };
  } catch (e) {
    return { error: String(e) };
  }
})()
'@

    $result = Invoke-CdpEvaluate -WebSocketUrl $WebSocketUrl -Expression $js -TimeoutSec $TimeoutSec
    $signals = @{
        urlHit        = $false
        passwordInput = $false
        paywallNode   = $false
        textHit       = $null
        textLen       = -1
        probeError    = $null
    }
    $finalUrl = ''
    $title    = ''

    if ($null -ne $result) {
        try { $signals.urlHit        = [bool]$result.urlHit }        catch { }
        try { $signals.passwordInput = [bool]$result.passwordInput } catch { }
        try { $signals.paywallNode   = [bool]$result.paywallNode }   catch { }
        try { $signals.textHit       = $result.textHit }             catch { }
        try { $signals.textLen       = [int]$result.textLen }        catch { }
        try { $finalUrl              = [string]$result.url }         catch { }
        try { $title                 = [string]$result.title }       catch { }
        try { $signals.probeError    = $result.error }               catch { }
    } else {
        $signals.probeError = 'runtime-evaluate-timeout'
    }

    # Decision. Strong signals fire on their own. Short text alone is
    # not enough (many valid pages are short after JS render); it must
    # co-occur with a weaker signal.
    $reason = ''
    if ($signals.passwordInput) {
        $reason = 'password input present'
    } elseif ($signals.paywallNode) {
        $reason = 'paywall/login-wall DOM node present'
    } elseif ($signals.urlHit) {
        $reason = "URL path looks like login/auth: $finalUrl"
    } elseif ($signals.textHit) {
        $reason = "login/paywall phrase matched: $($signals.textHit)"
    } elseif ($signals.textLen -ge 0 -and $signals.textLen -lt $MinTextLen -and ($signals.urlHit -or $signals.textHit -or $signals.paywallNode)) {
        $reason = "very short body ($($signals.textLen) chars) plus weak signal"
    }

    return [PSCustomObject]@{
        IsWall   = [bool]$reason
        Reason   = $reason
        Signals  = $signals
        FinalUrl = $finalUrl
        Title    = $title
    }
}

Export-ModuleMember -Function *
