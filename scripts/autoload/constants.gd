extends Node

# ─── DEBUG ───
const DEBUG: bool = false
const DEBUG_SEED: int = 12345

# ─── ECONOMY ───
const STARTING_COIN: int = 500
const STARTING_MINERS: int = 2
const MAX_UNITS: int = 100
# The training queue is uncapped — limited only by coin and population.
# Welfare trickle (EconomyManager): a team with zero living miners and not
# enough coin to buy one gains WELFARE_COIN every WELFARE_INTERVAL seconds of
# game time, so a wiped economy can always re-staff eventually. The AI's amount
# is scaled by the difficulty coin multiplier (rates, never rules).
const WELFARE_COIN: int = 10
const WELFARE_INTERVAL: float = 30.0
# Baseline income: both teams trickle a little coin every interval from match
# start, so the early game never stalls waiting on the first deposit trips.
# The AI's share scales with the difficulty coin multiplier (rates, never
# rules). Welfare (above) remains the anti-death-spiral rescue for wiped
# economies.
const BASELINE_INCOME_COIN: int = 5
const BASELINE_INCOME_INTERVAL: float = 10.0

# ─── UNIT COSTS ───
const COSTS: Dictionary = {
	"miner": 50,
	"swordsman": 100,
	"archer": 150,
	"wizard": 250,
	"dragon": 400,
	"pigeon": 100,
}

# ─── TRAIN TIMES (seconds) ───
const TRAIN_TIMES: Dictionary = {
	"miner": 3.0,
	"swordsman": 5.0,
	"archer": 6.0,
	"wizard": 10.0,
	"dragon": 14.0,
	"pigeon": 8.0,
}

# ─── UNIT STATS ───
# Fighter stats are authoritative in scripts/resources/units/*.tres.
# (The old FIGHTER_STATS dictionary was removed in Phase 2 to avoid a second
# source of truth.)

const MINER_STATS: Dictionary = {
	1: { "hp": 50, "speed": 60, "mine_dps": 12, "carry": 20, "max_layer": 2 },
	2: { "hp": 75, "speed": 70, "mine_dps": 24, "carry": 30, "max_layer": 4 },
	3: { "hp": 100, "speed": 80, "mine_dps": 50, "carry": 40, "max_layer": 7 }
}

# Authoritative mining swing stats per upgrade level. DPS = damage * swings.
const MINING_STATS: Dictionary = {
	1: { "damage": 6, "swings": 2.0 },   # 12 dps
	2: { "damage": 8, "swings": 3.0 },   # 24 dps
	3: { "damage": 10, "swings": 5.0 },  # 50 dps
}

# How far an idle miner scans for dropped coin pickups (killed-miner cargo).
const MINER_COIN_SCAN_RANGE_CELLS: int = 8

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
# Vision radii in grid cells. Miners only light the layer they are on (a
# miner's lamp does not shine up the shaft); surface fighters and buildings
# light only the surface, while underground lanterns light only the
# underground. A tile left behind by vision stays "remembered" for
# FOG_MEMORY_DURATION seconds of game time, then fades back to full fog.
const VISION_MINER_SURFACE: int = 4
const VISION_MINER_UNDERGROUND: int = 3
const VISION_SWORDSMAN: int = 8
const VISION_ARCHER: int = 12
const VISION_WIZARD: int = 10
const VISION_DRAGON: int = 14
const VISION_PIGEON: int = 2
const VISION_BUILDING: int = 6
const FOG_MEMORY_DURATION: float = 10.0
const FOG_COLOR: Color = Color("#05070a")
# Alpha of the fog overlay on remembered tiles (revealed tiles draw none).
const FOG_MEMORY_ALPHA: float = 0.7

# ─── LANTERNS (Revamp Phase 1) ───
# Surface lanterns: static vision structures, built on the own half's surface
# row and upgraded in place T1 → T2 → T3. Radii are deliberately smaller than
# the half-map width so a single lantern (even T3) cannot light the entire
# side; players must place several lanterns and/or upgrade them to maintain
# coverage. Max count is raised so a lighting network is affordable.
const LANTERN_T1_COST: int = 200
const LANTERN_T2_COST: int = 600
const LANTERN_T3_COST: int = 1000
const LANTERN_T1_VISION: int = 4
const LANTERN_T2_VISION: int = 7
const LANTERN_T3_VISION: int = 10
const LANTERN_HP: int = 500
const LANTERN_BUILD_TIME: float = 5.0
const LANTERN_MAX_COUNT: int = 5
const LANTERN_MIN_DISTANCE: int = 3  # cells between surface lanterns
# Underground lanterns: placed in dug-out tunnel cells; they permanently
# reveal buried ore in their radius for the owning team (like an Ore Sonar
# scan that never expires).
const UNDERGROUND_LANTERN_COST: int = 100
const UNDERGROUND_LANTERN_VISION: int = 5
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
# Player-initiated demolition of own towers/walls/lanterns/traps refunds this
# share of the structure's total spent cost directly as coin (no pickup).
const STRUCTURE_DEMOLISH_REFUND_RATIO: float = 0.25

