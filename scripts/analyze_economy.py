"""Models the economy's pacing: how fast typical players earn coins and XP,
level up and can buy each shop weapon, from the numbers in the Luau configs.

Run: python3 scripts/analyze_economy.py [--ref GIT_REF] [--squad] [--live-ops] [--days N]
  --ref REF   read the configs as they are at a git ref (a branch, a tag, a
              commit) instead of the working tree: before/after comparisons
  --squad     add the squad bonus (a Roblox friend on your team all session)
  --live-ops  count Bean Rain and the season track as if their flags were on
  --days N    how many days to simulate at most (default 400)
Plain Python 3, nothing to install. The configs are parsed, not copied:
change a number in ProgressionConfig, RewardsConfig, WeaponConfig or
GameConfig and run it again. docs/economy.md has the targets and results.

The model (expected values, no luck): each simulated player plays one
session a day of a fixed length on a full 10v10 server, claims the daily
reward at the start of it, spins every free spin as soon as they have one,
and buys each shop weapon the moment it's both unlocked and affordable,
cheapest first. Combat pays per round from the profile's eliminations,
assists, chain/barrel kills and 5-kill streaks; participation, the
ten-minute gifts and the daily track pay as the configs say; weapon mastery
counts eliminations with the newest weapon bought. The profiles below are
assumptions, not config: change them here if real telemetry
(kills per minute, samples.coinsPer10Minutes) says otherwise.
"""
from __future__ import annotations

import argparse
import math
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

root = Path(__file__).resolve().parents[1]
CONFIG = 'src/shared/Config/'


@dataclass
class Profile:
    name: str
    eliminations: float  # a 5-minute round
    assists: float
    chain_kills: float  # of those eliminations, chain or barrel kills (+chainBonus)
    streaks: float  # 5-kill streaks (the alpha bonus) a round
    minutes_per_day: int  # one session a day


PROFILES = [
    Profile('casual', eliminations=1, assists=1, chain_kills=0, streaks=0, minutes_per_day=45),
    Profile('average', eliminations=3, assists=2, chain_kills=0.3, streaks=0.1, minutes_per_day=60),
    Profile('strong', eliminations=6, assists=3, chain_kills=1, streaks=0.4, minutes_per_day=90),
    # The strong player with no life: the stress test for level 50 and for
    # coins piling up.
    Profile('grinder', eliminations=6, assists=3, chain_kills=1, streaks=0.4, minutes_per_day=180),
]
# Profile the targets are judged on, and the session length that counts as
# the "first session".
AVERAGE = 'average'
FIRST_SESSION_MINUTES = 45
# Profiles the "rich with nothing to buy" target is judged on (the others
# are reported).
WAIT_PROFILES = ('average', 'strong', 'grinder')
STEP_SECONDS = 5


# --- A small Luau reader: enough of the language to evaluate config tables
# and simple functions. Anything it doesn't need (colours, enums, functions)
# comes back as an Opaque value.

TOKEN = re.compile(r'''
    (?P<ws>\s+)
  | (?P<lcomment>--\[(?P<ceq>=*)\[.*?\](?P=ceq)\])
  | (?P<comment>--[^\n]*)
  | (?P<lstring>\[(?P<seq>=*)\[.*?\](?P=seq)\])
  | (?P<number>0[xX][0-9a-fA-F_]+|(?:\d[\d_]*(?:\.(?!\.)[\d_]*)?|\.\d[\d_]*)(?:[eE][+-]?\d+)?)
  | (?P<string>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`)
  | (?P<name>[A-Za-z_]\w*)
  | (?P<op>\.\.\.|\.\.|::|->|==|~=|<=|>=|//|[-+*/%^#<>=(){}\[\];:,.|?&])
''', re.S | re.X)

KEYWORDS = {'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'if', 'in',
            'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while'}
BINARY = {'or': (1, 1), 'and': (2, 2), '<': (3, 3), '>': (3, 3), '<=': (3, 3), '>=': (3, 3),
          '~=': (3, 3), '==': (3, 3), '..': (9, 8), '+': (10, 10), '-': (10, 10),
          '*': (11, 11), '/': (11, 11), '//': (11, 11), '%': (11, 11), '^': (14, 13)}
UNARY = 12


class Opaque:
    def __init__(self, text: str):
        self.text = text

    def __repr__(self):
        return f'<{self.text}>'


class Ref(Opaque):
    """A name the reader can't resolve (a global, a local defined elsewhere)."""


