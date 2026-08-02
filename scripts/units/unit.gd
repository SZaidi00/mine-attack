class_name Unit
extends Node2D

signal died(unit)

enum State { IDLE, MOVE, ATTACK, MINE, DEPOSIT, ENTER_MINE, EXIT_MINE, CLIMB_UP, CLIMB_DOWN, DEAD }

const _HP_BAR_BG: Texture2D = preload("res://frost_mines_assets/ui/hp_bar_unit_bg.png")
const _HP_BAR_GREEN: Texture2D = preload("res://frost_mines_assets/ui/hp_bar_unit_green.png")
const _HP_BAR_ORANGE: Texture2D = preload("res://frost_mines_assets/ui/hp_bar_unit_orange.png")

const _MINER_TEXTURES: Dictionary = {
	GameManager.Team.PLAYER: [
		preload("res://frost_mines_assets/units/miner_l1_player.png"),
		preload("res://frost_mines_assets/units/miner_l2_player.png"),
		preload("res://frost_mines_assets/units/miner_l3_player.png")
	],
	GameManager.Team.ENEMY: [
		preload("res://frost_mines_assets/units/miner_l1_enemy.png"),
		preload("res://frost_mines_assets/units/miner_l2_enemy.png"),
		preload("res://frost_mines_assets/units/miner_l3_enemy.png")
	]
}

const _SELECTION_RING: Texture2D = preload("res://frost_mines_assets/effects/selection_ring.png")
const _IMPACT_TEXTURE: Texture2D = preload("res://frost_mines_assets/effects/impact_hit.png")

# How long a cell stays on this miner's no-path blacklist before a retry.
const _UNREACHABLE_FORGET_MS: int = 10000
# Idle wait near the surface entry before re-scanning an exhausted mine.
const _EXHAUSTED_RETRY_SEC: float = 5.0

@export var data: UnitData
@export var team: GameManager.Team = GameManager.Team.PLAYER

var hp: int = 0
var carried_coin: int = 0
var is_underground: bool = false
var selected: bool = false
var hovered: bool = false

var _state: State = State.IDLE
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _target_unit = null
var _target_building: Node2D = null
var _target_cell: Vector2i = Vector2i(-9999, -9999)
var _target_position: Vector2 = Vector2.ZERO
var _attack_timer: float = 0.0
var _mine_timer: float = 0.0
var _mine_target_angle: float = 0.0
var _mine_hit_flash: float = 0.0
var _hit_flash_timer: float = 0.0
var _dead_timer: float = 0.0
var _flee_timer: float = 0.0
var _flee_target: Vector2 = Vector2.ZERO
# Set when the miner still has cargo but nothing left to dig; the next surface
# idle tick sends it to the building deposit point instead of back down.
var _deposit_requested: bool = false
# Phase 3.3: cells this miner failed to path to (Vector2i -> Time.get_ticks_msec()
# when marked). Forgotten after a cooldown so newly connected pockets are retried.
var _unreachable_cells: Dictionary = {}
# Set when a seek scan found no diggable target; the miner waits near the
# surface entry and retries periodically instead of thrashing down and up.
var _mine_exhausted: bool = false
var _exhausted_retry_timer: float = 0.0
# Set when a mine command arrives while the miner is on the surface: digging
# is only allowed from inside the mine, so the miner rides the ladder down
# first and _handle_idle_miner re-issues this cell once underground.
var _pending_mine_cell: Vector2i = Vector2i(-9999, -9999)
# Phase 3.4: small per-unit offset applied to deposit and mine-entry targets
# so multiple miners do not stack into a single sprite on the surface parade.
var _movement_offset: Vector2 = Vector2.ZERO
# Rally stance: fighters hunt every enemy on the surface (miners included)
# and fall back to the rally point. Any explicit command cancels the rally.
var _rally_active: bool = false
var _rally_point: Vector2 = Vector2.ZERO
var _rally_scan_timer: float = 0.0
# Team-wide fighter upgrade level already applied to this unit's data.
var _fighter_level_applied: int = 1
# Research tree bonuses: _armor is a flat damage reduction (Bulwark). The
# base combat stats below are captured once so research bonuses recompute
# from them each tick — nothing else mutates them, and the recompute never
# compounds (miner speed/carry recompute from Constants.MINER_STATS for the
# same reason: _apply_miner_upgrade rewrites those stats on level-up).
var _armor: int = 0
var _research_base_captured: bool = false
var _base_attack_range: float = 0.0
var _base_aoe_radius: float = 0.0
var _base_attack_cooldown: float = 0.0
# Out-of-combat regen: counts down after each hit taken; HP accrues once it
# reaches zero (see _process).
var _regen_delay: float = 0.0
var _regen_accum: float = 0.0
# The spot a fighter returns to when idle on the surface (its "standing
# point"). Set at spawn, updated by explicit move/stop orders; attack and
# auto-attack engagements leave it alone, so units regroup after a fight
# instead of spreading across the map.
var _post_point: Vector2 = Vector2.ZERO
# Last applied flight altitude for HoverArea / z_index sync.
var _flight_visual_altitude: float = -1.0

@onready var _grid: GridWorld = get_node("/root/Main/World/GridWorld")


func _ready() -> void:
	if data == null:
		data = preload("res://scripts/resources/units/swordsman.tres")
	if data.is_miner:
		_apply_miner_upgrade()
	_apply_research_bonuses()
	hp = data.max_hp
	add_to_group("units")
	_add_hover_area()
	add_to_group(team_name())
	_movement_offset = Vector2(randf_range(-8, 8), randf_range(-6, 6))
	_post_point = global_position
	_connect_view_mode()
	queue_redraw()
	# Spawners (the building) are responsible for issuing the first command.
	# This avoids double-ordering a miner before its first _process tick.
	# Deferred safety net: if a surface miner is still idle after spawn, send it in.
	if data.is_miner:
		# Any destroyed tile can open a new path or ore pocket; wake up immediately.
		if not _grid.cell_destroyed.is_connected(_on_cell_destroyed):
			_grid.cell_destroyed.connect(_on_cell_destroyed)
		call_deferred("_deferred_enter_mine_check")


func _process(delta: float) -> void:
	if _state == State.DEAD:
		_dead_timer -= delta
		modulate.a = max(0, _dead_timer)
		if _dead_timer <= 0:
			queue_free()
		return

	# Match over: freeze all unit AI and movement in place.
	if not GameManager.game_active:
		return

	# Out-of-combat regeneration: a few seconds without taking damage slowly
	# restores HP (rewards retreating wounded units without erasing fights).
	if hp < data.max_hp:
		if _regen_delay > 0.0:
			_regen_delay -= delta
		else:
			_regen_accum += Constants.UNIT_REGEN_PER_SEC * delta
			var whole: int = int(_regen_accum)
			if whole > 0:
				_regen_accum -= whole
				hp = mini(hp + whole, data.max_hp)
				_spawn_heal_popup(whole)
				queue_redraw()

	if _hit_flash_timer > 0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0:
			queue_redraw()

	if _flee_timer > 0:
		_flee_timer -= delta
		if _state == State.IDLE:
			_continue_flee()
		match _state:
			State.MOVE:
				_follow_path(delta)
		return

	_apply_research_bonuses()
	_sync_flight_visuals()
	if data.is_miner:
		_apply_miner_upgrade()
		if _mine_exhausted:
			_exhausted_retry_timer -= delta
			if _exhausted_retry_timer <= 0.0:
				_mine_exhausted = false
		if _state == State.IDLE:
			_handle_idle_miner()
	elif data.is_fighter:
		_apply_fighter_upgrade()
		if _state == State.IDLE:
			_handle_idle_fighter()
		elif _rally_active and _state == State.MOVE:
			# Attack-move: scan for surface enemies while travelling.
			_rally_scan_timer -= delta
			if _rally_scan_timer <= 0.0:
				_rally_scan_timer = 0.25
				_engage_rally_target_if_any()
	# Keep the selection ring pulsing and the lantern glow flickering.
	if selected or (data.is_miner and is_underground) or get_flight_altitude() > 0.0:
		queue_redraw()
	match _state:
		State.MOVE:
			_follow_path(delta)
		State.ATTACK:
			_process_attack(delta)
		State.MINE:
			_process_mine(delta)
		State.DEPOSIT:
			_process_deposit(delta)
		State.ENTER_MINE:
			_process_enter_mine(delta)
		State.EXIT_MINE:
			_process_exit_mine(delta)
		State.CLIMB_UP:
			_process_climb_up(delta)
		State.CLIMB_DOWN:
			_process_climb_down(delta)


# ---------- Commands ----------

func move_to(world_pos: Vector2) -> void:
	if data.is_fighter and _is_enemy_underground(world_pos):
		DebugLog.log_reject("Unit %d" % get_instance_id(), "move_to", "enemy underground territory")
		_spawn_reject_popup(world_pos)
		return
	_clear_target()
	_target_position = world_pos
	_repath(world_pos)
	if _path.is_empty():
		DebugLog.log_reject("Unit %d" % get_instance_id(), "move_to", "no path to " + str(world_pos))
		_spawn_reject_popup(world_pos)
		_set_state(State.IDLE, "move target unreachable")
		return
	DebugLog.log_command("Unit %d" % get_instance_id(), "move_to", str(world_pos))
	_post_point = world_pos
	_set_state(State.MOVE, "move_to command")


