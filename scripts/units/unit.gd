class_name Unit
extends Node2D

signal died(unit)

enum State { IDLE, MOVE, ATTACK, MINE, DEPOSIT, ENTER_MINE, EXIT_MINE, CLIMB_UP, CLIMB_DOWN, DEAD }

const _COIN_PICKUP_SCENE: PackedScene = preload("res://scenes/effects/coin_pickup.tscn")
const _REJECT_POPUP_SCENE: PackedScene = preload("res://scenes/effects/reject_popup.tscn")

# Helper modules are instance-based so unit.gd stays readable; preloading them
# here makes their class_name types resolvable in headless/export builds.
const UnitCommands = preload("res://scripts/units/unit_commands.gd")
const UnitCombat = preload("res://scripts/units/unit_combat.gd")
const UnitMining = preload("res://scripts/units/unit_mining.gd")
const UnitNavigation = preload("res://scripts/units/unit_navigation.gd")
const UnitAbilities = preload("res://scripts/units/unit_abilities.gd")
const UnitVisionTargeting = preload("res://scripts/units/unit_vision_targeting.gd")
const UnitRendering = preload("res://scripts/units/unit_rendering.gd")
const UnitIdle = preload("res://scripts/units/unit_idle.gd")

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
# Rolling window of damage taken: [age_seconds, amount] entries, aged in
# _process and pruned past 3s. Feeds get_incoming_dps(), which the AI's
# predictive retreat and bait-and-switch spring both read.
var _damage_log: Array = []
# The spot a fighter returns to when idle on the surface (its "standing
# point"). Set at spawn, updated by explicit move/stop orders; attack and
# auto-attack engagements leave it alone, so units regroup after a fight
# instead of spreading across the map.
var _post_point: Vector2 = Vector2.ZERO
# Defend leash: _hold_post is set by hold-style orders (stop / garrison) and
# cleared by movement and attack orders. _auto_engaged marks a target the
# idle handler picked on its own (not an explicit order). While both are
# set, the chase is leashed to UNIT_DEFEND_LEASH_RANGE from the standing
# point — a little chase is fine, then the unit drops the target and walks
# home. Explicit player orders are never leashed.
var _hold_post: bool = false
var _auto_engaged: bool = false
# Last applied flight altitude for HoverArea / z_index sync.
var _flight_visual_altitude: float = -1.0
# Faction (Revamp Phase 2): cached once in _ready; null = neutral (no pick,
# e.g. tests). Stat multipliers are folded into the per-tick recompute
# functions; the rest is applied once by _apply_faction_bonuses().
var _faction: FactionData = null
# Rune Blade (Arcane): the first hit of each engagement deals bonus damage.
var _has_hit_this_engagement: bool = false
# Mana Burn (Arcane dragon): debuff multiplier consumed by this unit's next
# damage-dealing hit.
var _next_attack_damage_mult: float = 1.0
# Miner Reveal (Arcane): personal ore-sonar cooldown.
var _reveal_timer: float = 0.0
# Swarm (Industrial): throttled proximity check around the captured base speed.
var _swarm_timer: float = 0.0
var _base_speed: float = 0.0
var _swarm_active: bool = false
# Heavy Bolt (Brute archer): movement-slow debuff.
var _slow_mult: float = 1.0
var _slow_timer: float = 0.0
# Crush (Brute dragon): hard stun — no movement or attacks while it lasts.
var _stun_timer: float = 0.0
# Blink (wizard): defensive teleport, 15s cooldown (Arcane: 10s).
var _blink_timer: float = 0.0
# Arcane Shot (Arcane archer): piercing-arrow cooldown (8s).
var _arcane_shot_timer: float = 0.0
# Volley (Industrial archer): group-fire cooldown (12s).
var _volley_timer: float = 0.0

# Instance helpers (created in _init so other nodes can call Unit APIs from
# their own _ready() before this node's _ready() runs).
var _commands: UnitCommands
var _combat: UnitCombat
var _mining: UnitMining
var _navigation: UnitNavigation
var _abilities: UnitAbilities
var _vision: UnitVisionTargeting
var _rendering: UnitRendering
var _idle: UnitIdle

@onready var _grid: GridWorld = get_node("/root/Main/World/GridWorld")


func _init() -> void:
	_init_helpers()


