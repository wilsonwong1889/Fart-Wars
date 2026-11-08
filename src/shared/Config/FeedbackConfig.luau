-- Player feedback (FeatureFlags.FEEDBACK): the M menu's FEEDBACK window
-- and what the server accepts and keeps (FeedbackService). Shared, so the
-- window and the server count characters the same way.
local FeedbackConfig = {}

-- The types a report can have, in the window's order.
FeedbackConfig.KINDS = table.freeze({ "Bug", "Idea", "Other" })
-- How each type looks in the window, and what its text box asks.
FeedbackConfig.LOOKS = table.freeze({
	Bug = table.freeze({ label = "BUG", icon = "🐛", color = Color3.fromRGB(235, 80, 70), prompt = "WHAT BROKE? WHERE WERE YOU, WHAT WERE YOU DOING?" }),
	Idea = table.freeze({ label = "IDEA", icon = "💡", color = Color3.fromRGB(255, 185, 35), prompt = "WHAT SHOULD WE ADD? GO FULL BIG BRAIN." }),
	Other = table.freeze({ label = "OTHER", icon = "💬", color = Color3.fromRGB(45, 155, 245), prompt = "SAY WHAT'S ON YOUR MIND." }),
})
-- The M menu's button.
FeedbackConfig.BUTTON = table.freeze({ label = "FEEDBACK", icon = "📝", color = Color3.fromRGB(230, 90, 160) })

-- The text, in characters (not bytes), after cleaning (FeedbackConfig.clean).
FeedbackConfig.MIN_LENGTH = 3
FeedbackConfig.MAX_LENGTH = 300
-- A payload's text longer than this many bytes is refused before it's read.
FeedbackConfig.MAX_BYTES = 2000

-- Limits per player, across servers: one report every COOLDOWN_SECONDS and
-- PER_DAY a UTC day. One request a REQUEST_SECONDS at most, whatever its fate.
FeedbackConfig.COOLDOWN_SECONDS = 120
FeedbackConfig.PER_DAY = 5
FeedbackConfig.REQUEST_SECONDS = 1

-- What comes along from the client: its last few script errors, each cut
-- to MAX_ERROR_LENGTH characters.
FeedbackConfig.MAX_ERRORS = 5
FeedbackConfig.MAX_ERROR_LENGTH = 200

-- Where reports are kept: each under its own key in STORE_NAME (keys start
-- with the user ID), listed by time in the ordered INDEX_NAME. A server also
-- keeps its last MEMORY_REPORTS in memory (all it has without DataStores).
FeedbackConfig.STORE_NAME = "FartWarsFeedback"
FeedbackConfig.INDEX_NAME = "FartWarsFeedbackIndex"
FeedbackConfig.MEMORY_REPORTS = 50
-- Writes are tried this many times (1 s, then 2 s apart) before giving up.
FeedbackConfig.SAVE_ATTEMPTS = 3

-- `/fw feedback [n]`: how many of the newest reports, by default and at most.
FeedbackConfig.READ_DEFAULT = 10
FeedbackConfig.READ_MAX = 25

-- Control characters (keeping newlines), and the invisible Unicode marks
-- that reorder or hide text: right-to-left overrides and isolates, and
-- zero-width spaces and joiners.
local CONTROL = "[%z\1-\9\11-\31\127]"
local INVISIBLE = { "\226\128[\139-\143]", "\226\128[\170-\174]", "\226\129[\166-\169]", "\239\187\191" }

-- `text` as it's kept: tabs as spaces, other control characters and
-- invisible marks gone, Windows line ends as newlines, at most one blank
-- line in a row, no spaces at the ends of lines or of the whole. Expects
-- valid UTF-8 (check with utf8.len first).
function FeedbackConfig.clean(text: string): string
	local out = string.gsub(text, "\r\n?", "\n")
	out = string.gsub(out, "\t", " ")
	out = string.gsub(out, CONTROL, "")
	for _, mark in INVISIBLE do
		out = string.gsub(out, mark, "")
	end
	out = string.gsub(out, "[ ]+\n", "\n")
	out = string.gsub(out, "\n\n\n+", "\n\n")
	out = string.match(out, "^%s*(.-)%s*$") or ""
	return out
end

-- How many characters `text` has (0 for text that isn't valid UTF-8).
function FeedbackConfig.length(text: string): number
	return utf8.len(text) or 0
end

-- `text` cut to at most `max` characters. Text that isn't valid UTF-8 is
-- cut before its first bad byte.
function FeedbackConfig.cut(text: string, max: number): string
	local count, bad = utf8.len(text)
	if not count then
		text = string.sub(text, 1, (bad :: number) - 1)
		count = utf8.len(text) :: number
	end
	if count <= max then
		return text
	end
	local stop = utf8.offset(text, max + 1) :: number
	return string.sub(text, 1, stop - 1)
end

-- `text` with every one of `names` (players' names) replaced by
-- "<player>", longest first, so a name never reaches a report.
function FeedbackConfig.scrub(text: string, names: { string }): string
	local sorted = table.clone(names)
	table.sort(sorted, function(a, b)
		return #a > #b
	end)
	for _, name in sorted do
		if #name >= 3 then
			local pieces = {}
			local from = 1
			while true do
				local first, last = string.find(text, name, from, true)
				if not first then
					break
				end
				table.insert(pieces, string.sub(text, from, first - 1))
				table.insert(pieces, "<player>")
				from = (last :: number) + 1
			end
			if #pieces > 0 then
				table.insert(pieces, string.sub(text, from))
				text = table.concat(pieces)
			end
		end
	end
	return text
end

return table.freeze(FeedbackConfig)
