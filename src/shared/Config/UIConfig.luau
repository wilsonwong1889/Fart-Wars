-- What the client shows: palette, words, keys and screen timings.
local UIConfig = {
	colors = table.freeze({
		panel = Color3.fromRGB(24, 20, 34),
		panelLight = Color3.fromRGB(44, 38, 60),
		stroke = Color3.fromRGB(12, 10, 18),
		text = Color3.fromRGB(245, 242, 250),
		muted = Color3.fromRGB(170, 162, 190),
		accent = Color3.fromRGB(150, 230, 60),
		play = Color3.fromRGB(102, 220, 60),
		warning = Color3.fromRGB(255, 120, 60),
		disabled = Color3.fromRGB(90, 86, 100),
	}),
	font = Enum.Font.FredokaOne,
	bodyFont = Enum.Font.GothamBold,

	title = "FART WARS",
	tagline = "Skibidi Stinkers vs Sigma Sharters",

	phaseLabels = table.freeze({
		WAITING = "WAITING FOR PLAYERS",
		ACTIVE = "ROUND",
		RESULTS = "NEXT ROUND IN",
		-- Continuous play: a match that never ends.
		LIVE = "LIVE MATCH",
	}),
	afkWarning = "BRO FELL ASLEEP MID-FART!",

	-- Home screen and M menu entries that arrive in later phases.
	comingSoon = table.freeze({ "Weapons", "Abilities", "Shop", "Rewards", "Profile", "Settings", "Leaderboard" }),

	keys = table.freeze({
		dash = Enum.KeyCode.LeftShift,
		fire = Enum.UserInputType.MouseButton1,
		camera = Enum.KeyCode.V,
		menu = Enum.KeyCode.M,
		scoreboard = Enum.KeyCode.Tab,
		-- Kept free for later mechanics; nothing in Phase 1 binds them.
		reserved = table.freeze({ Enum.KeyCode.Q, Enum.KeyCode.R, Enum.KeyCode.F }),
	}),
	-- The one-time card on a player's first PLAY.
	controls = table.freeze({
		{ "WASD", "Move" },
		{ "MOUSE", "Aim" },
		{ "LEFT CLICK", "Fire" },
		{ "SHIFT", "Fart Dash" },
		{ "SPACE", "Jump" },
		{ "V", "First / third person" },
		{ "M", "Menu" },
		{ "TAB", "Scoreboard" },
	}),
	controlsSeconds = 8,
	toastSeconds = 4,

	-- Third-person camera distance after switching back from first person.
	thirdPersonDistance = 12,
	-- The home screen's live view holds each fixed camera point this long.
	spectatorShotSeconds = 8,
}

return table.freeze(UIConfig)