func _ready() -> void:
	if data == null:
		data = preload("res://scripts/resources/units/swordsman.tres")
	_faction = FactionManager.get_faction(team)
	if data.is_miner:
		_apply_miner_upgrade()
	_apply_research_bonuses()
	_apply_faction_bonuses()
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
		if not _grid.cell_destroyed.is_connected(_mining._on_cell_destroyed):
			_grid.cell_destroyed.connect(_mining._on_cell_destroyed)
		call_deferred("_deferred_enter_mine_check")


func _init_helpers() -> void:
	_commands = UnitCommands.new(self)
	_combat = UnitCombat.new(self)
	_mining = UnitMining.new(self)
	_navigation = UnitNavigation.new(self)
	_abilities = UnitAbilities.new(self)
	_vision = UnitVisionTargeting.new(self)
	_rendering = UnitRendering.new(self)
	_idle = UnitIdle.new(self)


func _process(delta: float) -> void:
	if _state == State.DEAD:
		_dead_timer -= delta
		modulate.a = max(0, _dead_timer)
		if _dead_timer <= 0:
			queue_free()
		return

	# Fog of War: enemy units are only drawn while inside the player's vision.
	# (Runs before the game_active freeze so the fog state stays correct on the
	# game-over screen too.)
	if team != GameManager.Team.PLAYER:
		visible = _grid.is_visible_to(GameManager.Team.PLAYER, global_position)

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
				_combat._spawn_heal_popup(whole)
				queue_redraw()

	# Age the incoming-damage window (game time, so it freezes with the match).
	for i in range(_damage_log.size() - 1, -1, -1):
		_damage_log[i][0] += delta
		if _damage_log[i][0] > 3.0:
			_damage_log.remove_at(i)

	# Revamp Phase 2 debuffs: the Heavy Bolt slow expires back to full speed;
	# the Crush stun freezes all actions (regen above still ticks).
	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_mult = 1.0
	if _stun_timer > 0.0:
		_stun_timer -= delta
		return

	if _hit_flash_timer > 0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0:
			queue_redraw()

	if _flee_timer > 0:
		_flee_timer -= delta
		if _state == State.IDLE:
			_navigation._continue_flee()
		match _state:
			State.MOVE:
				_navigation._follow_path(delta)
		return

	_apply_research_bonuses()
	_sync_flight_visuals()
	if data.is_miner:
		_apply_miner_upgrade()
		# Miner Reveal (Arcane): a personal 4-cell ore scan every 30s while
		# underground — same reveal mechanism as the Ore Sonar research.
		if _faction != null and _faction.miner_reveal and is_underground:
			_reveal_timer -= delta
			if _reveal_timer <= 0.0:
				_reveal_timer = 30.0
				_abilities.miner_reveal_scan()
		if _mine_exhausted:
			_exhausted_retry_timer -= delta
			if _exhausted_retry_timer <= 0.0:
				_mine_exhausted = false
		if _state == State.IDLE:
			_mining._handle_idle_miner()
	elif data.is_fighter:
		_apply_fighter_upgrade()
		# Swarm (Industrial): swordsmen move faster in groups of 3+.
		if _faction != null and _faction.swordsman_swarm and data.unit_name.to_lower() == "swordsman":
			_swarm_timer -= delta
			if _swarm_timer <= 0.0:
				_swarm_timer = 0.25
				_abilities.update_swarm()
		match data.unit_name.to_lower():
			"wizard":
				# Blink: teleport away from a point-blank melee threat (15s
				# cooldown, 10s for Arcane).
				_blink_timer -= delta
				if _blink_timer <= 0.0:
					_abilities.try_blink()
			"archer":
				_arcane_shot_timer -= delta
				_volley_timer -= delta
		if _state == State.IDLE:
			_idle._handle_idle_fighter()
		elif _rally_active and _state == State.MOVE:
			# Attack-move: scan for surface enemies while travelling.
			_rally_scan_timer -= delta
			if _rally_scan_timer <= 0.0:
				_rally_scan_timer = 0.25
				_idle._engage_rally_target_if_any()
	# Keep the selection ring pulsing and the lantern glow flickering.
	if selected or (data.is_miner and is_underground) or get_flight_altitude() > 0.0:
		queue_redraw()
	match _state:
		State.MOVE:
			_navigation._follow_path(delta)
		State.ATTACK:
			_combat._process_attack(delta)
		State.MINE:
			_mining._process_mine(delta)
		State.DEPOSIT:
			_commands._process_deposit(delta)
		State.ENTER_MINE:
			_commands._process_enter_mine(delta)
		State.EXIT_MINE:
			_commands._process_exit_mine(delta)
		State.CLIMB_UP:
			_commands._process_climb_up(delta)
		State.CLIMB_DOWN:
			_commands._process_climb_down(delta)


