-- Sound asset IDs by name. Empty means silent: upload the game's own
-- sounds (fart sounds included) and paste their rbxassetid:// IDs here.
-- Clients play them only at Roblox's volume setting, so muting Roblox
-- mutes the game.
return table.freeze({
	blaster = "", -- the Gas Blaster firing
	hit = "", -- your shot landed
	inflate = "", -- a stage up on your own gas meter
	critical = "", -- your gas reached the critical stage
	explosion = "", -- someone exploded
	dash = "", -- Fart Dash
	alpha = "", -- BRO IS THE ALPHA FART!
	barrel = "", -- a gas barrel exploding
	spritzer = "", -- the Spritzer firing
	thunderclapper = "", -- the Thunderclapper firing
	lobber = "", -- the Stink Lobber throwing
	splat = "", -- a stink bomb landing
	vent = "", -- Recovery Burst
	pulse = "", -- Gas Pulse
	purchase = "", -- a shop purchase
	emote = "", -- an emote (E)
	coins = "", -- you earned coins
	levelUp = "", -- you reached a new level
})