# ─── PIGEON SCOUT ───
# Flying scouts trained from sentry towers. They provide vision but are fragile
# and only vulnerable to anti-air attackers (archers, wizards, dragons, towers).
const PIGEON_MAX_COUNT: int = 2
const PIGEON_LINGER_ENEMY_TIME: float = 12.0
const PIGEON_LINGER_HOME_TIME: float = 5.0

# ─── DYNAMIC TERRAIN & EVENTS (Revamp Phase 4) ───
# Lava rising: every LAVA_MIN/MAX_INTERVAL seconds of match time (random,
# uniform) a warning sounds, then a random span of bottom layers floods.
# The flood top is picked between LAVA_TOP_LAYER_MIN and MAX (layer 1 is the
# shallowest; layer 7 is the deepest). Before LAVA_TOP_LAYER_UNLOCK_TIME the
# minimum top is LAVA_TOP_LAYER_EARLY_MIN, so the most severe floods (top
# layer 3) cannot happen in the first 7 minutes. Units caught in the zone
# die instantly (no cargo drop), underground lanterns are destroyed, and
# every non-wall cell becomes indestructible LAVA. After LAVA_DURATION the
# lava recedes into diggable MAGMA_ROCK (0 gold), with MAGMA_ORE_CHANCE per
# cell of high-value FRESH_ORE instead — on layers 5, 6, and 7.
const LAVA_MIN_INTERVAL: float = 70.0
const LAVA_MAX_INTERVAL: float = 125.0
const LAVA_WARNING_TIME: float = 5.0
# Creeping tide: lava rises from the bottom to the wave peak over this many
# seconds, then recedes back down. There is no fixed "active" hold at the top;
# the tide flows in and out continuously.
const LAVA_CREEP_UP_TIME: float = 8.0
const LAVA_CREEP_DOWN_TIME: float = 8.0
const LAVA_TOP_LAYER_MIN: int = 3
const LAVA_TOP_LAYER_MAX: int = 7
const LAVA_TOP_LAYER_EARLY_MIN: int = 5
const LAVA_TOP_LAYER_UNLOCK_TIME: float = 420.0
const MAGMA_ROCK_HP: int = 150
const MAGMA_ORE_CHANCE: float = 0.4
const MAGMA_ORE_MIN: int = 100
const MAGMA_ORE_MAX: int = 200
# While the tide is creeping up, units standing in a newly flooded lava cell are
# re-checked this often (in-flight paths can carry stragglers into the zone).
const LAVA_SWEEP_INTERVAL: float = 0.5
# Non-linear lava wave (Revamp Phase 4+): each rise follows a cosine profile so
# the flood height varies by column. Amplitude is in rows (not layers); cycles
# are full waves across the underground width. A secondary, faster wave is added
# so the surface looks uneven rather than a single clean curve.
const LAVA_WAVE_AMPLITUDE_MIN: int = 1    # rows
const LAVA_WAVE_AMPLITUDE_MAX: int = 3    # rows
const LAVA_WAVE_CYCLES_MIN: float = 1.5
const LAVA_WAVE_CYCLES_MAX: float = 3.0
const LAVA_WAVE_SECONDARY_AMP: float = 0.6   # rows
const LAVA_WAVE_SECONDARY_CYCLES: float = 5.0
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
# and lantern vision radii are halved, surface units move at the difficulty
# scaled snowstorm speed multiplier (see GameManager.DIFFICULTY_MODIFIERS),
# and any surface unit outside a friendly lantern's radius takes
# SNOWSTORM_DAMAGE_PER_SEC (buildings are immune). The Arctic Training
# research raises the storm movement multiplier for the owning team.
# Both the scheduling interval and the exposure damage are further scaled by
# difficulty (more frequent and deadlier storms on higher difficulties).
# Intervals overlap with lava/volcano so no single event always comes first.
const SNOWSTORM_MIN_INTERVAL: float = 50.0
const SNOWSTORM_MAX_INTERVAL: float = 105.0
const SNOWSTORM_DURATION: float = 15.0
const SNOWSTORM_WARNING_TIME: float = 5.0
const SNOWSTORM_VISION_MULT: float = 0.25
const SNOWSTORM_DAMAGE_PER_SEC: float = 2.0