func attack_unit(target) -> void:
	if target == null:
		DebugLog.log_reject("Unit %d" % get_instance_id(), "attack_unit", "null target")
		return
	if target.team == team:
		DebugLog.log_reject("Unit %d" % get_instance_id(), "attack_unit", "friendly target")
		return
	if not can_damage_unit(target):
		DebugLog.log_reject("Unit %d" % get_instance_id(), "attack_unit", "target immune")
		_spawn_reject_popup(target.get_combat_position() if target.has_method("get_combat_position") else target.global_position)
		return
	_clear_target()
	_repath(target.global_position)
	if _path.is_empty():
		DebugLog.log_reject("Unit %d" % get_instance_id(), "attack_unit", "no path to target")
		_spawn_reject_popup(target.get_combat_position() if target.has_method("get_combat_position") else target.global_position)
		_set_state(State.IDLE, "attack target unreachable")
		return
	DebugLog.log_command("Unit %d" % get_instance_id(), "attack_unit", "target=%d" % target.get_instance_id())
	_target_unit = target
	_set_state(State.ATTACK, "attack_unit command")


func attack_building(target: Node2D) -> void:
	if target == null:
		DebugLog.log_reject("Unit %d" % get_instance_id(), "attack_building", "null target")
		return
	# Path to a standing spot at the building's base; the footprint itself is
	# not a valid path target.
	var stand: Vector2 = _building_stand_point(target)
	_clear_target()
	_repath(stand)
	if _path.is_empty():
		DebugLog.log_reject("Unit %d" % get_instance_id(), "attack_building", "no path to building")
		_spawn_reject_popup(target.global_position)
		_set_state(State.IDLE, "building unreachable")
		return
	DebugLog.log_command("Unit %d" % get_instance_id(), "attack_building", "target=%d" % target.get_instance_id())
	_target_building = target
	_set_state(State.ATTACK, "attack_building command")


func mine_cell(grid_pos: Vector2i) -> void:
	if data == null or not data.is_miner:
		DebugLog.log_reject("Unit %d" % get_instance_id(), "mine_cell", "not a miner")
		return
	if not is_underground:
		# Digging is only allowed from inside the mine. Ride the ladder down
		# first; _handle_idle_miner re-issues this cell once underground.
		# (Set after climb_down_ladder because it clears targets.)
		climb_down_ladder()
		_pending_mine_cell = grid_pos
		DebugLog.log_command("Unit %d" % get_instance_id(), "mine_cell", str(grid_pos) + " (deferred until underground)")
		return
	_pending_mine_cell = Vector2i(-9999, -9999)
	DebugLog.log_command("Unit %d" % get_instance_id(), "mine_cell", str(grid_pos))
	_clear_target()
	_target_cell = grid_pos
	# Reserve the tile so other auto-seeking miners pick a different one.
	_grid.claim_cell(grid_pos, get_instance_id())
	_set_state(State.MINE, "mine_cell command")
	# Move adjacent. Underground an empty A* result means we can't reach this
	# tile yet — blacklist it and re-seek instead of walking through solid dirt.
	var adj: Vector2 = _nearest_adjacent_world(grid_pos)
	_repath(adj)
	if _path.is_empty() or not _path_reaches(adj):
		_mark_cell_unreachable(grid_pos)
		_set_state(State.IDLE, "mine target unreachable")


func deposit_coin() -> void:
	if data == null or not data.is_miner:
		DebugLog.log_reject("Unit %d" % get_instance_id(), "deposit_coin", "not a miner")
		return
	if carried_coin <= 0:
		DebugLog.log_reject("Unit %d" % get_instance_id(), "deposit_coin", "cargo empty")
		return
	_clear_target()
	if is_underground:
		# Deposits happen at the building on the surface; climb the ladder out,
		# then _handle_idle_miner sends us to the deposit point.
		DebugLog.log_command("Unit %d" % get_instance_id(), "deposit_coin", "cargo=%d" % carried_coin)
		climb_up_ladder()
		_deposit_requested = true
		return
	var building: Node2D = _friendly_building()
	if building == null:
		# Base destroyed (game over); stay idle without log-spamming every tick.
		_set_state(State.IDLE, "no building for deposit")
		return
	DebugLog.log_command("Unit %d" % get_instance_id(), "deposit_coin", "cargo=%d" % carried_coin)
	_set_state(State.DEPOSIT, "deposit command")
	_target_position = building.call("get_deposit_point") + _movement_offset
	_repath(_target_position)


func enter_mine() -> void:
	DebugLog.log_command("Unit %d" % get_instance_id(), "enter_mine")
	_clear_target()
	_set_state(State.ENTER_MINE, "enter_mine command")
	var entry: Node2D = _nearest_friendly_mine_entry()
	if entry:
		var entry_target: Vector2 = entry.call("get_ladder_top") + _movement_offset * 0.5
		_repath(entry_target)
		# If A* can't find a route, walk straight to the shaft instead of freezing.
		if _path.is_empty():
			_path.append(entry_target)
	else:
		_set_state(State.IDLE, "no mine entry")


func exit_mine() -> void:
	DebugLog.log_command("Unit %d" % get_instance_id(), "exit_mine")
	_clear_target()
	_set_state(State.EXIT_MINE, "exit_mine command")
	var entry: Node2D = _nearest_friendly_mine_entry()
	if entry:
		var underground_target: Vector2 = entry.call("get_underground_position") + _movement_offset
		_repath(underground_target)
		if _path.is_empty():
			_path.append(underground_target)
	else:
		_set_state(State.IDLE, "no mine entry")


func climb_up_ladder() -> void:
	DebugLog.log_command("Unit %d" % get_instance_id(), "climb_up_ladder")
	_clear_target()
	_set_state(State.CLIMB_UP, "climb_up_ladder command")
	var entry: Node2D = _nearest_friendly_mine_entry()
	if entry == null:
		_set_state(State.IDLE, "no mine entry")


func climb_down_ladder() -> void:
	DebugLog.log_command("Unit %d" % get_instance_id(), "climb_down_ladder")
	_clear_target()
	_set_state(State.CLIMB_DOWN, "climb_down_ladder command")
	var entry: Node2D = _nearest_friendly_mine_entry()
	if entry == null:
		_set_state(State.IDLE, "no mine entry")


func stop() -> void:
	DebugLog.log_command("Unit %d" % get_instance_id(), "stop")
	_clear_target()
	_post_point = global_position  # Defend/hold means: stay right here.
	_set_state(State.IDLE, "stop command")
	_path.clear()


## Disband: instant self-destruct on the owner's order. No coin refund — the
## point is freeing the population slot. Goes through _die() like any death:
## the corpse fades and a miner's cargo still drops as a pickup.
func kill() -> void:
	if _state == State.DEAD:
		return
	DebugLog.log_command("Unit %d" % get_instance_id(), "kill", "disbanded by owner")
	_die()



## Garrison order (fighters): fall back and defend the home base. Underground
## fighters come out of the mine first (the idle handler walks them to the
## post once they surface); surface fighters move straight to the building's
## deposit point and hold there (it becomes their new standing point).
func garrison_home() -> void:
	if data == null or not data.is_fighter:
		DebugLog.log_reject("Unit %d" % get_instance_id(), "garrison_home", "not a fighter")
		return
	_clear_target()
	var building: Node2D = _friendly_building()
	if building == null:
		_set_state(State.IDLE, "no building to garrison")
		return
	_post_point = building.call("get_deposit_point") + _movement_offset
	DebugLog.log_command("Unit %d" % get_instance_id(), "garrison_home", str(_post_point))
	if is_underground:
		exit_mine()
	else:
		move_to(_post_point)


## Rally stance order (fighters only): move to the point while hunting every
## enemy on the surface — miners included. The rally stays active until any
## explicit command cancels it (_clear_target resets the flag). Underground
## points are rejected (the sweep is a surface hunt); underground fighters
## ride the ladder up first and resume the rally on the surface.
func rally_to(world_pos: Vector2) -> void:
	if data == null or not data.is_fighter:
		DebugLog.log_reject("Unit %d" % get_instance_id(), "rally_to", "not a fighter")
		return
	if world_pos.y > GridWorld.CELL_SIZE:
		DebugLog.log_reject("Unit %d" % get_instance_id(), "rally_to", "underground rally point")
		_spawn_reject_popup(world_pos)
		return
	_clear_target()
	if is_underground:
		# Climb out first; _clear_target inside climb_up_ladder would wipe the
		# rally state, so it is set below, after the climb is under way.
		climb_up_ladder()
	_rally_active = true
	_rally_point = world_pos
	if _state == State.CLIMB_UP:
		DebugLog.log_command("Unit %d" % get_instance_id(), "rally_to", str(world_pos) + " (after climbing out)")
		return
	_target_position = world_pos
	_repath(world_pos)
	if _path.is_empty():
		# No route (e.g. clicked solid dirt): hold position and hunt from here.
		DebugLog.log_reject("Unit %d" % get_instance_id(), "rally_to", "no path to " + str(world_pos))
		_rally_point = global_position
		_set_state(State.IDLE, "rally point unreachable")
		return
	DebugLog.log_command("Unit %d" % get_instance_id(), "rally_to", str(world_pos))
	_set_state(State.MOVE, "rally_to command")


