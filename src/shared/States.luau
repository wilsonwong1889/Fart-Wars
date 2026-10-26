-- The names the server and clients share for player states and round
-- phases. The server is the only one that changes either.
return table.freeze({
	-- A player's state, also on the Player as the "State" attribute.
	Player = table.freeze({
		MENU_SPECTATOR = "MENU_SPECTATOR", -- on the home screen, watching; no avatar, no team slot
		ACTIVE = "ACTIVE", -- on a team with an avatar
		AFK_SPECTATOR = "AFK_SPECTATOR", -- moved off their team for being idle
	}),
	Phase = table.freeze({
		WAITING = "WAITING", -- not enough active players to start
		ACTIVE = "ACTIVE", -- a round is running
		RESULTS = "RESULTS", -- the round is over; intermission before the next
	}),
})
