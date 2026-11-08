-- Finding the fight and your team on a 480-stud map (FeatureFlags.COMPASS):
-- the compass strip at the top of the screen, the markers over teammates
-- too far away to pick out, and pings. The client's screen and the
-- server's checks on pings both read this, so they can't disagree.
-- Distances are in studs, sizes in pixels at HUD size 100%.
return table.freeze({
	-- The strip: `spanDegrees` of the horizon across its width, a tick every
	-- tickDegrees and a letter every 45 degrees. North is the Stinkers' end
	-- of the map (-Z) and east the Gas Gutter's side (+X). The lanes and the
	-- plaza are named by their gates' signs (the map's Landmarks), each at
	-- the middle of its two gates; a name leaves the strip while you're
	-- within landmarkHideWithin of that spot (you're there), and when two
	-- would overlap the nearer one shows.
	strip = table.freeze({
		width = 420,
		height = 36,
		-- From the top of the screen, above the score boxes (they start at 52,
		-- and both grow downward with the HUD size).
		top = 4,
		spanDegrees = 150,
		tickDegrees = 15,
		landmarkHideWithin = 60,
		-- The least space between two names on the strip.
		labelGap = 8,
	}),

	-- Markers over teammates (players and bots on your team) further than
	-- minDistance from the camera: that's where the symbol over their heads
	-- stops showing (CombatController's TeamMark), so one or the other is
	-- always there. A teammate who fired or took gas in the last
	-- fightSeconds is in a fight, and one counting down to explode is
	-- blowing up: their marker says so (and pulses, unless Reduce motion),
	-- and while they're off the screen an arrow near its edge points at
	-- them. At most maxArrows at once, blowing up first, then the nearest.
	markers = table.freeze({
		minDistance = 150,
		fightSeconds = 4,
		maxArrows = 3,
		-- How far in from the screen's sides and its top and bottom the arrows
		-- sit; the top and bottom keep clear of the score boxes and the hotbar.
		edgeInsetX = 70,
		edgeInsetY = 150,
		-- A teammate this many pixels inside the screen's edge counts as on it.
		onScreenMargin = 24,
	}),

	-- Pings: the spot under the crosshair, marked for your team (and only
	-- your team) for `seconds`, with a sound; one each, so a new ping moves
	-- your old one. The client waits cooldownSeconds between pings and the
	-- server refuses any closer together than cooldownSeconds - slackSeconds
	-- (network jitter can bunch two honest ones). A spot must be inside the
	-- map's bounds (give or take boundsMargin) and within `range` of the
	-- camera along the crosshair.
	ping = table.freeze({
		seconds = 5,
		cooldownSeconds = 1.5,
		slackSeconds = 0.3,
		range = 700,
		boundsMargin = 4,
		-- The ping's caption colour (a pin needs no team colour: only your
		-- team ever sees it).
		color = Color3.fromRGB(80, 200, 255),
		-- How long a new ping pops in, and fades out at the end (none with
		-- Reduce motion).
		popSeconds = 0.25,
		fadeSeconds = 0.6,
	}),

	words = table.freeze({
		-- The marker over a teammate with team symbols off.
		pip = "◆",
		-- After the symbol, for a teammate in a fight or blowing up.
		fight = "⚔️",
		boom = "💥",
		-- The arrow toward a teammate in trouble (turned to point at them).
		arrow = "▲",
		-- A ping: the pin, its caption (who sent it, YOU for your own, and how
		-- many studs it is from you), and on the strip the pin or, when it's
		-- off the strip, an arrow at the strip's end.
		pin = "📍",
		caption = "%s · %d",
		you = "YOU",
		pingLeft = "◀",
		pingRight = "▶",
	}),
})