func _draw() -> void:
	if _rendering != null:
		_rendering.draw()


# ---------- Public command wrappers ----------

func move_to(world_pos: Vector2) -> void:
	_commands.move_to(world_pos)


func attack_unit(target) -> void:
	_commands.attack_unit(target)


func attack_building(target: Node2D) -> void:
	_commands.attack_building(target)


func mine_cell(grid_pos: Vector2i) -> void:
	_commands.mine_cell(grid_pos)


func deposit_coin() -> void:
	_commands.deposit_coin()


func enter_mine() -> void:
	_commands.enter_mine()


func exit_mine() -> void:
	_commands.exit_mine()


func climb_up_ladder() -> void:
	_commands.climb_up_ladder()


func climb_down_ladder() -> void:
	_commands.climb_down_ladder()


func stop() -> void:
	_commands.stop()


func kill() -> void:
	_commands.kill()


func garrison_home() -> void:
	_commands.garrison_home()


func rally_to(world_pos: Vector2) -> void:
	_commands.rally_to(world_pos)


# ---------- Public combat / status wrappers ----------

func take_damage(amount: int, attacker: Node2D = null) -> void:
	_combat.take_damage(amount, attacker)


## Revamp Phase 4: lava deaths are instant and drop no cargo — the coin melts.
func die_in_lava() -> void:
	carried_coin = 0
	_die()


func get_incoming_dps() -> float:
	return _combat.get_incoming_dps()


func can_be_damaged_by(attacker: Node2D) -> bool:
	return _combat.can_be_damaged_by(attacker)


func can_damage_unit(target: Node2D) -> bool:
	return _combat.can_damage_unit(target)


func apply_slow(mult: float, duration: float) -> void:
	_abilities.apply_slow(mult, duration)


func apply_stun(duration: float) -> void:
	_abilities.apply_stun(duration)


# ---------- Public vision / mining wrappers ----------

func get_vision_radius() -> int:
	return _vision.get_vision_radius()


func get_vision_layer() -> int:
	return _vision.get_vision_layer()


func is_cell_blacklisted(grid_pos: Vector2i) -> bool:
	return _mining.is_cell_blacklisted(grid_pos)


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


# ---------- Backwards-compatibility wrappers ----------
# The test suite (and a few direct call sites) reach into private Unit helpers
# that now live in the instance-based modules below. Thin wrappers keep the
# public surface identical without exposing helper internals.

func _has_empty_neighbor(grid_pos: Vector2i) -> bool:
	return _mining._has_empty_neighbor(grid_pos)


func _find_and_mine() -> void:
	_mining._find_and_mine()


func _find_auto_attack_target():
	return _vision._find_auto_attack_target()


func _process_attack(delta: float) -> void:
	_combat._process_attack(delta)


func _follow_path(delta: float) -> void:
	_navigation._follow_path(delta)


func _nearest_visible_enemy_structure() -> Node2D:
	return _vision._nearest_visible_enemy_structure()


func _is_walkable_point(world_pos: Vector2) -> bool:
	return _navigation._is_walkable_point(world_pos)


func _find_rally_target() -> Unit:
	return _vision._find_rally_target()


func _engage_rally_target_if_any() -> bool:
	return _idle._engage_rally_target_if_any()


func _try_blink() -> void:
	_abilities.try_blink()


func _handle_idle_fighter() -> void:
	_idle._handle_idle_fighter()


func _repath(world_pos: Vector2) -> void:
	_navigation._repath(world_pos)


# ---------- Core state / lifecycle (kept in Unit) ----------

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
	_auto_engaged = false
	# Rune Blade (Arcane): a new engagement means the first-hit bonus re-arms.
	_has_hit_this_engagement = false
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
	var pickup: Node2D = _COIN_PICKUP_SCENE.instantiate()
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


func _friendly_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == team:
			return b
	return null


func _get_enemy_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") != team:
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
	var sprite_texture: Texture2D = _rendering._get_unit_texture()
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


## Flashes a red X where a command was rejected. Player-team only: command
## feedback is UI for the player, not noise around AI units.
func _spawn_reject_popup(at: Vector2) -> void:
	if team != GameManager.Team.PLAYER:
		return
	var popup: Node2D = _REJECT_POPUP_SCENE.instantiate()
	popup.global_position = at
	get_tree().current_scene.add_child(popup)


