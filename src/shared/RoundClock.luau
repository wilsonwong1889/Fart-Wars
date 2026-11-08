-- Clients never count down on their own: they work the time left out of the
-- server's snapshot (an absolute end time on the server clock) and
-- workspace:GetServerTimeNow(), so a laggy client is right again as soon as
-- it looks.

-- One award card on the results screen (AwardService works them out).
export type Award = {
	award: string, -- "TopFragger", "ChainMaster", "BarrelBuster" or "TeamPlayer" (UIConfig.awards)
	id: number, -- the winner's UserId, or a bot's (negative) BotId
	name: string, -- their display name (a bot's says it's a bot)
	team: string?,
	bot: boolean,
	value: number, -- eliminations, the biggest chain, barrels or assists
}
export type Snapshot = {
	roundId: number,
	phase: string,
	phaseStartTime: number,
	phaseEndTime: number?,
	scoresByTeam: { [string]: number },
	activePlayersByTeam: { [string]: number },
	-- How many of activePlayersByTeam are bots.
	botsByTeam: { [string]: number }?,
	result: { winner: string?, draw: boolean, scores: { [string]: number }, mode: string? }?,
	-- With the result: the round's awards, in the cards' order (empty when
	-- nobody earned one; nil with FeatureFlags.ROUND_AWARDS off).
	awards: { Award }?,
	mode: string,
	modeName: string?,
	objective: string?, -- "eliminations" or "zone"
	matchMode: string, -- "Rounds" or "Continuous" (FeatureFlags.MATCH_MODE)
	map: string,
	serverTime: number,
}

local RoundClock = {}

-- Seconds left in the snapshot's phase at `now`; nil when the phase has no
-- end (waiting for players).
function RoundClock.remaining(snapshot: Snapshot?, now: number): number?
	if not snapshot or not snapshot.phaseEndTime then
		return nil
	end
	return math.max(0, snapshot.phaseEndTime - now)
end

-- "4:59": whole seconds, rounded up, so the timer reads 0:00 only at the end.
function RoundClock.format(seconds: number?): string
	if not seconds then
		return "--:--"
	end
	local whole = math.max(0, math.ceil(seconds - 1e-6))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

return RoundClock
