extends Node

# ─── DEBUG ───
const DEBUG: bool = false
const DEBUG_SEED: int = 12345

# ─── ECONOMY ───
const STARTING_COIN: int = 500
const STARTING_MINERS: int = 2
const MAX_UNITS: int = 100
# The training queue is uncapped — limited only by coin and population.

# ─── UNIT COSTS ───
const COSTS: Dictionary = {
	"miner": 50,
	"swordsman": 100,
	"archer": 150,
	"wizard": 250,
	"dragon": 400,
}

# ─── TRAIN TIMES (seconds) ───
const TRAIN_TIMES: Dictionary = {
	"miner": 3.0,
	"swordsman": 5.0,
	"archer": 6.0,
	"wizard": 10.0,
	"dragon": 14.0,
}

# ─── UNIT STATS ───
# Fighter stats are authoritative in scripts/resources/units/*.tres.
# (The old FIGHTER_STATS dictionary was removed in Phase 2 to avoid a second
# source of truth.)

const MINER_STATS: Dictionary = {
	1: { "hp": 50, "speed": 60, "mine_dps": 10, "carry": 20, "max_layer": 2 },
	2: { "hp": 75, "speed": 70, "mine_dps": 15, "carry": 30, "max_layer": 4 },
	3: { "hp": 100, "speed": 80, "mine_dps": 25, "carry": 40, "max_layer": 7 }
}

# Authoritative mining swing stats per upgrade level. DPS = damage * swings.
const MINING_STATS: Dictionary = {
	1: { "damage": 5, "swings": 2.0 },   # 10 dps
	2: { "damage": 5, "swings": 3.0 },   # 15 dps
	3: { "damage": 5, "swings": 5.0 },   # 25 dps
}

# ─── MINER UPGRADES ───
const MINER_UPGRADE_COSTS: Dictionary = {
	2: 500,   # L1 → L2
	3: 1500   # L2 → L3
}

# ─── FIGHTER UPGRADES ───
# Team-wide per-type levels (like miner upgrades). Level 1 rows mirror the
# .tres base stats; levels 2–3 are authoritative overrides applied on top
# (roughly +30% HP and +25% damage per level).
const FIGHTER_UPGRADE_COSTS: Dictionary = {
	"swordsman": { 2: 400, 3: 1200 },
	"archer": { 2: 500, 3: 1500 },
	"wizard": { 2: 600, 3: 1800 },
	"dragon": { 2: 800, 3: 2400 },
}
const FIGHTER_UPGRADES: Dictionary = {
	"swordsman": {
		1: { "hp": 150, "damage": 7.5 },
		2: { "hp": 195, "damage": 9.5 },
		3: { "hp": 245, "damage": 12.0 },
	},
	"archer": {
		1: { "hp": 80, "damage": 12.0 },
		2: { "hp": 105, "damage": 15.0 },
		3: { "hp": 130, "damage": 19.0 },
	},
	"wizard": {
		1: { "hp": 60, "damage": 37.5 },
		2: { "hp": 80, "damage": 47.0 },
		3: { "hp": 100, "damage": 58.0 },
	},
	"dragon": {
		1: { "hp": 120, "damage": 45.0 },
		2: { "hp": 155, "damage": 56.0 },
		3: { "hp": 200, "damage": 70.0 },
	},
}

# ─── BUILDINGS ───
const PLAYER_BUILDING_HP: float = 5000.0
const ENEMY_BUILDING_HP: float = 5000.0

# ─── FOG OF WAR (Revamp Phase 1) ───
# Vision radii in grid cells. Miners and dragons only light the layer they are
# on (a miner's lamp does not shine up the shaft); other fighters and
# buildings light both. A tile left behind by vision stays "remembered" for
# FOG_MEMORY_DURATION seconds of game time, then fades back to full fog.
const VISION_MINER_SURFACE: int = 4
const VISION_MINER_UNDERGROUND: int = 3
const VISION_SWORDSMAN: int = 8
const VISION_ARCHER: int = 12
const VISION_WIZARD: int = 10
const VISION_DRAGON: int = 14
const VISION_BUILDING: int = 10
const FOG_MEMORY_DURATION: float = 10.0
const FOG_COLOR: Color = Color("#05070a")
# Alpha of the fog overlay on remembered tiles (revealed tiles draw none).
const FOG_MEMORY_ALPHA: float = 0.7