func take_damage(amount: int, attacker: Node2D = null) -> void:
	# Corpses take no damage: a dying unit stays valid for its 1s fade-out and
	# in-flight projectiles can still land on it — without this guard each
	# extra hit re-runs _die() and leaks a population slot (army grows past
	# MAX_UNITS over a long match).
	if _state == State.DEAD:
		return
	if not can_be_damaged_by(attacker):
		_spawn_immune_popup()
		return
	# Bulwark research: flat damage reduction, but a hit always lands for 1+.
	if _armor > 0:
		amount = maxi(1, amount - _armor)
	hp -= amount
	_regen_delay = Constants.UNIT_REGEN_DELAY
	_hit_flash_timer = 0.15
	queue_redraw()
	_spawn_damage_popup(amount)
	if hp <= 0:
		_die()
	elif data.is_miner:
		_start_flee()
	elif team == GameManager.Team.ENEMY:
		_maybe_retaliate(attacker)


## Dragons only take damage from Archers and Wizards. All other units are
## fully vulnerable to any attacker (including null for legacy call sites).
func can_be_damaged_by(attacker: Node2D) -> bool:
	if data == null or data.unit_name.to_lower() != "dragon":
		return true
	if attacker == null or not is_instance_valid(attacker):
		return false
	if not (attacker is Unit):
		return false
	var atk_data: UnitData = attacker.data
	if atk_data == null:
		return false
	var unit_id: String = atk_data.unit_name.to_lower()
	return unit_id == "archer" or unit_id == "wizard"


