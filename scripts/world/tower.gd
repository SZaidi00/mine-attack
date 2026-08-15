class_name Tower
extends Node2D

## Sentry tower (Revamp Phase 3): a static surface defense that auto-attacks
## the highest-priority enemy in range (fighters > miners > buildings).
## Only lanterns lift fog; towers do not provide vision. Towers are
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

# Selection highlight (set by PlayerController when the player clicks this
# structure; drawn as a gold ring around the base).
var selected: bool = false

var _attack_timer: float = 0.0
var _scan_timer: float = 0.0
var _target: Node2D = null
# Scan-beam angle (purely cosmetic). Idle towers point outward; when they
# have a target the beam snaps to face it, so it can aim behind the building.
var _scan_angle: float = 0.0
# Post-faction base stats; research bonuses recompute from these so already-
# placed towers update on research changes without compounding.
var _base_attack_range: float = 0.0
var _base_max_hp: int = 0
var _base_damage: int = 0
var _base_attack_cooldown: float = 0.0
var _base_build_time: float = 0.0

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
	_base_max_hp = max_hp
	_base_damage = damage
	_base_attack_cooldown = attack_cooldown
	_base_build_time = build_time
	_apply_research_bonuses()
	if not ResearchManager.research_completed.is_connected(_on_research_completed):
		ResearchManager.research_completed.connect(_on_research_completed)
	if not ResearchManager.research_changed.is_connected(_on_research_changed):
		ResearchManager.research_changed.connect(_on_research_changed)
	_scan_angle = 0.0 if team == GameManager.Team.PLAYER else PI
	queue_redraw()


func _on_research_completed(completed_team: GameManager.Team, _tech_id: String) -> void:
	if completed_team == team:
		_apply_research_bonuses()


func _on_research_changed(changed_team: GameManager.Team) -> void:
	if changed_team == team:
		_apply_research_bonuses()


## Apply all research-derived bonuses (Surface War range, Fortification HP/damage/
## build-time/cooldown, Artillery splash). Recomputed from post-faction bases so
## respecs and new research update already-placed towers.
func _apply_research_bonuses() -> void:
	# Range: Surface War + Sentry Network stack multiplicatively.
	var range_mult: float = 1.0
	if ResearchManager.has_branch(team, "surface_war"):
		range_mult *= _Constants.SURFACE_WAR_TOWER_RANGE_MULT
	range_mult *= (1.0 + ResearchManager.get_stat_bonus(team, "tower_range_mult"))
	attack_range = _base_attack_range * range_mult

	# Max HP: Fortification root + structure_hp_mult.
	var hp_mult: float = 1.0 + ResearchManager.get_stat_bonus(team, "structure_hp_mult")
	var new_max: int = roundi(_base_max_hp * hp_mult)
	if new_max != max_hp:
		var hp_delta: int = new_max - max_hp
		max_hp = new_max
		if hp_delta > 0:
			hp += hp_delta
		else:
			hp = clampi(hp, 0, max_hp)
		hp_changed.emit(hp, max_hp)

	# Damage: Artillery tower damage mult.
	damage = roundi(_base_damage * (1.0 + ResearchManager.get_stat_bonus(team, "tower_damage_mult")))

	# Attack cooldown / scan cadence: Sentry Network target-acquisition mult.
	attack_cooldown = _base_attack_cooldown * (1.0 - ResearchManager.get_stat_bonus(team, "tower_target_acquisition_mult"))

	# Build time: Fortification root build-time reduction.
	build_time = _base_build_time * maxf(0.1, 1.0 - ResearchManager.get_stat_bonus(team, "structure_build_time_mult"))
	queue_redraw()


func is_built() -> bool:
	return _is_built


func _process(delta: float) -> void:
	if not GameManager.game_active:
		return
	if not _is_built:
		_build_progress += delta
		if _build_progress >= build_time:
			_is_built = true
			construction_complete.emit(self)
		queue_redraw()
		return
	queue_redraw()
	_attack_timer -= delta
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.25
		_target = _pick_target()
	_update_scan_angle()
	if _target != null and _attack_timer <= 0.0:
		_fire_at(_target)


## Aim the cosmetic scan beam at the current target; idle towers point outward.
func _update_scan_angle() -> void:
	if _target != null and is_instance_valid(_target):
		var aim: Vector2 = _target.global_position
		if _target.has_method("get_combat_position"):
			aim = _target.get_combat_position()
		_scan_angle = (aim - global_position).angle()
	else:
		_scan_angle = 0.0 if team == GameManager.Team.PLAYER else PI


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
	# Artillery: tower shots splash in a radius.
	var splash_radius: float = ResearchManager.get_stat_bonus(team, "tower_splash_radius_cells") * GridWorld.CELL_SIZE
	if splash_radius > 0.0:
		proj.set("splash_radius", splash_radius)
		proj.set("splash_damage_pct", _Constants.ARTILLERY_SPLASH_DAMAGE_PCT)
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


## Player-initiated demolition: refunds 25% of the total cost directly as
## coin and removes the tower (no salvage pickup).
func demolish() -> void:
	remove_from_group("towers")
	destroyed.emit(self)
	AudioManager.play("blast", global_position, -6.0)
	var refund: int = roundi(total_cost * _Constants.STRUCTURE_DEMOLISH_REFUND_RATIO)
	if refund > 0 and team == GameManager.Team.PLAYER:
		EconomyManager.add_coin(team, refund)
	queue_free()


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

	# Selection highlight ring.
	if selected:
		draw_arc(Vector2(0, 14.0), 13.0, 0, TAU, 16, Color(1.0, 0.9, 0.25), 2.0)

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