def luau_round(x: float) -> float:
    return math.floor(x + 0.5) if x >= 0 else -math.floor(-x + 0.5)


MATH = {
    'math.round': luau_round, 'math.floor': math.floor, 'math.ceil': math.ceil,
    'math.min': min, 'math.max': max, 'math.abs': abs, 'math.sqrt': math.sqrt,
    'math.clamp': lambda x, lo, hi: max(lo, min(hi, x)), 'math.log': math.log, 'math.exp': math.exp,
}


def tokenize(text: str) -> list[tuple[str, str]]:
    tokens, pos = [], 0
    while pos < len(text):
        match = TOKEN.match(text, pos)
        if not match:
            raise SyntaxError(f'unexpected character {text[pos]!r} at {text[pos:pos + 40]!r}')
        kind = match.lastgroup
        if kind in ('ceq', 'seq'):
            kind = 'lcomment' if match.group('lcomment') else 'lstring'
        pos = match.end()
        if kind in ('ws', 'comment', 'lcomment'):
            continue
        value = match.group(kind)
        if kind == 'name' and value in KEYWORDS:
            kind = 'kw'
        tokens.append((kind, value))
    tokens.append(('eof', ''))
    return tokens


def number(text: str) -> float:
    text = text.replace('_', '')
    value = int(text, 16) if text[:2].lower() == '0x' else float(text)
    return int(value) if float(value).is_integer() else value


def unquote(text: str) -> str:
    if text.startswith('['):
        body = text[text.index('[', 1) + 1:text.rindex(']', 0, -1)]
        return body[1:] if body.startswith('\n') else body
    return bytes(text[1:-1], 'utf-8').decode('unicode_escape').encode('latin-1').decode('utf-8')


