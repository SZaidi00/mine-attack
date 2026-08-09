# Mine Attack: Complete Revamp Implementation Guide

**Version:** 2.0 — ML-Ready Edition  
**Engine:** Godot 4.7  
**Last Updated:** 2026-08-05

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Phase 1: Fog of War & Vision System](#2-phase-1-fog-of-war--vision-system)
3. [Phase 2: Faction System](#3-phase-2-faction-system)
4. [Phase 3: Placeable Structures](#4-phase-3-placeable-structures)
5. [Phase 4: Dynamic Terrain & Events](#5-phase-4-dynamic-terrain--events)
6. [Phase 5: Weather System](#6-phase-5-weather-system)
7. [Phase 6: Tech Tree Overhaul](#7-phase-6-tech-tree-overhaul)
8. [Phase 7: UI & Menu Updates](#8-phase-7-ui--menu-updates)
9. [Phase 8: AI Controller Refactor](#9-phase-8-ai-controller-refactor)
10. [Appendix A: Data Structures](#appendix-a-data-structures)
11. [Appendix B: Constants Reference](#appendix-b-constants-reference)

---

## 1. Executive Summary

This document describes the complete revamp of Mine Attack from a symmetric, omniscient RTS into an asymmetric, imperfect-information game suitable for end-to-end machine learning. The revamp introduces:

- **Fog of War** with player-placed lanterns (surface and underground)
- **Three asymmetric factions** (Arcane, Brute, Industrial) chosen at match start
- **Placeable structures** (sentry towers, walls)
- **Dynamic terrain** (lava rises, cave-ins, ore depletion)
- **Weather events** (snowstorms with damage and vision reduction)
- **Binary tech tree branches** (irreversible choices that define strategy)
- **Hidden information** (enemy faction and tech choices must be scouted)

---

## 2. Phase 1: Fog of War & Vision System

### 2.1 Overview

Both teams lose omniscience. The map is divided into:
- **Revealed tiles**: Currently within any friendly unit's or lantern's vision radius
- **Remembered tiles**: Were revealed within the last 10 seconds but are no longer in vision
- **Fog tiles**: Never revealed, or memory expired

**Critical rule:** You can never see the enemy's side of the map, even if they build lanterns. Lanterns only provide vision for their owning team. The only way to see enemy territory is to move units there.

### 2.2 Vision Sources

| Source | Radius | Notes |
|--------|--------|-------|
| Miner (surface) | 6 cells | Only on surface |
| Miner (underground) | 4 cells | Only underground |
| Swordsman | 8 cells | Both layers |
| Archer | 12 cells | Both layers |
| Wizard | 10 cells | Both layers |
| Dragon | 14 cells | Surface only (flight) |
| Surface Lantern T1 | 8 cells | Static structure |
| Surface Lantern T2 | 14 cells | Static structure |
| Surface Lantern T3 | 22 cells | Static structure |
| Underground Lantern | 10 cells | Static structure |
| Sentry Tower | 18 cells | Static structure, surface only |
| Building | 10 cells | Both layers |

### 2.3 Fog Rendering

**Visual Design:**
- Fog tiles are rendered as **pitch black** (`#05070a`) with **zero transparency**
- Remembered tiles are rendered at **30% brightness** (darkened but visible)
- Revealed tiles render at **100% brightness**
- The transition between revealed and remembered uses a **soft edge** (2-cell gradient)
- Enemy units in remembered tiles are shown as **frozen silhouettes** at their last known position with a "?" indicator

**Implementation in `GridWorld`:**

```gdscript
# New properties in GridWorld
var _vision_maps: Dictionary = {
    GameManager.Team.PLAYER: [],  # Array[Array[bool]] — same dims as _cells
    GameManager.Team.ENEMY: []
}
var _memory_maps: Dictionary = {
    GameManager.Team.PLAYER: [],  # Array[Array[float]] — timestamp of last seen
    GameManager.Team.ENEMY: []
}
const MEMORY_DURATION: float = 10.0
const FOG_COLOR: Color = Color("#05070a")
const MEMORY_COLOR: Color = Color("#05070a").darkened(0.7)

func _ready():
    _init_vision_maps()

func _init_vision_maps():
    for team in [GameManager.Team.PLAYER, GameManager.Team.ENEMY]:
        _vision_maps[team] = []
        _memory_maps[team] = []
        for x in range(GRID_X_MIN, GRID_X_MAX + 1):
            var vision_col = []
            var memory_col = []
            for y in range(GRID_Y_MIN, GRID_Y_MAX + 1):
                vision_col.append(false)
                memory_col.append(0.0)
            _vision_maps[team].append(vision_col)
            _memory_maps[team].append(memory_col)

func _process(delta: float):
    _update_vision(GameManager.Team.PLAYER)
    _update_vision(GameManager.Team.ENEMY)
    queue_redraw()

func _update_vision(team: GameManager.Team):
    # Clear current vision
    for x in range(GRID_X_MIN, GRID_X_MAX + 1):
        for y in range(GRID_Y_MIN, GRID_Y_MAX + 1):
            var idx_x = x - GRID_X_MIN
            var idx_y = y - GRID_Y_MIN
            if _vision_maps[team][idx_x][idx_y]:
                # Was visible, now going to memory
                _memory_maps[team][idx_x][idx_y] = Time.get_time_dict_from_system()["second"]
            _vision_maps[team][idx_x][idx_y] = false

    # Recalculate from all vision sources
    var sources = _get_vision_sources(team)
    for source in sources:
        var center = _world_to_cell(source.position)
        var radius = source.vision_radius
        _reveal_circle(team, center, radius)

func _reveal_circle(team: GameManager.Team, center: Vector2i, radius: int):
    for dx in range(-radius, radius + 1):
        for dy in range(-radius, radius + 1):
            if dx * dx + dy * dy > radius * radius:
                continue
            var x = center.x + dx
            var y = center.y + dy
            if x < GRID_X_MIN or x > GRID_X_MAX or y < GRID_Y_MIN or y > GRID_Y_MAX:
                continue
            var idx_x = x - GRID_X_MIN
            var idx_y = y - GRID_Y_MIN
            _vision_maps[team][idx_x][idx_y] = true
            _memory_maps[team][idx_x][idx_y] = 0.0  # Currently visible

func is_visible_to(team: GameManager.Team, world_pos: Vector2) -> bool:
    var cell = _world_to_cell(world_pos)
    var idx_x = cell.x - GRID_X_MIN
    var idx_y = cell.y - GRID_Y_MIN
    return _vision_maps[team][idx_x][idx_y]

func is_remembered_by(team: GameManager.Team, world_pos: Vector2) -> bool:
    var cell = _world_to_cell(world_pos)
    var idx_x = cell.x - GRID_X_MIN
    var idx_y = cell.y - GRID_Y_MIN
    if _vision_maps[team][idx_x][idx_y]:
        return true
    var last_seen = _memory_maps[team][idx_x][idx_y]
    if last_seen == 0.0:
        return false
    var elapsed = Time.get_time_dict_from_system()["second"] - last_seen
    return elapsed < MEMORY_DURATION
```

### 2.4 Lantern System

#### Surface Lanterns

**Placement Rules:**
- Can only be placed on the **player's half** of the map (x < 0 for player, x > 0 for enemy)
- Must be on surface ground (y = 0)
- Cannot be placed within 3 cells of another lantern
- Max 3 lanterns per team

**Stats:**

| Tier | Cost | Vision | HP | Build Time |
|------|------|--------|-----|------------|
| 1 | 200g | 8 cells | 500 | 5s |
| 2 | 600g | 14 cells | 500 | 5s |
| 3 | 1000g | 22 cells | 500 | 5s |

**Upgrade path:** T1 → T2 → T3 (must be built in order at the same location)

**Destruction:**
- Lanterns can be attacked by enemy fighters
- When HP reaches 0, the lantern is destroyed and vision is lost
- Destroyed lanterns drop 50% of their build cost as a coin pickup

**Visual:**
- T1: Small campfire on a metal post (warm yellow glow, subtle pulse)
- T2: Iron lantern with glass enclosure (brighter glow, wider radius)
- T3: Industrial floodlight tower (brightest, widest, slight beam effect)

#### Underground Lanterns

**Placement Rules:**
- Can be placed on any **diggable** underground cell
- Cannot be placed within 2 cells of another underground lantern
- Max 5 underground lanterns per team

**Stats:**
- Cost: 100g
- Vision: 10 cells
- HP: 200
- Build Time: 3s

**Special behavior:**
- Underground lanterns reveal **ore** within their radius (even buried ore)
- This revealed ore is remembered by the team permanently (does not fade with memory)
- Destroyed by lava rising (instant)
- Destroyed by cave-ins (instant)

#### Lantern Placement UI

- New "Build" button in the bottom bar (next to stance buttons)
- Clicking Build opens a radial menu: Lantern / Tower / Wall
- Selecting Lantern enters "placement mode":
  - Ghost sprite follows cursor
  - Valid placement: ghost is semi-transparent green
  - Invalid placement: ghost is semi-transparent red with X overlay
  - Left-click to confirm, Right-click or Esc to cancel
  - Cost is deducted on confirm

### 2.5 Impact on Existing Systems

**Mining (Blind Dig):**
- Previously: miners dig blindly but prefer damaged cells
- Now: miners in **unlanterned** areas cannot see ore at all — they dig completely randomly
- Miners in lantern radius can see ore and use the old preference logic
- This makes underground lanterns **essential** for efficient mining

**AI Controller:**
- The AI must now maintain a **belief state** about the map
- It cannot read enemy unit positions directly from the scene tree
- It must track what it has seen and infer what it hasn't
- New `AIBeliefSystem` autoload required (see Phase 8)

**Combat:**
- Units cannot auto-attack enemies they cannot see
- If a unit's target moves into fog, the attack is cancelled
- Archers cannot shoot into fog (no line of sight)

---

## 3. Phase 2: Faction System

> **Status: fully implemented.** `FactionData` + `scripts/resources/factions/{arcane,brute,industrial}.tres`, the `FactionManager` autoload (hidden enemy faction, scouting identification, faction-modified costs), the main-menu faction select, HUD/building faction icons, all stat/economic modifiers, and all abilities: Rune Blade, Berserk, Swarm, Fortify (splash), Blink, Arcane Shot (pierce), Heavy Bolt (slow), Volley, Fight Back, Miner Reveal, Mana Burn, Crush (stun), Supply Drop, Industrial miner Efficiency. The AI's faction is a random pick each match. Two deliberate interpretation calls: **Blink** is innate to all wizards at 15s (the guide's "reduced from 15s to 10s" implies a baseline) with Arcane shaving 5s, and **Crush** stuns on the dragon's breath hit (dragons never land, so "landing attack" was read as the dragon's attack). Wizard "Efficiency (0 mana)" is intentionally skipped — the game has no mana.

### 3.1 Overview

Three asymmetric factions replace the symmetric teams. Each faction has unique unit stats, abilities, and economic modifiers. The faction is chosen in the main menu and is **hidden from the opponent** until scouted.

### 3.2 Faction Selection

**Main Menu Update:**
- After selecting difficulty, a "Choose Faction" screen appears
- Three large cards showing faction name, icon, and brief description
- Player clicks one to select, then clicks "Play"
- The AI's faction is randomly selected (or fixed per difficulty)
- **Critical:** Faction choice is NOT shown to the opponent

**In-Game Identification:**
- Units do NOT change color based on faction (player is always blue, enemy is always red)
- The only way to identify a faction is through behavior:
  - Arcane: wizards appear earlier, units have subtle glow effects
  - Brute: swordsmen are visibly larger/tankier, move slower
  - Industrial: more miners early, buildings have steam/smoke particles
- A scout (any unit) that gets within 8 cells of the enemy building can "identify" the faction
- Once identified, the faction icon appears next to the enemy building HP bar

### 3.3 Faction: Arcane

**Theme:** Magic enhances all units. Fragile but powerful abilities.

| Unit | HP Modifier | Damage Modifier | Special Ability |
|------|-------------|-----------------|-----------------|
| Swordsman | -20% | +15% | **Rune Blade**: First hit in each engagement deals +50% damage |
| Archer | -15% | Normal | **Arcane Shot**: Cooldown 8s — arrow pierces through first target to hit second target behind |
| Wizard | -10% | +25% | **Blink**: Teleport cooldown reduced from 15s to 10s |
| Miner | Normal | Normal | **Reveal**: Personal 4-cell sonar scan, 30s cooldown |
| Dragon | Normal | Normal | **Mana Burn**: Fireballs reduce target's next attack damage by 20% |

**Economic Modifiers:**
- All units cost +10% more (magic is expensive)
- Miners mine at normal speed
- Towers (Arcane variant): 600 HP, shoot homing magic missiles (slight tracking), cost 350g

**Win Condition Bias:** Win early with ability combos before enemy scales.

### 3.4 Faction: Brute

**Theme:** Raw combat power. Tanky units, slow economy.

| Unit | HP Modifier | Damage Modifier | Special Ability |
|------|-------------|-----------------|-----------------|
| Swordsman | +30% | +10% | **Berserk**: Below 30% HP, +40% attack speed |
| Archer | +20% | Normal | **Heavy Bolt**: Attacks slow target by 30% for 2s |
| Wizard | +25% | -15% | **Fortify**: Fireballs have +30% splash radius |
| Miner | +15 HP | Normal (can fight) | **Fight Back**: Miners deal 5 melee damage when attacked |
| Dragon | +20% | Normal | **Crush**: Landing attack stuns target for 0.5s |

**Economic Modifiers:**
- All units cost normal
- Miners mine at -20% speed
- Miner carry capacity: -5 (base 20, not 25)
- Towers (Brute variant): 1200 HP, slower fire rate (1.8s), higher damage (18), cost 300g

**Win Condition Bias:** Win mid-game with overwhelming army value and siege potential.

### 3.5 Faction: Industrial

**Theme:** Superior economy and production. Weak individual units, strong attrition.

| Unit | HP Modifier | Damage Modifier | Special Ability |
|------|-------------|-----------------|-----------------|
| Swordsman | -15% | -10% | **Swarm**: +15% speed when 3+ friendly swordsmen within 6 cells |
| Archer | -10% | -5% | **Volley**: Cooldown 12s — all archers within 50px fire at target area simultaneously |
| Wizard | Normal | Normal | **Efficiency**: Fireballs cost 0 mana (no cooldown change) |
| Miner | Normal | Normal | **Efficiency**: +25% mining speed, +10 carry capacity, ore yields +15% gold |
| Dragon | -10% | Normal | **Supply Drop**: Killing a unit generates 10g for the team |

**Economic Modifiers:**
- Swordsman cost: 75g (not 100g)
- Archer cost: 120g (not 150g)
- Wizard cost: 200g (not 250g)
- Starts with +200g and 1 extra miner
- Towers cost: 200g (not 300g), build 2× faster
- Walls cost: 30g (not 50g), max 15 segments (not 10)

**Win Condition Bias:** Win late-game by out-producing the enemy. Swarm with cheap units.

### 3.6 Faction Balance (Rock-Paper-Scissors)

```
Arcane beats Brute (abilities shred slow tanks)
Brute beats Industrial (overwhelms cheap units before they swarm)
Industrial beats Arcane (swarm negates precision abilities, out-economies)
```

This is a **soft** RPS — skill and execution can overcome the matchup, but each faction has a natural advantage against one and disadvantage against another.

### 3.7 Implementation

**New `FactionData` Resource:**

```gdscript
# scripts/resources/faction_data.gd
class_name FactionData
extends Resource

@export var faction_name: String
@export var description: String
@export var icon_texture: Texture2D

# Unit stat modifiers (multipliers, 1.0 = normal)
@export var swordsman_hp_mult: float = 1.0
@export var swordsman_dmg_mult: float = 1.0
@export var archer_hp_mult: float = 1.0
@export var archer_dmg_mult: float = 1.0
@export var wizard_hp_mult: float = 1.0
@export var wizard_dmg_mult: float = 1.0
@export var miner_mining_mult: float = 1.0
@export var miner_carry_bonus: int = 0

# Cost modifiers
@export var unit_cost_mult: float = 1.0
@export var tower_cost: int = 300
@export var wall_cost: int = 50

# Starting bonuses
@export var starting_gold_bonus: int = 0
@export var starting_miner_bonus: int = 0

# Special flags
@export var swordsman_rune_blade: bool = false
@export var archer_arcane_shot: bool = false
@export var wizard_blink_reduction: float = 0.0
@export var swordsman_berserk: bool = false
@export var archer_heavy_bolt: bool = false
@export var wizard_fortify: bool = false
@export var miner_fight_back: bool = false
@export var swordsman_swarm: bool = false
@export var archer_volley: bool = false
@export var dragon_supply_drop: bool = false
```

**New `FactionManager` Autoload:**

```gdscript
# scripts/autoload/faction_manager.gd
extends Node

var player_faction: FactionData
var enemy_faction: FactionData

const FACTIONS = {
    "arcane": preload("res://scripts/resources/factions/arcane.tres"),
    "brute": preload("res://scripts/resources/factions/brute.tres"),
    "industrial": preload("res://scripts/resources/factions/industrial.tres")
}

func set_faction(team: GameManager.Team, faction_id: String):
    if team == GameManager.Team.PLAYER:
        player_faction = FACTIONS[faction_id]
    else:
        enemy_faction = FACTIONS[faction_id]

func get_faction(team: GameManager.Team) -> FactionData:
    return player_faction if team == GameManager.Team.PLAYER else enemy_faction

func apply_faction_stats(unit: Unit, team: GameManager.Team):
    var faction = get_faction(team)
    if not faction:
        return

    # Apply multipliers to unit data
    match unit.data.unit_id:
        "swordsman":
            unit.data.max_hp = int(unit.data.max_hp * faction.swordsman_hp_mult)
            unit.data.damage_per_hit *= faction.swordsman_dmg_mult
        "archer":
            unit.data.max_hp = int(unit.data.max_hp * faction.archer_hp_mult)
            unit.data.damage_per_hit *= faction.archer_dmg_mult
        # ... etc
```

---

## 4. Phase 3: Placeable Structures

> **Status: implemented**, following the project's existing Lantern pattern (per-structure classes `Tower`/`WallSegment` under `Main/Structures`) rather than the unified `Structure` base class sketched in §4.3. Towers: placement rules, faction variants (Arcane 350g/600 HP purple-tinted missiles, Brute 1200 HP/1.8s/18 dmg, Industrial 200g/2× build), fighter>miner>building priority, vision, salvage. Walls: A* movement block once built, projectile absorption, faction cost/max (Industrial 30g/3), salvage. Both are invulnerable under construction and attackable via right-click; towers are also auto-attacked like lanterns. **Deviations:** tower range/vision reduced from 18 cells to 8 attack / 10 vision (18 cells covered a third of the map); wall cap reduced from 10 (15 Industrial) to 2 (3 Industrial) and chain placement dropped — a 2D map this size has no room for long walls; walls seal their full column (surface + dug cells beneath, re-sealed as new cells are dug) instead of just the surface cell — otherwise A* routes enemies through tunnels below the surface row and walls never get attacked; the seal is team-aware (`find_path` lifts the owner's seals) so a wall never blocks its builder; miners cannot breach placed walls (mining is underground-only in this game — fighters destroy walls); walls are not auto-attack targets (explicit orders only); the AI does not place structures yet (deferred to the Phase 8 AI refactor).

### 4.1 Sentry Tower

**Placement:**
- Surface only
- Player's half of map
- Cannot be placed within 2 cells of a building or mine entry
- Max 2 towers per team

**Stats:**
- Cost: 300g (modified by faction)
- Build Time: 8s
- HP: 800 (Arcane: 600, Brute: 1200)
- Range: 18 cells
- Damage: 12 per shot
- Cooldown: 1.2s (Brute: 1.8s, damage 18)
- Target Priority: enemy fighters > enemy miners > enemy buildings

**Behavior:**
- Automatically attacks the highest-priority target in range
- Does not move
- Cannot be manually controlled
- Emits a subtle "scan" animation (rotating light beam)

**Visual:**
- Small stone/wood fortification (2×2 cells)
- Archer silhouette on top
- Player: blue-gray stone
- Enemy: red-brown stone

### 4.2 Placeable Walls

**Placement:**
- Surface only
- Player's half of map
- Must be adjacent to existing wall or building (chain placement)
- Max 10 segments per team (Industrial: 15)

**Stats:**
- Cost: 50g (Industrial: 30g)
- Build Time: 3s
- HP: 400 per segment
- Blocks movement and projectiles

**Behavior:**
- Can be breached by miners (takes time, scales with miner level)
- Can be destroyed by fighters
- Does not attack

**Visual:**
- 1×1 cell segments
- Player: gray stone blocks
- Enemy: brown wooden stakes
- Slightly shorter than central wall

### 4.3 Structure System Architecture

```gdscript
# scripts/world/structure.gd
class_name Structure
extends StaticBody2D

enum Type { LANTERN, TOWER, WALL }

@export var structure_type: Type
@export var team: GameManager.Team
@export var hp: int = 100
@export var max_hp: int = 100
@export var vision_radius: int = 0
@export var build_time: float = 3.0

var _build_progress: float = 0.0
var _is_built: bool = false

signal hp_changed(current: int, maximum: int)
signal destroyed(structure: Structure)
signal construction_complete

func _ready():
    add_to_group("structures")
    add_to_group("buildings" if structure_type == Type.TOWER else "structures")
    if team == GameManager.Team.PLAYER:
        add_to_group("player")
    else:
        add_to_group("enemy")

func _process(delta: float):
    if not _is_built:
        _build_progress += delta
        if _build_progress >= build_time:
            _is_built = true
            construction_complete.emit()

func take_damage(amount: int):
    if not _is_built:
        return  # Invulnerable while building
    hp -= amount
    hp_changed.emit(hp, max_hp)
    if hp <= 0:
        _destroy()

func _destroy():
    destroyed.emit(self)
    # Spawn dust particles
    # Drop 50% build cost as coin pickup
    queue_free()
```

---

## 5. Phase 4: Dynamic Terrain & Events

> **Status: implemented**, following the guide's behavior sequence with the code in a new `scripts/world/grid_events.gd` helper module (lava, cave-ins, ore respawn) plus `LAVA`/`MAGMA_ROCK`/`FRESH_ORE`/`SOLID_ROCK` cell types, instead of growing `grid_world.gd`. Lava: random 90–120s interval, warning (screen shake + rumble + pulsing red glow over the bottom layers + HUD countdown banner), 1–2 bottom layers flood (kills units instantly with no cargo drop, destroys underground lanterns, spares the central wall and borders), 20s up with a periodic straggler sweep, then recedes into diggable magma rock (150 HP, 0 gold) with 40% fresh ore (100–200g). Cave-ins: random 45–75s, 3×3 underground collapse — diggable tiles become indestructible SOLID_ROCK for 10s, units take 50 damage and are pushed to the nearest walkable cell, underground lanterns destroyed. Ore depletion: veins past 80% yielded trickle at 10% per swing and draw dull; fresh veins respawn in layers 3+ every 60s when ore runs low. **Deviations:** the destruction payout still pays the full remainder on depleted ore (keeps the project-wide "every tile yields exactly coin_value" invariant — only the per-swing trickle drops); magma rock is A*-solid until dug like normal dirt (the guide's sketch made it walkable, which contradicts how digging works here); events accumulate game-time in `GridWorld._process` instead of `Timer` nodes so they freeze on pause/game-over like everything else; the Weather Alert warning extension is wired (`ResearchManager.get_level(team, "weather_alert")`) but stays at 5s until that Phase 5/6 tech exists. New constants in `constants.gd` (`LAVA_*`, `CAVEIN_*`, `MAGMA_*`, `ORE_*`), sprites `frost_mines_assets/tiles/{magma_rock,fresh_ore}.png` + `icons/icon_lava.png`, a `rumble` SFX, and tests in `tests/test_dynamic_terrain.gd` (random scheduling is disabled there via `GridWorld.set_dynamic_events_enabled(false)` and every event is forced).

### 5.1 Lava Rising

**Overview:** The most dramatic terrain event. Lava periodically rises from the bottom of the mine, destroying everything in its path, then recedes and leaves new terrain.

**Timing:**
- **Interval:** Random between 90–120 seconds (uniform distribution)
- **Warning:** 5 seconds before rise, screen shakes slightly and a red glow pulses at the bottom
- **Duration:** Lava stays up for 20 seconds
- **Weather Alert Research:** If purchased, gives a 15-second warning instead of 5-second warning

**Behavior Sequence:**

```
T-15s (or T-5s without research): Warning phase begins
  - Screen shake intensity: 0.2
  - Red glow pulses at bottom of screen
  - Audio: low rumbling sound

T-0s: Lava rises
  - Lava covers bottom 1–2 layers (random: 1 or 2)
  - All cells in lava zone become LAVA type (indestructible, impassable)
  - Any miner in lava zone dies instantly (no corpse, no cargo drop)
  - Any underground lantern in lava zone is destroyed instantly
  - Any diggable tile in lava zone is converted to MAGMA ROCK

T+20s: Lava recedes
  - Lava cells become MAGMA ROCK (diggable, high HP)
  - 40% of magma rocks become FRESH ORE (high gold value: 100–200)
  - 60% remain empty magma rock (0 gold, but blocks path)
  - New A* paths must be recalculated

T+30s: Next interval begins (random 90–120s)
```

**Cell Types:**

```gdscript
enum CellType {
    EMPTY,
    SURFACE_GROUND,
    DIRT,
    ORE,
    WALL,
    LAVA,        # New: impassable, deals damage
    MAGMA_ROCK,  # New: diggable, high HP, may contain ore
    FRESH_ORE    # New: high-value ore spawned by lava
}
```

**Magma Rock Stats:**
- HP: 150 (harder than normal dirt)
- Mining time: 2× normal
- If it contains ore: yields 100–200 gold (random)
- Visual: Glowing red-orange rock with ember particles

> **Current code location:** `GridWorld` logic has been split into helper modules under `scripts/world/`. Map generation and cell management live in `grid_world.gd`, `grid_map_generation.gd`, and `grid_mining.gd`; drawing/effects live in `grid_drawing.gd`. Any new dynamic-terrain code should hook into those modules rather than expanding `grid_world.gd` directly.

**Implementation in `GridWorld`:**

```gdscript
# New properties
var _lava_timer: Timer
var _lava_active: bool = false
var _lava_layers: int = 0  # How many layers from bottom are lava
const LAVA_WARNING_TIME: float = 5.0
const LAVA_WARNING_TIME_RESEARCH: float = 15.0
const LAVA_DURATION: float = 20.0
const LAVA_MIN_INTERVAL: float = 90.0
const LAVA_MAX_INTERVAL: float = 120.0
const MAGMA_ORE_CHANCE: float = 0.4
const MAGMA_ORE_MIN: int = 100
const MAGMA_ORE_MAX: int = 200

func _ready():
    _init_lava_timer()

func _init_lava_timer():
    _lava_timer = Timer.new()
    _lava_timer.one_shot = true
    _lava_timer.timeout.connect(_on_lava_timer_timeout)
    add_child(_lava_timer)
    _schedule_next_lava()

func _schedule_next_lava():
    var interval = randf_range(LAVA_MIN_INTERVAL, LAVA_MAX_INTERVAL)
    _lava_timer.start(interval)

func _on_lava_timer_timeout():
    _start_lava_warning()

func _start_lava_warning():
    var warning_time = LAVA_WARNING_TIME
    if ResearchManager.has_research(GameManager.Team.PLAYER, "weather_alert"):
        warning_time = LAVA_WARNING_TIME_RESEARCH

    # Emit warning signal (HUD listens and shows alert)
    lava_warning_started.emit(warning_time)

    # Start screen shake and red glow
    GameManager.start_lava_warning(warning_time)

    # Wait for warning period
    await get_tree().create_timer(warning_time).timeout
    _rise_lava()

func _rise_lava():
    _lava_active = true
    _lava_layers = randi_range(1, 2)

    var bottom_layer_start = GRID_Y_MAX - (_lava_layers * ROWS_PER_LAYER) + 1

    for y in range(bottom_layer_start, GRID_Y_MAX + 1):
        for x in range(GRID_X_MIN, GRID_X_MAX + 1):
            var cell = _cells[x - GRID_X_MIN][y - GRID_Y_MIN]

            # Kill any unit in lava
            for unit in _get_units_at_cell(x, y):
                if unit.data.unit_id == "miner":
                    unit.die_instantly()  # No corpse, no cargo drop
                else:
                    unit.take_damage(9999)  # Instakill

            # Destroy lanterns
            for structure in _get_structures_at_cell(x, y):
                if structure.structure_type == Structure.Type.LANTERN:
                    structure._destroy()

            # Convert cell to lava
            cell.type = CellType.LAVA
            cell.hp = 9999
            cell.max_hp = 9999
            cell.solid = true
            cell.diggable = false

            # Update A*
            _astar.set_point_solid(Vector2i(x, y), true)

    # Visual: lava glow effect, steam particles
    lava_risen.emit(_lava_layers)

    # Wait for lava duration
    await get_tree().create_timer(LAVA_DURATION).timeout
    _recede_lava()

func _recede_lava():
    var bottom_layer_start = GRID_Y_MAX - (_lava_layers * ROWS_PER_LAYER) + 1

    for y in range(bottom_layer_start, GRID_Y_MAX + 1):
        for x in range(GRID_X_MIN, GRID_X_MAX + 1):
            var cell = _cells[x - GRID_X_MIN][y - GRID_Y_MIN]

            # Convert lava to magma rock
            cell.type = CellType.MAGMA_ROCK
            cell.hp = 150
            cell.max_hp = 150
            cell.solid = true
            cell.diggable = true

            # Chance to spawn fresh ore
            if randf() < MAGMA_ORE_CHANCE:
                cell.type = CellType.FRESH_ORE
                cell.coin_value = randi_range(MAGMA_ORE_MIN, MAGMA_ORE_MAX)
                cell.hp = 150
                cell.max_hp = 150

            # Update A* (now diggable, so not solid)
            _astar.set_point_solid(Vector2i(x, y), false)

    _lava_active = false
    lava_receded.emit()
    _schedule_next_lava()
```

### 5.2 Cave-Ins

**Overview:** Random collapses that block underground paths and damage units.

**Timing:**
- **Interval:** Random between 45–75 seconds
- **Warning:** None (sudden event)
- **Area:** 3×3 cell region, random location underground

**Behavior:**
- All diggable tiles in the 3×3 area become SOLID ROCK (indestructible for 10s)
- Any unit in the area takes 50 damage and is pushed to the nearest empty cell
- After 10s, solid rock becomes normal diggable dirt
- Any underground lantern in the area is destroyed

**Visual:**
- Dust/debris particle burst
- Screen shake (intensity 0.3)
- Rocks appear as dark gray boulders

### 5.3 Ore Depletion

**Overview:** Ore veins run dry after yielding most of their gold, forcing miners to migrate.

**Mechanic:**
- Each ore tile tracks `gold_yielded`
- When `gold_yielded >= coin_value * 0.8`, the tile becomes DEPLETED
- Depleted ore yields only 10% of normal gold per swing
- New rich veins spawn randomly in deeper layers every 60 seconds (if total ore count is below threshold)

**Visual:**
- Depleted ore changes from bright gold to dull gray-brown
- Still visible as ore, but miners should prefer fresh veins

---

## 6. Phase 5: Weather System

### 6.1 Snowstorms

**Overview:** Periodic surface weather events that reduce visibility and movement, and deal damage to unprotected units.

**Timing:**
- **Interval:** Random between 60–90 seconds (independent of lava timer)
- **Warning:** 5 seconds before (10 seconds with Weather Alert research)
- **Duration:** 15 seconds
- **Weather Alert Research:** Warns that "a weather event is incoming" but does NOT specify snowstorm vs lava

**Effects:**

| Effect | Value |
|--------|-------|
| Vision radius | -50% for ALL units and lanterns |
| Movement speed | -10% for all surface units |
| Damage | 2 HP/s to any surface unit NOT within a lantern's vision radius |
| Building damage | 0 (buildings are immune) |

**Damage Logic:**

```gdscript
func _apply_snowstorm_damage(delta: float):
    if not _snowstorm_active:
        return

    for unit in get_tree().get_nodes_in_group("units"):
        if unit.is_underground:
            continue  # Snowstorm only affects surface

        # Check if unit is within any friendly lantern's vision
        var is_protected = false
        for lantern in _get_lanterns_for_team(unit.team):
            if lantern.global_position.distance_to(unit.global_position) <= lantern.vision_radius * CELL_SIZE:
                is_protected = true
                break

        if not is_protected:
            unit.take_damage(int(2.0 * delta))  # 2 HP per second
            # Visual: unit turns slightly blue, frost particles
            unit.apply_frost_effect()
```

**Visual Design:**
- Heavy snowfall particle effect (2× normal snow density)
- Wind gusts (snow particles angle 15°)
- Screen vignette (dark blue edges)
- Ground becomes white/icy
- Units not near lanterns gain a subtle blue frost overlay

**Audio:**
- Howling wind ( louder than normal ambient wind)
- Occasional ice crack sounds

### 6.2 Weather Alert Research

**Name:** Meteorological Array  
**Cost:** 2500g  
**Research Time:** 60 seconds  
**Effect:**
- Extends weather event warning from 5 seconds to 15 seconds
- Extends lava warning from 5 seconds to 15 seconds
- Does NOT tell you WHICH event is coming (snowstorm or lava)
- Does NOT tell you WHERE lava will rise

**Why expensive:** This is a luxury research for players who want to optimize miner safety. At 2500g, it is a significant investment that delays army production.

### 6.3 Weather Implementation

> **Current status:** A standalone `weather_manager.gd` does **not** exist yet. Ambient snow/dust particles are spawned by `scripts/world/grid_ambience.gd` from `GridWorld._ready()`. The weather-event system below is the intended design; when implemented it should live in a new `scripts/autoload/weather_manager.gd` autoload.

```gdscript
# scripts/autoload/weather_manager.gd
extends Node

enum EventType { NONE, SNOWSTORM, LAVA }

var _event_timer: Timer
var _current_event: EventType = EventType.NONE
var _event_active: bool = false
var _warning_active: bool = false

const SNOWSTORM_MIN_INTERVAL: float = 60.0
const SNOWSTORM_MAX_INTERVAL: float = 90.0
const SNOWSTORM_DURATION: float = 15.0
const WARNING_TIME_BASE: float = 5.0
const WARNING_TIME_RESEARCH: float = 15.0

signal weather_warning(seconds_remaining: float)
signal snowstorm_started
signal snowstorm_ended
signal lava_warning_started(seconds_remaining: float)

func _ready():
    _event_timer = Timer.new()
    _event_timer.one_shot = true
    _event_timer.timeout.connect(_on_event_timer_timeout)
    add_child(_event_timer)
    _schedule_next_event()

func _schedule_next_event():
    var interval = randf_range(SNOWSTORM_MIN_INTERVAL, SNOWSTORM_MAX_INTERVAL)
    _event_timer.start(interval)

func _on_event_timer_timeout():
    # Choose event (50/50 snowstorm or lava warning)
    # Lava has its own timer, but we coordinate warnings
    if randf() < 0.5:
        _trigger_snowstorm_warning()
    else:
        # This slot is reserved for future weather types
        _schedule_next_event()

func _trigger_snowstorm_warning():
    var warning_time = WARNING_TIME_BASE
    if ResearchManager.has_research(GameManager.Team.PLAYER, "weather_alert"):
        warning_time = WARNING_TIME_RESEARCH

    _warning_active = true
    weather_warning.emit(warning_time)

    await get_tree().create_timer(warning_time).timeout
    _start_snowstorm()

func _start_snowstorm():
    _current_event = EventType.SNOWSTORM
    _event_active = true
    _warning_active = false
    snowstorm_started.emit()

    await get_tree().create_timer(SNOWSTORM_DURATION).timeout
    _end_snowstorm()

func _end_snowstorm():
    _current_event = EventType.NONE
    _event_active = false
    snowstorm_ended.emit()
    _schedule_next_event()

func is_snowstorm_active() -> bool:
    return _current_event == EventType.SNOWSTORM and _event_active

func get_vision_multiplier() -> float:
    if is_snowstorm_active():
        return 0.5
    return 1.0
```

---

## 7. Phase 6: Tech Tree Overhaul

### 7.1 Binary Branch System

The tech tree is restructured into **mutually exclusive branches**. At each tier, choosing one path **permanently locks** the other.

**Tier 1 (Match Start — Choose 1):**

| Path A: Deep Delve | Path B: Surface War |
|-------------------|---------------------|
| Miners can access layers 5–7 immediately | Fighters +15% speed and damage on surface |
| Miners +10% underground movement speed | Miners capped at layer 4 |
| | Towers gain +20% range |

**Tier 2 (Requires Tier 1 — Choose 1):**

If you chose **Deep Delve**:
| Path A1: Ore Sonar | Path A2: Reinforced Pack |
|-------------------|--------------------------|
| Scan reveals ore in 12-cell radius, 40s cooldown | Miners +20 carry, +10 HP |
| Can detect Fresh Ore from lava | Miners immune to cave-in push |

If you chose **Surface War**:
| Path B1: Longbow | Path B2: Rapid Fire |
|-------------------|---------------------|
| Archers +25 range | All fighters +20% attack speed |
| Archers can shoot into fog (blind fire) | Swordsmen gain +10% movement speed |

**Tier 3 (Requires Tier 2 — Choose 1):**

If you chose **A1 or A2**:
| Path A→X: Crystal Forge | Path A→Y: Earth Shield |
|--------------------------|------------------------|
| Wizards +40% damage | All units +15% HP |
| Fireballs leave burning ground (5 DPS for 3s) | Buildings +1000 HP |

If you chose **B1 or B2**:
| Path B→X: Siege Master | Path B→Y: Guerrilla |
|------------------------|---------------------|
| Swordsmen +30% damage vs buildings | Units +20% speed when no allies within 6 cells |
| Towers cost -50% | Miners can place traps (50 damage to enemies) |

### 7.2 Tech Tree UI

- Research panel shows a **diverging tree** with locked branches grayed out
- Once a choice is made, the other branch fades and becomes unclickable
- A "Respec" option costs 500g and resets all tech choices (one-time use per match)
- Hovering a locked branch shows what it would have done (for learning)

### 7.3 Implementation

```gdscript
# scripts/autoload/research_manager.gd
var _tech_branches: Dictionary = {}  # team -> { "tier1": "deep_delve", "tier2": "ore_sonar", ... }
var _locked_branches: Dictionary = {}  # team -> ["surface_war", "reinforced_pack", ...]

func choose_branch(team: GameManager.Team, tier: int, branch_id: String) -> bool:
    if _tech_branches[team].has(tier):
        return false  # Already chose this tier

    _tech_branches[team][tier] = branch_id

    # Lock the alternative
    var alternative = Constants.BRANCH_ALTERNATIVES[branch_id]
    _locked_branches[team].append(alternative)

    branch_chosen.emit(team, tier, branch_id)
    return true

func has_branch(team: GameManager.Team, branch_id: String) -> bool:
    for tier in _tech_branches[team]:
        if _tech_branches[team][tier] == branch_id:
            return true
    return false
```

---

## 8. Phase 7: UI & Menu Updates

### 8.1 Main Menu Flow

```
[Title Screen]
    ↓
[Difficulty Select] (Easy / Normal / Hard / Nightmare / Godly)
    ↓
[Faction Select] (Arcane / Brute / Industrial)
    ↓
[Play] → Loads main.tscn
```

### 8.2 Faction Select Screen

- Three large vertical cards (left to right: Arcane, Brute, Industrial)
- Each card shows:
  - Faction icon (large, centered)
  - Faction name
  - One-line description
  - Key stat highlights (3 bullet points)
  - "Select" button at bottom
- Selected card gets a gold border and glow
- Background: dark, with subtle faction-themed particles (purple sparks for Arcane, red embers for Brute, yellow steam for Industrial)

### 8.3 In-Game HUD Updates

**Top Bar:**
- Add faction icon next to team color indicator
- Add "Enemy Faction: ???" until scouted, then shows icon

**Bottom Bar:**
- Add "Build" button (opens radial menu)
- Radial menu options: Lantern / Tower / Wall
- Cost shown next to each option
- Grayed out if unaffordable or at max count

**New Alerts:**
- Weather warning banner (top center, red flashing, 15s countdown)
- Lava warning banner (bottom center, orange flashing, countdown)
- Faction identified popup (when scout reaches enemy base)

### 8.4 New Sprites Required

See the visual mockup for full sprite specifications. Summary:

| Sprite | Size | Purpose |
|--------|------|---------|
| lantern_t1.png | 32×48 | Surface lantern tier 1 |
| lantern_t2.png | 32×56 | Surface lantern tier 2 |
| lantern_t3.png | 40×64 | Surface lantern tier 3 |
| lantern_underground.png | 24×32 | Underground lantern |
| faction_arcane.png | 64×64 | Menu icon |
| faction_brute.png | 64×64 | Menu icon |
| faction_industrial.png | 64×64 | Menu icon |
| tower_player.png | 48×72 | Sentry tower |
| tower_enemy.png | 48×72 | Sentry tower |
| wall_player.png | 32×32 | Placeable wall |
| wall_enemy.png | 32×32 | Placeable wall |
| icon_snowstorm.png | 32×32 | Weather UI |
| icon_lava.png | 32×32 | Lava UI |
| icon_weather_alert.png | 32×32 | Research icon |
| magma_rock.png | 32×32 | Post-lava terrain |
| fresh_ore.png | 32×32 | High-value ore |
| fog_overlay.png | 32×32 | Fog tile texture |

---

## 9. Phase 8: AI Controller Refactor

> **Current status:** `AIBeliefSystem` is **not yet implemented**. The current AI reads the scene tree directly (with fog-of-war gating mostly in `unit.gd` / `unit_vision_targeting.gd`) and its smart behaviors live in `scripts/controllers/ai_controller.gd` plus `scripts/controllers/ai_smart_behaviors.gd`. The design below describes the intended future autoload.

### 9.1 AIBeliefSystem

New autoload that tracks what the AI knows vs. what is true.

```gdscript
# scripts/autoload/ai_belief_system.gd
extends Node

# Belief maps: what the AI thinks the map looks like
var _believed_cells: Dictionary = {}  # team -> Array[Array[CellType]]
var _believed_units: Dictionary = {}  # team -> Array[UnitBelief]
var _believed_faction: Dictionary = {}  # team -> String ("unknown" until scouted)

class UnitBelief:
    var unit_id: String
    var last_seen_position: Vector2
    var last_seen_time: float
    var estimated_hp: int
    var confidence: float  # 0.0–1.0, decays over time

func update_belief_from_vision(team: GameManager.Team):
    # Called every frame after vision update
    # For each cell the team can see, update belief to match reality
    # For cells not seen, belief remains unchanged (stale intel)
    pass

func get_believed_enemy_army(team: GameManager.Team) -> Dictionary:
    # Returns estimated count of each enemy unit type
    # Based on last seen + economic inference
    pass

func infer_enemy_faction(team: GameManager.Team) -> String:
    # Based on observed unit composition and behavior
    # "arcane" if many wizards early
    # "brute" if swordsmen are unusually tanky
    # "industrial" if many miners and cheap units
    pass
```

### 9.2 AI Behavior Updates

**Scouting:**
- AI must now send scouts to identify enemy faction and tech choices
- Scout priority: 1 swordsman sent to enemy base at 1:00 mark
- If scout dies, send another after 30s

**Lantern Placement:**
- AI places lanterns at optimal defensive positions
- Algorithm: maximize coverage of base + mine entrance
- Prioritize T1 lantern early (200g), upgrade to T2 when economy allows

**Weather Response:**
- When snowstorm warning triggers, recall all surface miners to lantern radius
- When lava warning triggers, evacuate bottom 2 layers
- AI uses the same warning time as player (no cheating)

**Faction-Specific AI:**

| Faction | AI Strategy |
|---------|-------------|
| Arcane | Rush wizards, use blink for harassment, tech Crystal Forge |
| Brute | Mass swordsmen, push mid-game, tech Siege Master |
| Industrial | Fast expand, many miners, swarm late, tech Guerrilla |

---

## Appendix A: Data Structures

### A.1 Vision Source

```gdscript
class_name VisionSource
extends RefCounted

var position: Vector2
var vision_radius: int
var team: GameManager.Team
var is_structure: bool = false
```

### A.2 Structure Data

```gdscript
class_name StructureData
extends Resource

@export var structure_id: String
@export var display_name: String
@export var cost: int
@export var build_time: float
@export var hp: int
@export var vision_radius: int
@export var can_attack: bool = false
@export var attack_range: int = 0
@export var attack_damage: int = 0
@export var attack_cooldown: float = 1.0
```

### A.3 Faction Data

See Phase 2 for full `FactionData` resource definition.

---

## Appendix B: Constants Reference

### B.1 New Constants

```gdscript
# In constants.gd

# Fog of War
const VISION_MINER_SURFACE: int = 6
const VISION_MINER_UNDERGROUND: int = 4
const VISION_SWORDSMAN: int = 8
const VISION_ARCHER: int = 12
const VISION_WIZARD: int = 10
const VISION_DRAGON: int = 14
const VISION_BUILDING: int = 10

# Lanterns
const LANTERN_T1_COST: int = 200
const LANTERN_T2_COST: int = 600
const LANTERN_T3_COST: int = 1000
const LANTERN_T1_VISION: int = 8
const LANTERN_T2_VISION: int = 14
const LANTERN_T3_VISION: int = 22
const LANTERN_HP: int = 500
const LANTERN_MAX_COUNT: int = 3
const LANTERN_MIN_DISTANCE: int = 3

const UNDERGROUND_LANTERN_COST: int = 100
const UNDERGROUND_LANTERN_VISION: int = 10
const UNDERGROUND_LANTERN_HP: int = 200
const UNDERGROUND_LANTERN_MAX_COUNT: int = 5
const UNDERGROUND_LANTERN_MIN_DISTANCE: int = 2

# Structures
const TOWER_COST: int = 300
const TOWER_HP: int = 800
const TOWER_RANGE: int = 18
const TOWER_DAMAGE: int = 12
const TOWER_COOLDOWN: float = 1.2
const TOWER_MAX_COUNT: int = 2

const WALL_COST: int = 50
const WALL_HP: int = 400
const WALL_MAX_COUNT: int = 10
const WALL_MAX_COUNT_INDUSTRIAL: int = 15

# Lava
const LAVA_MIN_INTERVAL: float = 90.0
const LAVA_MAX_INTERVAL: float = 120.0
const LAVA_WARNING_TIME: float = 5.0
const LAVA_WARNING_TIME_RESEARCH: float = 15.0
const LAVA_DURATION: float = 20.0
const LAVA_LAYERS_MIN: int = 1
const LAVA_LAYERS_MAX: int = 2
const MAGMA_ROCK_HP: int = 150
const MAGMA_ORE_CHANCE: float = 0.4
const MAGMA_ORE_MIN: int = 100
const MAGMA_ORE_MAX: int = 200

# Weather
const SNOWSTORM_MIN_INTERVAL: float = 60.0
const SNOWSTORM_MAX_INTERVAL: float = 90.0
const SNOWSTORM_DURATION: float = 15.0
const SNOWSTORM_WARNING_TIME: float = 5.0
const SNOWSTORM_WARNING_TIME_RESEARCH: float = 15.0
const SNOWSTORM_VISION_MULT: float = 0.5
const SNOWSTORM_SPEED_MULT: float = 0.9
const SNOWSTORM_DAMAGE_PER_SEC: float = 2.0

# Cave-ins
const CAVEIN_MIN_INTERVAL: float = 45.0
const CAVEIN_MAX_INTERVAL: float = 75.0
const CAVEIN_AREA_SIZE: int = 3  # 3x3
const CAVEIN_DAMAGE: int = 50
const CAVEIN_ROCK_DURATION: float = 10.0

# Research
const WEATHER_ALERT_COST: int = 2500
const WEATHER_ALERT_TIME: float = 60.0
const BRANCH_RESPEC_COST: int = 500
```

---

*End of Implementation Guide*