## Team-wide fighter upgrades (swordsman/archer/wizard): applies the
## authoritative per-level stats from Constants.FIGHTER_UPGRADES once per
## level change, healing the max_hp delta like miner upgrades do.
## Faction multipliers (Revamp Phase 2) are folded in here so level-ups
## recompute from the same modified values.
func _apply_fighter_upgrade() -> void:
	var unit_id: String = data.unit_name.to_lower()
	if not Constants.FIGHTER_UPGRADES.has(unit_id):
		return
	var level: int = EconomyManager.get_fighter_level(team, unit_id)
	if level == _fighter_level_applied:
		return
	var stats: Dictionary = Constants.FIGHTER_UPGRADES[unit_id][level]
	var hp_mult: float = 1.0
	var dmg_mult: float = 1.0
	if _faction != null:
		hp_mult = _faction.get(unit_id + "_hp_mult")
		dmg_mult = _faction.get(unit_id + "_dmg_mult")
	var new_max_hp: int = roundi(stats.hp * hp_mult)
	var hp_gain: int = new_max_hp - data.max_hp
	data.max_hp = new_max_hp
	data.damage_per_hit = stats.damage * dmg_mult
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
	# Authoritative per-level stats — no incremental compounding. The faction
	# mining-speed multiplier (Revamp Phase 2) rides on top.
	data.speed = Constants.MINER_STATS[level].speed
	var mining_stats: Dictionary = Constants.MINING_STATS[level]
	data.mining_damage = mining_stats.damage
	data.mining_swings_per_sec = mining_stats.swings * (_faction.miner_mining_mult if _faction != null else 1.0)
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
		# Faction carry bonus (Revamp Phase 2) composes with research here so
		# the per-tick recompute never erases it.
		var carry_bonus: int = _faction.miner_carry_bonus if _faction != null else 0
		data.speed = Constants.MINER_STATS[level].speed + ResearchManager.get_stat_bonus(team, "miner_speed")
		data.carry_capacity = maxi(1, Constants.MINER_STATS[level].carry + int(ResearchManager.get_stat_bonus(team, "miner_carry")) + carry_bonus)
	elif data.is_fighter:
		match data.unit_name.to_lower():
			"swordsman":
				_armor = int(ResearchManager.get_stat_bonus(team, "swordsman_armor"))
				data.attack_cooldown = _base_attack_cooldown * (1.0 - ResearchManager.get_stat_bonus(team, "swordsman_cdr"))
			"archer":
				data.attack_range = _base_attack_range + ResearchManager.get_stat_bonus(team, "archer_range")
				data.attack_cooldown = _base_attack_cooldown * (1.0 - ResearchManager.get_stat_bonus(team, "archer_cdr"))
			"wizard":
				var aoe_mult: float = 1.0 + ResearchManager.get_stat_bonus(team, "wizard_aoe_mult")
				# Fortify (Brute): fireballs splash 30% wider.
				if _faction != null and _faction.wizard_fortify:
					aoe_mult += 0.3
				data.aoe_radius = _base_aoe_radius * aoe_mult
				var fighter_level: int = EconomyManager.get_fighter_level(team, "wizard")
				var wizard_dmg_mult: float = _faction.wizard_dmg_mult if _faction != null else 1.0
				data.damage_per_hit = Constants.FIGHTER_UPGRADES["wizard"][fighter_level].damage * (1.0 + ResearchManager.get_stat_bonus(team, "wizard_damage_mult")) * wizard_dmg_mult


## Revamp Phase 2: one-shot faction stat modifiers at spawn. Fields that are
## re-derived every tick elsewhere (miner speed/carry, wizard damage/AoE) get
## their faction terms inside those recompute functions instead, so the two
## systems compose without compounding.
func _apply_faction_bonuses() -> void:
	if _faction != null:
		if data.is_miner:
			data.max_hp += _faction.miner_hp_bonus
			data.mining_swings_per_sec *= _faction.miner_mining_mult
		elif data.is_fighter:
			match data.unit_name.to_lower():
				"swordsman":
					data.max_hp = roundi(data.max_hp * _faction.swordsman_hp_mult)
					data.damage_per_hit *= _faction.swordsman_dmg_mult
				"archer":
					data.max_hp = roundi(data.max_hp * _faction.archer_hp_mult)
					data.damage_per_hit *= _faction.archer_dmg_mult
				"wizard":
					data.max_hp = roundi(data.max_hp * _faction.wizard_hp_mult)
				"dragon":
					data.max_hp = roundi(data.max_hp * _faction.dragon_hp_mult)
					data.damage_per_hit *= _faction.dragon_dmg_mult
	_base_speed = data.speed