class Reader:
    def __init__(self, tokens, env=None):
        self.tokens, self.i, self.env = tokens, 0, env or {}

    def peek(self, k=0):
        return self.tokens[min(self.i + k, len(self.tokens) - 1)]

    def at(self, value, k=0):
        kind, text = self.peek(k)
        return text == value and kind in ('op', 'kw')

    def take(self, value=None):
        token = self.peek()
        if value is not None and not self.at(value):
            raise SyntaxError(f'expected {value!r}, got {token[1]!r}')
        self.i += 1
        return token

    def expr(self, limit=0):
        kind, text = self.peek()
        if kind in ('op', 'kw') and text in ('-', 'not', '#'):
            self.take()
            value = self.expr(UNARY)
            if text == '-' and isinstance(value, (int, float)):
                value = -value
            elif text == 'not':
                value = value is None or value is False
            else:
                value = Opaque(text) if not isinstance(value, (int, float)) else value
        else:
            value = self.simple()
        while True:
            kind, op = self.peek()
            if kind not in ('op', 'kw') or op not in BINARY or BINARY[op][0] <= limit:
                return value
            self.take()
            value = self.binary(op, value, self.expr(BINARY[op][1]))

    @staticmethod
    def binary(op, a, b):
        numbers = isinstance(a, (int, float)) and isinstance(b, (int, float))
        if op in ('+', '-', '*', '/', '//', '%', '^') and numbers:
            return {'+': lambda: a + b, '-': lambda: a - b, '*': lambda: a * b, '/': lambda: a / b,
                    '//': lambda: math.floor(a / b), '%': lambda: a - math.floor(a / b) * b,
                    '^': lambda: float(a) ** b}[op]()
        if op == '..' and isinstance(a, (str, int, float)) and isinstance(b, (str, int, float)):
            return f'{a}{b}'
        if op in ('<', '>', '<=', '>=') and numbers:
            return {'<': a < b, '>': a > b, '<=': a <= b, '>=': a >= b}[op]
        if op in ('==', '~='):
            return (a == b) == (op == '==')
        if op == 'and':
            return b if a not in (None, False) else a
        if op == 'or':
            return a if a not in (None, False) else b
        return Opaque(f'{a} {op} {b}')

    def simple(self):
        kind, text = self.peek()
        if kind == 'number':
            self.take()
            value = number(text)
        elif kind in ('string', 'lstring'):
            self.take()
            value = unquote(text)
        elif kind == 'kw' and text in ('nil', 'true', 'false'):
            self.take()
            value = {'nil': None, 'true': True, 'false': False}[text]
        elif self.at('...'):
            self.take()
            value = Opaque('...')
        elif self.at('{'):
            value = self.table()
        elif self.at('function'):
            value = self.skip_function()
        elif self.at('if'):
            value = self.if_expr()
        else:
            value = self.suffixed()
        while self.at('::'):
            self.take()
            self.skip_type()
        return value

    def if_expr(self):
        self.take('if')
        cond = self.expr()
        self.take('then')
        yes = self.expr()
        if self.at('elseif'):
            self.tokens[self.i] = ('kw', 'if')
            no = self.if_expr()
        else:
            self.take('else')
            no = self.expr()
        if isinstance(cond, Opaque):
            return Opaque('if')
        return yes if cond not in (None, False) else no

    def suffixed(self):
        kind, text = self.peek()
        if self.at('('):
            self.take()
            value = self.expr()
            self.take(')')
        elif kind == 'name':
            self.take()
            value = self.env[text] if text in self.env else Ref(text)
        else:
            raise SyntaxError(f'unexpected {text!r}')
        while True:
            if self.at('.'):
                self.take()
                name = self.take()[1]
                if isinstance(value, dict):
                    value = value.get(name)
                elif isinstance(value, Ref):
                    value = Ref(f'{value.text}.{name}')
                else:
                    value = Opaque(f'{value}.{name}')
            elif self.at('['):
                self.take()
                key = self.expr()
                self.take(']')
                value = value.get(key) if isinstance(value, dict) else Opaque('index')
            elif self.at(':'):
                self.take()
                self.take()
                self.call_args()
                value = Opaque('method call')
            elif self.at('(') or self.at('{') or self.peek()[0] in ('string', 'lstring'):
                value = self.call(value, self.call_args())
            else:
                return value

    def call_args(self):
        if self.at('{'):
            return [self.table()]
        if self.peek()[0] in ('string', 'lstring'):
            return [unquote(self.take()[1])]
        self.take('(')
        args = []
        while not self.at(')'):
            args.append(self.expr())
            if not self.at(','):
                break
            self.take(',')
        self.take(')')
        return args

    @staticmethod
    def call(fn, args):
        name = fn.text if isinstance(fn, Ref) else None
        if name == 'table.freeze' and args:
            return args[0]
        if name in MATH and args and all(isinstance(a, (int, float)) for a in args):
            return MATH[name](*args)
        return Opaque(f'{name or "?"}(...)')

    def table(self):
        self.take('{')
        result, n = {}, 0
        while not self.at('}'):
            if self.at('['):
                self.take()
                key = self.expr()
                self.take(']')
                self.take('=')
                result[int(key) if isinstance(key, float) and key.is_integer() else key] = self.expr()
            elif self.peek()[0] == 'name' and self.at('=', 1):
                key = self.take()[1]
                self.take('=')
                result[key] = self.expr()
            else:
                n += 1
                result[n] = self.expr()
            if self.at(',') or self.at(';'):
                self.take()
            else:
                break
        self.take('}')
        return result

    def skip_type(self):
        depth = 0
        while True:
            kind, text = self.peek()
            if kind == 'eof':
                return
            if kind == 'op' and text in ('(', '{', '[', '<'):
                depth += 1
            elif kind == 'op' and text in (')', '}', ']', '>'):
                if depth == 0:
                    return
                depth -= 1
            elif depth == 0 and (kind == 'kw' and text not in ('nil',) or text in (',', ';', '=')):
                return
            self.take()

    def skip_function(self):
        depth = 0
        while True:
            kind, text = self.take()
            if kind == 'eof':
                raise SyntaxError('function without end')
            if kind == 'kw' and text in ('function', 'if', 'do', 'repeat'):
                depth += 1
            elif kind == 'kw' and text in ('end', 'until'):
                depth -= 1
                if depth == 0:
                    return Opaque('function')


def as_list(table) -> list:
    if not isinstance(table, dict):
        return []
    return [table[i] for i in range(1, len(table) + 1) if i in table]


def read_source(rel: str, ref: str | None) -> str:
    if ref:
        result = subprocess.run(['git', 'show', f'{ref}:{rel}'], cwd=root, capture_output=True, text=True)
        if result.returncode != 0:
            sys.exit(f"Can't read {rel} at {ref}: {result.stderr.strip()}")
        return result.stdout
    return (root / rel).read_text(encoding='utf-8')


def assigned(text: str, target: str, file: str):
    """The value assigned to `target` (`local X = ...` or `X = ...`)."""
    match = re.search(rf'(?m)^\s*(?:local\s+)?{re.escape(target)}\s*(?::[^=\n]*)?=(?!=)', text)
    if not match:
        sys.exit(f"{file}: couldn't find `{target} = ...`; update scripts/analyze_economy.py")
    return Reader(tokenize(text[match.end():])).expr()


