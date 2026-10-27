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

	-- The hit marker at the crosshair, by the server's verdict: a body hit,
	-- a headshot, the hit that fills the target's gas ("kaboom": they're
	-- going off) and one that did nothing ("blocked": protected, or already
	-- going off). Each pops in at `pop` times its size and settles in
	-- popSeconds, shows for `seconds` and fades over the last fadeSeconds;
	-- the kaboom one also throws a ring out to ringSize pixels across. A
	-- headshot plays the hit sound at headshotPitch (playback speed) and
	-- headshotVolume (times the usual).
	hitMarker = table.freeze({
		looks = table.freeze({
			body = table.freeze({ size = 30, color = Color3.fromRGB(245, 242, 250), pop = 1.5, seconds = 0.2 }),
			headshot = table.freeze({ size = 42, color = Color3.fromRGB(255, 205, 50), pop = 1.7, seconds = 0.3 }),
			kaboom = table.freeze({ size = 50, color = Color3.fromRGB(255, 120, 60), pop = 1.9, seconds = 0.45 }),
			blocked = table.freeze({ size = 24, color = Color3.fromRGB(170, 162, 190), pop = 1, seconds = 0.15 }),
		}),
		popSeconds = 0.12,
		fadeSeconds = 0.1,
		ringSize = 90,
		headshotPitch = 1.35,
		headshotVolume = 1.4,
	}),

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
	-- How each locker page looks on its buttons, tabs and header.
	pages = table.freeze({
		Weapons = table.freeze({ label = "SHOP", icon = "🛒", color = Color3.fromRGB(92, 205, 50) }),
		Abilities = table.freeze({ label = "ABILITIES", icon = "⚡", color = Color3.fromRGB(45, 155, 245) }),
		Progression = table.freeze({ label = "LEVELS", icon = "⭐", color = Color3.fromRGB(155, 95, 235) }),
		Store = table.freeze({ label = "STORE", icon = "💎", color = Color3.fromRGB(255, 170, 30) }),
		Settings = table.freeze({ label = "SETTINGS", icon = "⚙️", color = Color3.fromRGB(115, 120, 140) }),
	}),
	-- The home screen: the locker's pages down the left, everything else as
	-- tiles down the right (Season only while one is on).
	lobbyPages = table.freeze({ "Weapons", "Abilities", "Progression", "Store" }),
	lobbyTiles = table.freeze({
		table.freeze({ id = "Rewards", label = "DAILY", icon = "🎁", color = Color3.fromRGB(255, 185, 35) }),
		table.freeze({ id = "Spin", label = "SPIN", icon = "🎡", color = Color3.fromRGB(165, 90, 235) }),
		table.freeze({ id = "Season", label = "SEASON", icon = "🏆", color = Color3.fromRGB(240, 120, 40) }),
		table.freeze({ id = "Players", label = "PLAYERS", icon = "👥", color = Color3.fromRGB(45, 155, 245) }),
		table.freeze({ id = "Leaderboard", label = "TOP", icon = "📊", color = Color3.fromRGB(30, 185, 160) }),
		table.freeze({ id = "Settings", label = "SETTINGS", icon = "⚙️", color = Color3.fromRGB(115, 120, 140) }),
	}),
	gold = Color3.fromRGB(255, 205, 50),

	keys = table.freeze({
		dash = Enum.KeyCode.LeftShift,
		ability = Enum.KeyCode.Q,
		emote = Enum.KeyCode.E,
		-- Hotbar slots 1-4: your weapons.
		slots = table.freeze({ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }),
		fire = Enum.UserInputType.MouseButton1,
		camera = Enum.KeyCode.V,
		-- Frees the mouse from the crosshair (and locks it again).
		unlockMouse = Enum.KeyCode.LeftAlt,
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
		{ "ALT", "Free the mouse" },
		{ "M", "Menu" },
		{ "TAB", "Scoreboard" },
	}),
	controlsSeconds = 8,
	toastSeconds = 4,

	-- Third-person camera distance after switching back from first person.
	thirdPersonDistance = 12,
	-- Over the shoulder: how far the third-person camera sits to the right
	-- of and above the avatar (studs, in the camera's own axes), so the
	-- crosshair has a clear view past the avatar instead of onto its head.
	shoulderOffset = Vector3.new(2.25, 1.5, 0),
	-- The home screen's live view holds each fixed camera point this long.
	spectatorShotSeconds = 8,
}

return table.freeze(UIConfig)