# ─── LANTERNS (Revamp Phase 1) ───
# Surface lanterns: static vision structures, built on the own half's surface
# row and upgraded in place T1 → T2 → T3.
const LANTERN_T1_COST: int = 200
const LANTERN_T2_COST: int = 600
const LANTERN_T3_COST: int = 1000
const LANTERN_T1_VISION: int = 8
const LANTERN_T2_VISION: int = 14
const LANTERN_T3_VISION: int = 22
const LANTERN_HP: int = 500
const LANTERN_BUILD_TIME: float = 5.0
const LANTERN_MAX_COUNT: int = 3
const LANTERN_MIN_DISTANCE: int = 3  # cells between surface lanterns
# Underground lanterns: placed in dug-out tunnel cells; they permanently
# reveal buried ore in their radius for the owning team (like an Ore Sonar
# scan that never expires).
const UNDERGROUND_LANTERN_COST: int = 100
const UNDERGROUND_LANTERN_VISION: int = 6
const UNDERGROUND_LANTERN_HP: int = 200
const UNDERGROUND_LANTERN_BUILD_TIME: float = 3.0
const UNDERGROUND_LANTERN_MAX_COUNT: int = 5
const UNDERGROUND_LANTERN_MIN_DISTANCE: int = 2  # cells between underground lanterns
# Destroyed lanterns drop this share of their build cost as a coin pickup.
const LANTERN_SALVAGE_RATIO: float = 0.5

# ─── PLACEABLE STRUCTURES (Revamp Phase 3) ───
# Sentry towers: static surface defenses that auto-attack the highest-priority
# enemy in range (fighters > miners > buildings) and double as vision sources.
# Factions override cost/HP/damage/cooldown/build speed (see FactionData).
const TOWER_COST: int = 300
const TOWER_HP: int = 800
const TOWER_RANGE_CELLS: int = 8
const TOWER_DAMAGE: int = 12
const TOWER_COOLDOWN: float = 1.2
const TOWER_BUILD_TIME: float = 8.0
const TOWER_MAX_COUNT: int = 2
const TOWER_VISION: int = 10  # surface only
const TOWER_MIN_BUILDING_DISTANCE: int = 2  # cells from any building/mine entry
# Placeable walls: single-cell surface barriers that block movement (A* solid
# once built) and projectiles. Destroyed by fighter attacks. Factions override
# cost and max count (Industrial: 30g, 3).
# (PLACED_ prefix: WALL_HP/WALL_* already name the central wall's constants.)
const PLACED_WALL_COST: int = 50
const PLACED_WALL_HP: int = 400
const PLACED_WALL_BUILD_TIME: float = 3.0
const PLACED_WALL_MAX_COUNT: int = 2
# Destroyed towers/walls drop this share of their build cost (as lanterns do).
const STRUCTURE_SALVAGE_RATIO: float = 0.5

