-- Template body for the macOS "ObsidianClip" Shortcut (Shortcuts.app).
-- Paste this into a "Run AppleScript" action inside a Shortcut named
-- exactly SHORTCUT_NAME from config/clipper.conf (default "ObsidianClip").
--
-- If you customized the Web Clipper hotkey in Chrome, update the
-- `keystroke "s" using {shift down, option down}` line below to match
-- (see https://support.apple.com/guide/shortcuts-mac for AppleScript syntax).
--
-- Modifiers accepted: shift down, control down, option down, command down.

on run {input, parameters}
  tell application "Google Chrome"
    activate
  end tell

  delay 0.3

  tell application "System Events"
    keystroke "s" using {shift down, option down}
  end tell

  return input
end run
