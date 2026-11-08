-- A chain reaction's running count. The first explosion (a player, bot or
-- barrel going off) starts a chain; everything its blast sets off is the
-- next link of the same chain, and so on, so every explosion in one
-- reaction shares one count however the chain branches. Blasts carry the
-- chain (ExplosionService), gas from a blast carries it into the meter it
-- fills (GasService, BotService), and a barrel lit by a blast keeps it
-- (BarrelService). Gas from anything else (a shot, a stink bomb, Gas
-- Pulse, a cloud) carries none, so what it sets off starts a new chain.
-- Each explosion's CombatEvent carries its place in the chain (`chain`: 1
-- for the first), so screens show the server's count, never a guess.
local Chain = {}

export type Chain = { count: number }

-- The link one explosion makes: the next in `chain`, or the first of a new
-- one. Returns the chain (pass it on with the blast); its count is this
-- explosion's place in it.
function Chain.link(chain: Chain?): Chain
	local link = chain or { count = 0 }
	link.count += 1
	return link
end

return Chain
