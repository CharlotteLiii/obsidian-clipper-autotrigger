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

Export-ModuleMember -Function *