def returned(text: str, file: str):
    matches = list(re.finditer(r'(?m)^return\s', text))
    if not matches:
        sys.exit(f'{file}: no top-level return')
    return Reader(tokenize(text[matches[-1].end():])).expr()


def function_of(text: str, name: str, file: str):
    """A one-parameter function whose body is `return <expression>`, as Python."""
    match = re.search(rf'function\s+{re.escape(name)}\s*\(\s*(\w+)[^)]*\)[^\n]*\n\s*return\s', text)
    if not match:
        sys.exit(f"{file}: couldn't read `function {name}` (expected a single `return <expression>`)")
    param, tokens = match.group(1), tokenize(text[match.end():])

    def evaluate(value):
        result = Reader(tokens, {param: value}).expr()
        if not isinstance(result, (int, float)):
            sys.exit(f'{file}: {name}({value}) did not evaluate to a number: {result}')
        return result
    return evaluate


# --- The configs.

@dataclass
class Gun:
    id: str
    name: str
    price: int
    level: int


@dataclass
class Economy:
    grants: dict
    participation: list
    max_level: int
    xp_to_next: list  # index = level
    unlocks: dict
    cap_coins: int
    cap_repeat_xp: int
    cap_repeat_coins: int
    mastery: list
    daily: list
    duplicate_coins: int
    gift_minutes: float
    gifts_per_day: int
    max_spins: int
    starting_spins: int
    spin: list
    squad: dict
    guns: list
    cycle_seconds: float
    round_seconds: float
    players: int
    flags: dict
    beans_per_round: float = 0
    bean_coins: float = 0
    season: dict = field(default_factory=dict)

    @property
    def spin_coins(self) -> float:
        total = sum(p['weight'] for p in self.spin)
        return sum(p.get('coins', 0) * p['weight'] for p in self.spin) / total

    @property
    def spin_xp(self) -> float:
        total = sum(p['weight'] for p in self.spin)
        return sum(p.get('xp', 0) * p['weight'] for p in self.spin) / total


def load(ref: str | None, live_ops: bool) -> Economy:
    files = {}

    def source(name):
        files[name] = read_source(CONFIG + name + '.luau', ref)
        return files[name]

    prog_text = source('ProgressionConfig')
    prog = assigned(prog_text, 'ProgressionConfig', 'ProgressionConfig')
    xp_fn = function_of(prog_text, 'ProgressionConfig.xpToNext', 'ProgressionConfig')
    rewards = assigned(source('RewardsConfig'), 'RewardsConfig', 'RewardsConfig')
    weapon_text = source('WeaponConfig')
    weapons = assigned(weapon_text, 'weapons', 'WeaponConfig')
    order = as_list(assigned(weapon_text, 'order', 'WeaponConfig'))
    game = assigned(source('GameConfig'), 'GameConfig', 'GameConfig')
    flags = returned(source('FeatureFlags'), 'FeatureFlags')
    events = returned(source('EventConfig'), 'EventConfig')
    season_text = source('SeasonConfig')

    max_level = prog['MAX_LEVEL']
    guns = [Gun(id, weapons[id]['displayName'], weapons[id]['price'], weapons[id]['level'])
            for id in order if weapons[id]['price'] > 0]
    guns.sort(key=lambda g: (g.level, g.price))
    continuous = flags.get('MATCH_MODE') == 'Continuous'
    economy = Economy(
        grants=prog['grants'],
        participation=as_list(prog['participation']),
        max_level=max_level,
        xp_to_next=[0] + [xp_fn(level) for level in range(1, max_level)],
        unlocks=prog['unlocks'],
        cap_coins=prog['CAP_REWARD']['coins'],
        cap_repeat_xp=prog['CAP_REPEAT_XP'],
        cap_repeat_coins=prog['CAP_REPEAT_COINS'],
        mastery=as_list(prog['mastery']),
        daily=as_list(rewards['daily']),
        duplicate_coins=rewards['DUPLICATE_COSMETIC_COINS'],
        gift_minutes=rewards['GIFT_ACTIVE_MINUTES'],
        gifts_per_day=rewards['GIFTS_PER_DAY'],
        max_spins=rewards['MAX_SPINS'],
        starting_spins=rewards['STARTING_SPINS'],
        spin=as_list(rewards['spin']),
        squad={k: rewards[k] for k in ('SQUAD_MINUTES', 'SQUAD_COINS', 'SQUAD_XP', 'SQUAD_PER_DAY')},
        guns=guns,
        cycle_seconds=game['ROUND_SECONDS'] + (0 if continuous else game['INTERMISSION_SECONDS']),
        round_seconds=game['ROUND_SECONDS'],
        players=2 * game['MAX_TEAM_SIZE'],
        flags=flags,
    )
    if not flags.get('PROGRESSION', True):
        sys.exit('FeatureFlags.PROGRESSION is off: nothing pays, nothing to model.')
    if not flags.get('REWARDS', True):
        economy.daily, economy.spin, economy.starting_spins, economy.gifts_per_day = [], [], 0, 0
    if flags.get('EVENTS') or live_ops:
        rain = events['BEAN_RAIN']
        per_player = rain['BEANS_PER_SECOND'] * rain['DURATION_SECONDS'] / economy.players
        economy.beans_per_round = events['CHANCE_PER_ROUND'] * min(rain['MAX_PER_PLAYER'], per_player)
        economy.bean_coins = rain['COINS']
    if flags.get('SEASONS') or live_ops:
        tier = re.search(r'tiers\[n\]\s*=\s*\{\s*coins\s*=\s*(\d+)\s*\+\s*(\d+)\s*\*\s*n', season_text)
        count = re.search(r'for\s+n\s*=\s*1\s*,\s*(\d+)\s+do', season_text)
        if not tier or not count:
            sys.exit("SeasonConfig: couldn't read the tiers' coins; update scripts/analyze_economy.py")
        economy.season = {
            'share': assigned(season_text, 'SeasonConfig.XP_SHARE', 'SeasonConfig'),
            'per_tier': assigned(season_text, 'SeasonConfig.XP_PER_TIER', 'SeasonConfig'),
            'per_challenge': assigned(season_text, 'SeasonConfig.XP_PER_CHALLENGE', 'SeasonConfig'),
            'challenges': assigned(season_text, 'SeasonConfig.CHALLENGES_PER_WEEK', 'SeasonConfig'),
            'tier_coins': [int(tier.group(1)) + int(tier.group(2)) * n for n in range(1, int(count.group(1)) + 1)],
        }
    return economy


