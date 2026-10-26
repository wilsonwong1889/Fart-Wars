-- The player's choices from the Settings screen, for this session. The
-- controllers read them; only the Settings screen changes them.
return {
	-- Fewer puffs and clouds (stink clouds that gas you always show).
	reducedEffects = false,
	-- The game's sound effects, and their volume (0 to 1, on top of
	-- Roblox's own volume).
	sound = true,
	volume = 1,
	-- Low detail: no shadows and fewer effects, for slower PCs.
	lowDetail = false,
	-- Accessibility (Phase 6): less motion and flashing (still spectator
	-- shots, no pulsing outlines, softer bursts); the HUD's size; team
	-- symbols (▲ ●) next to names and over teammates, so teams don't rely
	-- on colour alone.
	reduceMotion = false,
	hudScale = 1,
	teamSymbols = true,
	-- Contextual tips (the "tips" experiment can start them off).
	tips = true,
	-- Players whose emotes are hidden (the Players screen), by user ID.
	hiddenEmotes = {} :: { [number]: boolean },
	-- The ones the player has changed themselves.
	chosen = {} :: { [string]: boolean },
}
