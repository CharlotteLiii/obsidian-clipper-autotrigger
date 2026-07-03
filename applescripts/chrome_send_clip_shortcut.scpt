-- Sends the Obsidian Web Clipper keystroke to Google Chrome.
-- Key combo is passed via env var OCA_CLIP_SHORTCUT (e.g. "Shift+Option+S").
-- Falls back to Shift+Option+S if unset.

on parseShortcut(raw)
	set AppleScript's text item delimiters to "+"
	set toks to text items of raw
	set AppleScript's text item delimiters to ""
	set mods to {}
	set mainKey to ""
	repeat with tok in toks
		set t to (do shell script "printf %s " & quoted form of (tok as string) & " | tr '[:upper:]' '[:lower:]'")
		if t is "shift" then
			set end of mods to "shift"
		else if t is "ctrl" or t is "control" then
			set end of mods to "control"
		else if t is "alt" or t is "option" then
			set end of mods to "option"
		else if t is "cmd" or t is "command" or t is "meta" or t is "win" then
			set end of mods to "command"
		else
			set mainKey to (tok as string)
		end if
	end repeat
	if mainKey is "" then error "Invalid CLIP_SHORTCUT: " & raw
	-- lowercase single letters for keystroke reliability
	if length of mainKey is 1 then
		set mainKey to (do shell script "printf %s " & quoted form of mainKey & " | tr '[:upper:]' '[:lower:]'")
	end if
	return {mods, mainKey}
end parseShortcut

on run
	try
		set raw to (system attribute "OCA_CLIP_SHORTCUT")
		if raw is "" then set raw to "Shift+Option+S"
	on error
		set raw to "Shift+Option+S"
	end try

	set parsed to parseShortcut(raw)
	set mods to item 1 of parsed
	set mainKey to item 2 of parsed

	set modifierList to {}
	repeat with m in mods
		if (m as string) is "shift" then set end of modifierList to shift down
		if (m as string) is "control" then set end of modifierList to control down
		if (m as string) is "option" then set end of modifierList to option down
		if (m as string) is "command" then set end of modifierList to command down
	end repeat

	tell application "Google Chrome"
		activate
	end tell
	delay 0.3

	tell application "System Events"
		keystroke mainKey using modifierList
	end tell
end run