func can_damage_unit(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	# Combat never crosses the surface/underground boundary — flying dragons
	# included. A* can't path between layers, so cross-layer locks only ever
	# produced free hits on units (e.g. dragons sniping miners in the mine).
	if target is Unit and target.is_underground != is_underground:
		return false
	if target.has_method("can_be_damaged_by"):
		return target.can_be_damaged_by(self)
	return true


## Surface flight height in pixels (0 underground / non-flyers). Feet stay on
## the ground for pathing; combat and draw use the offset aim point.
func get_flight_altitude() -> float:
	if data == null or data.flight_altitude <= 0.0 or is_underground:
		return 0.0
	return data.flight_altitude


func get_combat_position() -> Vector2:
	return global_position + Vector2(0, -get_flight_altitude())


func combat_distance_squared_to(other: Node2D) -> float:
	if other == null or not is_instance_valid(other):
		return INF
	var other_pos: Vector2 = other.global_position
	if other.has_method("get_combat_position"):
		other_pos = other.get_combat_position()
	return get_combat_position().distance_squared_to(other_pos)


func _uses_fireball() -> bool:
	if data == null:
		return false
	var unit_id: String = data.unit_name.to_lower()
	return unit_id == "wizard" or unit_id == "dragon"


## AI-only target re-evaluation: a fighter locked onto a building ignores
## nothing forever — when enemy fighters damage it, some peel off to fight
## back (per-hit roll against the difficulty's retaliation chance), so a siege
## under fire turns into a real battle instead of a shooting gallery. Units
## already engaging units are left alone, so a retaliate decision never
## flip-flops mid-duel.
func _maybe_retaliate(attacker: Node2D) -> void:
	if _state != State.ATTACK or _target_building == null:
		return
	if randf() > GameManager.get_ai_retaliation_chance():
		return
	var target: Unit = _pick_retaliation_target(attacker)
	if target != null:
		DebugLog.log_command("Unit %d" % get_instance_id(), "retaliate", "target=%d" % target.get_instance_id())
		attack_unit(target)


## Best unit to fight back against: the attacker itself when it is a reachable
## fighter nearby, otherwise the closest enemy fighter in sight on the same
## level (A* can't cross the surface/underground boundary).
func _pick_retaliation_target(attacker: Node2D) -> Unit:
	if attacker is Unit and is_instance_valid(attacker) and attacker._state != State.DEAD \
			and attacker.data.is_fighter and attacker.is_underground == is_underground \
			and combat_distance_squared_to(attacker) <= (data.sight_range * 1.5) * (data.sight_range * 1.5):
		return attacker
	var best: Unit = null
	var best_dist: float = data.sight_range * data.sight_range
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == team or unit._state == State.DEAD:
			continue
		if not unit.data.is_fighter or unit.is_underground != is_underground:
			continue
		var d: float = combat_distance_squared_to(unit)
		if d <= best_dist:
			best_dist = d
			best = unit
	return best


func _spawn_damage_popup(amount: int) -> void:
	var popup: DamagePopup = preload("res://scenes/effects/damage_popup.tscn").instantiate()
	popup.setup(amount)
	popup.global_position = get_combat_position() + Vector2(0, -20)
	get_tree().current_scene.add_child(popup)


func _spawn_immune_popup() -> void:
	var popup: DamagePopup = preload("res://scenes/effects/damage_popup.tscn").instantiate()
	popup.setup_immune()
	popup.global_position = get_combat_position() + Vector2(0, -20)
	get_tree().current_scene.add_child(popup)


func _spawn_heal_popup(amount: int) -> void:
	var popup: DamagePopup = preload("res://scenes/effects/damage_popup.tscn").instantiate()
	popup.setup(amount, true)
	popup.global_position = get_combat_position() + Vector2(0, -20)
	get_tree().current_scene.add_child(popup)


# ---------- State processing ----------

func _follow_path(delta: float) -> void:
	if _path.is_empty() or _path_index >= _path.size():
		# Climb states handle arrival themselves; don't drop back to IDLE.
		if _state != State.CLIMB_UP and _state != State.CLIMB_DOWN:
			_set_state(State.IDLE, "path empty/start")
		return
	var target: Vector2 = _path[_path_index]
	var dist: float = target.distance_to(global_position)
	# Arrive when within one movement step of the point (or 2px, whichever is
	# larger). Without the step-aware threshold, a large delta (lag spike, high
	# time scale) plus the separation nudge can orbit the point forever without
	# ever coming within 2px at the start of a frame.
	var step: float = data.speed * delta
	if is_underground and data.is_fighter:
		step *= 0.6
	var arrive: float = maxf(2.0, step)
	# Advance past every point the step covers — at high game speeds with a
	# low frame rate a single step can span several cell centers.
	while dist <= arrive:
		_path_index += 1
		if _path_index >= _path.size():
			# Move onto the final point before transitioning. Without this a
			# large step completes the path while still far from the
			# destination (e.g. out of mining range), and the miner freezes
			# mid-approach bouncing between MINE and IDLE at 10x speed.
			global_position = global_position.move_toward(target, minf(step, dist))
			if _state != State.CLIMB_UP and _state != State.CLIMB_DOWN:
				_set_state(State.IDLE, "path completed")
			return
		target = _path[_path_index]
		dist = target.distance_to(global_position)
	var dir: Vector2 = target - global_position
	var move: Vector2 = dir.normalized() * minf(step, dist)
	# Phase 3.4: soft separation so same-team units don't hard-collide or stack.
	# Skip separation while walking to a ladder; it can push the unit away from
	# the exact ladder bottom/top and make it oscillate around the arrival threshold.
	if _state != State.CLIMB_UP and _state != State.CLIMB_DOWN:
		var separation: Vector2 = _compute_separation()
		if separation != Vector2.ZERO:
			move += separation.normalized() * min(step * 0.6, separation.length())
	global_position += move


## Phase 3.4: push away from nearby friendly units to avoid stacking and
## single-file parade artifacts. This is a soft steering nudge, not physics.
func _compute_separation() -> Vector2:
	var sep: Vector2 = Vector2.ZERO
	var radius: float = 22.0
	var radius_sq: float = radius * radius
	for unit in get_tree().get_nodes_in_group(team_name()):
		if unit == self or unit._state == State.DEAD:
			continue
		var offset: Vector2 = global_position - unit.global_position
		var dist_sq: float = offset.length_squared()
		if dist_sq > 0.001 and dist_sq < radius_sq:
			# Stronger repulsion as units get closer.
			sep += offset.normalized() * (radius - sqrt(dist_sq))
	return sep


## Ranged kiting: a direct steering step away from a closing threat. Deliberately
## not a path/move command — the ATTACK state (and its target) must survive, so
## the unit keeps firing on cooldown while it backs off.
func _kite_away_from(threat_pos: Vector2, delta: float) -> void:
	var away: Vector2 = global_position - threat_pos
	if away.length_squared() < 0.001:
		away = Vector2.LEFT
	var step: float = data.speed * delta
	if is_underground and data.is_fighter:
		step *= 0.6
	var next_pos: Vector2 = global_position + away.normalized() * step
	if _is_walkable_point(next_pos):
		global_position = next_pos


## Cheap point walkability for kiting (no A*): the surface row is open ground;
## underground only EMPTY cells can be stood on.
func _is_walkable_point(world_pos: Vector2) -> bool:
	if world_pos.y <= GridWorld.CELL_SIZE:
		return world_pos.y >= 0.0 \
			and world_pos.x >= GridWorld.X_MIN * GridWorld.CELL_SIZE \
			and world_pos.x <= (GridWorld.X_MAX + 1) * GridWorld.CELL_SIZE
	var cell: GridWorld.Cell = _grid.get_cell(_grid.world_to_grid(world_pos))
	return cell != null and cell.type == GridWorld.CellType.EMPTY


func _process_attack(delta: float) -> void:
	_attack_timer -= delta
	var path_pos: Vector2 = Vector2.ZERO  # Ground feet / stand point for A*.
	var range_pos: Vector2 = Vector2.ZERO  # Combat aim point for range + shots.
	var target_alive: bool = false

	if _target_unit != null and is_instance_valid(_target_unit) and _target_unit._state != State.DEAD:
		if _target_unit.is_underground != is_underground:
			# The target crossed the surface/underground boundary mid-chase
			# (a miner escaped down the shaft) — the chase can't follow.
			_clear_target()
			_set_state(State.IDLE, "target crossed layers")
			return
		path_pos = _target_unit.global_position
		range_pos = _target_unit.get_combat_position() if _target_unit.has_method("get_combat_position") else path_pos
		target_alive = true
	elif _target_building != null and is_instance_valid(_target_building) and _target_building.is_in_group("buildings"):
		# Measure range to the closest point on the building's body rect, not
		# its center, so melee units engage at the edge of the footprint.
		var rect: Rect2 = _target_building.call("get_bounds_rect")
		range_pos = _closest_point_on_rect(rect, get_combat_position())
		path_pos = _building_stand_point(_target_building)
		target_alive = true
	else:
		_set_state(State.IDLE, "target lost")
		return

	if get_combat_position().distance_to(range_pos) > data.attack_range:
		# Re-path only when there is no path or the destination has moved
		# significantly (moving unit targets), not every physics frame.
		if _path.is_empty() or _path[_path.size() - 1].distance_to(path_pos) > GridWorld.CELL_SIZE * 0.75:
			_repath(path_pos)
		if _path.is_empty():
			_set_state(State.IDLE, "attack target unreachable")
			return
		_follow_path(delta)
		return

	_path.clear()
	# Ranged standoff: if a unit target slips inside 40% of the attack range,
	# step back to re-establish distance before the next shot. Melee units
	# (attack_range <= 35) and building sieges are unaffected. Gap uses combat
	# positions (air vs ground); kite steering still moves feet on the ground.
	if data.attack_range > 35.0 and _target_unit != null:
		var gap: float = sqrt(combat_distance_squared_to(_target_unit))
		if gap < data.attack_range * 0.4:
			_kite_away_from(path_pos, delta)
	if _attack_timer <= 0:
		_attack_timer = data.attack_cooldown
		var hit_damage: int = roundi(data.damage_per_hit)
		if data.attack_range <= 35.0:
			# Melee
			AudioManager.play("sword", global_position, -8.0)
			if _target_unit != null:
				_target_unit.take_damage(hit_damage, self)
			elif _target_building != null:
				_target_building.call("take_damage", hit_damage)
		else:
			# Ranged projectile: aim at the point the range was measured to
			# (the enemy unit, or the closest point on the building's rect).
			_spawn_projectile(range_pos)


func _spawn_projectile(target_pos: Vector2) -> void:
	var fireball: bool = _uses_fireball()
	var spawn_pos: Vector2 = get_combat_position()
	AudioManager.play("blast" if fireball else "bow", spawn_pos, -6.0)
	var proj: Node2D = preload("res://scenes/projectile.tscn").instantiate()
	proj.position = spawn_pos
	proj.set("team", team)
	proj.set("damage", roundi(data.damage_per_hit))
	proj.set("is_fireball", fireball)
	# Dragons breathe fire: same splash as a fireball, flame-breath visuals.
	proj.set("is_dragon_flame", data.unit_name.to_lower() == "dragon")
	proj.set("speed", data.projectile_speed)
	proj.set("aoe_radius", data.aoe_radius)
	proj.set("target_position", target_pos)
	proj.set("source", self)
	# Try to find the actual target node for homing.
	if _target_unit != null and is_instance_valid(_target_unit):
		proj.set("homing_target", _target_unit)
	elif _target_building != null and is_instance_valid(_target_building):
		proj.set("homing_building", _target_building)
	get_node("/root/Main/Projectiles").add_child(proj)


func _process_mine(delta: float) -> void:
	var cell: GridWorld.Cell = _grid.get_cell(_target_cell)
	if cell == null or cell.type == GridWorld.CellType.EMPTY:
		# Already mined; idle or find next ore.
		_set_state(State.IDLE, "cell mined")
		return
	if carried_coin >= data.carry_capacity:
		deposit_coin()
		return
	if data.miner_level < cell.miner_level_required:
		_release_claim()
		_set_state(State.IDLE, "miner level too low")
		return

	var cell_world: Vector2 = _grid.grid_to_world(_target_cell)
	if global_position.distance_to(cell_world) > GridWorld.CELL_SIZE * 1.5:
		# Repath only when there is no path in flight (see _process_climb_up).
		if _path.is_empty():
			var adj: Vector2 = _nearest_adjacent_world(_target_cell)
			_repath(adj)
			if not _path_reaches(adj):
				_mark_cell_unreachable(_target_cell)
				_set_state(State.IDLE, "mine target unreachable")
				return
		_follow_path(delta)
		return

	_path.clear()
	_mine_target_angle = (cell_world - global_position).angle()
	_mine_timer -= delta
	_mine_hit_flash -= delta
	queue_redraw()
	if _mine_timer <= 0:
		_mine_timer = 1.0 / max(0.1, data.mining_swings_per_sec)
		_mine_hit_flash = 0.08
		var dmg: int = max(1, data.mining_damage)
		var coin: int = _grid.damage_cell(_target_cell, dmg, data.miner_level)
		AudioManager.play("pickaxe", global_position, -10.0)
		if coin > 0:
			carried_coin = min(data.carry_capacity, carried_coin + coin)
			queue_redraw()


func _process_deposit(delta: float) -> void:
	var building: Node2D = _friendly_building()
	if building == null:
		_set_state(State.IDLE, "no building for deposit")
		return
	var target_pos: Vector2 = building.call("get_deposit_point")
	var path_done: bool = not _path.is_empty() and _path_index >= _path.size()
	if global_position.distance_to(target_pos) > GridWorld.CELL_SIZE and not path_done:
		# Repath only when there is no path in flight (see _process_climb_up).
		if _path.is_empty():
			_repath(target_pos)
			# Surface-only fallback: the surface row is fully walkable, so walking
			# straight to the deposit point is harmless if A* hiccups.
			if _path.is_empty():
				_path.append(target_pos)
		_follow_path(delta)
		return
	building.call("deposit", self)
	_deposit_requested = false
	_set_state(State.IDLE, "deposit complete")


func _process_enter_mine(delta: float) -> void:
	var entry: Node2D = _nearest_friendly_mine_entry()
	if entry == null:
		_set_state(State.IDLE, "no mine entry")
		return
	# Path to the ladder top (centered on the shaft column). A* ends on the
	# cell center below the ladder top, so accept a completed path as arrival.
	var top: Vector2 = entry.call("get_ladder_top")
	var path_completed: bool = not _path.is_empty() and _path_index >= _path.size()
	if global_position.distance_to(top) > GridWorld.CELL_SIZE and not path_completed:
		# Repath only when there is no path in flight (see _process_climb_up).
		if _path.is_empty():
			_repath(top)
			# Fallback: walk straight to the mine entry if pathfinding fails.
			if _path.is_empty():
				_path.append(top)
		_follow_path(delta)
		return
	entry.call("enter_mine", self)
	_refresh_visibility()
	_set_state(State.IDLE, "entered mine")


func _process_exit_mine(delta: float) -> void:
	var entry: Node2D = _nearest_friendly_mine_entry()
	if entry == null:
		_set_state(State.IDLE, "no mine entry")
		return
	var target: Vector2 = entry.call("get_underground_position")
	if global_position.distance_to(target) > GridWorld.CELL_SIZE * 0.5:
		# Repath only when there is no path in flight (see _process_climb_up).
		if _path.is_empty():
			_repath(target)
			if _path.is_empty():
				_path.append(target)
		_follow_path(delta)
		return
	entry.call("exit_mine", self)
	_refresh_visibility()
	_set_state(State.IDLE, "exited mine")


func _process_climb_up(delta: float) -> void:
	var entry: Node2D = _nearest_friendly_mine_entry()
	if entry == null:
		_set_state(State.IDLE, "no mine entry")
		return

	var ladder_bottom: Vector2 = entry.call("get_ladder_bottom") + _movement_offset * 0.5
	var ladder_top: Vector2 = entry.call("get_ladder_top")

	# Phase 1: path to the bottom of the ladder. Once the path completes,
	# transition to the climb even if separation nudged us slightly past the
	# arrival threshold. A unit already on the ladder column at or above the
	# bottom skips phase 1 entirely — otherwise ascending in phase 2 would
	# grow the distance to the ladder bottom and re-trigger phase 1 (ping-pong).
	var on_column: bool = absf(global_position.x - ladder_bottom.x) <= 8.0 and global_position.y <= ladder_bottom.y + 4.0
	var arrival_threshold: float = GridWorld.CELL_SIZE * 0.35
	var path_completed: bool = not _path.is_empty() and _path_index >= _path.size()
	if not on_column and not path_completed and global_position.distance_to(ladder_bottom) > arrival_threshold:
		# Repath only when there is no path in flight. Repathing every frame
		# resets _path_index to the unit's own cell center, which can pull the
		# unit back and forth across a cell boundary and freeze it in place.
		if _path.is_empty():
			_repath(ladder_bottom)
			if _path.is_empty():
				_path.append(ladder_bottom)
		_follow_path(delta)
		return

	# Phase 2: climb straight up, sliding horizontally onto the ladder column
	# first instead of snapping.
	_path.clear()
	var dest: Vector2 = ladder_top
	var to_dest: Vector2 = dest - global_position
	if to_dest.length() <= 8.0:
		entry.call("exit_mine_climb", self)
		_refresh_visibility()
		_set_state(State.IDLE, "climbed out")
		return

	var climb_speed: float = data.speed * 0.9
	var step: float = climb_speed * delta
	var dx: float = dest.x - global_position.x
	if absf(dx) > 1.0:
		global_position.x += clampf(dx, -step, step)
	else:
		global_position.x = dest.x
		global_position.y += clampf(dest.y - global_position.y, -step, step)


func _process_climb_down(delta: float) -> void:
	var entry: Node2D = _nearest_friendly_mine_entry()
	if entry == null:
		_set_state(State.IDLE, "no mine entry")
		return
	var ladder_top: Vector2 = entry.call("get_ladder_top")
	var ladder_bottom: Vector2 = entry.call("get_ladder_bottom")

	# Phase 1: path to the top of the ladder. Once the path completes,
	# transition to the climb even if separation nudged us slightly past the
	# arrival threshold. A unit already on the ladder column at or below the
	# top skips phase 1 entirely — otherwise descending in phase 2 would grow
	# the distance to the ladder top and re-trigger phase 1 (ping-pong).
	var on_column: bool = absf(global_position.x - ladder_top.x) <= 8.0 and global_position.y >= ladder_top.y - 4.0
	var arrival_threshold: float = GridWorld.CELL_SIZE * 0.35
	var path_completed: bool = not _path.is_empty() and _path_index >= _path.size()
	if not on_column and not path_completed and global_position.distance_to(ladder_top) > arrival_threshold:
		# Repath only when there is no path in flight (see _process_climb_up).
		if _path.is_empty():
			_repath(ladder_top)
			if _path.is_empty():
				_path.append(ladder_top)
		_follow_path(delta)
		return

	# Phase 2: climb straight down, sliding horizontally onto the ladder column
	# first instead of snapping.
	_path.clear()
	var dest: Vector2 = ladder_bottom
	var to_dest: Vector2 = dest - global_position
	if to_dest.length() <= 8.0:
		entry.call("enter_mine_climb", self)
		_refresh_visibility()
		_set_state(State.IDLE, "climbed in")
		return

	var climb_speed: float = data.speed * 0.9
	var step: float = climb_speed * delta
	var dx: float = dest.x - global_position.x
	if absf(dx) > 1.0:
		global_position.x += clampf(dx, -step, step)
	else:
		global_position.x = dest.x
		global_position.y += clampf(dest.y - global_position.y, -step, step)


# ---------- Helpers ----------

func _set_state(new_state: State, reason: String = "") -> void:
	if _state == new_state:
		return
	var from: String = State.keys()[_state]
	var to: String = State.keys()[new_state]
	DebugLog.log_state("Unit %d" % get_instance_id(), from, to, reason)
	_state = new_state


func _clear_target() -> void:
	_release_claim()
	_rally_active = false
	_target_unit = null
	_target_building = null
	_target_cell = Vector2i(-9999, -9999)
	_pending_mine_cell = Vector2i(-9999, -9999)
	_target_position = Vector2.ZERO
	_path.clear()
	_path_index = 0


func _release_claim() -> void:
	if _target_cell != Vector2i(-9999, -9999):
		_grid.release_cell(_target_cell, get_instance_id())


## True when the current A* path ends on the target cell or one of its
## orthogonal/diagonal neighbours. find_path() redirects blocked endpoints to
## the nearest walkable cell, so a non-empty path can stop one cell short even
## though the miner can still stand next to the tile and dig.
func _path_reaches(world_target: Vector2) -> bool:
	if _path.is_empty():
		return false
	var end_grid: Vector2i = _grid.world_to_grid(_path[_path.size() - 1])
	var target_grid: Vector2i = _grid.world_to_grid(world_target)
	var diff: Vector2i = (end_grid - target_grid).abs()
	return diff.x <= 1 and diff.y <= 1


## Blacklists a cell this miner cannot path to and drops its reservation, so
## the next seek picks a different candidate instead of thrashing on this one.
func _mark_cell_unreachable(grid_pos: Vector2i) -> void:
	DebugLog.log_reject("Unit %d" % get_instance_id(), "mine_cell", "no path to " + str(grid_pos))
	_unreachable_cells[grid_pos] = Time.get_ticks_msec()
	_release_claim()


## True while the cell is on this miner's no-path blacklist (the AI consults
## this so it doesn't re-order cells the miner already failed to reach).
func is_cell_blacklisted(grid_pos: Vector2i) -> bool:
	if not _unreachable_cells.has(grid_pos):
		return false
	if Time.get_ticks_msec() - _unreachable_cells[grid_pos] >= _UNREACHABLE_FORGET_MS:
		_unreachable_cells.erase(grid_pos)
		return false
	return true


func _repath(target_world: Vector2) -> void:
	_path = _grid.find_path(global_position, target_world)
	_path_index = 0
	# Skip the first point if it is the current cell or if moving to it would
	# send us backward relative to the overall target direction (can happen when
	# the unit spawns on a sub-cell position and A* returns the cell center).
	if _path.size() > 1:
		var to_first: Vector2 = _path[0] - global_position
		var to_target: Vector2 = target_world - global_position
		if to_first.distance_to(Vector2.ZERO) < 4.0 or to_first.dot(to_target) < 0.0:
			_path_index = 1


func _nearest_adjacent_world(grid_pos: Vector2i) -> Vector2:
	var best: Vector2 = _grid.grid_to_world(grid_pos)
	var best_dist: float = 999999.0
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var adj: Vector2i = grid_pos + off
		if not _grid.is_solid(adj):
			var pos: Vector2 = _grid.grid_to_world(adj)
			var d: float = global_position.distance_squared_to(pos)
			if d < best_dist:
				best_dist = d
				best = pos
	return best


func _closest_point_on_rect(rect: Rect2, point: Vector2) -> Vector2:
	return Vector2(
		clampf(point.x, rect.position.x, rect.end.x),
		clampf(point.y, rect.position.y, rect.end.y)
	)


## Where to stand to attack a building: on the walkable surface row at its
## base, horizontally clamped to the building's span.
func _building_stand_point(building: Node2D) -> Vector2:
	var rect: Rect2 = building.call("get_bounds_rect")
	var x: float = clampf(global_position.x, rect.position.x, rect.end.x)
	return Vector2(x, rect.end.y + GridWorld.CELL_SIZE * 0.5)


## Flashes a red X where a command was rejected. Player-team only: command
## feedback is UI for the player, not noise around AI units.
func _spawn_reject_popup(at: Vector2) -> void:
	if team != GameManager.Team.PLAYER:
		return
	var popup: Node2D = preload("res://scenes/effects/reject_popup.tscn").instantiate()
	popup.global_position = at
	get_tree().current_scene.add_child(popup)


func _handle_idle_miner() -> void:
	# Full miners (and miners flagged with nothing left to dig) deposit at the
	# building. Otherwise surface miners climb down the ladder — digging only
	# happens inside the mine — and underground miners resume a pending mine
	# command or look for the next cell to dig.
	if carried_coin >= data.carry_capacity or (_deposit_requested and carried_coin > 0):
		deposit_coin()
	elif not is_underground:
		climb_down_ladder()
	elif _pending_mine_cell != Vector2i(-9999, -9999):
		mine_cell(_pending_mine_cell)
	elif _mine_exhausted:
		_idle_near_mine_entry()
	else:
		_find_and_mine()


func _find_and_mine() -> void:
	# If the bag is nearly full, cash in before starting a big ore tile that
	# would waste most of its value.
	if carried_coin > 0 and (data.carry_capacity - carried_coin) < 5:
		deposit_coin()
		return

	var center: Vector2i = _grid.world_to_grid(global_position)
	var team_dir: int = _team_dir()
	var id: int = get_instance_id()
	var now_ms: int = Time.get_ticks_msec()

	# Scan the whole own side (both sides once the wall is down) so no corner
	# of the mine is starved. Miners don't know where buried ore is: every
	# diggable face is equal until a tile proves itself — ore that already
	# took mining damage (hp < max_hp) yielded gold, so it counts as
	# discovered and is preferred over everything else.
	var wall_intact: bool = _grid.get_wall_hp() > 0
	var x_lo: int = GridWorld.X_MIN if team_dir == -1 or not wall_intact else 2
	var x_hi: int = GridWorld.X_MAX if team_dir == 1 or not wall_intact else -2

	var best_gold: Vector2i = Vector2i(-9999, -9999)
	var best_gold_dist: float = INF
	var best_cell: Vector2i = Vector2i(-9999, -9999)
	var best_cell_dist: float = INF

	for x in range(x_lo, x_hi + 1):
		for y in range(1, GridWorld.Y_MAX + 1):
			var pos: Vector2i = Vector2i(x, y)
			var cell: GridWorld.Cell = _grid.get_cell(pos)
			if cell == null:
				continue
			if cell.type != GridWorld.CellType.DIRT and cell.type != GridWorld.CellType.ORE:
				continue
			# Level gate enforced at seek time so miners never path to tiles
			# they can never dig.
			if data.miner_level < cell.miner_level_required:
				continue
			# Skip tiles another miner reserved.
			if not _grid.is_cell_claimable(pos, id):
				continue
			# Skip tiles this miner recently failed to reach.
			if _unreachable_cells.has(pos):
				if now_ms - _unreachable_cells[pos] < _UNREACHABLE_FORGET_MS:
					continue
				_unreachable_cells.erase(pos)
			# Fully surrounded tiles can't be stood next to yet.
			if not _has_empty_neighbor(pos):
				continue
			var d: float = center.distance_to(pos)
			if cell.type == GridWorld.CellType.ORE and (cell.hp < cell.max_hp or cell.sonar_revealed.get(team, false)):
				# Discovered gold: this tile already yielded coin or an Ore
				# Sonar scan revealed it, so the miner knows it is worth
				# coming back to.
				if d < best_gold_dist:
					best_gold_dist = d
					best_gold = pos
			elif d < best_cell_dist:
				best_cell_dist = d
				best_cell = pos

	if best_gold != Vector2i(-9999, -9999):
		mine_cell(best_gold)
		return
	if best_cell != Vector2i(-9999, -9999):
		mine_cell(best_cell)
		return

	# Nothing diggable remains in range: cash in any cargo, then wait near the
	# shaft instead of thrashing up and down.
	_mine_exhausted = true
	_exhausted_retry_timer = _EXHAUSTED_RETRY_SEC
	if carried_coin > 0:
		deposit_coin()
	else:
		_idle_near_mine_entry()


## A tile was destroyed (by anyone). It may have opened a new route or ore
## pocket, so drop the exhausted flag and forget any blacklist for that cell.
func _on_cell_destroyed(grid_pos: Vector2i) -> void:
	_mine_exhausted = false
	_unreachable_cells.erase(grid_pos)


## Exhausted-mine idle: only surface to cash in cargo. Empty-handed miners wait
## near the shaft bottom so the retry timer can re-open the seek without a
## pointless climb up and down.
func _idle_near_mine_entry() -> void:
	var entry: Node2D = _nearest_friendly_mine_entry()
	if entry == null:
		return
	if is_underground:
		if carried_coin > 0:
			climb_up_ladder()
		else:
			var bottom: Vector2 = entry.call("get_ladder_bottom")
			if global_position.distance_to(bottom) > GridWorld.CELL_SIZE * 1.5:
				move_to(bottom)
		return
	if global_position.distance_to(entry.global_position) > GridWorld.CELL_SIZE * 2.0:
		move_to(entry.global_position)


func _has_empty_neighbor(grid_pos: Vector2i) -> bool:
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not _grid.is_solid(grid_pos + off):
			return true
	return false


func _nearest_friendly_mine_entry() -> Node2D:
	var best: Node2D = null
	var best_dist: float = 999999.0
	for entry in get_tree().get_nodes_in_group("mine_entries"):
		if entry.get("team") == team:
			var d: float = global_position.distance_squared_to(entry.global_position)
			if d < best_dist:
				best_dist = d
				best = entry
	return best


func _die() -> void:
	# Idempotent: take_damage already guards, keep a second line of defence so
	# population is never removed twice for the same unit.
	if _state == State.DEAD:
		return
	_set_state(State.DEAD, "death")
	_dead_timer = 1.0
	_release_claim()
	# Miners drop their full cargo where they died (any team, any layer), so
	# the coin is never lost — any miner that walks over the pickup collects it.
	if data.is_miner and carried_coin > 0:
		_spawn_coin_pickup(carried_coin)
	remove_from_group("units")
	remove_from_group(team_name())
	EconomyManager.remove_population(team, data.population)
	died.emit(self)
	queue_redraw()


func _spawn_coin_pickup(amount: int) -> void:
	var pickup: Node2D = preload("res://scenes/effects/coin_pickup.tscn").instantiate()
	pickup.global_position = global_position
	pickup.set("coin_value", amount)
	get_tree().current_scene.add_child(pickup)


func _deferred_enter_mine_check() -> void:
	if data == null or not data.is_miner:
		return
	if not is_underground and _state == State.IDLE:
		climb_down_ladder()


func _connect_view_mode() -> void:
	var pc: PlayerController = get_node_or_null("/root/Main/PlayerController")
	if pc:
		if not pc.view_mode_changed.is_connected(_on_view_mode_changed):
			pc.view_mode_changed.connect(_on_view_mode_changed)
		_refresh_visibility()


func _refresh_visibility() -> void:
	var pc: PlayerController = get_node_or_null("/root/Main/PlayerController")
	if pc == null:
		return
	_on_view_mode_changed(pc.get_current_view_mode())


func _on_view_mode_changed(mode: PlayerController.ViewMode) -> void:
	# Surface and underground are shown simultaneously; keep the unit visible.
	visible = true


func team_name() -> String:
	return "player" if team == GameManager.Team.PLAYER else "enemy"


func _team_dir() -> int:
	return -1 if team == GameManager.Team.PLAYER else 1


func _is_enemy_underground(world_pos: Vector2) -> bool:
	if world_pos.y <= GridWorld.CELL_SIZE:
		return false
	return world_pos.x * _team_dir() < 0


func _start_flee() -> void:
	_flee_timer = 3.0
	var friendly_fighter: Unit = _nearest_friendly_fighter()
	# Only flee to a fighter on the same level; A* can't cross the
	# surface/underground boundary, so a surface fighter can't save a miner
	# underground (and vice versa).
	if friendly_fighter != null and friendly_fighter.is_underground == is_underground and global_position.distance_to(friendly_fighter.global_position) <= 300:
		_flee_target = friendly_fighter.global_position
	else:
		var entry: Node2D = _nearest_friendly_mine_entry()
		if entry == null:
			_flee_timer = 0.0
			return
		# Flee to the shaft on the level we're currently on.
		_flee_target = entry.call("get_underground_position") if is_underground else entry.global_position
	_clear_target()
	_target_position = _flee_target
	_set_state(State.MOVE, "flee")
	_repath(_flee_target)


func _continue_flee() -> void:
	if _flee_target == Vector2.ZERO:
		return
	_set_state(State.MOVE, "continue flee")
	_repath(_flee_target)


func _nearest_friendly_fighter() -> Unit:
	var best: Unit = null
	var best_dist: float = 999999.0
	for unit in get_tree().get_nodes_in_group(team_name()):
		if unit == self or not unit.data.is_fighter:
			continue
		if unit._state == State.DEAD:
			continue
		var d: float = global_position.distance_squared_to(unit.global_position)
		if d < best_dist:
			best_dist = d
			best = unit
	return best


func _handle_idle_fighter() -> void:
	if _rally_active:
		if _engage_rally_target_if_any():
			return
		_return_to_rally_point()
		return
	var target = _find_auto_attack_target()
	if target != null:
		if target is Unit:
			attack_unit(target)
		else:
			attack_building(target)
		return
	if is_underground:
		_patrol_underground()
		return
	_return_to_post_if_needed()


## Idle on the surface with nothing to fight: drift back to the standing point
## (spawn spot, last move destination, or hold position) so the army regroups
## instead of spreading across the map after every engagement.
func _return_to_post_if_needed() -> void:
	if _post_point == Vector2.ZERO:
		return
	if global_position.distance_to(_post_point) <= GridWorld.CELL_SIZE * 1.5:
		return
	_repath(_post_point + _movement_offset)
	if not _path.is_empty():
		_set_state(State.MOVE, "return to post")


## Rally hunt: engage the best surface target without cancelling the rally.
## Deliberately bypasses attack_unit(), because explicit commands clear the
## rally flag via _clear_target() and this engagement must keep it — after
## the kill the unit goes idle and resumes the hunt / returns to the point.
func _engage_rally_target_if_any() -> bool:
	var target: Unit = _find_rally_target()
	if target == null:
		return false
	DebugLog.log_command("Unit %d" % get_instance_id(), "rally engage", "target=%d" % target.get_instance_id())
	_target_unit = target
	_repath(target.global_position)
	_set_state(State.ATTACK, "rally engage")
	return true


## Rally targets: any living enemy on the surface — fighters AND miners.
## Underground enemies are out of scope (the rally sweep is a surface hunt).
## Skip targets this unit cannot damage (e.g. swordsman vs dragon).
func _find_rally_target() -> Unit:
	if is_underground:
		return null
	var best: Unit = null
	var best_dist: float = data.sight_range * data.sight_range
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == team or unit._state == State.DEAD:
			continue
		if unit.is_underground:
			continue
		if not can_damage_unit(unit):
			continue
		var d: float = combat_distance_squared_to(unit)
		if d <= best_dist:
			best_dist = d
			best = unit
	return best


func _return_to_rally_point() -> void:
	if global_position.distance_to(_rally_point) <= GridWorld.CELL_SIZE:
		return
	_target_position = _rally_point
	_repath(_rally_point)
	if not _path.is_empty():
		_set_state(State.MOVE, "return to rally point")


func _find_auto_attack_target():
	# 1. Enemy fighters in attack range (closest first).
	var best: Unit = null
	var best_dist: float = data.attack_range * data.attack_range
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == team or unit._state == State.DEAD:
			continue
		if not unit.data.is_fighter:
			continue
		if not can_damage_unit(unit):
			continue
		var d: float = combat_distance_squared_to(unit)
		if d <= best_dist:
			best_dist = d
			best = unit
	if best != null:
		return best

	# 2. Enemy fighters in sight range.
	best = null
	best_dist = data.sight_range * data.sight_range
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == team or unit._state == State.DEAD:
			continue
		if not unit.data.is_fighter:
			continue
		if not can_damage_unit(unit):
			continue
		var d: float = combat_distance_squared_to(unit)
		if d <= best_dist:
			best_dist = d
			best = unit
	if best != null:
		return best

	# 3. Enemy building in sight range.
	var enemy_building: Node2D = _get_enemy_building()
	if enemy_building != null:
		var d: float = get_combat_position().distance_squared_to(enemy_building.global_position)
		if d <= data.sight_range * data.sight_range:
			return enemy_building

	# 4. Enemy miners on our side of the wall (underground only).
	if is_underground:
		best = null
		best_dist = data.sight_range * data.sight_range
		var team_dir: int = _team_dir()
		for unit in get_tree().get_nodes_in_group("units"):
			if unit.team == team or unit._state == State.DEAD:
				continue
			if not unit.data.is_miner:
				continue
			if not can_damage_unit(unit):
				continue
			var grid_x: int = _grid.world_to_grid(unit.global_position).x
			if grid_x * team_dir < 2:
				continue
			var d: float = combat_distance_squared_to(unit)
			if d <= best_dist:
				best_dist = d
				best = unit
		if best != null:
			return best
	return null


func _patrol_underground() -> void:
	var entry: Node2D = _nearest_friendly_mine_entry()
	if entry == null:
		return
	var center: Vector2 = entry.call("get_underground_position")
	var angle: float = randf() * TAU
	var radius: float = randf_range(80, 240)
	var target: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
	# Clamp within the mine bounds.
	target.x = clamp(target.x, (GridWorld.X_MIN + 1) * GridWorld.CELL_SIZE, (GridWorld.X_MAX - 1) * GridWorld.CELL_SIZE)
	target.y = clamp(target.y, GridWorld.CELL_SIZE, GridWorld.Y_MAX * GridWorld.CELL_SIZE)
	move_to(target)


func _get_enemy_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") != team:
			return b
	return null


func _friendly_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == team:
			return b
	return null


func _add_hover_area() -> void:
	var area: Area2D = Area2D.new()
	area.name = "HoverArea"
	area.input_pickable = true
	area.mouse_entered.connect(func(): hovered = true; queue_redraw())
	area.mouse_exited.connect(func(): hovered = false; queue_redraw())
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	var sprite_texture: Texture2D = _get_unit_texture()
	var scale_factor: float = data.draw_scale if data != null and data.draw_scale > 0.0 else 1.0
	if sprite_texture != null:
		rect.size = sprite_texture.get_size() * scale_factor
	else:
		rect.size = Vector2(22, 22) * scale_factor
	shape.shape = rect
	area.add_child(shape)
	add_child(area)
	_sync_flight_visuals()


## Keep HoverArea / z_index aligned with surface flight altitude (drops to 0
## underground so tunnel dragons don't float through the ceiling).
func _sync_flight_visuals() -> void:
	var altitude: float = get_flight_altitude()
	if is_equal_approx(altitude, _flight_visual_altitude):
		return
	_flight_visual_altitude = altitude
	z_index = 1 if altitude > 0.0 else 0
	var area: Area2D = get_node_or_null("HoverArea") as Area2D
	if area != null:
		area.position = Vector2(0, -altitude)
	queue_redraw()


## Team-wide fighter upgrades (swordsman/archer/wizard): applies the
## authoritative per-level stats from Constants.FIGHTER_UPGRADES once per
## level change, healing the max_hp delta like miner upgrades do.
func _apply_fighter_upgrade() -> void:
	var unit_id: String = data.unit_name.to_lower()
	if not Constants.FIGHTER_UPGRADES.has(unit_id):
		return
	var level: int = EconomyManager.get_fighter_level(team, unit_id)
	if level == _fighter_level_applied:
		return
	var stats: Dictionary = Constants.FIGHTER_UPGRADES[unit_id][level]
	var hp_gain: int = stats.hp - data.max_hp
	data.max_hp = stats.hp
	data.damage_per_hit = stats.damage
	hp += hp_gain
	_fighter_level_applied = level
	queue_redraw()


func _apply_miner_upgrade() -> void:
	var level: int = EconomyManager.get_miner_level(team)
	if data.miner_level == level:
		return
	data.miner_level = level
	if level >= 2:
		data.max_dig_layer = 4
		data.carry_capacity += 10
		data.max_hp += 10
	if level >= 3:
		data.max_dig_layer = 7
		data.carry_capacity += 10
		data.max_hp += 15
	# Authoritative per-level stats — no incremental compounding.
	data.speed = Constants.MINER_STATS[level].speed
	var mining_stats: Dictionary = Constants.MINING_STATS[level]
	data.mining_damage = mining_stats.damage
	data.mining_swings_per_sec = mining_stats.swings
	hp += 10
	# New layers unlocked: stale no-path marks and the exhausted flag may now
	# be wrong, so reset the seek state and let the miner re-scan.
	_unreachable_cells.clear()
	_mine_exhausted = false
	queue_redraw()


## Research tree bonuses (ResearchManager): recomputes the team's researched
## stat bonuses into this unit's duplicated UnitData every tick from
## authoritative sources (captured base stats / Constants tables), so the
## result never compounds and survives upgrades rewriting the same stats.
func _apply_research_bonuses() -> void:
	if not _research_base_captured:
		_research_base_captured = true
		_base_attack_range = data.attack_range
		_base_aoe_radius = data.aoe_radius
		_base_attack_cooldown = data.attack_cooldown
	if data.is_miner:
		var level: int = clampi(data.miner_level, 1, 3)
		data.speed = Constants.MINER_STATS[level].speed + ResearchManager.get_stat_bonus(team, "miner_speed")
		data.carry_capacity = Constants.MINER_STATS[level].carry + int(ResearchManager.get_stat_bonus(team, "miner_carry"))
	elif data.is_fighter:
		match data.unit_name.to_lower():
			"swordsman":
				_armor = int(ResearchManager.get_stat_bonus(team, "swordsman_armor"))
				data.attack_cooldown = _base_attack_cooldown * (1.0 - ResearchManager.get_stat_bonus(team, "swordsman_cdr"))
			"archer":
				data.attack_range = _base_attack_range + ResearchManager.get_stat_bonus(team, "archer_range")
				data.attack_cooldown = _base_attack_cooldown * (1.0 - ResearchManager.get_stat_bonus(team, "archer_cdr"))
			"wizard":
				data.aoe_radius = _base_aoe_radius * (1.0 + ResearchManager.get_stat_bonus(team, "wizard_aoe_mult"))
				var fighter_level: int = EconomyManager.get_fighter_level(team, "wizard")
				data.damage_per_hit = Constants.FIGHTER_UPGRADES["wizard"][fighter_level].damage * (1.0 + ResearchManager.get_stat_bonus(team, "wizard_damage_mult"))


func _draw_pickaxe(draw_body: bool = true) -> void:
	# Base pose: pickaxe held at the miner's side.
	var pivot: Vector2 = Vector2(4, 4)
	var base_rotation: float = -PI / 4.0
	var swing: float = 0.0
	var lunge: Vector2 = Vector2.ZERO
	var striking: bool = false

	if _state == State.MINE:
		# Time the swing to the mining rate so the strike lands on each hit.
		var period: float = 1.0 / max(0.1, data.mining_swings_per_sec)
		var t: float = clamp(1.0 - (_mine_timer / period), 0.0, 1.0)
		# Aim the pickaxe toward the target cell.
		var aim_angle: float = _mine_target_angle - global_rotation
		base_rotation = aim_angle - PI / 6.0
		# Backswing (0%..60%), then sharp strike (60%..100%).
		if t < 0.6:
			swing = -PI * 0.55 * (t / 0.6)
		else:
			var strike_t: float = (t - 0.6) / 0.4
			swing = -PI * 0.55 + PI * 0.9 * strike_t
			striking = strike_t > 0.75
		if striking:
			lunge = Vector2(cos(aim_angle), sin(aim_angle)) * 3.0

	pivot += lunge
	if draw_body:
		draw_set_transform(pivot, base_rotation + swing, Vector2.ONE)
		# Handle.
		draw_line(Vector2.ZERO, Vector2(12, -12), GameManager.COLOR_STEEL, 2.5)
		# Pick head.
		draw_rect(Rect2(7, -16, 10, 5), GameManager.COLOR_STEEL, true)
		draw_line(Vector2(8, -18), Vector2(16, -14), Color.WHITE, 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Spark burst on the strike impact.
	if _state == State.MINE and (_mine_hit_flash > 0.0 or striking):
		var tip: Vector2 = pivot + Vector2(cos(base_rotation + swing), sin(base_rotation + swing)) * 16.0
		var burst_color: Color = Color.YELLOW if _mine_hit_flash > 0.0 else Color.ORANGE
		# Bright impact point.
		draw_circle(tip, 3.0, burst_color)
		draw_circle(tip, 1.5, Color.WHITE)
		# Fixed radial sparks so they do not flicker every redraw.
		var spark_count: int = 6
		for i in range(spark_count):
			var spark_angle: float = base_rotation + swing + (i / float(spark_count)) * TAU
			var spark_len: float = 5.0 if _mine_hit_flash > 0.0 else 3.0
			draw_line(tip, tip + Vector2(cos(spark_angle), sin(spark_angle)) * spark_len, burst_color, 1.5)


# ---------- Drawing ----------

# Shared soft radial texture for the miner lantern glow (built once).
static var _glow_texture: Texture2D = null


static func _make_glow_texture() -> Texture2D:
	var size: int = 64
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center: float = (size - 1) / 2.0
	for x in range(size):
		for y in range(size):
			var d: float = Vector2(x - center, y - center).length() / center
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 2))
	return ImageTexture.create_from_image(img)