# ─── DYNAMIC TERRAIN & EVENTS (Revamp Phase 4) ───
# Lava rising: every LAVA_MIN/MAX_INTERVAL seconds of match time (random,
# uniform) a warning sounds, then the bottom 1–2 layers flood with lava.
# Units caught in the zone die instantly (no cargo drop), underground
# lanterns are destroyed, and every non-wall cell becomes indestructible
# LAVA. After LAVA_DURATION the lava recedes into diggable MAGMA_ROCK
# (0 gold), with MAGMA_ORE_CHANCE per cell of high-value FRESH_ORE instead.
const LAVA_MIN_INTERVAL: float = 90.0
const LAVA_MAX_INTERVAL: float = 120.0
const LAVA_WARNING_TIME: float = 5.0
const LAVA_DURATION: float = 20.0
const LAVA_LAYERS_MIN: int = 1
const LAVA_LAYERS_MAX: int = 2
const MAGMA_ROCK_HP: int = 150
const MAGMA_ORE_CHANCE: float = 0.4
const MAGMA_ORE_MIN: int = 100
const MAGMA_ORE_MAX: int = 200
# While lava is up, units standing in a lava cell are re-checked this often
# (in-flight paths can carry stragglers into the zone after the rise).
const LAVA_SWEEP_INTERVAL: float = 0.5
# Cave-ins: sudden 3×3 collapses underground. Diggable tiles become
# indestructible SOLID_ROCK for CAVEIN_ROCK_DURATION seconds, units in the
# area take CAVEIN_DAMAGE and are pushed to the nearest walkable cell, and
# underground lanterns in the area are destroyed.
const CAVEIN_MIN_INTERVAL: float = 45.0
const CAVEIN_MAX_INTERVAL: float = 75.0
const CAVEIN_AREA_SIZE: int = 3  # 3x3
const CAVEIN_DAMAGE: int = 50
const CAVEIN_ROCK_DURATION: float = 10.0
# Ore depletion: once an ore tile has yielded ORE_DEPLETION_RATIO of its
# gold, per-swing trickle drops to ORE_DEPLETED_YIELD_MULT of normal (the
# destruction payout still pays the remainder, so totals stay exact).
const ORE_DEPLETION_RATIO: float = 0.8
const ORE_DEPLETED_YIELD_MULT: float = 0.1
# Vein respawn: if the total ore count falls below ORE_RESPAWN_THRESHOLD,
# up to ORE_RESPAWN_COUNT fresh veins appear in layers 3+ every interval.
const ORE_RESPAWN_INTERVAL: float = 60.0
const ORE_RESPAWN_THRESHOLD: int = 40
const ORE_RESPAWN_COUNT: int = 8
const ORE_RESPAWN_MIN_LAYER: int = 3

# ─── WEATHER (Revamp Phase 5) ───
# Snowstorms: every SNOWSTORM_MIN/MAX_INTERVAL seconds of match time (random,
# uniform, independent of the lava timer) a warning sounds, then a storm
# sweeps the surface for SNOWSTORM_DURATION seconds. While it rages: all unit
# and lantern vision radii are halved, surface units move at
# SNOWSTORM_SPEED_MULT, and any surface unit outside a friendly lantern's
# radius takes SNOWSTORM_DAMAGE_PER_SEC (buildings are immune).
const SNOWSTORM_MIN_INTERVAL: float = 60.0
const SNOWSTORM_MAX_INTERVAL: float = 90.0
const SNOWSTORM_DURATION: float = 15.0
const SNOWSTORM_WARNING_TIME: float = 5.0
const SNOWSTORM_VISION_MULT: float = 0.5
const SNOWSTORM_SPEED_MULT: float = 0.9
const SNOWSTORM_DAMAGE_PER_SEC: float = 2.0

