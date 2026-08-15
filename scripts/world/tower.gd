class_name Tower
extends Node2D

## Sentry tower (Revamp Phase 3): a static surface defense that auto-attacks
## the highest-priority enemy in range (fighters > miners > buildings) and
## doubles as a surface vision source once construction finishes. Towers are
## invulnerable while under construction; a destroyed tower drops half its
## build cost as a coin pickup. Faction variants (Arcane cheaper-HP magic
## missiles, Brute heavy bolts, Industrial fast build) come from FactionData.

signal hp_changed(current: int, maximum: int)
signal destroyed(tower: Tower)
signal construction_complete(tower: Tower)

const _Constants = preload("res://scripts/autoload/constants.gd")

const _TEXTURES: Dictionary = {
	GameManager.Team.PLAYER: preload("res://frost_mines_assets/props/tower_player.png"),
	GameManager.Team.ENEMY: preload("res://frost_mines_assets/props/tower_enemy.png"),
}

var team: GameManager.Team = GameManager.Team.PLAYER

var vision_radius: int = _Constants.TOWER_VISION
var attack_range: float = _Constants.TOWER_RANGE_CELLS * GridWorld.CELL_SIZE
var damage: int = _Constants.TOWER_DAMAGE
var attack_cooldown: float = _Constants.TOWER_COOLDOWN
var max_hp: int = _Constants.TOWER_HP
var hp: int = 0
var build_time: float = _Constants.TOWER_BUILD_TIME
# Coin spent on this tower (salvage pays half).
var total_cost: int = 0

var _build_progress: float = 0.0
var _is_built: bool = false
var _attack_timer: float = 0.0
var _scan_timer: float = 0.0
var _target: Node2D = null
# Rotating scan-beam angle (purely cosmetic).
var _scan_angle: float = 0.0
# Post-faction attack range; the Surface Warfare branch bonus multiplies this
# base so recomputing on research changes never compounds.
var _base_attack_range: float = 0.0

@onready var _grid: GridWorld = get_node("/root/Main/World/GridWorld")


func _ready() -> void:
	add_to_group("towers")
	# Faction variant stats (Revamp Phase 2 hooks; neutral without a pick).
	var faction: FactionData = FactionManager.get_faction(team)
	if faction != null:
		max_hp = faction.tower_hp
		damage = faction.tower_damage
		attack_cooldown = faction.tower_cooldown
		build_time = _Constants.TOWER_BUILD_TIME * faction.tower_build_time_mult
	hp = max_hp
	_base_attack_range = attack_range
	_apply_branch_range()
	if not ResearchManager.research_completed.is_connected(_on_research_completed):
		ResearchManager.research_completed.connect(_on_research_completed)
	if not ResearchManager.research_changed.is_connected(_on_research_changed):
		ResearchManager.research_changed.connect(_on_research_changed)
	_scan_angle = randf() * TAU
	queue_redraw()


func _on_research_completed(completed_team: GameManager.Team, _tech_id: String) -> void:
	if completed_team == team:
		_apply_branch_range()


func _on_research_changed(changed_team: GameManager.Team) -> void:
	if changed_team == team:
		_apply_branch_range()


## Phase 6: the Surface Warfare branch widens tower range; respec reverts it.
## Recomputed from the post-faction base so already-placed towers update.
func _apply_branch_range() -> void:
	attack_range = _base_attack_range
	if ResearchManager.has_branch(team, "surface_war"):
		attack_range = _base_attack_range * _Constants.SURFACE_WAR_TOWER_RANGE_MULT


func is_built() -> bool:
	return _is_built


func _process(delta: float) -> void:
	_scan_angle += delta * 0.8
	if not GameManager.game_active:
		return
	if not _is_built:
		_build_progress += delta
		if _build_progress >= build_time:
			_is_built = true
			construction_complete.emit(self)
		queue_redraw()
		return
	queue_redraw()  # scan beam keeps rotating
	_attack_timer -= delta
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.25
		_target = _pick_target()
	if _target != null and _attack_timer <= 0.0:
		_fire_at(_target)


