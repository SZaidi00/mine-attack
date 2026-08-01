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

# ─── RESEARCH TREE ───
# Timed techs bought with coin through the ResearchManager (one active
# research per team, 100% refund on cancel). These coexist with the instant
# miner/fighter upgrades above — research only covers new techs.
# Each tech: name, optional unit branch, tree_pos (column = tier, row =
# branch) for the research overlay, optional requires (prerequisite tech id →
# level), and per-level cost/time/effects/desc (desc feeds the hover tooltip).
# Effect keys are read through ResearchManager.get_stat_bonus():
#   building_hp     → flat max-HP added to the team's building (heals the delta)
#   building_regen  → building HP regenerated per second
#   swordsman_armor → flat damage reduction per hit taken
#   swordsman_cdr   → swordsman attack-cooldown reduction (0.2 = 20% faster)
#   archer_range    → flat attack-range bonus
#   archer_cdr      → archer attack-cooldown reduction
#   wizard_aoe_mult → fireball AoE radius multiplier bonus (0.5 = +50%)
#   wizard_damage_mult → wizard damage multiplier bonus (0.25 = +25%)
#   miner_carry     → flat carry-capacity bonus
#   miner_speed     → flat move-speed bonus
const RESEARCH_TECHS: Dictionary = {
	# ── Economy branch ──
	"reinforced_pack": {
		"name": "Reinforced Pack",
		"unit": "miner",
		"tree_pos": Vector2i(0, 0),
		"levels": {
			1: { "cost": 400, "time": 15.0, "miner_carry": 15, "desc": "Miners +15 carry capacity" },
		},
	},
	"swift_boots": {
		"name": "Swift Boots",
		"unit": "miner",
		"tree_pos": Vector2i(1, 0),
		"requires": { "reinforced_pack": 1 },
		"levels": {
			1: { "cost": 500, "time": 20.0, "miner_speed": 15, "desc": "Miners +15 move speed" },
		},
	},
	# ── Recon branch ──
	"ore_sonar": {
		"name": "Ore Sonar",
		"unit": "",
		"tree_pos": Vector2i(0, 1),
		"levels": {
			1: { "cost": 300, "time": 15.0, "desc": "Unlock Scan: reveal buried ore within 8 cells of the mine (60s cooldown)" },
			2: { "cost": 800, "time": 20.0, "desc": "Scan radius 12 cells, cooldown 40s" },
		},
	},
	"deep_scan": {
		"name": "Deep Scan",
		"unit": "",
		"tree_pos": Vector2i(1, 1),
		"requires": { "ore_sonar": 2 },
		"levels": {
			1: { "cost": 1000, "time": 25.0, "desc": "Scan radius 16 cells, cooldown 25s" },
		},
	},
	# ── Defense branch ──
	"fortify": {
		"name": "Fortify",
		"unit": "",
		"tree_pos": Vector2i(0, 2),
		"levels": {
			1: { "cost": 600, "time": 20.0, "building_hp": 2000, "desc": "Building +2000 max HP (heals the difference)" },
			2: { "cost": 1500, "time": 30.0, "building_hp": 3000, "desc": "Building +3000 more max HP" },
		},
	},
	"self_repair": {
		"name": "Self-Repair",
		"unit": "",
		"tree_pos": Vector2i(1, 2),
		"requires": { "fortify": 1 },
		"levels": {
			1: { "cost": 800, "time": 25.0, "building_regen": 5.0, "desc": "Building regenerates 5 HP per second" },
		},
	},
	# ── Swords branch ──
	"bulwark": {
		"name": "Bulwark",
		"unit": "swordsman",
		"tree_pos": Vector2i(0, 3),
		"levels": {
			1: { "cost": 500, "time": 20.0, "swordsman_armor": 2, "desc": "Swordsmen take 2 less damage per hit" },
			2: { "cost": 1000, "time": 25.0, "swordsman_armor": 2, "desc": "Swordsmen take 2 less damage per hit (4 total)" },  # total 4
		},
	},
	"berserk": {
		"name": "Berserk",
		"unit": "swordsman",
		"tree_pos": Vector2i(1, 3),
		"requires": { "bulwark": 2 },
		"levels": {
			1: { "cost": 800, "time": 25.0, "swordsman_cdr": 0.2, "desc": "Swordsmen attack 20% faster" },
		},
	},
	# ── Bows branch ──
	"longbow": {
		"name": "Longbow",
		"unit": "archer",
		"tree_pos": Vector2i(0, 4),
		"levels": {
			1: { "cost": 500, "time": 20.0, "archer_range": 30.0, "desc": "Archers +30 attack range" },
		},
	},
	"rapid_fire": {
		"name": "Rapid Fire",
		"unit": "archer",
		"tree_pos": Vector2i(1, 4),
		"requires": { "longbow": 1 },
		"levels": {
			1: { "cost": 700, "time": 25.0, "archer_cdr": 0.25, "desc": "Archers attack 25% faster" },
		},
	},
	# ── Arcane branch ──
	"inferno": {
		"name": "Inferno",
		"unit": "wizard",
		"tree_pos": Vector2i(0, 5),
		"levels": {
			1: { "cost": 600, "time": 25.0, "wizard_aoe_mult": 0.5, "desc": "Fireballs +50% blast radius" },
		},
	},
	"arcane_might": {
		"name": "Arcane Might",
		"unit": "wizard",
		"tree_pos": Vector2i(1, 5),
		"requires": { "inferno": 1 },
		"levels": {
			1: { "cost": 900, "time": 25.0, "wizard_damage_mult": 0.25, "desc": "Wizards +25% damage" },
		},
	},
}

# Ore Sonar scan ability: reveals buried ore around the team's mine so miners
# path straight to it. Radius is in grid cells, cooldown in seconds. The
# effective sonar level is ore_sonar + deep_scan levels (3 = Deep Scan).
const SONAR_RADIUS: Dictionary = { 1: 8, 2: 12, 3: 16 }
const SONAR_COOLDOWN: Dictionary = { 1: 60.0, 2: 40.0, 3: 25.0 }

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
const ENEMY_ATTACK_WAVE_INTERVAL: float = 18.0

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
const INPUT_PAUSE: StringName = &"pause"

const INPUT_CAMERA_UP: StringName = &"camera_up"
const INPUT_CAMERA_DOWN: StringName = &"camera_down"
const INPUT_CAMERA_LEFT: StringName = &"camera_left"
const INPUT_CAMERA_RIGHT: StringName = &"camera_right"
const INPUT_CAMERA_ZOOM_IN: StringName = &"camera_zoom_in"
const INPUT_CAMERA_ZOOM_OUT: StringName = &"camera_zoom_out"
