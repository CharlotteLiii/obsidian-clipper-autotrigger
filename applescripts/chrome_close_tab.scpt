on run argv
  if (count of argv) is not 2 then error "Expected window id and tab id"
  set targetWindowId to item 1 of argv as text
  set targetTabId to item 2 of argv as text

  tell application "Google Chrome"
    repeat with browserWindow in windows
      if ((id of browserWindow) as text) is targetWindowId then
        repeat with browserTab in tabs of browserWindow
          if ((id of browserTab) as text) is targetTabId then
            close browserTab
            return "closed"
          end if
        end repeat
      end if
    end repeat
  end tell

  return "missing"
end run