## Target priority per the guide: fighters > miners > buildings. Only what
## the team can currently see (Fog of War), surface targets only.
func _pick_target() -> Node2D:
	var best_fighter: Unit = null
	var best_fighter_d2: float = INF
	var best_miner: Unit = null
	var best_miner_d2: float = INF
	var range_sq: float = attack_range * attack_range
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == team or unit._state == Unit.State.DEAD or unit.is_underground:
			continue
		if not _grid.is_visible_to(team, unit.global_position):
			continue
		var d2: float = global_position.distance_squared_to(unit.get_combat_position())
		if d2 > range_sq:
			continue
		if unit.data.is_fighter and d2 < best_fighter_d2:
			best_fighter_d2 = d2
			best_fighter = unit
		elif unit.data.is_miner and d2 < best_miner_d2:
			best_miner_d2 = d2
			best_miner = unit
	if best_fighter != null:
		return best_fighter
	if best_miner != null:
		return best_miner
	# Buildings: only the enemy base, and only once the team remembers it.
	for building in get_tree().get_nodes_in_group("buildings"):
		if building.team == team:
			continue
		if not _grid.is_remembered_by(team, building.global_position):
			continue
		if global_position.distance_squared_to(building.global_position) <= range_sq:
			return building
	return null


func _fire_at(target: Node2D) -> void:
	_attack_timer = attack_cooldown
	var proj: Node2D = preload("res://scenes/projectile.tscn").instantiate()
	# The muzzle sits near the top of the tower sprite.
	proj.position = global_position + Vector2(0, -56.0)
	proj.set("team", team)
	proj.set("damage", damage)
	proj.set("speed", 300.0)
	proj.set("source", self)
	var aim: Vector2 = target.global_position
	if target.has_method("get_combat_position"):
		aim = target.get_combat_position()
	proj.set("target_position", aim)
	if target is Unit:
		proj.set("homing_target", target)
	else:
		proj.set("homing_building", target)
	# Arcane variant: homing magic missiles.
	var faction: FactionData = FactionManager.get_faction(team)
	if faction != null and faction.faction_id == "arcane":
		proj.set("tint", Color(0.75, 0.55, 1.0))
	AudioManager.play("bow", global_position, -10.0)
	get_node("/root/Main/Projectiles").add_child(proj)


func take_damage(amount: int) -> void:
	# Invulnerable while under construction (guide rule, same as lanterns).
	if not _is_built:
		return
	hp -= amount
	hp_changed.emit(hp, max_hp)
	queue_redraw()
	if hp <= 0:
		_destroy()


func _destroy() -> void:
	remove_from_group("towers")
	destroyed.emit(self)
	AudioManager.play("blast", global_position, -6.0)
	var salvage: int = roundi(total_cost * _Constants.STRUCTURE_SALVAGE_RATIO)
	if salvage > 0:
		var pickup: Node2D = preload("res://scenes/effects/coin_pickup.tscn").instantiate()
		pickup.global_position = global_position
		pickup.set("coin_value", salvage)
		get_tree().current_scene.add_child(pickup)
	queue_free()


## Interaction rect for unit.attack_building(): a zero-height strip at the
## tower's ground line so the stand point lands on the walkable surface row.
func get_bounds_rect() -> Rect2:
	return Rect2(global_position.x - 24.0, 0.0, 48.0, 0.0)


func _draw() -> void:
	var texture: Texture2D = _TEXTURES[team]
	var tex_size: Vector2 = texture.get_size()
	var alpha: float = 1.0 if _is_built else 0.55
	# The tower stands on the ground line at the bottom of the surface row.
	var dest := Rect2(Vector2(-tex_size.x / 2.0, 16.0 - tex_size.y), tex_size)
	draw_texture_rect(texture, dest, false, Color(1, 1, 1, alpha))

	# Rotating scan beam once built (a slim sweeping wedge from the top).
	if _is_built:
		var origin := Vector2(0, 16.0 - tex_size.y + 8.0)
		var beam := Vector2.RIGHT.rotated(_scan_angle) * 26.0
		draw_line(origin, origin + beam, Color(1.0, 0.85, 0.4, 0.35), 3.0)

	# Team marker ring at the base.
	var team_color: Color = GameManager.COLOR_PLAYER if team == GameManager.Team.PLAYER else GameManager.COLOR_ENEMY
	draw_arc(Vector2(0, 14.0), 10.0, 0, TAU, 14, team_color, 2.0)

	# Construction progress bar / HP bar.
	if not _is_built:
		var pct: float = clampf(_build_progress / build_time, 0.0, 1.0)
		var bar_rect := Rect2(-14, dest.position.y - 10, 28, 4)
		draw_rect(bar_rect, Color(0, 0, 0, 0.7), true)
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * pct, bar_rect.size.y)), Color(0.5, 0.8, 1.0), true)
	elif hp < max_hp:
		var pct: float = clampf(float(hp) / float(max_hp), 0.0, 1.0)
		var bar_rect := Rect2(-14, dest.position.y - 10, 28, 4)
		draw_rect(bar_rect, Color(0, 0, 0, 0.7), true)
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * pct, bar_rect.size.y)), Color.GREEN if pct >= 0.5 else Color.ORANGE, true)
