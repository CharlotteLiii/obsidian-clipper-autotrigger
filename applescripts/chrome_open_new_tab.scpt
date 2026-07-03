on run argv
  if (count of argv) < 1 then error "Expected URL argument"
  set targetUrl to item 1 of argv
  set tabSeparator to character id 9

  tell application "Google Chrome"
    activate

    if (count of argv) >= 2 then
      -- Reuse existing window when a window id is provided.
      set targetWindowId to item 2 of argv as text
      set targetWindow to missing value
      repeat with browserWindow in windows
        if ((id of browserWindow) as text) is targetWindowId then
          set targetWindow to browserWindow
          exit repeat
        end if
      end repeat

      if targetWindow is missing value then
        -- Window disappeared; create a new one.
        set targetWindow to make new window
      end if

      set newTab to make new tab at end of tabs of targetWindow
      set URL of newTab to targetUrl
      set index of targetWindow to 1
      return (id of targetWindow as text) & tabSeparator & (id of newTab as text)
    else
      -- Create a dedicated new window with one tab (original behavior).
      set targetWindow to make new window
      set newTab to item 1 of tabs of targetWindow
      set URL of newTab to targetUrl
      set index of targetWindow to 1
      return (id of targetWindow as text) & tabSeparator & (id of newTab as text)
    end if
  end tell
end run
