# Frost Mines — Complete Implementation Guide

**Version:** 1.0  
**Engine:** Godot 4.3+  
**Language:** GDScript  
**Genre:** 2D RTS / Mining / Base Defense  
**Theme:** Post-apocalyptic frozen wasteland (Frostpunk-inspired)  
**Session Length:** 8–15 minutes per match

---

## Table of Contents

1. [Visual Style Guide](#1-visual-style-guide)
2. [Game Design Overview](#2-game-design-overview)
3. [Component 1: Unit System & State Machine](#3-component-1-unit-system--state-machine)
4. [Component 2: Training Queue & Economy](#4-component-2-training-queue--economy)
5. [Component 3: Underground System & Pathfinding](#5-component-3-underground-system--pathfinding)
6. [UI/HUD Specifications](#6-uihud-specifications)
7. [Asset Specifications](#7-asset-specifications)
8. [Complete Constants & Balance Sheet](#8-complete-constants--balance-sheet)
9. [Scene Tree Reference](#9-scene-tree-reference)
10. [Implementation Roadmap](#10-implementation-roadmap)

---

## 1. Visual Style Guide

### 1.1 Color Palette

#### Primary Colors
| Name | Hex | Usage |
|------|-----|-------|
| Snow White | `#e2e8f0` | Primary text, ground surface, snow particles |
| Steel Gray | `#334155` | Buildings, UI panels, borders |
| Deep Night | `#0f172a` | Backgrounds, underground void, UI base |

#### Accent Colors
| Name | Hex | Usage |
|------|-----|-------|
| Amber Light | `#fbbf24` | Windows, lanterns, warning stripes, coin |
| Frost Blue | `#3b82f6` | Player units, ally highlights, crystal glow |
| Warning Red | `#ef4444` | Enemy units, damage, critical HP, alerts |
| Survival Green | `#22c55e` | Player building HP, positive feedback |
| Caution Orange | `#f59e0b` | Wall HP, medium threat, upgrade buttons |

#### Underground Layer Colors
| Layer | Background | Tile Fill | Accent |
|-------|-----------|-----------|--------|
| 1–2 | `#1e293b` | `#334155` | Ice crystals `#3b82f6` |
| 3–4 | `#374151` | `#4b5563` | Coal seams `#111827` |
| 5–6 | `#4b5563` | `#6b7280` | Magma cracks `#ea580c` |
| 7 | `#581c87` | `#7c3aed` | Crystal glow `#a855f7` |

### 1.2 Typography

| Role | Font | Size | Weight | Color |
|------|------|------|--------|-------|
| Headlines | System sans-serif | 16–18px | Bold | `#e2e8f0` |
| Body | System sans-serif | 13px | Regular | `#cbd5e1` |
| Captions | System sans-serif | 11px | Regular | `#64748b` |
| Stats/Numbers | System sans-serif | 14px | Bold | `#e2e8f0` |
| Damage Popups | System sans-serif | 10px | Bold | `#ef4444` / `#22c55e` |

Use `font-variant-numeric: tabular-nums` for all numeric displays.

### 1.3 Atmosphere & Effects

**Surface:**
- Falling snow particles (white, 1–2px, slow drift, 30% opacity)
- Wind gusts (horizontal particle streaks, occasional)
- Warm amber glow from building windows (`#fbbf24`, bloom filter)
- Ground: white/gray with subtle texture lines

**Underground:**
- Dust motes in light beams (golden, slow fall)
- Crystal glow pulses (Layer 7, `#a855f7`, sine wave opacity)
- Magma flicker (Layer 5–6, `#ea580c`, random intensity)
- Lantern light from miners (`#fbbf24`, 40px radius, soft falloff)

---

## 2. Game Design Overview

### 2.1 Premise

*Frost Mines* combines the **macro-economy and single-queue training** of *Stick War: Legacy* with the **layered underground exploration and destructible terrain** of *SteamWorld Dig*. Players manage a surface base and an underground mining operation simultaneously. Coin mined underground funds the training of surface fighters who march across an open field to destroy the enemy building.

### 2.2 Surface Layout (Left → Right)

```
[Player Building] → [Player Mine Entry] → [Open Field / Combat] → [Enemy Mine Entry] → [Enemy Building]
```

| Element | X Position | Width | Height | Notes |
|---------|-----------|-------|--------|-------|
| Player Building | 20px | 120px | 160px | Anchor bottom-left |
| Player Mine Entry | 200px | 60px | 80px | Elevator shaft visual |
| Open Field | 280px – 1640px | 1360px | Full | Combat zone |
| Enemy Mine Entry | 1720px | 60px | 80px | Mirror of player |
| Enemy Building | 1800px | 120px | 160px | Anchor bottom-right |

### 2.3 Underground Layers

```
Layer 1 (Surface-1)  ← Miner L1 accessible
Layer 2              ← Miner L1 accessible
─────────────────────
Layer 3              ← Miner L2 required
Layer 4              ← Miner L2 required
─────────────────────
Layer 5              ← Miner L3 required
Layer 6              ← Miner L3 required
Layer 7 (Bottom)     ← Miner L3 required
```

| Layer | Depth | Miner Level | Coin/Block | Tile HP | Theme |
|-------|-------|-------------|------------|---------|-------|
| 1 | 0 to -100 | 1 | 5–10 | 50 | Frost soil, ice crystals |
| 2 | -100 to -200 | 1 | 8–15 | 50 | Packed ice, frozen roots |
| 3 | -200 to -300 | 2 | 12–20 | 75 | Dark rock, coal seams |
| 4 | -300 to -400 | 2 | 15–25 | 75 | Iron ore, rusted debris |
| 5 | -400 to -500 | 3 | 20–35 | 100 | Deep granite, magma cracks |
| 6 | -500 to -600 | 3 | 25–40 | 100 | Obsidian, ancient ruins |
| 7 | -600 to -700 | 3 | 30–50 | 100 | Crystalline cavern, glow minerals |

### 2.4 The Central Wall

A thick vertical wall separates the player's mine from the enemy's.

| Property | Value |
|----------|-------|
| Position | Center X of underground map |
| Width | 80px (2.5 tiles) |
| Height | Full depth of all 7 layers |
| HP | 2000 |
| Damage/Sec | 10 per miner |
| Breakable | Either side, but only when actively targeted |
| Visual | Reinforced steel plates with frost, warning stripes |

**Behavior:** The wall does **not** auto-target. The player must click the wall and select "Breach" to send miners to break it. Once broken, it becomes empty space. Does not regenerate.

### 2.5 Unit Types

#### Miner (3 Levels)

| Property | L1 | L2 | L3 |
|----------|----|----|-----|
| Cost | 50 coin | — | — |
| Train Time | 3s | — | — |
| HP | 50 | 75 | 100 |
| Speed | 60 px/s | 70 px/s | 80 px/s |
| Mine DPS | 10 | 15 | 25 |
| Carry Capacity | 20 | 30 | 50 |
| Mining Rate | 10 coin/s | 15 coin/s | 25 coin/s |
| Max Layer | 2 | 4 | 7 |

#### Swordsman

| Property | Value |
|----------|-------|
| Cost | 100 coin |
| Train Time | 5s |
| HP | 150 |
| DPS | 15 |
| Range | 30px (melee) |
| Speed | 80 px/s |

#### Archer

| Property | Value |
|----------|-------|
| Cost | 150 coin |
| Train Time | 6s |
| HP | 80 |
| DPS | 12 |
| Range | 150px |
| Speed | 70 px/s |
| Projectile Speed | 300 px/s |

#### Wizard

| Property | Value |
|----------|-------|
| Cost | 250 coin |
| Train Time | 10s |
| HP | 60 |
| DPS | 25 |
| Range | 120px |
| Speed | 50 px/s |
| AOE Radius | 40px |

### 2.6 Buildings

| Property | Player Building | Enemy Building |
|----------|----------------|----------------|
| HP | 5000 | 5000 |
| Size | 120×160px | 120×160px |
| Visual | Industrial bunker, warm amber windows, smokestack | Dark fortress, red warning lights, spikes |

### 2.7 Economy

| Source | Rate |
|--------|------|
| Starting Coin | 150 (both sides) |
| Mining | Variable by layer |
| Killing Enemy Miners | 50% of carried cargo |

| Sink | Cost |
|------|------|
| Train Miner | 50 |
| Train Swordsman | 100 |
| Train Archer | 150 |
| Train Wizard | 250 |
| Upgrade Miners L1→L2 | 500 |
| Upgrade Miners L2→L3 | 1500 |

### 2.8 Unit Caps & Queue

- Max units per player: **100**
- Max training queue: **5 units**
- Queue processing: **FIFO** (single queue, one at a time)
- Cancel queued unit: **100% refund**

### 2.9 Fighter Rules

1. **Cannot enter enemy mine.** Walk past Enemy Mine Entry to attack Enemy Building.
2. **Can garrison own mine.** Select fighters → click Mine Entry → they patrol underground.
3. **Underground combat:** Garrisoned fighters engage enemy units on player's side.
4. **Auto-attack priority:** Enemy fighters → Enemy building → Enemy miners (on player side only).
5. **No retreat.** Fight until death.

### 2.10 Win Conditions

- **Victory:** Enemy Building HP reaches 0.
- **Defeat:** Player Building HP reaches 0.

---

## 3. Component 1: Unit System & State Machine

This component handles all unit behavior — movement, mining, combat, death, and AI decision-making. It is the heart of the game.

### 3.1 File Structure

```
res://
├── scripts/
│   ├── state_machines/
│   │   ├── UnitStateMachine.gd      # Base state machine
│   │   ├── MinerStates.gd           # Miner-specific states
│   │   └── FighterStates.gd         # Fighter-specific states
│   ├── units/
│   │   ├── UnitBase.gd              # Shared unit logic
│   │   ├── Miner.gd                 # Miner class
│   │   ├── Swordsman.gd             # Swordsman class
│   │   ├── Archer.gd                # Archer class
│   │   └── Wizard.gd                # Wizard class
│   └── ai/
│       └── UnitAI.gd                # Targeting and pathfinding helpers
```

### 3.2 UnitBase.gd — Shared Unit Logic

```gdscript
# scripts/units/UnitBase.gd
class_name UnitBase
extends CharacterBody2D

signal died(unit: UnitBase)
signal health_changed(current: float, maximum: float)

@export var unit_type: String = "miner"
@export var side: String = "player"  # "player" or "enemy"
@export var max_hp: float = 100.0
@export var speed: float = 60.0
@export var attack_range: float = 0.0
@export var dps: float = 0.0
@export var attack_cooldown: float = 1.0

var current_hp: float = 100.0
var is_dead: bool = false
var attack_timer: float = 0.0
var target: Node2D = null
var target_position: Vector2 = Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite2D
@onready var health_bar = $HealthBar
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var selection_ring = $SelectionRing
@onready var attack_range_area: Area2D = $AttackRange

func _ready():
    current_hp = max_hp
    health_changed.emit(current_hp, max_hp)
    if attack_range_area:
        attack_range_area.body_entered.connect(_on_attack_range_body_entered)

func take_damage(amount: float):
    if is_dead:
        return
    current_hp -= amount
    health_changed.emit(current_hp, max_hp)
    _flash_damage()
    if current_hp <= 0:
        _die()

func _flash_damage():
    if sprite and sprite.material:
        sprite.material.set_shader_parameter("flash_amount", 1.0)
        await get_tree().create_timer(0.1).timeout
        if sprite and sprite.material:
            sprite.material.set_shader_parameter("flash_amount", 0.0)

func _die():
    is_dead = true
    if anim_player:
        anim_player.play("death")
        await anim_player.animation_finished
    died.emit(self)
    queue_free()

func heal(amount: float):
    current_hp = min(current_hp + amount, max_hp)
    health_changed.emit(current_hp, max_hp)

func set_selected(selected: bool):
    if selection_ring:
        selection_ring.visible = selected

func _on_attack_range_body_entered(body: Node2D):
    if body != self and body.has_method("take_damage") and _is_enemy(body):
        target = body

func _is_enemy(other: Node2D) -> bool:
    if other.has_method("get_side"):
        return other.get_side() != side
    return false

func get_side() -> String:
    return side

func can_attack() -> bool:
    return attack_timer <= 0.0 and target != null and not target.is_dead

func _physics_process(delta: float):
    if attack_timer > 0:
        attack_timer -= delta
    if target and is_instance_valid(target) and target.is_dead:
        target = null
```

### 3.3 UnitStateMachine.gd — Base State Machine

```gdscript
# scripts/state_machines/UnitStateMachine.gd
class_name UnitStateMachine
extends Node

enum State {
    IDLE,
    MOVING,
    MINING,
    ATTACKING,
    RETURNING,
    DEAD
}

var current_state: State = State.IDLE
var unit: UnitBase
var state_data: Dictionary = {}

func _ready():
    unit = get_parent()

func _physics_process(delta: float):
    if unit.is_dead:
        return
    match current_state:
        State.IDLE:
            _process_idle(delta)
        State.MOVING:
            _process_moving(delta)
        State.MINING:
            _process_mining(delta)
        State.ATTACKING:
            _process_attacking(delta)
        State.RETURNING:
            _process_returning(delta)

func transition_to(new_state: State, data: Dictionary = {}):
    _exit_state(current_state)
    current_state = new_state
    state_data = data
    _enter_state(new_state)

func _enter_state(state: State):
    match state:
        State.IDLE:
            if unit.anim_player:
                unit.anim_player.play("idle")
        State.MOVING:
            if unit.anim_player:
                unit.anim_player.play("walk")
        State.MINING:
            if unit.anim_player:
                unit.anim_player.play("mine")
        State.ATTACKING:
            if unit.anim_player:
                unit.anim_player.play("attack")
        State.RETURNING:
            if unit.anim_player:
                unit.anim_player.play("walk")

func _exit_state(state: State):
    pass

func _process_idle(delta: float):
    pass

func _process_moving(delta: float):
    var target_pos = state_data.get("target_position", Vector2.ZERO)
    if target_pos == Vector2.ZERO:
        transition_to(State.IDLE)
        return

    var direction = (target_pos - unit.global_position).normalized()
    unit.velocity = direction * unit.speed
    unit.move_and_slide()

    # Flip sprite based on direction
    if direction.x != 0 and unit.sprite:
        unit.sprite.flip_h = direction.x < 0

    if unit.global_position.distance_to(target_pos) < 5.0:
        unit.velocity = Vector2.ZERO
        transition_to(State.IDLE)

func _process_mining(delta: float):
    pass

func _process_attacking(delta: float):
    pass

func _process_returning(delta: float):
    var target_pos = state_data.get("target_position", Vector2.ZERO)
    if target_pos == Vector2.ZERO:
        transition_to(State.IDLE)
        return

    var direction = (target_pos - unit.global_position).normalized()
    unit.velocity = direction * unit.speed
    unit.move_and_slide()

    if direction.x != 0 and unit.sprite:
        unit.sprite.flip_h = direction.x < 0

    if unit.global_position.distance_to(target_pos) < 5.0:
        unit.velocity = Vector2.ZERO
        transition_to(State.IDLE)
```

### 3.4 Miner.gd + MinerStates.gd — Mining Logic

```gdscript
# scripts/units/Miner.gd
class_name Miner
extends UnitBase

@export var miner_level: int = 1
@export var mine_dps: float = 10.0
@export var carry_capacity: float = 20.0
@export var max_accessible_layer: int = 1

var cargo: float = 0.0
var current_tile = null
var mine_timer: float = 0.0

func _ready():
    super._ready()
    add_to_group("miners")
    add_to_group(side + "_miners")

func get_carry_percent() -> float:
    return cargo / carry_capacity

func is_full() -> bool:
    return cargo >= carry_capacity
```

```gdscript
# scripts/state_machines/MinerStates.gd
class_name MinerStates
extends UnitStateMachine

@onready var pathfinder = get_node_or_null("/root/UndergroundWorld/Pathfinder")
@onready var underground = get_node_or_null("/root/UndergroundWorld")
@onready var game_state = get_node_or_null("/root/GameState")

var mine_target = null
var mine_progress: float = 0.0

func _process_idle(delta: float):
    if unit.is_full():
        _start_returning()
        return

    # Find deepest accessible unmined tile
    var max_layer = unit.miner_level
    if unit.miner_level == 1:
        max_layer = 1
    elif unit.miner_level == 2:
        max_layer = 3
    else:
        max_layer = 6

    var candidate_tiles = underground.get_tiles_by_side_and_layer(unit.side, max_layer)
    var unmined = candidate_tiles.filter(func(t): return not t.mined)

    if unmined.is_empty():
        # No tiles available, try shallower layers
        for layer in range(max_layer, -1, -1):
            candidate_tiles = underground.get_tiles_by_side_and_layer(unit.side, layer)
            unmined = candidate_tiles.filter(func(t): return not t.mined)
            if not unmined.is_empty():
                break

    if unmined.is_empty():
        # Nothing to mine, return to surface
        _start_returning()
        return

    # Pick closest unmined tile
    mine_target = unmined.reduce(func(closest, tile):
        var dist_to_unit = unit.global_position.distance_to(tile.global_position)
        var dist_to_closest = unit.global_position.distance_to(closest.global_position)
        return tile if dist_to_unit < dist_to_closest else closest
    )

    transition_to(State.MOVING, {"target_position": mine_target.global_position})

func _process_mining(delta: float):
    if mine_target == null or not is_instance_valid(mine_target) or mine_target.mined:
        mine_target = null
        transition_to(State.IDLE)
        return

    mine_progress += delta * unit.mine_dps
    if mine_progress >= mine_target.hp:
        # Tile destroyed
        mine_target.mine()
        var coin_mined = mine_target.coin_value
        unit.cargo = min(unit.cargo + coin_mined, unit.carry_capacity)
        mine_target = null
        mine_progress = 0.0

        if unit.is_full():
            _start_returning()
        else:
            transition_to(State.IDLE)

func _start_returning():
    var mine_entry = underground.get_mine_entry(unit.side)
    if mine_entry:
        transition_to(State.RETURNING, {"target_position": mine_entry.global_position})

func _process_returning(delta: float):
    super._process_returning(delta)
    # When returning, check if we reached the mine entry
    if current_state == State.IDLE and unit.is_full():
        # Deposit coin
        if game_state:
            game_state.add_coin(unit.cargo, unit.side)
        unit.cargo = 0.0
        transition_to(State.IDLE)

func _on_moving_reached():
    if mine_target and is_instance_valid(mine_target):
        transition_to(State.MINING)
    else:
        transition_to(State.IDLE)
```

### 3.5 FighterStates.gd — Combat Logic

```gdscript
# scripts/state_machines/FighterStates.gd
class_name FighterStates
extends UnitStateMachine

@onready var game_state = get_node_or_null("/root/GameState")

var garrisoned: bool = false

func _process_idle(delta: float):
    if garrisoned:
        _process_garrison(delta)
        return

    # Find target
    var enemies = _get_enemies_in_range()
    if not enemies.is_empty():
        unit.target = enemies[0]
        transition_to(State.ATTACKING)
        return

    # No enemies in range, move toward enemy building
    var enemy_building = game_state.get_enemy_building(unit.side)
    if enemy_building:
        transition_to(State.MOVING, {"target_position": enemy_building.global_position})

func _process_attacking(delta: float):
    if unit.target == null or not is_instance_valid(unit.target) or unit.target.is_dead:
        unit.target = null
        transition_to(State.IDLE)
        return

    var dist = unit.global_position.distance_to(unit.target.global_position)
    if dist > unit.attack_range:
        transition_to(State.MOVING, {"target_position": unit.target.global_position})
        return

    if unit.can_attack():
        _perform_attack()

    # Face target
    var dir = (unit.target.global_position - unit.global_position).normalized()
    if dir.x != 0 and unit.sprite:
        unit.sprite.flip_h = dir.x < 0

func _perform_attack():
    unit.attack_timer = unit.attack_cooldown
    if unit.anim_player:
        unit.anim_player.play("attack")

    if unit.unit_type == "archer" or unit.unit_type == "wizard":
        _spawn_projectile()
    else:
        # Melee — direct damage
        if unit.target and is_instance_valid(unit.target):
            unit.target.take_damage(unit.dps)
            _show_damage_popup(unit.dps, unit.target.global_position)

func _spawn_projectile():
    var proj_scene = preload("res://scenes/effects/Projectile.tscn")
    var proj = proj_scene.instantiate()
    proj.global_position = unit.global_position
    proj.target = unit.target
    proj.damage = unit.dps
    proj.speed = 300.0 if unit.unit_type == "archer" else 250.0
    proj.is_aoe = unit.unit_type == "wizard"
    proj.aoe_radius = 40.0 if unit.unit_type == "wizard" else 0.0
    get_tree().current_scene.add_child(proj)

func _get_enemies_in_range() -> Array:
    var enemies = []
    var query = PhysicsShapeQueryParameters2D.new()
    var circle = CircleShape2D.new()
    circle.radius = unit.attack_range
    query.shape = circle
    query.transform = Transform2D(0, unit.global_position)
    query.collision_mask = 2  # Enemy layer

    var results = unit.get_world_2d().direct_space_state.intersect_shape(query)
    for result in results:
        var collider = result.collider
        if collider != unit and collider.has_method("get_side") and collider.get_side() != unit.side:
            enemies.append(collider)

    # Sort by distance
    enemies.sort_custom(func(a, b):
        return unit.global_position.distance_to(a.global_position) < unit.global_position.distance_to(b.global_position)
    )
    return enemies

func _show_damage_popup(amount: float, pos: Vector2):
    var popup = preload("res://scenes/effects/DamagePopup.tscn").instantiate()
    popup.text = "-" + str(int(amount))
    popup.global_position = pos + Vector2(0, -20)
    get_tree().current_scene.add_child(popup)

func _process_garrison(delta: float):
    # When garrisoned underground, patrol near mine entry
    var mine_entry = underground.get_mine_entry(unit.side)
    if mine_entry:
        var dist_to_entry = unit.global_position.distance_to(mine_entry.global_position)
        if dist_to_entry > 100:
            transition_to(State.MOVING, {"target_position": mine_entry.global_position + Vector2(randf_range(-50, 50), randf_range(-50, 50))})
        else:
            # Look for enemies on our side
            var enemies = _get_enemies_in_range()
            if not enemies.is_empty():
                unit.target = enemies[0]
                transition_to(State.ATTACKING)
```

### 3.6 Projectile.gd — Ranged Attacks

```gdscript
# scripts/effects/Projectile.gd
class_name Projectile
extends Area2D

var target: Node2D = null
var damage: float = 0.0
var speed: float = 300.0
var is_aoe: bool = false
var aoe_radius: float = 0.0
var direction: Vector2 = Vector2.ZERO

@onready var sprite = $Sprite2D

func _ready():
    body_entered.connect(_on_body_entered)
    if target:
        direction = (target.global_position - global_position).normalized()

func _physics_process(delta: float):
    if target and is_instance_valid(target) and not target.is_dead:
        direction = (target.global_position - global_position).normalized()

    global_position += direction * speed * delta

    # Rotate sprite to face direction
    if direction != Vector2.ZERO:
        sprite.rotation = direction.angle()

    # Despawn if too far from target or off-screen
    if target and global_position.distance_to(target.global_position) > 2000:
        queue_free()

func _on_body_entered(body: Node2D):
    if body.has_method("take_damage"):
        if is_aoe:
            _deal_aoe_damage()
        else:
            body.take_damage(damage)
        _spawn_impact()
        queue_free()

func _deal_aoe_damage():
    var query = PhysicsShapeQueryParameters2D.new()
    var circle = CircleShape2D.new()
    circle.radius = aoe_radius
    query.shape = circle
    query.transform = Transform2D(0, global_position)
    query.collision_mask = 2

    var results = get_world_2d().direct_space_state.intersect_shape(query)
    for result in results:
        var collider = result.collider
        if collider.has_method("take_damage"):
            collider.take_damage(damage)

func _spawn_impact():
    var impact = preload("res://scenes/effects/Impact.tscn").instantiate()
    impact.global_position = global_position
    get_tree().current_scene.add_child(impact)
```

---

## 4. Component 2: Training Queue & Economy

This component manages the single-queue training system (like Stick War: Legacy), coin economy, and unit spawning. It connects the player's decisions to the game world.

### 4.1 File Structure

```
res://
├── scripts/
│   ├── economy/
│   │   ├── GameState.gd             # Global state (coin, HP, pause)
│   │   ├── TrainingQueue.gd         # Queue manager
│   │   └── EconomyManager.gd        # Income/upgrade logic
│   └── ui/
│       ├── TrainingQueuePanel.gd    # UI controller
│       └── UnitButton.gd            # Train button behavior
├── scenes/
│   ├── ui/
│   │   ├── TrainingQueuePanel.tscn
│   │   ├── UnitButton.tscn
│   │   └── TopBarHUD.tscn
│   └── buildings/
│       ├── PlayerBuilding.tscn
│       └── EnemyBuilding.tscn
```

### 4.2 GameState.gd — Global Game State (Autoload)

```gdscript
# scripts/economy/GameState.gd
extends Node

signal coin_changed(side: String, amount: int)
signal building_hp_changed(side: String, hp: float)
signal unit_count_changed(side: String, count: int)
signal game_over(winner: String)
signal miner_level_changed(side: String, level: int)

# Player state
var player_coin: int = 150
var player_building_hp: float = 5000.0
var player_unit_count: int = 0
var player_miner_level: int = 1

# Enemy state
var enemy_coin: int = 150
var enemy_building_hp: float = 5000.0
var enemy_unit_count: int = 0
var enemy_miner_level: int = 1

var is_paused: bool = false
var game_ended: bool = false

func _ready():
	player_building_hp = Constants.PLAYER_BUILDING_HP
	enemy_building_hp = Constants.ENEMY_BUILDING_HP

func add_coin(amount: float, side: String):
	if side == "player":
		player_coin += int(amount)
		coin_changed.emit("player", player_coin)
	else:
		enemy_coin += int(amount)
		coin_changed.emit("enemy", enemy_coin)

func spend_coin(amount: int, side: String) -> bool:
	if side == "player":
		if player_coin >= amount:
			player_coin -= amount
			coin_changed.emit("player", player_coin)
			return true
	else:
		if enemy_coin >= amount:
			enemy_coin -= amount
			coin_changed.emit("enemy", enemy_coin)
			return true
	return false

func damage_building(amount: float, side: String):
	if game_ended:
		return
	if side == "player":
		player_building_hp -= amount
		building_hp_changed.emit("player", player_building_hp)
		if player_building_hp <= 0:
			_end_game("enemy")
	else:
		enemy_building_hp -= amount
		building_hp_changed.emit("enemy", enemy_building_hp)
		if enemy_building_hp <= 0:
			_end_game("player")

func add_unit_count(side: String):
	if side == "player":
		player_unit_count += 1
		unit_count_changed.emit("player", player_unit_count)
	else:
		enemy_unit_count += 1
		unit_count_changed.emit("enemy", enemy_unit_count)

func remove_unit_count(side: String):
	if side == "player":
		player_unit_count = max(0, player_unit_count - 1)
		unit_count_changed.emit("player", player_unit_count)
	else:
		enemy_unit_count = max(0, enemy_unit_count - 1)
		unit_count_changed.emit("enemy", enemy_unit_count)

func upgrade_miners(side: String) -> bool:
	var current_level = player_miner_level if side == "player" else enemy_miner_level
	if current_level >= 3:
		return false

	var cost = Constants.MINER_UPGRADE_COSTS[current_level]
	if not spend_coin(cost, side):
		return false

	if side == "player":
		player_miner_level += 1
		miner_level_changed.emit("player", player_miner_level)
	else:
		enemy_miner_level += 1
		miner_level_changed.emit("enemy", enemy_miner_level)

	# Upgrade all existing miners
	var miners = get_tree().get_nodes_in_group(side + "_miners")
	for miner in miners:
		if miner is Miner:
			_apply_miner_upgrade(miner, current_level + 1)

	return true

func _apply_miner_upgrade(miner: Miner, new_level: int):
	miner.miner_level = new_level
	var stats = Constants.MINER_STATS[new_level]
	miner.max_hp = stats.hp
	miner.speed = stats.speed
	miner.mine_dps = stats.mine_dps
	miner.carry_capacity = stats.carry
	miner.max_accessible_layer = stats.max_layer

func _end_game(winner: String):
	game_ended = true
	game_over.emit(winner)

func get_enemy_building(my_side: String) -> Node2D:
	if my_side == "player":
		return get_node_or_null("/root/World/EnemyBuilding")
	else:
		return get_node_or_null("/root/World/PlayerBuilding")

func get_mine_entry(side: String) -> Node2D:
	if side == "player":
		return get_node_or_null("/root/World/PlayerMineEntry")
	else:
		return get_node_or_null("/root/World/EnemyMineEntry")
```

### 4.3 TrainingQueue.gd — Single-Queue System

```gdscript
# scripts/economy/TrainingQueue.gd
class_name TrainingQueue
extends Node

signal unit_trained(unit_type: String, side: String)
signal queue_updated(queue: Array[String], progress: float, current_type: String)
signal unit_cancelled(unit_type: String, refund: int)

@export var side: String = "player"
@export var max_queue_size: int = 5

var queue: Array[String] = []
var current_training: String = ""
var current_progress: float = 0.0
var is_training: bool = false

@onready var game_state = get_node_or_null("/root/GameState")
@onready var spawn_point = get_parent().get_node("SpawnPoint")

func _process(delta: float):
	if is_training and current_training != "":
		current_progress += delta
		var train_time = Constants.TRAIN_TIMES[current_training]
		queue_updated.emit(get_full_queue(), current_progress / train_time, current_training)

		if current_progress >= train_time:
			_complete_training()
	elif not queue.is_empty() and not is_training:
		_start_next()

func enqueue(unit_type: String) -> bool:
	var total = queue.size() + (1 if is_training else 0)
	if total >= max_queue_size:
		return false

	var cost = Constants.COSTS[unit_type]
	if not game_state.spend_coin(cost, side):
		return false

	if not is_training:
		current_training = unit_type
		current_progress = 0.0
		is_training = true
	else:
		queue.append(unit_type)

	queue_updated.emit(get_full_queue(), get_progress_percent(), current_training)
	return true

func cancel_at_index(index: int) -> bool:
	if index == 0 and is_training:
		# Cancel current training
		var refund = Constants.COSTS[current_training]
		game_state.add_coin(refund, side)
		unit_cancelled.emit(current_training, refund)

		if queue.is_empty():
			current_training = ""
			current_progress = 0.0
			is_training = false
		else:
			current_training = queue.pop_front()
			current_progress = 0.0

		queue_updated.emit(get_full_queue(), get_progress_percent(), current_training)
		return true

	elif index > 0 and index - 1 < queue.size():
		var unit_type = queue[index - 1]
		var refund = Constants.COSTS[unit_type]
		queue.remove_at(index - 1)
		game_state.add_coin(refund, side)
		unit_cancelled.emit(unit_type, refund)
		queue_updated.emit(get_full_queue(), get_progress_percent(), current_training)
		return true

	return false

func _start_next():
	if queue.is_empty():
		is_training = false
		current_training = ""
		current_progress = 0.0
		return

	current_training = queue.pop_front()
	current_progress = 0.0
	is_training = true

func _complete_training():
	_spawn_unit(current_training)
	unit_trained.emit(current_training, side)
	game_state.add_unit_count(side)

	current_progress = 0.0

	if queue.is_empty():
		is_training = false
		current_training = ""
	else:
		current_training = queue.pop_front()

	queue_updated.emit(get_full_queue(), 0.0, current_training)

func _spawn_unit(unit_type: String):
	var scene_path = "res://scenes/units/" + unit_type.capitalize() + ".tscn"
	var scene = load(scene_path)
	if scene == null:
		push_error("Could not load unit scene: " + scene_path)
		return

	var unit = scene.instantiate()
	unit.side = side
	unit.global_position = spawn_point.global_position

	# Apply miner level if miner
	if unit is Miner and side == "player":
		_apply_miner_upgrade(unit, game_state.player_miner_level)
	elif unit is Miner and side == "enemy":
		_apply_miner_upgrade(unit, game_state.enemy_miner_level)

	get_tree().current_scene.add_child(unit)

	# Connect death signal
	if unit.has_signal("died"):
		unit.died.connect(_on_unit_died)

func _on_unit_died(unit: UnitBase):
	game_state.remove_unit_count(unit.side)

func get_full_queue() -> Array[String]:
	var full: Array[String] = []
	if is_training and current_training != "":
		full.append(current_training)
	full.append_array(queue)
	return full

func get_progress_percent() -> float:
	if current_training == "" or not is_training:
		return 0.0
	return current_progress / Constants.TRAIN_TIMES[current_training]

func get_queue_size() -> int:
	return queue.size() + (1 if is_training else 0)

func is_full() -> bool:
	return get_queue_size() >= max_queue_size
```

### 4.4 TrainingQueuePanel.gd — UI Controller

```gdscript
# scripts/ui/TrainingQueuePanel.gd
class_name TrainingQueuePanel
extends Control

@onready var queue_container = $QueueContainer
@onready var progress_bar = $ProgressBar
@onready var current_label = $CurrentLabel

@export var training_queue: TrainingQueue

var queue_item_scene = preload("res://scenes/ui/QueueItem.tscn")

func _ready():
	if training_queue:
		training_queue.queue_updated.connect(_on_queue_updated)

func _on_queue_updated(queue: Array[String], progress: float, current_type: String):
	# Clear existing items
	for child in queue_container.get_children():
		child.queue_free()

	# Add current training item
	if current_type != "" and queue.size() > 0:
		var item = queue_item_scene.instantiate()
		item.setup(current_type, progress, true)
		item.cancelled.connect(_on_item_cancelled.bind(0))
		queue_container.add_child(item)

		progress_bar.value = progress * 100
		current_label.text = current_type.capitalize() + " — " + str(int(progress * 100)) + "%"
	else:
		progress_bar.value = 0
		current_label.text = "Queue Empty"

	# Add queued items
	for i in range(1, queue.size()):
		var item = queue_item_scene.instantiate()
		item.setup(queue[i], 0.0, false)
		item.cancelled.connect(_on_item_cancelled.bind(i))
		queue_container.add_child(item)

func _on_item_cancelled(index: int):
	if training_queue:
		training_queue.cancel_at_index(index)
```

### 4.5 UnitButton.gd — Train Button

```gdscript
# scripts/ui/UnitButton.gd
class_name UnitButton
extends Button

@export var unit_type: String = "miner"
@export var training_queue: TrainingQueue

@onready var cost_label = $CostLabel
@onready var icon = $Icon
@onready var game_state = get_node_or_null("/root/GameState")

func _ready():
	pressed.connect(_on_pressed)
	if game_state:
		game_state.coin_changed.connect(_on_coin_changed)

	# Setup initial display
	cost_label.text = str(Constants.COSTS[unit_type])
	text = unit_type.capitalize()
	_update_state()

func _on_pressed():
	if training_queue:
		var success = training_queue.enqueue(unit_type)
		if not success:
			# Shake animation for feedback
			var tween = create_tween()
			tween.tween_property(self, "position:x", position.x + 5, 0.05)
			tween.tween_property(self, "position:x", position.x - 5, 0.05)
			tween.tween_property(self, "position:x", position.x, 0.05)

func _on_coin_changed(side: String, amount: int):
	if side == training_queue.side:
		_update_state()

func _update_state():
	var can_afford = false
	var queue_has_space = false

	if game_state and training_queue:
		var coin = game_state.player_coin if training_queue.side == "player" else game_state.enemy_coin
		can_afford = coin >= Constants.COSTS[unit_type]
		queue_has_space = not training_queue.is_full()

	disabled = not (can_afford and queue_has_space)
	modulate = Color(1, 1, 1, 0.4) if disabled else Color(1, 1, 1, 1)
```

### 4.6 TopBarHUD.gd — HUD Controller

```gdscript
# scripts/ui/TopBarHUD.gd
class_name TopBarHUD
extends Control

@onready var coin_label = $CoinLabel
@onready var miner_level_label = $MinerLevelLabel
@onready var unit_count_label = $UnitCountLabel
@onready var player_hp_label = $PlayerHPLabel
@onready var enemy_hp_label = $EnemyHPLabel
@onready var surface_tab = $SurfaceTab
@onready var underground_tab = $UndergroundTab

@onready var game_state = get_node_or_null("/root/GameState")

func _ready():
	if game_state:
		game_state.coin_changed.connect(_on_coin_changed)
		game_state.building_hp_changed.connect(_on_building_hp_changed)
		game_state.unit_count_changed.connect(_on_unit_count_changed)
		game_state.miner_level_changed.connect(_on_miner_level_changed)

	surface_tab.pressed.connect(_on_surface_tab_pressed)
	underground_tab.pressed.connect(_on_underground_tab_pressed)

	_update_all()

func _on_coin_changed(side: String, amount: int):
	if side == "player":
		coin_label.text = "💰 " + str(amount)

func _on_building_hp_changed(side: String, hp: float):
	if side == "player":
		player_hp_label.text = "🏠 " + str(int(hp))
	else:
		enemy_hp_label.text = "💀 " + str(int(hp))

func _on_unit_count_changed(side: String, count: int):
	if side == "player":
		unit_count_label.text = "⚔️ " + str(count) + "/100"

func _on_miner_level_changed(side: String, level: int):
	if side == "player":
		miner_level_label.text = "⛏️ Miner L" + str(level)

func _on_surface_tab_pressed():
	get_tree().call_group("camera_manager", "switch_to_surface")
	surface_tab.modulate = Color(1, 1, 1, 1)
	underground_tab.modulate = Color(1, 1, 1, 0.5)

func _on_underground_tab_pressed():
	get_tree().call_group("camera_manager", "switch_to_underground")
	underground_tab.modulate = Color(1, 1, 1, 1)
	surface_tab.modulate = Color(1, 1, 1, 0.5)

func _update_all():
	if game_state:
		_on_coin_changed("player", game_state.player_coin)
		_on_building_hp_changed("player", game_state.player_building_hp)
		_on_building_hp_changed("enemy", game_state.enemy_building_hp)
		_on_unit_count_changed("player", game_state.player_unit_count)
		_on_miner_level_changed("player", game_state.player_miner_level)
```

---

## 5. Component 3: Underground System & Pathfinding

This component manages the destructible tilemap, the 7-layer underground world, A* pathfinding, the central wall, and mine entry portals.

### 5.1 File Structure

```
res://
├── scripts/
│   ├── world/
│   │   ├── UndergroundWorld.gd      # Main underground controller
│   │   ├── Pathfinder.gd             # A* grid wrapper
│   │   └── UndergroundTile.gd        # Individual tile logic
│   └── ai/
│       └── EnemyAI.gd                # Enemy decision making
├── scenes/
│   ├── world/
│   │   ├── UndergroundWorld.tscn
│   │   └── Wall.tscn
│   └── tiles/
│       ├── UndergroundTile.tscn
│       └── MineEntry.tscn
```

### 5.2 UndergroundWorld.gd — Main Underground Controller

```gdscript
# scripts/world/UndergroundWorld.gd
class_name UndergroundWorld
extends Node2D

signal tile_mined(tile: UndergroundTile, side: String, layer: int)
signal wall_breached(side: String)

@export var layers: int = 7
@export var layer_height: int = 100
@export var tile_size: int = 32
@export var wall_x: int = 450
@export var wall_width: int = 80

var tiles: Array[UndergroundTile] = []
var wall_hp: float = 2000.0
var wall_breached: bool = false

@onready var pathfinder: Pathfinder = $Pathfinder
@onready var wall = $Wall
@onready var player_mine_entry = $PlayerMineEntry
@onready var enemy_mine_entry = $EnemyMineEntry

func _ready():
	_generate_tiles()
	if pathfinder:
		pathfinder.setup(self)

func _generate_tiles():
	var map_width = 900  # Total underground width
	var tiles_per_row = map_width / tile_size

	for layer in range(layers):
		var y = layer * layer_height + layer_height / 2
		var tile_hp = Constants.LAYER_TILE_HP[layer]
		var coin_range = Constants.LAYER_COIN_RANGES[layer]

		for x in range(0, map_width, tile_size):
			# Skip wall area
			if x >= wall_x - wall_width/2 and x < wall_x + wall_width/2:
				continue

			var side = "player" if x < wall_x else "enemy"

			var tile = preload("res://scenes/tiles/UndergroundTile.tscn").instantiate()
			tile.global_position = Vector2(x + tile_size/2, y)
			tile.setup(layer, side, tile_hp, coin_range)
			tile.mined.connect(_on_tile_mined)
			add_child(tile)
			tiles.append(tile)

func _on_tile_mined(tile: UndergroundTile):
	tile_mined.emit(tile, tile.side, tile.layer)
	if pathfinder:
		pathfinder.mark_cell_mined(tile.grid_position)

func get_tiles_by_side_and_layer(side: String, layer: int) -> Array[UndergroundTile]:
	return tiles.filter(func(t): return t.side == side and t.layer == layer and not t.mined)

func get_mine_entry(side: String) -> Node2D:
	if side == "player":
		return player_mine_entry
	return enemy_mine_entry

func damage_wall(amount: float, side: String):
	if wall_breached:
		return

	wall_hp -= amount
	if wall_hp <= 0:
		wall_hp = 0
		wall_breached = true
		_breach_wall()
		wall_breached.emit(side)

func _breach_wall():
	# Remove wall collision and visual
	if wall:
		wall.queue_free()
	# Open pathfinder through wall
	if pathfinder:
		pathfinder.open_wall(wall_x, wall_width, layers, layer_height)

func get_wall_hp_percent() -> float:
	return wall_hp / 2000.0

func get_tile_at_position(pos: Vector2) -> UndergroundTile:
	for tile in tiles:
		if tile.global_position.distance_to(pos) < tile_size / 2:
			return tile
	return null
```

### 5.3 Pathfinder.gd — A* Grid Wrapper

```gdscript
# scripts/world/Pathfinder.gd
class_name Pathfinder
extends Node

var astar: AStarGrid2D
var tilemap: Node2D
var cell_size: Vector2i = Vector2i(32, 32)
var grid_offset: Vector2i = Vector2i.ZERO

func setup(world: UndergroundWorld):
	tilemap = world
	astar = AStarGrid2D.new()

	# Calculate grid bounds based on world size
	var map_width = 900
	var map_height = world.layers * world.layer_height

	astar.region = Rect2i(0, 0, map_width / cell_size.x, map_height / cell_size.y)
	astar.cell_size = cell_size
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()

	# Mark all tiles as solid initially
	for x in range(astar.region.size.x):
		for y in range(astar.region.size.y):
			astar.set_point_solid(Vector2i(x, y), true)

	# Open tiles that exist
	for tile in world.tiles:
		if not tile.mined:
			var grid_pos = world_to_grid(tile.global_position)
			astar.set_point_solid(grid_pos, false)

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / cell_size.x), int(world_pos.y / cell_size.y))

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x * cell_size.x + cell_size.x / 2, grid_pos.y * cell_size.y + cell_size.y / 2)

func get_path(start: Vector2, end: Vector2) -> PackedVector2Array:
	var start_cell = world_to_grid(start)
	var end_cell = world_to_grid(end)

	if not astar.is_in_boundsv(start_cell) or not astar.is_in_boundsv(end_cell):
		return PackedVector2Array()

	if astar.is_point_solid(start_cell) or astar.is_point_solid(end_cell):
		return PackedVector2Array()

	return astar.get_point_path(start_cell, end_cell)

func mark_cell_mined(grid_pos: Vector2i):
	if astar.is_in_boundsv(grid_pos):
		astar.set_point_solid(grid_pos, false)

func mark_cell_occupied(grid_pos: Vector2i):
	if astar.is_in_boundsv(grid_pos):
		astar.set_point_solid(grid_pos, true)

func open_wall(wall_x: int, wall_width: int, layers: int, layer_height: int):
	# Open all cells in the wall area
	var start_x = int((wall_x - wall_width/2) / cell_size.x)
	var end_x = int((wall_x + wall_width/2) / cell_size.x)
	var end_y = int((layers * layer_height) / cell_size.y)

	for x in range(start_x, end_x):
		for y in range(0, end_y):
			astar.set_point_solid(Vector2i(x, y), false)

func is_valid_position(world_pos: Vector2) -> bool:
	var grid_pos = world_to_grid(world_pos)
	if not astar.is_in_boundsv(grid_pos):
		return false
	return not astar.is_point_solid(grid_pos)
```

### 5.4 UndergroundTile.gd — Destructible Tile

```gdscript
# scripts/world/UndergroundTile.gd
class_name UndergroundTile
extends StaticBody2D

signal mined(tile: UndergroundTile)

@export var layer: int = 0
@export var side: String = "player"
@export var max_hp: float = 50.0
@export var coin_value: float = 10.0

var current_hp: float = 50.0
var mined: bool = false
var grid_position: Vector2i = Vector2i.ZERO

@onready var sprite = $Sprite2D
@onready var collision = $CollisionShape2D
@onready var anim_player = $AnimationPlayer

func setup(p_layer: int, p_side: String, p_hp: float, p_coin_range: Array):
	layer = p_layer
	side = p_side
	max_hp = p_hp
	current_hp = p_hp
	coin_value = randf_range(p_coin_range[0], p_coin_range[1])

	# Set visual based on layer
	_set_layer_visual(p_layer)

	# Store grid position
	grid_position = Vector2i(int(global_position.x / 32), int(global_position.y / 32))

func _set_layer_visual(p_layer: int):
	match p_layer:
		0, 1:
			sprite.modulate = Color("#334155")
		2, 3:
			sprite.modulate = Color("#4b5563")
		4, 5:
			sprite.modulate = Color("#6b7280")
		6:
			sprite.modulate = Color("#7c3aed")

func take_mine_damage(damage: float) -> bool:
	if mined:
		return false

	current_hp -= damage
	_flash_damage()

	if current_hp <= 0:
		_mine_tile()
		return true
	return false

func _flash_damage():
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", Color(1.5, 1.5, 1.5, 1.0), 0.05)
		tween.tween_property(sprite, "modulate", _get_base_color(), 0.1)

func _get_base_color() -> Color:
	match layer:
		0, 1: return Color("#334155")
		2, 3: return Color("#4b5563")
		4, 5: return Color("#6b7280")
		6: return Color("#7c3aed")
	return Color.WHITE

func _mine_tile():
	mined = true
	if collision:
		collision.disabled = true
	if anim_player:
		anim_player.play("break")
		await anim_player.animation_finished

	sprite.visible = false
	mined.emit(self)

func mine():
	_mine_tile()

func is_mined() -> bool:
	return mined
```

### 5.5 EnemyAI.gd — Enemy Decision Making

```gdscript
# scripts/ai/EnemyAI.gd
class_name EnemyAI
extends Node

@export var decision_interval: float = 2.0
@export var aggression_check_interval: float = 10.0

var decision_timer: float = 0.0
var aggression_timer: float = 0.0
var aggression_level: String = "balanced"  # "defend", "balanced", "push"

@onready var game_state = get_node_or_null("/root/GameState")
@onready var training_queue = get_parent().get_node("TrainingQueue")
@onready var underground = get_node_or_null("/root/World/UndergroundWorld")

func _process(delta: float):
	decision_timer += delta
	aggression_timer += delta

	if decision_timer >= decision_interval:
		decision_timer = 0.0
		_make_economic_decision()

	if aggression_timer >= aggression_check_interval:
		aggression_timer = 0.0
		_update_aggression_level()

func _make_economic_decision():
	if not game_state or not training_queue:
		return

	var total_units = game_state.enemy_unit_count
	var miners = get_tree().get_nodes_in_group("enemy_miners").size()
	var fighters = total_units - miners

	# Queue decisions
	if training_queue.get_queue_size() < 3 and total_units < Constants.MAX_UNITS:
		if miners < 5 and game_state.enemy_coin >= Constants.COSTS["miner"]:
			training_queue.enqueue("miner")
		elif fighters < 3 and game_state.enemy_coin >= Constants.COSTS["swordsman"]:
			training_queue.enqueue("swordsman")
		elif game_state.enemy_coin >= Constants.COSTS["wizard"]:
			training_queue.enqueue("wizard")
		elif game_state.enemy_coin >= Constants.COSTS["archer"]:
			training_queue.enqueue("archer")
		elif game_state.enemy_coin >= Constants.COSTS["swordsman"]:
			training_queue.enqueue("swordsman")

	# Upgrade miners
	if game_state.enemy_miner_level == 1 and game_state.enemy_coin >= 500:
		game_state.upgrade_miners("enemy")
	elif game_state.enemy_miner_level == 2 and game_state.enemy_coin >= 1500:
		game_state.upgrade_miners("enemy")

func _update_aggression_level():
	var player_fighters = 0
	var enemy_fighters = 0

	for unit in get_tree().get_nodes_in_group("units"):
		if unit is UnitBase and unit.unit_type != "miner":
			if unit.side == "player":
				player_fighters += 1
			else:
				enemy_fighters += 1

	if enemy_fighters > player_fighters * 1.5:
		aggression_level = "push"
	elif enemy_fighters < player_fighters * 0.5:
		aggression_level = "defend"
	else:
		aggression_level = "balanced"

	_apply_aggression_behavior()

func _apply_aggression_behavior():
	var enemy_units = get_tree().get_nodes_in_group("enemy_units")

	match aggression_level:
		"push":
			# Send all fighters to attack
			for unit in enemy_units:
				if unit is UnitBase and unit.unit_type != "miner" and unit.has_method("set_aggressive"):
					unit.set_aggressive(true)
		"defend":
			# Garrison 30% of fighters
			var fighters = enemy_units.filter(func(u): return u is UnitBase and u.unit_type != "miner")
			var garrison_count = int(fighters.size() * 0.3)
			for i in range(min(garrison_count, fighters.size())):
				if fighters[i].has_method("garrison"):
					fighters[i].garrison()
		"balanced":
			# Default behavior
			pass

func _should_breach_wall() -> bool:
	if not underground:
		return false

	# Check if enemy has no accessible tiles left
	var accessible_tiles = underground.get_tiles_by_side_and_layer("enemy", game_state.enemy_miner_level)
	var unmined = accessible_tiles.filter(func(t): return not t.mined)

	return unmined.is_empty() and game_state.enemy_coin > 1000 and not underground.wall_breached
```

---

## 6. UI/HUD Specifications

### 6.1 Top Bar HUD

```
┌─────────────────────────────────────────────────────────────┐
│  💰 1,240          ⛏️ Miner L2          ⚔️ 45/100 Units    │
│                                                             │
│  [Surface] [Underground]                                    │
└─────────────────────────────────────────────────────────────┘
```

| Element | Position | Font | Color |
|---------|----------|------|-------|
| Coin | Top-left | 14px Bold | `#fbbf24` |
| Miner Level | Top-left offset | 14px Bold | `#3b82f6` |
| Unit Count | Top-center | 14px Bold | `#e2e8f0` |
| Player HP | Top-right | 14px Bold | `#22c55e` |
| Enemy HP | Top-right offset | 14px Bold | `#ef4444` |
| View Tabs | Below stats | 11px Bold | Active: `#e2e8f0`, Inactive: `#94a3b8` |

### 6.2 Unit Training Buttons

| State | Background | Border | Text | Opacity |
|-------|-----------|--------|------|---------|
| Normal | `#334155` → `#1e293b` (gradient) | `#475569` | `#e2e8f0` | 100% |
| Hover | `#475569` → `#334155` | `#e2e8f0` | `#e2e8f0` | 100% |
| Disabled | `#0f172a` | `#334155` | `#475569` | 40% |
| Pressed | `#1e293b` | `#475569` | `#e2e8f0` | 100% |

**Button Layout:** 100×70px, border-radius 8px, icon top, cost centered, train time below.

### 6.3 Training Queue Panel

```
┌─────────────────────────────────────────────────────────────┐
│  TRAINING                                                   │
│  [Swordsman ▓▓▓▓▓▓▓▓░░ 80%] [Archer] [Miner] [Wizard]     │
└─────────────────────────────────────────────────────────────┘
```

- Current training: 140×40px, progress bar fill `#3b82f6`, background `#0f172a`
- Queued items: 70×40px, border `#334555`, text `#94a3b8`
- Click queued item to cancel (100% refund)

### 6.4 Health Bars

| Type | Dimensions | Background | Fill (High) | Fill (Low) |
|------|-----------|------------|-------------|------------|
| Building | 120×6px | `#0f172a` | `#22c55e` (>50%) | `#ef4444` (<20%) |
| Unit | 32×4px | `#0f172a` | `#22c55e` (>50%) | `#f59e0b` (<50%) |
| Wall | 160×6px | `#0f172a` | `#f59e0b` | `#ef4444` (<20%) |

### 6.5 Selection & Targeting Visuals

| Element | Visual |
|---------|--------|
| Selected Unit | Dashed ellipse `#fbbf24`, 2px stroke, 4px dash/2px gap |
| Hover Target | Solid circle `#e2e8f0`, 1px stroke, 50% opacity |
| Damage Popup | Text `#ef4444`, 10px bold, floats up and fades over 1s |
| Coin Deposit | Text `#fbbf24`, 10px bold, floats up with sparkle |
| Attack Range | Circle `#ef4444`, 1px stroke, 20% fill opacity (on hover) |

### 6.6 Upgrade Button

```
┌─────────────────────────────────┐
│  ⬆ Upgrade Miners              │
│  Level 2 → 3 | Cost: 1,500     │
└─────────────────────────────────┘
```

- Background: `#111827`, border: `#fbbf24` 1px
- Text: `#fbbf24` bold, caption: `#94a3b8`
- Disabled: opacity 30%, text "Max Level"

### 6.7 Underground Layer Indicator

```
L1 [▓]  L2 [▓]  L3 [░]  L4 [░]  L5 [░]  L6 [░]  L7 [░]
```

- `▓` = accessible (blue border `#3b82f6`)
- `░` = locked (gray border `#475569`)
- Label: 10px `#94a3b8`

---

## 7. Asset Specifications

### 7.1 Sprite Sizes

| Asset | Dimensions | Frames | Notes |
|-------|-----------|--------|-------|
| Miner L1 | 32×48 | 8 | Pickaxe, lantern, hooded cloak |
| Miner L2 | 32×48 | 8 | Drill backpack, goggles |
| Miner L3 | 32×48 | 8 | Jackhammer, heavy armor |
| Swordsman | 32×48 | 8 | Rusted sword, fur pelt, scar |
| Archer | 32×48 | 8 | Recurve bow, ice quiver, white hood |
| Wizard | 32×48 | 8 | Frost staff, torn robes, blue aura |
| Player Building | 120×160 | 4 | Idle, damaged, critical, destroyed |
| Enemy Building | 120×160 | 4 | Dark variant with spikes |
| Mine Entry | 60×80 | 2 | Idle, active (elevator moves) |
| Wall Segment | 40×100 | 3 | Intact, damaged, breached |
| Underground Tile | 32×32 | 1 | Per layer variant |
| Arrow Projectile | 16×4 | 1 | Rotates to velocity |
| Wizard Blast | 32×32 | 6 | AOE explosion |
| Coin | 16×16 | 4 | Spin animation |
| Health Bar | 32×4 | 1 | Green/red fill |

### 7.2 Animation States

All units require these animations in `AnimationPlayer`:

| Animation | Duration | Description |
|-----------|----------|-------------|
| `idle` | 1.0s loop | Breathing/standing sway |
| `walk` | 0.8s loop | 4-frame leg cycle |
| `attack` | 0.5s | Strike + impact frame |
| `death` | 0.8s | Collapse + fade to black |
| `mine` | 1.0s loop | Pickaxe swing / drill vibration |

Buildings require:

| Animation | Duration | Description |
|-----------|----------|-------------|
| `idle` | 2.0s loop | Smoke puff, light flicker |
| `damaged` | 1.0s loop | Cracks appear, smoke increases |
| `critical` | 0.5s loop | Heavy smoke, sparks, red alert |
| `destroyed` | 2.0s | Collapse, explosion, fade |

### 7.3 Audio Assets

| Asset | Format | Duration | Description |
|-------|--------|----------|-------------|
| Ambient Surface | OGG | 60s loop | Howling wind, distant machinery, ice creak |
| Ambient Underground | OGG | 60s loop | Dripping water, echoing drills, low rumble |
| Music Tension | OGG | 120s loop | Low strings, industrial percussion |
| Music Combat | OGG | 120s loop | Faster tempo, brass stabs |
| SFX Mine L1 | WAV | <1s | Metallic clink, rock crack |
| SFX Mine L2 | WAV | <1s | Pneumatic whir, steam hiss |
| SFX Mine L3 | WAV | <1s | Heavy jackhammer thud |
| SFX Sword | WAV | <1s | Sharp swish + meaty thwack |
| SFX Arrow | WAV | <1s | Bow twang + whistle + impact |
| SFX Wizard | WAV | <1s | Icy crackle + explosion |
| SFX Building Hit | WAV | <1s | Deep boom + concrete crumble |
| SFX Building Destroyed | WAV | 2s | Massive explosion, alarm fade |
| SFX Coin Deposit | WAV | <1s | Satisfying chime + coin clink |
| SFX Unit Trained | WAV | <1s | Horn/bugle fanfare |
| SFX Wall Breach | WAV | 2s | Loud metal tear + grinding |

### 7.4 UI Asset Sizes

| Asset | Dimensions | Format |
|-------|-----------|--------|
| Button Background | 100×70 | 9-slice PNG or SVG |
| Panel Background | Variable | 9-slice PNG with frost border |
| Health Bar Fill | 1×4 | Horizontal stretch PNG |
| Selection Ring | 32×32 | PNG with transparency |
| Icon Miner | 16×16 | PNG |
| Icon Sword | 16×16 | PNG |
| Icon Archer | 16×16 | PNG |
| Icon Wizard | 16×16 | PNG |
| Icon Coin | 16×16 | PNG |

---

## 8. Complete Constants & Balance Sheet

```gdscript
# scripts/Constants.gd
extends Node

class_name Constants

# ─── ECONOMY ───
const STARTING_COIN = 150
const MAX_UNITS = 100
const MAX_QUEUE_SIZE = 5

# ─── UNIT COSTS ───
const COSTS = {
	"miner": 50,
	"swordsman": 100,
	"archer": 150,
	"wizard": 250
}

# ─── TRAIN TIMES (seconds) ───
const TRAIN_TIMES = {
	"miner": 3.0,
	"swordsman": 5.0,
	"archer": 6.0,
	"wizard": 10.0
}

# ─── UNIT STATS ───
const FIGHTER_STATS = {
	"swordsman": { "hp": 150, "dps": 15, "range": 30, "speed": 80, "attack_cooldown": 0.5 },
	"archer": { "hp": 80, "dps": 12, "range": 150, "speed": 70, "attack_cooldown": 1.0, "proj_speed": 300 },
	"wizard": { "hp": 60, "dps": 25, "range": 120, "speed": 50, "attack_cooldown": 1.5, "aoe_radius": 40 }
}

const MINER_STATS = {
	1: { "hp": 50, "speed": 60, "mine_dps": 10, "carry": 20, "max_layer": 1 },
	2: { "hp": 75, "speed": 70, "mine_dps": 15, "carry": 30, "max_layer": 3 },
	3: { "hp": 100, "speed": 80, "mine_dps": 25, "carry": 50, "max_layer": 6 }
}

# ─── MINER UPGRADES ───
const MINER_UPGRADE_COSTS = {
	1: 500,   # L1 → L2
	2: 1500   # L2 → L3
}

# ─── BUILDINGS ───
const PLAYER_BUILDING_HP = 5000.0
const ENEMY_BUILDING_HP = 5000.0

# ─── WALL ───
const WALL_HP = 2000.0
const WALL_DAMAGE_PER_MINER = 10.0

# ─── UNDERGROUND ───
const LAYERS = 7
const LAYER_HEIGHT = 100
const TILE_SIZE = 32

# Layer coin ranges [min, max]
const LAYER_COIN_RANGES = {
	0: [5, 10],
	1: [8, 15],
	2: [12, 20],
	3: [15, 25],
	4: [20, 35],
	5: [25, 40],
	6: [30, 50]
}

# Layer tile HP
const LAYER_TILE_HP = {
	0: 50, 1: 50,
	2: 75, 3: 75,
	4: 100, 5: 100, 6: 100
}

# ─── ENEMY AI ───
const ENEMY_DECISION_INTERVAL = 2.0
const ENEMY_AGGRESSION_INTERVAL = 10.0
const ENEMY_COIN_MULTIPLIER_EASY = 0.8
const ENEMY_COIN_MULTIPLIER_NORMAL = 1.0
const ENEMY_COIN_MULTIPLIER_HARD = 1.2
const ENEMY_COIN_MULTIPLIER_NIGHTMARE = 1.5
```

---

## 9. Scene Tree Reference

### 9.1 Main Game Scene

```
World (Node2D)
├── SurfaceWorld (Node2D)
│   ├── Background (Sprite2D / ParallaxLayer)
│   ├── Ground (StaticBody2D + Sprite2D)
│   ├── PlayerBuilding (StaticBody2D)
│   │   ├── Sprite2D
│   │   ├── CollisionShape2D
│   │   ├── Hitbox (Area2D)
│   │   ├── SpawnPoint (Marker2D)
│   │   ├── HealthBar (CanvasLayer)
│   │   ├── AnimationPlayer
│   │   └── TrainingQueue (Node, TrainingQueue.gd)
│   ├── PlayerMineEntry (Area2D)
│   │   ├── Sprite2D
│   │   └── CollisionShape2D
│   ├── EnemyMineEntry (Area2D)
│   ├── EnemyBuilding (StaticBody2D)
│   │   └── [Same structure as PlayerBuilding]
│   └── UnitsContainer (Node2D)
│       └── [Units spawned here]
├── UndergroundWorld (Node2D, UndergroundWorld.gd)
│   ├── TileMapLayer (TileMapLayer)
│   ├── Wall (StaticBody2D)
│   │   ├── Sprite2D
│   │   ├── CollisionShape2D
│   │   └── HealthBar
│   ├── Pathfinder (Node, Pathfinder.gd)
│   ├── PlayerMineEntry (Area2D)
│   ├── EnemyMineEntry (Area2D)
│   └── TilesContainer (Node2D)
│       └── [UndergroundTile instances]
├── Camera2D
│   └── CameraManager (Node)
├── HUD (CanvasLayer)
│   ├── TopBar (Control, TopBarHUD.gd)
│   ├── TrainingPanel (Control, TrainingQueuePanel.gd)
│   ├── UnitButtons (HBoxContainer)
│   │   ├── MinerButton (UnitButton.gd)
│   │   ├── SwordsmanButton (UnitButton.gd)
│   │   ├── ArcherButton (UnitButton.gd)
│   │   └── WizardButton (UnitButton.gd)
│   ├── UpgradeButton (Button)
│   └── LayerIndicator (Control)
└── EffectsContainer (Node2D)
	└── [Particles, projectiles, popups]
```

### 9.2 Unit Scene Template

```
CharacterBody2D (UnitBase.gd)
├── Sprite2D
│   └── Material: ShaderMaterial (for damage flash)
├── CollisionShape2D
│   └── RectangleShape2D
├── AnimationPlayer
├── HealthBar (CanvasLayer or Node2D)
│   ├── Background (ColorRect)
│   └── Fill (ColorRect)
├── SelectionRing (Sprite2D)
│   └── [Dashed ring texture, hidden by default]
├── AttackRange (Area2D) — fighters only
│   └── CollisionShape2D (CircleShape2D)
└── StateMachine (Node)
	└── [MinerStates.gd or FighterStates.gd]
```

### 9.3 Underground Tile Scene

```
StaticBody2D (UndergroundTile.gd)
├── Sprite2D
│   └── [Layer-colored square texture]
├── CollisionShape2D
│   └── RectangleShape2D (32×32)
├── AnimationPlayer
│   └── ["break" animation: scale down + fade]
└── CoinSparkle (CPUParticles2D)
	└── [Hidden until mined]
```

---

## 10. Implementation Roadmap

### Week 1: Foundation
- [ ] Set up Godot 4.3 project with correct settings
- [ ] Create `Constants.gd` with all balance numbers
- [ ] Create `GameState.gd` autoload
- [ ] Build SurfaceWorld scene with placeholder sprites
- [ ] Place PlayerBuilding, EnemyBuilding, MineEntries
- [ ] Implement basic unit spawning (no AI, just spawn at building)

### Week 2: Underground & Pathfinding
- [ ] Build UndergroundWorld scene
- [ ] Implement tile generation system
- [ ] Create `UndergroundTile.gd` with mine/break logic
- [ ] Implement `Pathfinder.gd` with AStarGrid2D
- [ ] Build The Wall with HP and breach logic
- [ ] Connect Surface ↔ Underground via MineEntry portals
- [ ] Test miner pathfinding to tiles and back

### Week 3: Unit AI & Combat
- [ ] Build `UnitBase.gd` with shared logic
- [ ] Implement `UnitStateMachine.gd` base class
- [ ] Implement `MinerStates.gd` (idle → move → mine → return → deposit)
- [ ] Implement `FighterStates.gd` (idle → move → attack)
- [ ] Build projectile system for Archer/Wizard
- [ ] Implement damage, health bars, death
- [ ] Add garrison command for fighters

### Week 4: Training Queue & Economy
- [ ] Build `TrainingQueue.gd` with FIFO logic
- [ ] Create UI buttons for all 4 unit types
- [ ] Build TrainingQueuePanel with progress bars
- [ ] Connect coin economy (mining → coin → training)
- [ ] Implement miner upgrade system (L1→L2→L3)
- [ ] Add cancel-queue functionality with refund
- [ ] Build TopBarHUD with all stats

### Week 5: Enemy AI & Polish
- [ ] Implement `EnemyAI.gd` with economic decisions
- [ ] Add aggression levels (defend/balanced/push)
- [ ] Implement wall breach AI logic
- [ ] Add win/lose screens with stats
- [ ] Implement pause menu
- [ ] Add difficulty selection (Easy/Normal/Hard/Nightmare)

### Week 6: Audio, Visuals & Optimization
- [ ] Add all SFX and music
- [ ] Implement particle effects (snow, dust, explosions)
- [ ] Add screen shake on heavy impacts
- [ ] Polish animations and transitions
- [ ] Optimize: object pooling for projectiles, off-screen culling
- [ ] Build and test export for Windows/Mac/Linux

---

## Appendix A: Input Map (Godot Project Settings)

| Action | Input | Description |
|--------|-------|-------------|
| `select` | Mouse Left | Select unit / click UI |
| `command` | Mouse Right | Move / Attack / Garrison / Mine |
| `queue_miner` | Key `1` | Quick-queue miner |
| `queue_swordsman` | Key `2` | Quick-queue swordsman |
| `queue_archer` | Key `3` | Quick-queue archer |
| `queue_wizard` | Key `4` | Quick-queue wizard |
| `toggle_view` | Key `Tab` | Switch surface/underground |
| `pause` | Key `Space` or `Esc` | Pause game |
| `select_all` | `Ctrl + A` | Select all visible fighters |
| `add_select` | `Shift + Click` | Add to selection |

---

## Appendix B: Collision Layers

| Layer | Bit | Used By |
|-------|-----|---------|
| 1 | 0 | Player units |
| 2 | 1 | Enemy units |
| 3 | 2 | Buildings |
| 4 | 3 | Underground tiles |
| 5 | 4 | Wall |
| 6 | 5 | Projectiles |
| 7 | 6 | Mine entries |

---

*Document Version 1.0 — Complete implementation guide for Frost Mines in Godot 4.3*