# --- The simulation.

@dataclass
class Result:
    profile: Profile
    level_at: dict = field(default_factory=dict)  # level -> (play seconds, day)
    bought_at: dict = field(default_factory=dict)  # gun id -> (play seconds, day)
    affordable_at: dict = field(default_factory=dict)  # gun id -> (play seconds, day)
    coins_after: dict = field(default_factory=dict)  # gun id -> balance after buying
    days: list = field(default_factory=list)  # per day: (coins, xp, {reason: coins})
    combat_coins_hour: float = 0
    combat_xp_hour: float = 0
    rounds_hour: float = 0


def simulate(eco: Economy, profile: Profile, days: int, squad: bool) -> Result:
    result = Result(profile)
    g = eco.grants
    per_round_coins = (profile.eliminations * g['elimination']['coins'] + profile.assists * g['assist']['coins']
                       + profile.chain_kills * g['chainBonus']['coins'] + profile.streaks * g['alpha']['coins']
                       + eco.beans_per_round * eco.bean_coins)
    per_round_xp = (profile.eliminations * g['elimination']['xp'] + profile.assists * g['assist']['xp']
                    + profile.chain_kills * g['chainBonus']['xp'] + profile.streaks * g['alpha']['xp'])
    result.rounds_hour = 3600 / eco.cycle_seconds
    result.combat_coins_hour = per_round_coins * result.rounds_hour
    result.combat_xp_hour = per_round_xp * result.rounds_hour
    coin_rate, xp_rate = per_round_coins / eco.cycle_seconds, per_round_xp / eco.cycle_seconds
    elim_rate = profile.eliminations / eco.cycle_seconds

    state = {'coins': 0.0, 'earned': 0.0, 'level': 1, 'xp': 0.0, 'spins': eco.starting_spins,
             'season_xp': 0.0, 'tiers': 0, 'repeats': 0}
    owned, mastery, claimed = [], {'starter': 0.0}, set()
    lime_owned, track, sparkle = 0.0, 0, False
    clock = 0.0
    day_log = {}
    result.level_at[1] = (0.0, 1)

    def pay(coins, xp, reason):
        state['coins'] += coins
        state['earned'] += coins
        day_log['coins'] += coins
        day_log['xp'] += xp
        day_log['by'][reason] = day_log['by'].get(reason, 0) + coins
        if xp:
            gain_xp(xp)

    def gain_xp(xp):
        state['xp'] += xp
        if eco.season:
            state['season_xp'] += xp * eco.season['share']
            season_tiers()
        while True:
            need = eco.xp_to_next[state['level']] if state['level'] < eco.max_level else eco.cap_repeat_xp
            if state['xp'] < need:
                return
            state['xp'] -= need
            if state['level'] < eco.max_level:
                state['level'] += 1
                result.level_at[state['level']] = (clock, day)
                if state['level'] == eco.max_level:
                    pay(eco.cap_coins, 0, 'level cap')
            else:
                state['repeats'] += 1
                pay(eco.cap_repeat_coins, 0, 'level cap')

    def season_tiers():
        tiers = eco.season['tier_coins']
        while state['tiers'] < len(tiers) and state['season_xp'] >= (state['tiers'] + 1) * eco.season['per_tier']:
            state['tiers'] += 1
            pay(tiers[state['tiers'] - 1], 0, 'season')

    def spin_all():
        nonlocal lime_owned
        while state['spins'] > 0 and eco.spin:
            state['spins'] -= 1
            total = sum(p['weight'] for p in eco.spin)
            coins = eco.spin_coins
            for prize in eco.spin:
                if prize.get('cosmetic'):
                    w = prize['weight'] / total
                    coins += w * lime_owned * eco.duplicate_coins
                    lime_owned += (1 - lime_owned) * w
            pay(coins, eco.spin_xp, 'spins')

    cumulative, total = {}, 0
    for gun in eco.guns:
        total += gun.price
        cumulative[gun.id] = total

    def shop():
        for gun in eco.guns:
            if gun.id not in result.affordable_at and state['earned'] >= cumulative[gun.id]:
                result.affordable_at[gun.id] = (clock, day)
        for gun in eco.guns:
            if gun.id in owned:
                continue
            if state['level'] < gun.level or state['coins'] < gun.price:
                return  # cheapest first: saving for this one
            state['coins'] -= gun.price
            owned.append(gun.id)
            mastery[gun.id] = 0.0
            result.bought_at[gun.id] = (clock, day)
            result.coins_after[gun.id] = state['coins']

    for day in range(1, days + 1):
        day_log = {'coins': 0.0, 'xp': 0.0, 'by': {}}
        if eco.daily:
            reward = eco.daily[track % len(eco.daily)]
            track += 1
            coins = reward.get('coins', 0)
            if reward.get('cosmetic'):
                coins += eco.duplicate_coins if sparkle else 0
                sparkle = True
            state['spins'] = min(eco.max_spins, state['spins'] + reward.get('spins', 0))
            pay(coins, 0, 'daily')
        if eco.season and day % 7 == 1:
            state['season_xp'] += eco.season['challenges'] * eco.season['per_challenge']
            season_tiers()
        spin_all()
        shop()
        session, gifts, squads = 0.0, 0, 0
        reached = set()
        while session < profile.minutes_per_day * 60:
            session += STEP_SECONDS
            clock += STEP_SECONDS
            pay(coin_rate * STEP_SECONDS, xp_rate * STEP_SECONDS, 'combat')
            weapon = owned[-1] if owned else 'starter'
            mastery[weapon] += elim_rate * STEP_SECONDS
            for milestone in eco.mastery:
                key = (weapon, milestone['eliminations'])
                if key not in claimed and mastery[weapon] >= milestone['eliminations']:
                    claimed.add(key)
                    pay(milestone['coins'], 0, 'mastery')
            for step in eco.participation:
                if step['minutes'] not in reached and session >= step['minutes'] * 60:
                    reached.add(step['minutes'])
                    pay(step['coins'], step['xp'], 'participation')
            if eco.spin and gifts < eco.gifts_per_day and session >= (gifts + 1) * eco.gift_minutes * 60:
                gifts += 1
                state['spins'] = min(eco.max_spins, state['spins'] + 1)
                spin_all()
            if squad and squads < eco.squad['SQUAD_PER_DAY'] and session >= (squads + 1) * eco.squad['SQUAD_MINUTES'] * 60:
                squads += 1
                pay(eco.squad['SQUAD_COINS'], eco.squad['SQUAD_XP'], 'squad')
            shop()
        result.days.append((day_log['coins'], day_log['xp'], day_log['by']))
        if state['level'] >= eco.max_level and len(owned) == len(eco.guns) and day >= 7:
            break
    return result


