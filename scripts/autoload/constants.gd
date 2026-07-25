extends Node

# ─── DEBUG ───
const DEBUG: bool = true
const DEBUG_SEED: int = 12345

# ─── ECONOMY ───
const STARTING_COIN: int = 500
const STARTING_MINERS: int = 2
const MAX_UNITS: int = 100
const MAX_QUEUE_SIZE: int = 5

# ─── UNIT COSTS ───
const COSTS: Dictionary = {
	"miner": 50,
	"swordsman": 100,
	"archer": 150,
	"wizard": 250,
}

# ─── TRAIN TIMES (seconds) ───
const TRAIN_TIMES: Dictionary = {
	"miner": 3.0,
	"swordsman": 5.0,
	"archer": 6.0,
	"wizard": 10.0,
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

# ─── BUILDINGS ───
const PLAYER_BUILDING_HP: float = 5000.0
const ENEMY_BUILDING_HP: float = 5000.0

# ─── WALL ───
const WALL_HP: float = 2000.0
const WALL_DAMAGE_PER_MINER: float = 10.0

# ─── UNDERGROUND ───
const LAYERS: int = 7
const LAYER_HEIGHT: int = 100
const TILE_SIZE: int = 32

# Layer coin ranges [min, max]. Sized so each side's layers yield enough for
# the miner upgrades (500 / 1500) before the next tier unlocks.
const LAYER_COIN_RANGES: Dictionary = {
	1: Vector2i(15, 25),
	2: Vector2i(20, 35),
	3: Vector2i(30, 50),
	4: Vector2i(40, 65),
	5: Vector2i(55, 90),
	6: Vector2i(70, 120),
	7: Vector2i(90, 150)
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
const INPUT_TRAIN_MINER: StringName = &"train_miner"
const INPUT_TRAIN_SWORDSMAN: StringName = &"train_swordsman"
const INPUT_TRAIN_ARCHER: StringName = &"train_archer"
const INPUT_TRAIN_WIZARD: StringName = &"train_wizard"
const INPUT_TOGGLE_VIEW: StringName = &"toggle_view"
const INPUT_PAUSE: StringName = &"pause"

const INPUT_CAMERA_UP: StringName = &"camera_up"
const INPUT_CAMERA_DOWN: StringName = &"camera_down"
const INPUT_CAMERA_LEFT: StringName = &"camera_left"
const INPUT_CAMERA_RIGHT: StringName = &"camera_right"
const INPUT_CAMERA_ZOOM_IN: StringName = &"camera_zoom_in"
const INPUT_CAMERA_ZOOM_OUT: StringName = &"camera_zoom_out"
