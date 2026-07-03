on run argv
  if (count of argv) is not 2 then error "Expected window id and tab id"
  set targetWindowId to item 1 of argv as text
  set targetTabId to item 2 of argv as text
  set tabSeparator to character id 9

  tell application "Google Chrome"
    repeat with browserWindow in windows
      if ((id of browserWindow) as text) is targetWindowId then
        repeat with browserTab in tabs of browserWindow
          if ((id of browserTab) as text) is targetTabId then
            set loadingState to loading of browserTab
            set tabTitle to title of browserTab
            set tabUrl to URL of browserTab
            return (loadingState as text) & tabSeparator & tabTitle & tabSeparator & tabUrl
          end if
        end repeat
      end if
    end repeat
  end tell

  return "missing" & tabSeparator & "" & tabSeparator & ""
end run