# --- The report.

def when(entry) -> str:
    if not entry:
        return 'never'
    seconds, day = entry
    minutes = round(seconds / 60)
    played = f'{minutes // 60}:{minutes % 60:02d}' if minutes < 600 else f'{minutes / 60:.0f} h'
    return f'{played} (d{day})'


def table(title: str, columns: list[str], rows: list[list[str]]):
    widths = [max(len(str(r[i])) for r in rows + [[title] + columns]) for i in range(len(columns) + 1)]
    line = '  '.join(str(c).ljust(widths[0]) if i == 0 else str(c).rjust(widths[i])
                     for i, c in enumerate([title] + columns))
    print(line)
    print('-' * len(line))
    for row in rows:
        print('  '.join(str(c).ljust(widths[0]) if i == 0 else str(c).rjust(widths[i]) for i, c in enumerate(row)))
    print()


def week(result: Result, index: int) -> float:
    return sum(d[index] for d in result.days[:7])


def report(eco: Economy, results: list[Result], args) -> bool:
    names = [r.profile.name for r in results]
    source = f'git ref {args.ref}' if args.ref else 'the working tree'
    extras = [x for x, on in (('squad bonus', args.squad), ('Bean Rain', eco.beans_per_round > 0),
                              ('season track', bool(eco.season))) if on]
    print(f'Fart Wars economy model: configs from {source}'
          + (f', with {", ".join(extras)}' if extras else '') + '\n')
    print(f'Round {eco.round_seconds:.0f} s + intermission = one round every {eco.cycle_seconds:.0f} s '
          f'({3600 / eco.cycle_seconds:.1f} an hour), {eco.players} players. '
          f'A free spin is worth {eco.spin_coins:.1f} coins and {eco.spin_xp:.1f} XP on average.')
    total_xp = sum(eco.xp_to_next[1:])
    print(f'XP to level 50: {total_xp:,.0f}. Guns: '
          + ', '.join(f'{g.name} {g.price:,} at level {g.level}' for g in eco.guns) + '.\n')

    table('profile (a round)', names, [
        ['eliminations / assists', *[f'{r.profile.eliminations:g} / {r.profile.assists:g}' for r in results]],
        ['chain kills / streaks', *[f'{r.profile.chain_kills:g} / {r.profile.streaks:g}' for r in results]],
        ['play a day', *[f'{r.profile.minutes_per_day} min' for r in results]],
    ])

    def first_session(r, index):
        return r.days[0][index] / r.profile.minutes_per_day

    table('income', names, [
        ['combat coins / 10 min', *[f'{r.combat_coins_hour / 6:,.0f}' for r in results]],
        ['combat XP / 10 min', *[f'{r.combat_xp_hour / 6:,.0f}' for r in results]],
        ['combat coins / hour', *[f'{r.combat_coins_hour:,.0f}' for r in results]],
        ['combat XP / hour', *[f'{r.combat_xp_hour:,.0f}' for r in results]],
        ['day 1, all: coins / 10 min', *[f'{first_session(r, 0) * 10:,.0f}' for r in results]],
        ['day 1, all: XP / 10 min', *[f'{first_session(r, 1) * 10:,.0f}' for r in results]],
        ['week 1, all: coins / hour', *[f'{week(r, 0) / (7 * r.profile.minutes_per_day) * 60:,.0f}' for r in results]],
        ['week 1, all: XP / hour', *[f'{week(r, 1) / (7 * r.profile.minutes_per_day) * 60:,.0f}' for r in results]],
        ['week 1 coins (XP)', *[f'{week(r, 0):,.0f} ({week(r, 1):,.0f})' for r in results]],
    ])

    reasons = ['combat', 'spins', 'daily', 'participation', 'mastery', 'squad', 'season', 'level cap']
    rows = []
    for reason in reasons:
        shares = [sum(d[2].get(reason, 0) for d in r.days[:7]) / max(1, week(r, 0)) for r in results]
        if any(shares):
            rows.append([f'  {reason}', *[f'{s:.0%}' for s in shares]])
    table('week 1 coins from', names, rows)

    milestones = [5, 10, 15, 20, 25, 30, 40, 50]
    table('level (XP from 1): play h:mm (day)', names, [
        [f'{lv} ({sum(eco.xp_to_next[1:lv]):,})' + (f' {eco.unlocks[lv]["text"]}' if lv in eco.unlocks else ''),
         *[when(r.level_at.get(lv)) for r in results]] for lv in milestones])

    rows = []
    for gun in eco.guns:
        rows.append([f'{gun.name} ({gun.price:,}, level {gun.level})', *['' for _ in results]])
        rows.append(['  unlocked', *[when(r.level_at.get(gun.level)) for r in results]])
        rows.append(['  coins for it', *[when(r.affordable_at.get(gun.id)) for r in results]])
        rows.append(['  bought (both)', *[when(r.bought_at.get(gun.id)) for r in results]])
        rows.append(['  waited with the coins', *[f'{idle(r, gun) / 3600:.1f} h' for r in results]])
        rows.append(['  coins left after', *[f'{r.coins_after.get(gun.id, 0):,.0f}' for r in results]])
    table('guns', names, rows)

    def first(r):
        bought = sorted((t, gid) for gid, t in r.bought_at.items())
        if not bought:
            return 'none'
        gun = next(g for g in eco.guns if g.id == bought[0][1])
        return f'{gun.name} {when(bought[0][0])}'
    table('first purchase', names, [['', *[first(r) for r in results]]])

    return judge(eco, results)