# ─── VOLCANO ───
# Volcano eruptions: independent random surface event. A warning sounds, then
# meteors rain down across the whole surface for VOLCANO_DURATION seconds.
# Each meteor deals impact damage in a small radius and leaves burning ground
# that damages units and structures over time. If a snowstorm is active, meteors
# still fall but do not leave fire; any existing volcano fires are extinguished
# when the snowstorm begins. HQ buildings and mine entries are protected.
# Intervals overlap with snowstorm/lava so the three events can arrive in any
# order after the shuffled first-occurrence deck is dealt.
const VOLCANO_MIN_INTERVAL: float = 90.0
const VOLCANO_MAX_INTERVAL: float = 145.0
const VOLCANO_WARNING_TIME: float = 7.0
const VOLCANO_DURATION: float = 18.0
const VOLCANO_METEOR_INTERVAL_BASE: float = 0.9
const VOLCANO_METEOR_IMPACT_DAMAGE_BASE: int = 35
const VOLCANO_METEOR_RADIUS_CELLS: float = 1.5
const VOLCANO_BURN_DPS_BASE: float = 6.0
const VOLCANO_BURN_DURATION_BASE: float = 9.0
const VOLCANO_BURN_RADIUS_CELLS: float = 1.0

# ─── RESEARCH TREE (Revamp Phase 6+) ───
# Timed research bought through ResearchManager (one active research per team,
# up to RESEARCH_QUEUE_MAX queued behind it, 100% refund on cancel). The tree
# has multiple independent discipline roots; within each discipline, tier-2
# techs can both be researched, but tier-3 capstones are mutually exclusive.
# Cross-path capstones at tier 4 require tier-3 techs from two disciplines.
# Completing a tech with a "locks" field permanently locks that alternative for
# the team (branch_locked signal); a one-time respec (BRANCH_RESPEC_COST) resets
# the team's choices. These coexist with the instant miner/fighter upgrades.
# Each tech: name, optional unit branch, tree_pos (column = tier, row =
# branch) for the research overlay, "locks" (alternative tech id locked on
# completion), optional requires (ALL prerequisite tech ids → level) or
# requires_any (AT LEAST ONE listed tech id at level ≥ 1), and per-level
# cost/time/effects/desc (desc feeds the hover tooltip).
# Effect keys are read through ResearchManager.get_stat_bonus():
#   miner_carry              → flat carry-capacity bonus
#   miner_hp                 → flat max-HP bonus for miners
#   archer_range             → flat attack-range bonus
#   fighter_cdr              → attack-cooldown reduction for all fighters (0.2 = 20% faster)
#   swordsman_speed          → swordsman move-speed multiplier bonus (0.1 = +10%)
#   wizard_damage_mult       → wizard damage multiplier bonus (0.4 = +40%)
#   unit_hp_mult             → max-HP multiplier bonus for all units (0.15 = +15%)
#   building_hp              → flat max-HP added to the team's building (heals the delta)
#   building_hp_mult         → max-HP multiplier bonus for the team's building
#   structure_hp_mult        → max-HP multiplier bonus for towers/walls
#   structure_build_time_mult→ build-time reduction multiplier for structures
#   wall_hp_mult             → wall max-HP multiplier bonus
#   wall_cost_mult           → wall cost reduction multiplier
#   wall_max_count_bonus     → flat bonus to max placed-wall count
#   tower_range_mult         → tower attack-range multiplier bonus
#   tower_max_count_bonus    → flat bonus to max tower count
#   tower_target_acquisition_mult → target-acquisition/cooldown reduction multiplier
#   tower_damage_mult        → tower damage multiplier bonus
#   tower_splash_radius_cells→ splash radius added to tower shots (cells)
#   tower_splash_damage_pct  → splash damage fraction dealt by tower shots
#   dragon_hp_mult           → dragon max-HP multiplier bonus
#   dragon_dmg_mult          → dragon damage multiplier bonus
#   dragon_train_time_mult   → dragon train-time reduction multiplier
#   dragon_cost_mult         → dragon cost reduction multiplier
#   snowstorm_speed          → added to the difficulty-scaled snowstorm movement multiplier
#   weather_warning_bonus    → seconds added to snowstorm/lava warning timers
#   vision_in_storm_mult     → vision multiplier bonus during snowstorms
#   storm_exposure_enemy_mult→ enemy snowstorm exposure damage multiplier bonus
#   storm_duration_bonus     → seconds added to snowstorm duration
#   building_regen_hp_per_sec→ building HP regenerated per second out of combat
#   environmental_damage_reduction → flat reduction to all snowstorm/volcano damage (0.2 = -20%)
#   snowstorm_damage_reduction → additional reduction to snowstorm exposure damage only
#   volcano_damage_reduction  → additional reduction to volcano meteor/burn damage only
# Techs without effect keys are read through ResearchManager.has_branch() by
# the systems that implement their hard-coded effects.
const RESEARCH_QUEUE_MAX: int = 3
const RESEARCH_TECHS: Dictionary = {
	# ═══════════════════════════════════════════════════════════════════════
	# Tier 1 roots
	# ═══════════════════════════════════════════════════════════════════════

	# ── Deep Delve discipline (rows 0-4) ──
	"deep_delve": {
		"name": "Deep Delve",
		"unit": "miner",
		"tree_pos": Vector2i(0, 0),
		"locks": "surface_war",
		"levels": {
			1: { "cost": 400, "time": 20.0, "desc": "Miners reach layers 5-7 immediately; miners +10% underground move speed" },
		},
	},
	# ── Surface War discipline (rows 5-9) ──
	"surface_war": {
		"name": "Surface War",
		"unit": "fighter",
		"tree_pos": Vector2i(0, 5),
		"locks": "deep_delve",
		"levels": {
			1: { "cost": 400, "time": 20.0, "desc": "Fighters +15% speed & damage on the surface; miners capped at layer 4; towers +20% range" },
		},
	},
	# ── Fortification discipline (rows 10-14) ──
	"fortification": {
		"name": "Fortification",
		"unit": "",
		"tree_pos": Vector2i(0, 10),
		"levels": {
			1: { "cost": 500, "time": 25.0, "building_hp_mult": 0.1, "structure_hp_mult": 0.15, "structure_build_time_mult": 0.2, "desc": "Buildings +10% max HP; towers/walls +15% max HP; structures build 20% faster" },
		},
	},
	# ── Dragon Mastery discipline (rows 15-19) ──
	"dragon_mastery": {
		"name": "Dragon Mastery",
		"unit": "dragon",
		"tree_pos": Vector2i(0, 15),
		"levels": {
			1: { "cost": 600, "time": 30.0, "dragon_hp_mult": 0.2, "dragon_dmg_mult": 0.2, "dragon_train_time_mult": 0.2, "desc": "Dragons +20% HP and damage; dragon train time -20%" },
		},
	},
	# ── Weather discipline (rows 20-24) ──
	"arctic_training": {
		"name": "Arctic Training",
		"unit": "",
		"tree_pos": Vector2i(0, 20),
		"levels": {
			1: { "cost": 400, "time": 20.0, "snowstorm_speed": 0.2, "desc": "Units move 20% faster during snowstorms" },
		},
	},
	# ── Survival discipline (rows 25-29) ──
	"survival_instinct": {
		"name": "Survival Instinct",
		"unit": "",
		"tree_pos": Vector2i(0, 25),
		"levels": {
			1: { "cost": 400, "time": 20.0, "environmental_damage_reduction": 0.2, "desc": "All units take 20% less damage from snowstorms and volcano events" },
		},
	},

	# ═══════════════════════════════════════════════════════════════════════
	# Tier 2 branches (both purchasable within the same discipline)
	# ═══════════════════════════════════════════════════════════════════════

	# ── Deep Delve tier 2 (rows 1-2) ──
	"ore_sonar": {
		"name": "Ore Sonar",
		"unit": "",
		"tree_pos": Vector2i(1, 1),
		"requires": { "deep_delve": 1 },
		"levels": {
			1: { "cost": 700, "time": 25.0, "desc": "Unlock Scan: reveal buried ore (incl. Fresh Ore) within 12 cells of the mine (40s cooldown)" },
		},
	},
	"reinforced_pack": {
		"name": "Reinforced Pack",
		"unit": "miner",
		"tree_pos": Vector2i(1, 2),
		"requires": { "deep_delve": 1 },
		"levels": {
			1: { "cost": 800, "time": 25.0, "miner_carry": 20, "miner_hp": 10, "desc": "Miners +20 carry capacity, +10 HP, immune to cave-in push" },
		},
	},
	# ── Surface War tier 2 (rows 6-7) ──
	"longbow": {
		"name": "Longbow",
		"unit": "archer",
		"tree_pos": Vector2i(1, 6),
		"requires": { "surface_war": 1 },
		"levels": {
			1: { "cost": 800, "time": 25.0, "archer_range": 25, "desc": "Archers +25 attack range and can blind-fire into the fog" },
		},
	},
	"rapid_fire": {
		"name": "Rapid Fire",
		"unit": "fighter",
		"tree_pos": Vector2i(1, 7),
		"requires": { "surface_war": 1 },
		"levels": {
			1: { "cost": 900, "time": 25.0, "fighter_cdr": 0.2, "swordsman_speed": 0.1, "desc": "All fighters attack 20% faster; swordsmen +10% move speed" },
		},
	},
	# ── Fortification tier 2 (rows 11-12) ──
	"stone_masonry": {
		"name": "Stone Masonry",
		"unit": "",
		"tree_pos": Vector2i(1, 11),
		"requires": { "fortification": 1 },
		"levels": {
			1: { "cost": 700, "time": 25.0, "wall_hp_mult": 0.3, "wall_cost_mult": 0.2, "wall_max_count_bonus": 1, "desc": "Walls +30% HP, -20% cost, +1 max wall count" },
		},
	},
	"sentry_network": {
		"name": "Sentry Network",
		"unit": "",
		"tree_pos": Vector2i(1, 12),
		"requires": { "fortification": 1 },
		"levels": {
			1: { "cost": 800, "time": 25.0, "tower_range_mult": 0.25, "tower_max_count_bonus": 1, "tower_target_acquisition_mult": 0.25, "desc": "Towers +25% range, +1 max tower count, acquire targets 25% faster" },
		},
	},
	# ── Dragon Mastery tier 2 (rows 16-17) ──
	"broodmother": {
		"name": "Broodmother",
		"unit": "dragon",
		"tree_pos": Vector2i(1, 16),
		"requires": { "dragon_mastery": 1 },
		"levels": {
			1: { "cost": 900, "time": 30.0, "dragon_train_time_mult": 0.3, "dragon_cost_mult": 0.15, "desc": "Dragons train 30% faster and cost 15% less" },
		},
	},
	"sky_raiders": {
		"name": "Sky Raiders",
		"unit": "dragon",
		"tree_pos": Vector2i(1, 17),
		"requires": { "dragon_mastery": 1 },
		"levels": {
			1: { "cost": 1000, "time": 30.0, "dragon_hp_mult": 0.25, "desc": "Dragons +25% HP; breath applies faction debuffs consistently" },
		},
	},
	# ── Weather tier 2 (rows 21-22) ──
	"weather_alert": {
		"name": "Weather Alert",
		"unit": "",
		"tree_pos": Vector2i(1, 21),
		"requires": { "arctic_training": 1 },
		"levels": {
			1: { "cost": 600, "time": 25.0, "weather_warning_bonus": 7.0, "desc": "Snowstorm/lava warnings last 12s; cave-ins give a 3s heads-up" },
		},
	},
	"storm_scout": {
		"name": "Storm Scout",
		"unit": "",
		"tree_pos": Vector2i(1, 22),
		"requires": { "arctic_training": 1 },
		"levels": {
			1: { "cost": 700, "time": 25.0, "vision_in_storm_mult": 0.25, "desc": "+25% vision radius during snowstorms; faction identification range +50%" },
		},
	},

	# ═══════════════════════════════════════════════════════════════════════
	# Tier 3 capstones (binary choice within each discipline)
	# ═══════════════════════════════════════════════════════════════════════

	# ── Deep Delve tier 3 (rows 3-4) ──
	"crystal_forge": {
		"name": "Crystal Forge",
		"unit": "wizard",
		"tree_pos": Vector2i(2, 3),
		"requires_any": ["ore_sonar", "reinforced_pack"],
		"locks": "earth_shield",
		"levels": {
			1: { "cost": 1500, "time": 35.0, "wizard_damage_mult": 0.4, "desc": "Wizards +40% damage; fireballs leave burning ground (5 DPS for 3s)" },
		},
	},
	"earth_shield": {
		"name": "Earth Shield",
		"unit": "",
		"tree_pos": Vector2i(2, 4),
		"requires_any": ["ore_sonar", "reinforced_pack"],
		"locks": "crystal_forge",
		"levels": {
			1: { "cost": 1400, "time": 35.0, "unit_hp_mult": 0.15, "building_hp": 1000, "desc": "All units +15% max HP; building +1000 max HP (heals the difference)" },
		},
	},
	# ── Surface War tier 3 (rows 8-9) ──
	"siege_master": {
		"name": "Siege Master",
		"unit": "swordsman",
		"tree_pos": Vector2i(2, 8),
		"requires_any": ["longbow", "rapid_fire"],
		"locks": "guerrilla",
		"levels": {
			1: { "cost": 1600, "time": 35.0, "desc": "Swordsmen +30% damage vs buildings; towers cost 50% less" },
		},
	},
	"guerrilla": {
		"name": "Guerrilla",
		"unit": "",
		"tree_pos": Vector2i(2, 9),
		"requires_any": ["longbow", "rapid_fire"],
		"locks": "siege_master",
		"levels": {
			1: { "cost": 1300, "time": 35.0, "desc": "Units +20% speed with no ally within 6 cells; miners can place traps (50 damage)" },
		},
	},
	# ── Fortification tier 3 (rows 13-14) ──
	"citadel": {
		"name": "Citadel",
		"unit": "",
		"tree_pos": Vector2i(2, 13),
		"requires_any": ["stone_masonry", "sentry_network"],
		"locks": "artillery",
		"levels": {
			1: { "cost": 1600, "time": 40.0, "building_hp": 1500, "building_regen_hp_per_sec": 5.0, "desc": "Building +1500 max HP; slowly repairs itself out of combat" },
		},
	},
	"artillery": {
		"name": "Artillery",
		"unit": "",
		"tree_pos": Vector2i(2, 14),
		"requires_any": ["stone_masonry", "sentry_network"],
		"locks": "citadel",
		"levels": {
			1: { "cost": 1500, "time": 40.0, "tower_damage_mult": 0.25, "tower_splash_radius_cells": 1.5, "tower_splash_damage_pct": 0.4, "desc": "Towers deal +25% damage and 40% splash in 1.5 cells" },
		},
	},
	# ── Dragon Mastery tier 3 (rows 18-19) ──
	"inferno": {
		"name": "Inferno",
		"unit": "dragon",
		"tree_pos": Vector2i(2, 18),
		"requires_any": ["broodmother", "sky_raiders"],
		"locks": "tempest_wings",
		"levels": {
			1: { "cost": 1700, "time": 40.0, "desc": "Dragon breath leaves burning ground (8 DPS for 4s)" },
		},
	},
	"tempest_wings": {
		"name": "Tempest Wings",
		"unit": "dragon",
		"tree_pos": Vector2i(2, 19),
		"requires_any": ["broodmother", "sky_raiders"],
		"locks": "inferno",
		"levels": {
			1: { "cost": 1500, "time": 40.0, "desc": "Dragons ignore snowstorm penalties and move 15% faster" },
		},
	},
	# ── Weather tier 3 (rows 23-24) ──
	"stormcaller": {
		"name": "Stormcaller",
		"unit": "",
		"tree_pos": Vector2i(2, 23),
		"requires_any": ["weather_alert", "storm_scout"],
		"locks": "pathfinder",
		"levels": {
			1: { "cost": 1400, "time": 35.0, "storm_exposure_enemy_mult": 0.5, "storm_duration_bonus": 5.0, "desc": "Enemy units take +50% snowstorm exposure damage; storms last +5s" },
		},
	},
	"pathfinder": {
		"name": "Pathfinder",
		"unit": "",
		"tree_pos": Vector2i(2, 24),
		"requires_any": ["weather_alert", "storm_scout"],
		"locks": "stormcaller",
		"levels": {
			1: { "cost": 1200, "time": 35.0, "vision_in_storm_mult": 0.3, "desc": "Friendly units +30% vision during storms; miners auto-recall on storm warning" },
		},
	},
	# ── Survival tier 2 (rows 25-26) ──
	"arctic_gear": {
		"name": "Arctic Gear",
		"unit": "",
		"tree_pos": Vector2i(1, 25),
		"requires": { "survival_instinct": 1 },
		"levels": {
			1: { "cost": 700, "time": 25.0, "snowstorm_damage_reduction": 0.2, "desc": "Units take an additional 20% less snowstorm exposure damage" },
		},
	},
	"volcano_wards": {
		"name": "Volcano Wards",
		"unit": "",
		"tree_pos": Vector2i(1, 26),
		"requires": { "survival_instinct": 1 },
		"levels": {
			1: { "cost": 700, "time": 25.0, "volcano_damage_reduction": 0.2, "desc": "Units take an additional 20% less volcano meteor and burn damage" },
		},
	},
	# ── Survival tier 3 (rows 27-28) ──
	"storm_refuge": {
		"name": "Storm Refuge",
		"unit": "",
		"tree_pos": Vector2i(2, 27),
		"requires_any": ["arctic_gear", "volcano_wards"],
		"locks": "eruption_drills",
		"levels": {
			1: { "cost": 1200, "time": 35.0, "snowstorm_damage_reduction": 0.3, "desc": "Units take 30% less snowstorm exposure damage" },
		},
	},
	"eruption_drills": {
		"name": "Eruption Drills",
		"unit": "",
		"tree_pos": Vector2i(2, 28),
		"requires_any": ["arctic_gear", "volcano_wards"],
		"locks": "storm_refuge",
		"levels": {
			1: { "cost": 1200, "time": 35.0, "volcano_damage_reduction": 0.35, "weather_warning_bonus": 5.0, "desc": "Volcano warnings last 5s longer; units take 35% less volcano damage" },
		},
	},

	# ═══════════════════════════════════════════════════════════════════════
	# Tier 4 cross-path capstones
	# ═══════════════════════════════════════════════════════════════════════
	"deep_fortress": {
		"name": "Deep Fortress",
		"unit": "",
		"tree_pos": Vector2i(3, 8),
		"requires": { "earth_shield": 1, "citadel": 1 },
		"levels": {
			1: { "cost": 2800, "time": 50.0, "building_hp": 1000, "building_regen_hp_per_sec": 5.0, "desc": "Buildings +1000 HP; walls/towers self-repair 5 HP/s; underground lanterns +3 vision" },
		},
	},
	"total_war": {
		"name": "Total War",
		"unit": "",
		"tree_pos": Vector2i(3, 11),
		"requires": { "siege_master": 1, "artillery": 1 },
		"levels": {
			1: { "cost": 3000, "time": 50.0, "fighter_dmg_mult": 0.1, "tower_max_count_bonus": 1, "wall_max_count_bonus": 1, "desc": "All fighters +10% damage; towers +1 max count, walls +1 max count" },
		},
	},
	"storm_dragon": {
		"name": "Storm Dragon",
		"unit": "dragon",
		"tree_pos": Vector2i(3, 21),
		"requires_any": ["tempest_wings", "stormcaller"],
		"levels": {
			1: { "cost": 3200, "time": 55.0, "desc": "Dragons ignore all weather penalties; breath extinguishes enemy lanterns" },
		},
	},
}

