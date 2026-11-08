-- Sound asset IDs by name. Empty means silent. These are free Creator
-- Store sound effects, from Roblox's own account (Roblox) or Pro Sound
-- Effects (PSE), chosen and approved 2026-10-26; preview any of them at
-- https://create.roblox.com/store/asset/<id>. Clients play them only at
-- Roblox's volume setting, so muting Roblox mutes the game.
-- After the IDs (in capitals): how loud each one plays and how far sounds
-- in the world carry (Audio).
export type Mix = {
	-- 0 to 1, before Settings.volume.
	volume: number,
	-- The playback speed (and so the pitch), picked at random in this range
	-- each time, so a sound heard over and over doesn't repeat exactly.
	pitch: NumberRange?,
	-- How far it carries when it happens somewhere in the world (a RANGES
	-- kind); sounds without one are only ever played flat.
	range: string?,
}
export type Range = { min: number, max: number }

return table.freeze({
	blaster = "rbxassetid://9114372425", -- the Gas Blaster firing (Farts Airy 8, PSE)
	hit = "rbxassetid://9113263649", -- your shot landed (Balloon Pop 3, PSE)
	inflate = "rbxassetid://9119198150", -- a stage up on your own gas meter (Slide Whistle 6, PSE)
	critical = "rbxassetid://9113438365", -- your gas reached the critical stage (Bike Horn Squeeze 2, PSE)
	explosion = "rbxassetid://9125360550", -- someone exploded (Wet Farty Bursts Low, PSE)
	dash = "rbxassetid://9113150517", -- Fart Dash (Arm Farts Squeezing Repeatedly 4, PSE)
	-- A launch pad's fart: Fart Dash's sound, pitched down and carrying
	-- further, until a whoopee cushion of its own is chosen.
	launch = "rbxassetid://9113150517",
	alpha = "rbxassetid://9114898840", -- BRO IS THE ALPHA FART! (Kazoo Fanfare 9, PSE)
	-- A chain reaction's "CHAIN x2!" (Kazoo Fanfare 9, PSE, the alpha call's
	-- for now: a placeholder until a chain sting of its own is chosen).
	chain = "rbxassetid://9114898840",
	barrel = "rbxassetid://3149249837", -- a gas barrel exploding (Cannon_Explode, Roblox)
	spritzer = "rbxassetid://9113047432", -- the Spritzer firing (Aerosol Spray Can 15, PSE)
	thunderclapper = "rbxassetid://9114372701", -- the Thunderclapper firing (Farts Airy 13, PSE)
	lobber = "rbxassetid://9120734010", -- the Stink Lobber throwing (Whoosh Rising Swish 2, PSE)
	splat = "rbxassetid://12222152", -- a stink bomb landing (splat.wav, Roblox)
	vent = "rbxassetid://9116496050", -- Recovery Burst (Medium Pressure Air Release 7, PSE)
	pulse = "rbxassetid://9125640290", -- Gas Pulse (Magic Poofs Short Breathy Bursts, PSE)
	purchase = "rbxassetid://10066947742", -- a shop purchase (RBLX UI Purchase, Roblox)
	emote = "rbxassetid://9117021487", -- an emote, E (Mouth Vocals Raspberry 1, PSE)
	coins = "rbxassetid://127645268874265", -- you earned coins (CoinTransfer_01, Roblox)
	levelUp = "rbxassetid://12222253", -- you reached a new level (victory.wav, Roblox)
	tick = "rbxasset://sounds/volume_slider.ogg", -- the spin wheel passing a segment (built into every Roblox client)
	-- A teammate's ping (or yours), Z: for now the same built-in click as the
	-- spin's tick, so it works with nothing to approve; swap in a store
	-- sound when one is picked.
	ping = "rbxasset://sounds/volume_slider.ogg",

	-- Each sound's mix. The IDs come from different libraries, so these even
	-- them out. They are set from the kind of sound, not by ear (nobody has
	-- listened to them side by side yet): tune them in Studio. The old flat
	-- level for everything was 0.5. Repeated sounds (shots, dash, splat,
	-- hits, coins) wobble in pitch; signals (warnings, fanfares) don't.
	MIX = table.freeze({
		-- Shots: the fast Spritzer quietest (ten a second), the slow, heavy
		-- Thunderclapper loudest.
		blaster = table.freeze({ volume = 0.5, pitch = NumberRange.new(0.94, 1.06), range = "shot" }),
		spritzer = table.freeze({ volume = 0.3, pitch = NumberRange.new(0.92, 1.08), range = "shot" }),
		thunderclapper = table.freeze({ volume = 0.65, pitch = NumberRange.new(0.95, 1.05), range = "shot" }),
		lobber = table.freeze({ volume = 0.45, pitch = NumberRange.new(0.93, 1.07), range = "shot" }),
		-- A sharp pop heard on every hit: a little under the shots.
		hit = table.freeze({ volume = 0.4, pitch = NumberRange.new(0.95, 1.08) }),
		-- Blasts: the low, wet fart burst needs more level to be heard than
		-- the punchy cannon.
		explosion = table.freeze({ volume = 0.8, pitch = NumberRange.new(0.92, 1.06), range = "blast" }),
		barrel = table.freeze({ volume = 0.6, pitch = NumberRange.new(0.94, 1.04), range = "blast" }),
		splat = table.freeze({ volume = 0.6, pitch = NumberRange.new(0.9, 1.1), range = "area" }),
		vent = table.freeze({ volume = 0.45, pitch = NumberRange.new(0.95, 1.05), range = "area" }),
		pulse = table.freeze({ volume = 0.55, range = "area" }),
		dash = table.freeze({ volume = 0.45, pitch = NumberRange.new(0.9, 1.1), range = "near" }),
		-- Deeper and louder than a dash, heard across a lane.
		launch = table.freeze({ volume = 0.6, pitch = NumberRange.new(0.8, 0.88), range = "area" }),
		emote = table.freeze({ volume = 0.5, pitch = NumberRange.new(0.95, 1.08), range = "near" }),
		-- Your own warnings: piercing on purpose, so not too loud.
		inflate = table.freeze({ volume = 0.4 }),
		critical = table.freeze({ volume = 0.55 }),
		alpha = table.freeze({ volume = 0.6 }),
		-- Each link of your chain plays it a step higher (ChainController),
		-- so no random wobble.
		chain = table.freeze({ volume = 0.55 }),
		-- The screens.
		purchase = table.freeze({ volume = 0.5 }),
		coins = table.freeze({ volume = 0.4, pitch = NumberRange.new(0.97, 1.04) }),
		levelUp = table.freeze({ volume = 0.55 }),
		-- Up to twenty a second as the wheel spins: quiet, and the same
		-- click each time, like a real wheel's pointer.
		tick = table.freeze({ volume = 0.3 }),
		-- A team callout, heard wherever the ping is (flat): a signal, so no
		-- wobble, and louder than the tick it borrows.
		ping = table.freeze({ volume = 0.7 }),
	}),

	-- How far sounds in the world carry, in studs (the map is 480 across):
	-- full volume within min (the third-person camera sits 12 behind you),
	-- fading to silence at max. Roblox hears from the camera.
	RANGES = table.freeze({
		-- Shots and throws: a fight across a good part of the map.
		shot = table.freeze({ min = 12, max = 250 }),
		-- Explosions and barrels: the loudest things, heard nearly map-wide.
		blast = table.freeze({ min = 30, max = 400 }),
		-- A stink bomb landing, Recovery Burst, Gas Pulse, a launch pad: gas
		-- nearby.
		area = table.freeze({ min = 14, max = 220 }),
		-- Fart Dash puffs and emotes: close by.
		near = table.freeze({ min = 12, max = 140 }),
	}),
	-- Inverse near the sound, tapering to nothing at max (no sudden cut).
	ROLL_OFF = Enum.RollOffMode.InverseTapered,
	-- Sounds in the world play from a pool of at most VOICES (in the spirit
	-- of GameConfig.BUDGET), no more than PER_SOUND of one name at once; a
	-- voice counts as free once its sound ends, or after VOICE_SECONDS if
	-- Roblox never says it ended.
	VOICES = 16,
	PER_SOUND = 4,
	VOICE_SECONDS = 4,
})