def idle(r: Result, gun: Gun) -> float:
    """Play seconds with the coins for `gun` (on top of the ones before it) but not its level."""
    if gun.id not in r.affordable_at or gun.level not in r.level_at:
        return 0
    return max(0.0, r.level_at[gun.level][0] - r.affordable_at[gun.id][0])


def judge(eco: Economy, results: list[Result]) -> bool:
    by = {r.profile.name: r for r in results}
    avg = by[AVERAGE]
    checks = []
    first_gun = eco.guns[0]
    entry = avg.bought_at.get(first_gun.id)
    checks.append((f'{first_gun.name} in the first session ({AVERAGE}, {FIRST_SESSION_MINUTES} min)',
                   bool(entry) and entry[1] == 1 and entry[0] <= FIRST_SESSION_MINUTES * 60, when(entry)))
    last = max((avg.bought_at.get(g.id, (math.inf, math.inf)) for g in eco.guns), key=lambda e: e[0])
    checks.append((f'all {len(eco.guns)} guns within a week at {avg.profile.minutes_per_day} min a day ({AVERAGE})',
                   last[1] <= 7, when(last) if last[1] != math.inf else 'never'))
    cap = avg.level_at.get(eco.max_level)
    checks.append((f'level {eco.max_level} takes several weeks ({AVERAGE}: day 21 or later)',
                   not cap or cap[1] >= 21, when(cap)))
    earliest = min((r.level_at.get(eco.max_level, (math.inf, math.inf)) for r in results), key=lambda e: e[1])
    checks.append((f'nobody reaches level {eco.max_level} in week 1 (even the grinder)',
                   earliest[1] > 7, when(earliest) if earliest[1] != math.inf else 'never'))
    def longest_wait(rs):
        wait, name, gun = max(((idle(r, g), r.profile.name, g.name) for r in rs for g in eco.guns), key=lambda x: x[0])
        length = f'{wait / 3600:.1f} h' if wait >= 3600 else f'{wait / 60:.0f} min'
        return wait, f'{length} ({name}, {gun})' if wait > 0 else 'none'
    worst = longest_wait([r for r in results if r.profile.name in WAIT_PROFILES])
    checks.append((f'never 1 h+ of play holding the next gun\'s coins, waiting for its level ({", ".join(WAIT_PROFILES)})',
                   worst[0] <= 3600, worst[1]))
    print('targets')
    print('-------')
    for text, ok, detail in checks:
        print(f'{"PASS" if ok else "MISS"}  {text}: {detail}')
    rest = longest_wait([r for r in results if r.profile.name not in WAIT_PROFILES])
    print(f'note  the longest such wait for the others: {rest[1]}; their coins are mostly spins and daily '
          'rewards, their XP almost all combat')
    after = []
    for r in results:
        last_day = max((r.bought_at.get(g.id, (0, math.inf))[1] for g in eco.guns))
        if last_day < len(r.days):
            after.append(f'{r.profile.name} {r.days[last_day][0]:,.0f}')
    print('note  after the last gun nothing in the beta costs coins; coins banked the day after: ' + ', '.join(after))
    return all(ok for _, ok, _ in checks)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--ref', help='read the configs at this git ref instead of the working tree')
    parser.add_argument('--squad', action='store_true', help='add the squad bonus (a friend on your team)')
    parser.add_argument('--live-ops', action='store_true', help='count Bean Rain and the season track')
    parser.add_argument('--days', type=int, default=400, help='days to simulate at most')
    args = parser.parse_args()
    eco = load(args.ref, args.live_ops)
    results = [simulate(eco, p, args.days, args.squad) for p in PROFILES]
    report(eco, results, args)


if __name__ == '__main__':
    main()
