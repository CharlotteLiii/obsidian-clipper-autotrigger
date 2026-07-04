-- Post-load login-wall / paywall probe for the macOS clipper.
--
-- Runs a JS heuristic in the active tab of the given Chrome window and
-- prints a tab-separated line the shell can consume:
--
--   isWall	reason	finalUrl	title	urlHit	passwordInput	paywallNode	textHit	textLen
--
--   isWall         "1" if suspected login wall, "0" otherwise
--   reason         short human-readable reason (may be empty)
--   finalUrl       location.href after page load
--   title          document.title (truncated)
--   urlHit         "1"/"0"  URL path matches login-style pattern
--   passwordInput  "1"/"0"  visible <input type=password> present
--   paywallNode    "1"/"0"  paywall/login-wall DOM node present
--   textHit        tag name of matched login/paywall phrase, or ""
--   textLen        length of trimmed body innerText (integer)
--
-- On probe error (Chrome AppleScript not allowed, JS threw, etc.):
--   error	<reason>	<url-if-any>	""	0	0	0		-1
--
-- Requires Chrome "View → Developer → Allow JavaScript from Apple Events"
-- to be enabled. If not, this script errors out with a clear message and
-- the caller should log-and-continue (mirrors the Windows probe fallback).
--
-- Arguments:
--   1: window id (as text)
--   2: tab id    (as text)
--   3: min body text length threshold (int) — pages shorter than this
--      combined with a weak signal are treated as suspicious.

on run argv
	if (count of argv) is less than 2 then error "Expected window id, tab id, [min text len]"
	set targetWindowId to item 1 of argv as text
	set targetTabId to item 2 of argv as text
	if (count of argv) is greater than or equal to 3 then
		set minTextLen to (item 3 of argv) as integer
	else
		set minTextLen to 300
	end if

	set TAB to character id 9

	set probeJS to "(() => { try {
    const url = location.href;
    const loginPathRe = /\\/(login|signin|sign_in|sign-in|sso|auth|authenticate|accounts|oauth|session|passport|register|signup|verify|captcha)(\\/|\\?|#|$)/i;
    const urlHit = loginPathRe.test(url);
    const passwordInput = !!document.querySelector('input[type=password]');
    const paywallNode = !!document.querySelector('[class*=\"paywall\" i], [id*=\"paywall\" i], [data-paywall], [class*=\"login-wall\" i], [class*=\"loginwall\" i], [class*=\"regwall\" i]');
    const rawText = (document.body ? (document.body.innerText || '') : '');
    const bodyText = rawText.slice(0, 20000);
    const textLen = bodyText.replace(/\\s+/g, ' ').trim().length;
    const patterns = [
      [/please\\s+(sign|log)\\s*in/i, 'en:please-sign-in'],
      [/you\\s+must\\s+be\\s+signed\\s+in/i, 'en:must-be-signed-in'],
      [/log\\s*in\\s+to\\s+continue/i, 'en:log-in-to-continue'],
      [/sign\\s*in\\s+to\\s+continue/i, 'en:sign-in-to-continue'],
      [/subscribe\\s+to\\s+(read|continue)/i, 'en:subscribe-to-read'],
      [/this\\s+content\\s+is\\s+for.*members/i, 'en:members-only'],
      [/become\\s+a\\s+(paid\\s+)?member/i, 'en:become-member'],
      [/登[录陆]后.{0,12}(阅读|查看|继续|访问)/, 'zh:login-to-view'],
      [/请先?登[录陆]/, 'zh:please-login'],
      [/需要登[录陆]/, 'zh:need-login'],
      [/会员(专享|可见)/, 'zh:members-only'],
      [/订阅后可(查看|阅读)/, 'zh:subscribe-to-read'],
      [/关注公众号后.{0,10}(阅读|查看)/, 'zh:wechat-follow']
    ];
    let textHit = '';
    for (const [re, tag] of patterns) { if (re.test(bodyText)) { textHit = tag; break; } }
    return [url, (document.title || '').slice(0, 200), urlHit ? 1 : 0, passwordInput ? 1 : 0, paywallNode ? 1 : 0, textHit, textLen].join('\\u0001');
  } catch (e) { return 'ERROR:' + String(e); }
})()"

	set probeResult to ""
	set probeError to ""

	try
		tell application "Google Chrome"
			set matchedTab to missing value
			repeat with browserWindow in windows
				if ((id of browserWindow) as text) is targetWindowId then
					repeat with browserTab in tabs of browserWindow
						if ((id of browserTab) as text) is targetTabId then
							set matchedTab to browserTab
							exit repeat
						end if
					end repeat
				end if
				if matchedTab is not missing value then exit repeat
			end repeat
			if matchedTab is missing value then error "tab-not-found"
			set probeResult to (execute matchedTab javascript probeJS)
		end tell
	on error errText number errNum
		set probeError to (errText & " (" & (errNum as text) & ")")
	end try

	if probeError is not "" then
		return "error" & TAB & probeError & TAB & "" & TAB & "" & TAB & "0" & TAB & "0" & TAB & "0" & TAB & "" & TAB & "-1"
	end if

	if probeResult starts with "ERROR:" then
		return "error" & TAB & (text 7 thru -1 of probeResult) & TAB & "" & TAB & "" & TAB & "0" & TAB & "0" & TAB & "0" & TAB & "" & TAB & "-1"
	end if

	-- probeResult is fields joined by \u0001 (SOH)
	set SOH to character id 1
	set AppleScript's text item delimiters to SOH
	set fields to text items of probeResult
	set AppleScript's text item delimiters to ""
	if (count of fields) is less than 7 then
		return "error" & TAB & "malformed-probe-result" & TAB & "" & TAB & "" & TAB & "0" & TAB & "0" & TAB & "0" & TAB & "" & TAB & "-1"
	end if

	set finalUrl to item 1 of fields
	set docTitle to item 2 of fields
	set urlHit to item 3 of fields
	set passwordInput to item 4 of fields
	set paywallNode to item 5 of fields
	set textHit to item 6 of fields
	set textLen to (item 7 of fields) as integer

	-- Decision. Strong signals fire on their own. Short text alone is not
	-- enough; it must co-occur with a weaker signal. Mirrors Test-CdpLoginWall.
	set isWall to "0"
	set reason to ""
	if passwordInput is "1" then
		set isWall to "1"
		set reason to "password input present"
	else if paywallNode is "1" then
		set isWall to "1"
		set reason to "paywall/login-wall DOM node present"
	else if urlHit is "1" then
		set isWall to "1"
		set reason to "URL path looks like login/auth: " & finalUrl
	else if textHit is not "" then
		set isWall to "1"
		set reason to "login/paywall phrase matched: " & textHit
	else if textLen is greater than or equal to 0 and textLen is less than minTextLen and (urlHit is "1" or textHit is not "" or paywallNode is "1") then
		set isWall to "1"
		set reason to "very short body (" & (textLen as text) & " chars) plus weak signal"
	end if

	return isWall & TAB & reason & TAB & finalUrl & TAB & docTitle & TAB & urlHit & TAB & passwordInput & TAB & paywallNode & TAB & textHit & TAB & (textLen as text)
end run
