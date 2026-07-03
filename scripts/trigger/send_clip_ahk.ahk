; AutoHotkey v2 helper for Obsidian Web Clipper on Windows.
; Sends the configured keystroke to the currently-active Chrome window so
; the caller can pick which tab to clip via CDP Page.bringToFront beforehand.
;
; Usage:
;   AutoHotkey64.exe send_clip_ahk.ahk "+!s"
;
; The single argument is an AHK Send() string (e.g. "+!s" for Shift+Alt+S).
; If omitted, defaults to "+!s" for backward compatibility.

#Requires AutoHotkey v2.0
#SingleInstance Off

keys := "+!s"
if A_Args.Length >= 1 && A_Args[1] != "" {
    keys := A_Args[1]
}

; Prefer whatever window CDP just brought to front. Only re-activate if
; the foreground window is not a Chrome window at all.
if !WinActive("ahk_exe chrome.exe") {
    if !WinExist("ahk_exe chrome.exe") {
        FileAppend "ERROR: No Chrome window found`n", "*"
        ExitApp 2
    }
    WinActivate "ahk_exe chrome.exe"
    if !WinWaitActive("ahk_exe chrome.exe", , 3) {
        FileAppend "ERROR: Could not activate Chrome window`n", "*"
        ExitApp 3
    }
}

; Small settle so Chrome receives the keystroke reliably.
Sleep 150
Send keys
ExitApp 0
