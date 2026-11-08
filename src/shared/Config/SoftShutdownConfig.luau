-- The soft shutdown (SoftShutdownService on the server, ShutdownController
-- on the client): the names both sides agree on, and the words players see.
return table.freeze({
	-- Workspace's attribute while a closing server moves its players:
	-- "update" (the developer restarted or shut down the servers, or the
	-- reason is unknown) or "closing" (Roblox maintenance, out of memory).
	-- A Player's attribute of the same name, in the reserved server they
	-- pass through: "moving" while they're sent on, "stay" if no teleport
	-- worked and they play there instead.
	ATTRIBUTE = "SoftShutdown",
	-- The teleport data key that marks a player passing through a reserved
	-- server on the way to a fresh one; its value is "update" or "closing".
	TELEPORT_KEY = "FartWarsSoftShutdown",

	text = table.freeze({
		update = "FART WARS JUST GOT AN UPDATE!",
		closing = "THIS SERVER RAN OUT OF GAS!",
		moving = "Moving you to a fresh server...",
		stay = "NO FRESH SERVER FOUND. THIS ONE'S ALL YOURS, KEEP FARTING!",
	}),
	-- How long the "stay" note shows before the screen goes.
	STAY_SECONDS = 4,
})
