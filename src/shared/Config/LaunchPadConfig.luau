-- Launch pads (FeatureFlags.LAUNCH_PADS): giant whoopee cushions on the
-- map (MapKit.launchPad) that fart whoever steps on one forward and up,
-- along the pad's arc to its landing spot (LaunchPads). A player's client
-- launches its own avatar, as with Fart Dash, and tells the server
-- (LaunchPad); the server checks it and allows for the flight in its
-- movement checks (LaunchPadService). Bots are launched by the server.
-- Values are proposals to tune.
return table.freeze({
	-- One launch per player (or bot) this often, from any pad. A new life
	-- starts ready.
	COOLDOWN_SECONDS = 2,
	-- A pad's trigger: an avatar whose root is over the cushion and no
	-- more than this far above its top (a standing avatar's root is about
	-- 3 up; jumping onto a pad catches you on the way down).
	TRIGGER_HEIGHT = 7,
	-- The server takes a launch from an avatar up to SLACK_STUDS outside
	-- the cushion, or that close to where the arc would have carried it in
	-- LAG_SECONDS (the request arrives after the client launched, and the
	-- server sees the avatar a moment late): generous, since a refused
	-- launch would leave its flight unallowed for. Just after a Fart Dash,
	-- a dash's length further across the ground (LaunchPadService).
	SLACK_STUDS = 12,
	LAG_SECONDS = 0.6,
	-- The movement checks allow a flight's length to anything they measure
	-- from GRACE_SECONDS before it starts to GRACE_SECONDS after it ends
	-- (network jitter).
	GRACE_SECONDS = 1,
	-- A flight ends when the avatar lands (but not in its first
	-- MIN_FLIGHT_SECONDS, while it may still be over the pad) or
	-- OVERRUN_SECONDS after it should have; then it runs on at no more
	-- than walking speed (GameConfig.WALK_SPEED).
	MIN_FLIGHT_SECONDS = 0.2,
	OVERRUN_SECONDS = 0.4,
	-- A bot is launched by a pad it walks onto heading roughly the pad's
	-- way (its walking direction's dot with the pad's at least this), so
	-- one backing off to its spawn isn't thrown back into the fight.
	BOT_ALIGNMENT = 0.5,
	-- The look: a pink whoopee cushion on a glowing gas-green rim, with
	-- neon chevrons pointing the way it throws you.
	CUSHION_COLOR = Color3.fromRGB(255, 96, 170),
	RIM_COLOR = Color3.fromRGB(150, 230, 60),
	ARROW_COLOR = Color3.fromRGB(222, 255, 72),
	-- The launch: a puff of gas under you and a green cloud left on the pad.
	PUFF_COLOR = Color3.fromRGB(150, 230, 60),
	CLOUD_COLOR = Color3.fromRGB(190, 240, 120),
	CLOUD_SECONDS = 1.6,
	-- At most this many puff and cloud parts at once on a client (in the
	-- spirit of GameConfig.BUDGET); past that the oldest goes.
	MAX_EFFECT_PARTS = 30,
})