func _get_unit_texture() -> Texture2D:
	var textures: Array[Texture2D]
	if team == GameManager.Team.PLAYER:
		textures = data.player_textures
	else:
		textures = data.enemy_textures

	if data.is_miner:
		var idx: int = clampi(data.miner_level - 1, 0, 2)
		if textures.size() > idx and textures[idx] != null:
			return textures[idx]
		return _MINER_TEXTURES[team][idx]

	if textures.size() > 0 and textures[0] != null:
		return textures[0]
	return null


func _draw() -> void:
	var color: Color = GameManager.COLOR_PLAYER if team == GameManager.Team.PLAYER else GameManager.COLOR_ENEMY
	var sprite_texture: Texture2D = _get_unit_texture()
	var scale_factor: float = data.draw_scale if data != null and data.draw_scale > 0.0 else 1.0
	var altitude: float = get_flight_altitude()
	var body_top: float
	var selection_radius: float

	if sprite_texture != null:
		var sprite_size: Vector2 = sprite_texture.get_size() * scale_factor
		body_top = -altitude - sprite_size.y / 2.0
		selection_radius = max(sprite_size.x, sprite_size.y) / 2.0 + 4.0
	else:
		var size: float = 18.0 * scale_factor
		body_top = -altitude - size / 2.0
		selection_radius = size + 4.0

	# Ground shadow under flying units (feet stay at local origin).
	if altitude > 0.0:
		var shadow_w: float = 18.0 * scale_factor
		var shadow_h: float = 6.0 * scale_factor
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(shadow_w / 10.0, shadow_h / 10.0))
		draw_circle(Vector2.ZERO, 5.0, Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Lantern glow: a warm halo around miners working underground (Phase 8).
	if data.is_miner and is_underground:
		if _glow_texture == null:
			_glow_texture = _make_glow_texture()
		var flicker: float = 0.30 + 0.05 * sin(Time.get_ticks_msec() / 220.0 + get_instance_id() % 100)
		var glow_size: float = 100.0
		draw_texture_rect(_glow_texture, Rect2(-glow_size / 2.0, -glow_size / 2.0, glow_size, glow_size), false, Color(1.0, 0.85, 0.55, flicker))

	# Selection indicator (gentle pulse) centered on the combat body.
	if selected:
		var pulse: float = 1.0 + 0.08 * sin(Time.get_ticks_msec() / 160.0)
		var ring_radius: float = selection_radius * pulse
		draw_texture_rect(_SELECTION_RING, Rect2(-ring_radius, -altitude - ring_radius, ring_radius * 2.0, ring_radius * 2.0), false)

	# Body (offset upward when flying).
	if sprite_texture != null:
		var sprite_size: Vector2 = sprite_texture.get_size() * scale_factor
		var dest := Rect2(-sprite_size / 2.0 + Vector2(0, -altitude), sprite_size)
		draw_texture_rect(sprite_texture, dest, false)
	else:
		var size: float = 18.0 * scale_factor
		var body_offset := Vector2(0, -altitude)
		draw_rect(Rect2(-size / 2.0 + body_offset.x, -size / 2.0 + body_offset.y, size, size), color, true)
		draw_rect(Rect2(-size / 2.0 + body_offset.x, -size / 2.0 + body_offset.y, size, size), GameManager.COLOR_SHADOW, false, 1.0)

		# Weapon / class indicator (fallback body).
		if data.unit_name == "Swordsman":
			draw_line(Vector2(4, 4) + body_offset, Vector2(16, -8) + body_offset, Color.WHITE, 3.0)
		elif data.unit_name == "Archer":
			draw_arc(Vector2(10, 0) + body_offset, 7, -PI / 2, PI / 2, 8, GameManager.COLOR_RUST, 2.0)
			draw_line(Vector2(10, -7) + body_offset, Vector2(10, 7) + body_offset, GameManager.COLOR_RUST, 2.0)
		elif data.unit_name == "Wizard":
			draw_line(Vector2(6, 6) + body_offset, Vector2(12, -14) + body_offset, GameManager.COLOR_RUST, 2.0)
			draw_circle(Vector2(12, -16) + body_offset, 4, Color.PURPLE)
		elif data.unit_name == "Dragon":
			draw_circle(Vector2(0, -2) + body_offset, 8 * scale_factor, color.darkened(0.15))
			draw_circle(Vector2(10, -6) + body_offset, 3 * scale_factor, Color(1.0, 0.45, 0.15))

	# Miner pickaxe animation and spark burst. Drawn on top of sprites as well
	# so the mining strike is readable even when textured miners are used.
	if data.is_miner:
		_draw_pickaxe(sprite_texture == null)

	# Impact hit flash.
	if _hit_flash_timer > 0:
		var impact_size: Vector2 = _IMPACT_TEXTURE.get_size()
		draw_texture(_IMPACT_TEXTURE, -impact_size / 2.0 + Vector2(0, -altitude))

	# HP bar when damaged, hovered, or selected.
	if selected or hovered or hp < data.max_hp:
		var hp_pct: float = float(hp) / float(data.max_hp)
		var bar_rect: Rect2 = Rect2(-10, body_top - 8, 20, 4)
		draw_texture_rect(_HP_BAR_BG, bar_rect, false)
		if hp_pct > 0.0:
			var fill_texture: Texture2D = _HP_BAR_GREEN if hp_pct >= 0.5 else _HP_BAR_ORANGE
			var fill_rect: Rect2 = Rect2(-10, body_top - 8, 20 * hp_pct, 4)
			var src_rect: Rect2 = Rect2(0, 0, fill_texture.get_width() * hp_pct, fill_texture.get_height())
			draw_texture_rect_region(fill_texture, fill_rect, src_rect)

	# Cargo readout above miners: carried / capacity, shown while hauling and
	# whenever the miner is hovered or selected.
	if data.is_miner and (carried_coin > 0 or selected or hovered):
		var cargo_text: String = "%d/%d" % [carried_coin, data.carry_capacity]
		var font: Font = ThemeDB.fallback_font
		var text_pos := Vector2(-20, body_top - 12)
		draw_string(font, text_pos + Vector2(1, 1), cargo_text, HORIZONTAL_ALIGNMENT_CENTER, 40, 10, Color(0, 0, 0, 0.8))
		draw_string(font, text_pos, cargo_text, HORIZONTAL_ALIGNMENT_CENTER, 40, 10, Color(0.984, 0.749, 0.141))