# Ore Sonar scan ability: reveals buried ore around the team's mine so miners
# path straight to it. Radius is in grid cells, cooldown in seconds. The
# effective sonar level equals the ore_sonar research level.
const SONAR_RADIUS: Dictionary = { 1: 12 }
const SONAR_COOLDOWN: Dictionary = { 1: 40.0 }

# ─── RESEARCH BRANCH EFFECTS (Revamp Phase 6+) ───
# Hard-coded branch effects read through ResearchManager.has_branch() or
# ResearchManager.get_stat_bonus(). One-time respec cost resets branches/locks.
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
# Ignite: a unit that takes a burning-ground tick stays lit for
# BURN_LINGER_DURATION after leaving the patch, taking BURN_TICK_INTERVAL
# ticks at BURN_LINGER_DPS_RATIO of the patch's dps — standing in the fire
# damages faster (full dps), walking through still stings.
const BURN_TICK_INTERVAL: float = 0.5
const BURN_LINGER_DURATION: float = 3.0
const BURN_LINGER_DPS_RATIO: float = 0.5
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

# fortification root: building and structure HP multipliers / build-time reduction.
const FORTIFICATION_BUILDING_HP_MULT: float = 0.1
const FORTIFICATION_STRUCTURE_HP_MULT: float = 0.15
const FORTIFICATION_BUILD_TIME_MULT: float = 0.2
# stone_masonry: wall upgrades.
const STONE_MASONRY_WALL_HP_MULT: float = 0.3
const STONE_MASONRY_WALL_COST_MULT: float = 0.2
const STONE_MASONRY_WALL_MAX_BONUS: int = 1
# sentry_network: tower upgrades.
const SENTRY_NETWORK_TOWER_RANGE_MULT: float = 0.25
const SENTRY_NETWORK_TOWER_MAX_BONUS: int = 1
const SENTRY_NETWORK_TARGET_ACQUISITION_MULT: float = 0.25
# citadel: building regen and HP.
const CITADEL_BUILDING_HP_BONUS: int = 1500
const CITADEL_REGEN_HP_PER_SEC: float = 5.0
# artillery: tower splash damage.
const ARTILLERY_TOWER_DAMAGE_MULT: float = 0.25
const ARTILLERY_SPLASH_RADIUS_CELLS: float = 1.5
const ARTILLERY_SPLASH_DAMAGE_PCT: float = 0.4