# ─── RESEARCH TREE (Revamp Phase 6) ───
# Mutually-exclusive branch techs: timed research bought with coin through the
# ResearchManager (one active research per team, 100% refund on cancel).
# Completing a tech permanently locks its "locks" alternative for the team
# (branch_locked signal); a one-time respec (BRANCH_RESPEC_COST) resets the
# team's choices. These coexist with the instant miner/fighter upgrades above.
# Each tech: name, optional unit branch, tree_pos (column = tier, row =
# branch) for the research overlay, "locks" (alternative tech id locked on
# completion), optional requires (ALL prerequisite tech ids → level) or
# requires_any (AT LEAST ONE listed tech id at level ≥ 1), and per-level
# cost/time/effects/desc (desc feeds the hover tooltip).
# Effect keys are read through ResearchManager.get_stat_bonus():
#   miner_carry        → flat carry-capacity bonus
#   miner_hp           → flat max-HP bonus for miners
#   archer_range       → flat attack-range bonus
#   fighter_cdr        → attack-cooldown reduction for all fighters (0.2 = 20% faster)
#   swordsman_speed    → swordsman move-speed multiplier bonus (0.1 = +10%)
#   wizard_damage_mult → wizard damage multiplier bonus (0.4 = +40%)
#   unit_hp_mult       → max-HP multiplier bonus for all units (0.15 = +15%)
#   building_hp        → flat max-HP added to the team's building (heals the delta)
# Techs without effect keys (deep_delve, surface_war, ore_sonar,
# siege_master, guerrilla) are read through ResearchManager.has_branch() by
# the systems that implement their hard-coded effects.
const RESEARCH_TECHS: Dictionary = {
	# ── Tier 1: the branch root ──
	"deep_delve": {
		"name": "Deep Delve",
		"unit": "miner",
		"tree_pos": Vector2i(0, 0),
		"locks": "surface_war",
		"levels": {
			1: { "cost": 400, "time": 20.0, "desc": "Miners reach layers 5-7 immediately; miners +10% underground move speed" },
		},
	},
	"surface_war": {
		"name": "Surface War",
		"unit": "fighter",
		"tree_pos": Vector2i(0, 1),
		"locks": "deep_delve",
		"levels": {
			1: { "cost": 400, "time": 20.0, "desc": "Fighters +15% speed & damage on the surface; miners capped at layer 4; towers +20% range" },
		},
	},
	# ── Tier 2: Deep Delve side ──
	"ore_sonar": {
		"name": "Ore Sonar",
		"unit": "",
		"tree_pos": Vector2i(1, 0),
		"requires": { "deep_delve": 1 },
		"locks": "reinforced_pack",
		"levels": {
			1: { "cost": 500, "time": 20.0, "desc": "Unlock Scan: reveal buried ore (incl. Fresh Ore) within 12 cells of the mine (40s cooldown)" },
		},
	},
	"reinforced_pack": {
		"name": "Reinforced Pack",
		"unit": "miner",
		"tree_pos": Vector2i(1, 1),
		"requires": { "deep_delve": 1 },
		"locks": "ore_sonar",
		"levels": {
			1: { "cost": 600, "time": 25.0, "miner_carry": 20, "miner_hp": 10, "desc": "Miners +20 carry capacity, +10 HP, immune to cave-in push" },
		},
	},
	# ── Tier 2: Surface War side ──
	"longbow": {
		"name": "Longbow",
		"unit": "archer",
		"tree_pos": Vector2i(1, 2),
		"requires": { "surface_war": 1 },
		"locks": "rapid_fire",
		"levels": {
			1: { "cost": 600, "time": 25.0, "archer_range": 25, "desc": "Archers +25 attack range and can blind-fire into the fog" },
		},
	},
	"rapid_fire": {
		"name": "Rapid Fire",
		"unit": "fighter",
		"tree_pos": Vector2i(1, 3),
		"requires": { "surface_war": 1 },
		"locks": "longbow",
		"levels": {
			1: { "cost": 700, "time": 25.0, "fighter_cdr": 0.2, "swordsman_speed": 0.1, "desc": "All fighters attack 20% faster; swordsmen +10% move speed" },
		},
	},
	# ── Tier 3: Deep Delve side ──
	"crystal_forge": {
		"name": "Crystal Forge",
		"unit": "wizard",
		"tree_pos": Vector2i(2, 0),
		"requires_any": ["ore_sonar", "reinforced_pack"],
		"locks": "earth_shield",
		"levels": {
			1: { "cost": 1000, "time": 30.0, "wizard_damage_mult": 0.4, "desc": "Wizards +40% damage; fireballs leave burning ground (5 DPS for 3s)" },
		},
	},
	"earth_shield": {
		"name": "Earth Shield",
		"unit": "",
		"tree_pos": Vector2i(2, 1),
		"requires_any": ["ore_sonar", "reinforced_pack"],
		"locks": "crystal_forge",
		"levels": {
			1: { "cost": 900, "time": 30.0, "unit_hp_mult": 0.15, "building_hp": 1000, "desc": "All units +15% max HP; building +1000 max HP (heals the difference)" },
		},
	},
	# ── Tier 3: Surface War side ──
	"siege_master": {
		"name": "Siege Master",
		"unit": "swordsman",
		"tree_pos": Vector2i(2, 2),
		"requires_any": ["longbow", "rapid_fire"],
		"locks": "guerrilla",
		"levels": {
			1: { "cost": 1000, "time": 30.0, "desc": "Swordsmen +30% damage vs buildings; towers cost 50% less" },
		},
	},
	"guerrilla": {
		"name": "Guerrilla",
		"unit": "",
		"tree_pos": Vector2i(2, 3),
		"requires_any": ["longbow", "rapid_fire"],
		"locks": "siege_master",
		"levels": {
			1: { "cost": 800, "time": 30.0, "desc": "Units +20% speed with no ally within 6 cells; miners can place traps (50 damage)" },
		},
	},
}

