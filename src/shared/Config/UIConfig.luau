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
	-- Live events' banner (%d: seconds).
	events = table.freeze({
		BeanRain = table.freeze({
			warning = "🫘 BEAN RAIN IN %ds! Grab beans for coins and a Fart Dash",
			active = "🫘 BEAN RAIN! Grab the beans: coins and a Fart Dash (%ds)",
		}),
	}),
	-- Gas Control's zone line under the score boxes (%s: a team's short
	-- name; the counts are each team's players in the zone).
	zone = table.freeze({
		held = "%s HOLD THE PLAZA · +1 A SECOND",
		contested = "PLAZA CONTESTED (%d v %d)",
		empty = "STAND IN THE PLAZA TO SCORE",
	}),

	-- What each reward line says it was for.
	rewardReasons = table.freeze({
		elimination = "Elimination",
		assist = "Assist",
		chainBonus = "Chain reaction",
		alpha = "Alpha streak",
		participation = "Time played",
		levelCap = "Level 50",
		levelCapRepeat = "Level 50 bonus",
		mastery = "Mastery",
		daily = "Daily reward",
		spin = "Free spin",
		squad = "Playing with friends",
		season = "Season tier",
		event = "Bean Rain",
		zone = "Holding the plaza",
		welcome = "Welcome a friend",
		purchase = "Store",
		test = "Test",
	}),
	rewardSeconds = 2.5,
	levelUpSeconds = 3.5,

	-- Contextual tips: each once a session, never mid-fight.
	tipSeconds = 6,
	tips = table.freeze({
		dash = "Tip: SHIFT for a Fart Dash out of trouble.",
		barrels = "Tip: shoot a gas barrel when enemies are standing near it.",
		buy = "You can buy the %s now: press M, then Weapons.",
		ability = "%s unlocked: press M, then Abilities, to equip it.",
	}),

	-- The locker's tabs, on the home screen and in the M menu.
	menuSections = table.freeze({ "Weapons", "Abilities", "Progression", "Store", "Settings" }),
	-- Entries that arrive in later phases.
	comingSoon = table.freeze({ "Leaderboard" }),

	keys = table.freeze({
		dash = Enum.KeyCode.LeftShift,
		ability = Enum.KeyCode.Q,
		emote = Enum.KeyCode.E,
		-- Hotbar slots 1-4: your weapons.
		slots = table.freeze({ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }),
		fire = Enum.UserInputType.MouseButton1,
		camera = Enum.KeyCode.V,
		menu = Enum.KeyCode.M,
		scoreboard = Enum.KeyCode.Tab,
		-- Kept free for later mechanics.
		reserved = table.freeze({ Enum.KeyCode.R, Enum.KeyCode.F }),
	}),
	-- The one-time card on a player's first PLAY.
	controls = table.freeze({
		{ "WASD", "Move" },
		{ "MOUSE", "Aim" },
		{ "LEFT CLICK", "Fire" },
		{ "SHIFT", "Fart Dash" },
		{ "Q", "Ability (once unlocked)" },
		{ "1-4", "Pick a weapon" },
		{ "E", "Emote" },
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