# dragon_mastery root: dragon stat/train-time bonuses.
const DRAGON_MASTERY_HP_MULT: float = 0.2
const DRAGON_MASTERY_DMG_MULT: float = 0.2
const DRAGON_MASTERY_TRAIN_TIME_MULT: float = 0.2
# broodmother: dragon production bonuses.
const BROODMOTHER_TRAIN_TIME_MULT: float = 0.3
const BROODMOTHER_COST_MULT: float = 0.15
# sky_raiders: dragon HP bonus.
const SKY_RAIDER_HP_MULT: float = 0.25
# inferno: dragon breath burning ground.
const INFERNO_BURNING_GROUND_DPS: float = 8.0
const INFERNO_BURNING_GROUND_DURATION: float = 4.0
# tempest_wings: dragon weather immunity and speed.
const TEMPEST_WINGS_SPEED_MULT: float = 0.15

# weather_alert: warning extension (added to base 5s) and cave-in heads-up.
const WEATHER_ALERT_WARNING_BONUS: float = 7.0
const WEATHER_ALERT_CAVEIN_WARNING: float = 3.0
# storm_scout: vision and identification range during storms.
const STORM_SCOUT_VISION_MULT: float = 0.25
const STORM_SCOUT_IDENTIFY_RANGE_MULT: float = 0.5
# stormcaller: enemy exposure damage and storm duration.
const STORMCALLER_EXPOSURE_MULT: float = 0.5
const STORMCALLER_DURATION_BONUS: float = 5.0
# pathfinder: friendly vision during storms.
const PATHFINDER_VISION_MULT: float = 0.3