# Ore Sonar scan ability: reveals buried ore around the team's mine so miners
# path straight to it. Radius is in grid cells, cooldown in seconds. The
# effective sonar level equals the ore_sonar research level.
const SONAR_RADIUS: Dictionary = { 1: 12 }
const SONAR_COOLDOWN: Dictionary = { 1: 40.0 }

# ─── RESEARCH BRANCH EFFECTS (Revamp Phase 6) ───
# Hard-coded branch effects read through ResearchManager.has_branch().
# One-time respec cost: resets the team's researched branches and locks.
const BRANCH_RESPEC_COST: int = 500
# deep_delve: underground miner speed multiplier.
const DEEP_DELVE_UG_SPEED_MULT: float = 1.1
# surface_war: surface fighter speed/damage multipliers and tower range.
const SURFACE_WAR_SPEED_MULT: float = 1.15
const SURFACE_WAR_DMG_MULT: float = 1.15
const SURFACE_WAR_TOWER_RANGE_MULT: float = 1.2
# crystal_forge: burning ground left by fireballs.
const BURNING_GROUND_DPS: float = 5.0
const BURNING_GROUND_DURATION: float = 3.0
# guerrilla: miner-placed traps.
const TRAP_COST: int = 50
const TRAP_DAMAGE: float = 50.0
const TRAP_MAX_COUNT: int = 5
# guerrilla: speed multiplier while no ally is within this radius (cells).
const GUERRILLA_SPEED_MULT: float = 1.2
const GUERRILLA_ALLY_RADIUS_CELLS: int = 6
# siege_master: swordsman damage vs buildings and tower cost discount.
const SIEGE_MASTER_BUILDING_DMG_MULT: float = 1.3
const SIEGE_MASTER_TOWER_COST_MULT: float = 0.5

# ─── OUT-OF-COMBAT REGEN ───
# Units that avoid damage for this long slowly recover HP. Slow on purpose:
# it rewards retreating wounded units without erasing combat outcomes.
const UNIT_REGEN_DELAY: float = 5.0
const UNIT_REGEN_PER_SEC: float = 2.0

# ─── WALL ───
const WALL_HP: float = 2000.0
const WALL_DAMAGE_PER_MINER: float = 10.0

# ─── UNDERGROUND ───
const LAYERS: int = 7
const LAYER_HEIGHT: int = 100
const TILE_SIZE: int = 32

# Layer coin ranges [min, max]. Every swing on an ore tile extracts a share of
# its gold (destruction pays the remainder), so these are per-tile totals.
# Sized so each side's layers comfortably fund the miner upgrades (500 / 1500)
# before the next tier unlocks.
const LAYER_COIN_RANGES: Dictionary = {
	1: Vector2i(25, 40),
	2: Vector2i(30, 50),
	3: Vector2i(45, 70),
	4: Vector2i(55, 90),
	5: Vector2i(75, 120),
	6: Vector2i(95, 160),
	7: Vector2i(120, 200)
}

# Layer tile HP
const LAYER_TILE_HP: Dictionary = {
	1: 50, 2: 50,
	3: 75, 4: 75,
	5: 100, 6: 100, 7: 100
}

# ─── MAP / GRID ───
const GRID_X_MIN: int = -40
const GRID_X_MAX: int = 40
const GRID_Y_MIN: int = 0
const GRID_Y_MAX: int = 21

# Rows per underground layer in GridWorld (3 rows => 7 layers).
const ROWS_PER_LAYER: int = 3

