-- The player's choices from the Settings screen, for this session. The
-- controllers read them; only the Settings screen changes them.
return {
	-- Fewer puffs and clouds (stink clouds that gas you always show).
	reducedEffects = false,
	-- The game's sound effects.
	sound = true,
	-- Contextual tips (the "tips" experiment can start them off).
	tips = true,
	-- Players whose emotes are hidden (the Players screen), by user ID.
	hiddenEmotes = {} :: { [number]: boolean },
	-- The ones the player has changed themselves.
	chosen = {} :: { [string]: boolean },
}