# survival_instinct: base reduction to all environmental damage.
const SURVIVAL_INSTINCT_DAMAGE_REDUCTION: float = 0.2
# arctic_gear: additional snowstorm exposure damage reduction.
const ARCTIC_GEAR_SNOWSTORM_REDUCTION: float = 0.2
# volcano_wards: additional volcano meteor/burn damage reduction.
const VOLCANO_WARDS_VOLCANO_REDUCTION: float = 0.2
# storm_refuge: snowstorm exposure damage reduction.
const STORM_REFUGE_SNOWSTORM_REDUCTION: float = 0.3
# eruption_drills: volcano damage reduction and warning extension.
const ERUPTION_DRILLS_VOLCANO_REDUCTION: float = 0.35
const ERUPTION_DRILLS_WARNING_BONUS: float = 5.0

# Cross-path capstones.
const DEEP_FORTRESS_BUILDING_HP_BONUS: int = 1000
const DEEP_FORTRESS_REGEN_HP_PER_SEC: float = 5.0
const DEEP_FORTRESS_LANTERN_VISION_BONUS: int = 3
const TOTAL_WAR_FIGHTER_DMG_MULT: float = 0.1
const TOTAL_WAR_TOWER_MAX_BONUS: int = 1
const TOTAL_WAR_WALL_MAX_BONUS: int = 1
const STORM_DRAGON_LANTERN_EXTINGUISH_RADIUS_CELLS: int = 2

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
const ENEMY_HARASS_INTERVAL: float = 20.0  # seconds between miner-raid formations (tier 2+)
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
# Wave veto (tier 2+): organic launches below this simulated outcome ratio hold
# and keep massing instead of marching into a decisive loss.
const ENEMY_WAVE_VETO_SIM_RATIO: float = 0.5
# Anti-stall: the combat-predictor veto (smarts tier 2+) is ignored once no
# wave has marched for this many seconds — scaled by the difficulty "wave"
# attack-tempo multiplier, so harder difficulties get desperate sooner. A wave
# sent into a losing fight still deals damage; sitting at home forever does not.
# Desperation also drops the launch threshold to ENEMY_DESPERATE_WAVE_SIZE so an
# out-produced AI still raids with whatever it has instead of never attacking.
const ENEMY_WAVE_DESPERATION_DELAY: float = 90.0
const ENEMY_DESPERATE_WAVE_SIZE: int = 3
# Wave hunting (tier 2+): at launch, each fighter engages a visible enemy
# field unit within this range instead of beelining the enemy base — waves
# fight the army they meet on the way instead of marching past it.
const ENEMY_WAVE_HUNT_RANGE: float = 1000.0
# Wave retreat (tier 2+): an active wave (launched within the active window,
# older than the minimum age) that the combat predictor says is being wiped
# pulls back home to heal and remass instead of fighting to zero. Desperate
# waves and all-ins against a nearly-dead enemy base never retreat.
const ENEMY_WAVE_RETREAT_SIM_RATIO: float = 0.35
const ENEMY_WAVE_RETREAT_MIN_AGE: float = 4.0
const ENEMY_WAVE_ACTIVE_WINDOW: float = 45.0
# Miner raids (tier 2+): a small squad camps the enemy mine entry to ambush
# deposit trips (fighters cannot enter the enemy mine, so the raid lives on
# the surface). The squad retreats home when outnumbered at the camp or when
# the raid outstays its welcome, and joins the next wave naturally.
const ENEMY_RAID_SIZE: int = 3
const ENEMY_RAID_MAX_DURATION: float = 30.0
const ENEMY_RAID_RETREAT_RADIUS: float = 550.0
const ENEMY_RAID_RETREAT_ODDS: int = 2  # retreat when local defenders exceed raiders by this many
# AI-team miners re-scan for diggable cells this often while waiting at an
# exhausted mine (player miners keep the shared 5s retry in unit.gd).
const ENEMY_MINER_RESCAN_INTERVAL: float = 2.0
# Scouting (Revamp Phase 8): the first swordsman scout marches on the enemy
# base at the 1:00 mark to identify the hidden faction; a replacement goes
# out this long after the previous scout dies.
const ENEMY_SCOUT_TIME: float = 60.0
const ENEMY_SCOUT_RETRY_DELAY: float = 30.0
# AI lantern placement (Phase 8): decision cadence and coin buffers kept on
# top of the miner-upgrade reserve (build T1 early, upgrade to T2 only when
# the economy is comfortable).
const ENEMY_LANTERN_INTERVAL: float = 5.0
const ENEMY_LANTERN_BUFFER: int = 150
const ENEMY_LANTERN_UPGRADE_BUFFER: int = 400
# AI tower placement: same reserve rule as lanterns. Turtle openers build
# towers first on a leaner buffer; other openers wait for a lantern and a
# bigger cushion. Towers also unlock AI pigeon scouts (autonomous patrol).
const ENEMY_TOWER_BUFFER: int = 400
const ENEMY_TOWER_EARLY_BUFFER: int = 200
# Re-scouting (tier 2+): after the enemy faction is identified, a swordsman
# periodically re-visits the enemy base to refresh tower/army intel — skipped
# while an own pigeon is out (pigeons auto-patrol) or while defending.
const ENEMY_RESCOUT_INTERVAL: float = 75.0

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
const INPUT_TRAIN_PIGEON: StringName = &"train_pigeon"
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
