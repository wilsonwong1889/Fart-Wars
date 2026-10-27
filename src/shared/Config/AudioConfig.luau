-- Sound asset IDs by name. Empty means silent. These are free Creator
-- Store sound effects, from Roblox's own account (Roblox) or Pro Sound
-- Effects (PSE), chosen and approved 2026-10-26; preview any of them at
-- https://create.roblox.com/store/asset/<id>. Clients play them only at
-- Roblox's volume setting, so muting Roblox mutes the game.
return table.freeze({
	blaster = "rbxassetid://9114372425", -- the Gas Blaster firing (Farts Airy 8, PSE)
	hit = "rbxassetid://9113263649", -- your shot landed (Balloon Pop 3, PSE)
	inflate = "rbxassetid://9119198150", -- a stage up on your own gas meter (Slide Whistle 6, PSE)
	critical = "rbxassetid://9113438365", -- your gas reached the critical stage (Bike Horn Squeeze 2, PSE)
	explosion = "rbxassetid://9125360550", -- someone exploded (Wet Farty Bursts Low, PSE)
	dash = "rbxassetid://9113150517", -- Fart Dash (Arm Farts Squeezing Repeatedly 4, PSE)
	alpha = "rbxassetid://9114898840", -- BRO IS THE ALPHA FART! (Kazoo Fanfare 9, PSE)
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
})