# ─── ENEMY AI ───
const ENEMY_DECISION_INTERVAL: float = 2.0
const ENEMY_AGGRESSION_INTERVAL: float = 10.0
# The effective wave tick is this base interval scaled by the difficulty's
# "wave" attack-tempo multiplier (see GameManager.DIFFICULTY_MODIFIERS).
const ENEMY_ATTACK_WAVE_INTERVAL: float = 18.0
# Smart-behavior tuning (gated by the difficulty "smarts" tier — see
# GameManager.DIFFICULTY_MODIFIERS).
const ENEMY_HARASS_INTERVAL: float = 20.0  # seconds between miner-raid attempts
const ENEMY_WOUNDED_HP_RATIO: float = 0.3  # fighters below this HP fraction retreat to heal
const ENEMY_COUNTERATTACK_DROP: int = 3  # player fighter losses per sample that open a counter-attack window
# Predictive retreat: also retreat when predicted time-to-death beats the trip
# home by less than this slack (seconds).
const ENEMY_RETREAT_PREDICT_BUFFER: float = 3.0
# Bait-and-switch (tier 2+): seconds between bait attempts.
const ENEMY_BAIT_INTERVAL: float = 45.0
# Economic lookahead (tier 2+): a timing attack fires when the enemy's income
# rate beats ours by this ratio and we have at least this many free fighters.
const ENEMY_ECON_PRESSURE_RATIO: float = 1.2
const ENEMY_TIMING_ATTACK_ARMY: int = 4
# Combat predictor: seconds of abstract focus-fire exchange simulated per call.
const ENEMY_COMBAT_SIM_DURATION: float = 2.0
# AI-team miners re-scan for diggable cells this often while waiting at an
# exhausted mine (player miners keep the shared 5s retry in unit.gd).
const ENEMY_MINER_RESCAN_INTERVAL: float = 2.0

# ─── UNIT MICRO ───
# Ranged fighters kite (step back while firing) when an enemy melee threat
# closes inside this fraction of their attack range.
const UNIT_KITE_RANGE_FRACTION: float = 0.6
# Defend leash: a fighter holding its post (stop/garrison orders) may only
# chase auto-acquired targets this far from the standing point before
# dropping the target and walking home. Explicit player orders are never
# leashed.
const UNIT_DEFEND_LEASH_RANGE: float = 400.0
# While the team's own building is under attack the leash pulls in tight:
# defenders must finish the fight at the base instead of being lured away
# one chase at a time.
const UNIT_DEFEND_LEASH_UNDER_ATTACK: float = 150.0
# How long after the last hit the building counts as "under attack".
const BUILDING_UNDER_ATTACK_SEC: float = 4.0

# ─── AI DIFFICULTY ───
# The DIFFICULTY_MODIFIERS table lives in game_manager.gd (keyed by
# GameManager.Difficulty; Constants loads before GameManager so it cannot
# reference the enum here).

# ─── INPUT ACTIONS ───
const INPUT_SELECT: StringName = &"lmb"
const INPUT_COMMAND: StringName = &"rmb"
const INPUT_SELECT_ALL: StringName = &"select_all"
const INPUT_SELECT_MINERS: StringName = &"select_miners"
const INPUT_SELECT_FIGHTERS: StringName = &"select_fighters"
const INPUT_SELECT_DRAGONS: StringName = &"select_dragons"
const INPUT_TRAIN_MINER: StringName = &"train_miner"
const INPUT_TRAIN_SWORDSMAN: StringName = &"train_swordsman"
const INPUT_TRAIN_ARCHER: StringName = &"train_archer"
const INPUT_TRAIN_WIZARD: StringName = &"train_wizard"
const INPUT_TRAIN_DRAGON: StringName = &"train_dragon"
const INPUT_TOGGLE_VIEW: StringName = &"toggle_view"
const INPUT_TOGGLE_RESEARCH: StringName = &"toggle_research"
const INPUT_KILL_UNITS: StringName = &"kill_units"
const INPUT_PAUSE: StringName = &"pause"

const INPUT_CAMERA_UP: StringName = &"camera_up"
const INPUT_CAMERA_DOWN: StringName = &"camera_down"
const INPUT_CAMERA_LEFT: StringName = &"camera_left"
const INPUT_CAMERA_RIGHT: StringName = &"camera_right"
const INPUT_CAMERA_ZOOM_IN: StringName = &"camera_zoom_in"
const INPUT_CAMERA_ZOOM_OUT: StringName = &"camera_zoom_out"
