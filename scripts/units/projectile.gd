extends Node2D

const _ARROW_TEXTURE: Texture2D = preload("res://frost_mines_assets/effects/projectile_arrow.png")
const _BLAST_TEXTURE: Texture2D = preload("res://frost_mines_assets/effects/projectile_blast.png")
const _BURNING_GROUND_SCENE: PackedScene = preload("res://scenes/effects/burning_ground.tscn")

@export var speed: float = 300.0
@export var damage: int = 10
@export var is_fireball: bool = false
## Dragon breath: same splash mechanics as a fireball, but drawn as a
## flickering flame head with a fading fire trail instead of the wizard's
## blast orb.
@export var is_dragon_flame: bool = false
@export var team: GameManager.Team = GameManager.Team.PLAYER
@export var aoe_radius: float = 40.0
## Arcane Shot (Arcane archer): the arrow pierces through the first target
## and also strikes the nearest enemy behind it.
var pierce: bool = false
## Color multiplier for the sprite (Arcane tower magic missiles).
var tint: Color = Color.WHITE

var target_position: Vector2 = Vector2.ZERO
var homing_target: Node2D = null
var homing_building: Node2D = null
# The unit that fired this projectile; passed to take_damage so AI targets can
# retaliate against ranged attackers too.
var source: Node2D = null

# Flame trail: recent global positions with an age, drawn as fading embers
# behind the flame head (code-drawn, no particle nodes to churn).
var _trail: Array = []  # { pos: Vector2, age: float }
var _trail_timer: float = 0.0
var _flicker: float = 0.0

const _TRAIL_LIFETIME: float = 0.28


func _ready() -> void:
	_flicker = randf() * TAU  # desync flicker between simultaneous breaths
	queue_redraw()


func _process(delta: float) -> void:
	# Match over: freeze mid-flight.
	if not GameManager.game_active:
		return
	# Revamp Phase 3: walls block projectiles — an enemy wall segment in the
	# flight path absorbs the shot.
	for wall in get_tree().get_nodes_in_group("walls"):
		if wall.team != team and wall.is_built() and wall.global_position.distance_to(global_position) <= 14.0:
			wall.take_damage(damage)
			queue_free()
			return
	_update_target_position()
	var dir: Vector2 = target_position - global_position
	var dist: float = dir.length()
	var step: float = speed * delta
	if is_dragon_flame:
		_update_flame_trail(delta)
	if dist <= step:
		_impact()
		queue_free()
		return
	global_position += dir.normalized() * step
	look_at(target_position)


func _update_flame_trail(delta: float) -> void:
	_flicker += delta
	_trail_timer -= delta
	if _trail_timer <= 0.0:
		_trail_timer = 0.02
		_trail.append({ "pos": global_position, "age": 0.0 })
	for p in _trail:
		p.age += delta
	while not _trail.is_empty() and _trail[0].age > _TRAIL_LIFETIME:
		_trail.pop_front()
	queue_redraw()


func _update_target_position() -> void:
	if homing_target != null and is_instance_valid(homing_target):
		if homing_target.has_method("get_combat_position"):
			target_position = homing_target.get_combat_position()
		else:
			target_position = homing_target.global_position
	elif homing_building != null and is_instance_valid(homing_building):
		target_position = homing_building.global_position


func _impact() -> void:
	var hit_radius: float = aoe_radius if is_fireball else 8.0
	var pos: Vector2 = global_position
	var source_faction: FactionData = null
	# is_instance_valid first: the firing unit may have died while the
	# projectile was in flight, and `is` on a freed instance is an error.
	if source != null and is_instance_valid(source) and source is Unit and source.data != null:
		source_faction = FactionManager.get_faction(source.team)
	var hit_units: Array = []
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.get("team") == team:
			continue
		var hit_pos: Vector2 = unit.global_position
		if unit.has_method("get_combat_position"):
			hit_pos = unit.get_combat_position()
		if hit_pos.distance_to(pos) <= hit_radius:
			unit.take_damage(damage, source)
			hit_units.append(unit)
			if source_faction != null:
				# Mana Burn (Arcane dragon): flame dampens the victim's next attack.
				if is_dragon_flame and source_faction.dragon_mana_burn:
					unit.set("_next_attack_damage_mult", 0.8)
				# Crush (Brute dragon): the hit stuns briefly.
				if is_dragon_flame and source_faction.dragon_crush:
					unit.call("apply_stun", 0.5)
				# Heavy Bolt (Brute archer): the hit slows movement by 30%.
				if not is_fireball and source_faction.archer_heavy_bolt \
						and source.data.unit_name.to_lower() == "archer":
					unit.call("apply_slow", 0.7, 2.0)
	# Arcane Shot (Arcane archer): a piercing arrow continues through the first
	# target and strikes the nearest enemy just behind it.
	if pierce and not is_fireball and not hit_units.is_empty():
		var best: Node2D = null
		var best_d2: float = 64.0 * 64.0
		for unit in get_tree().get_nodes_in_group("units"):
			if unit in hit_units or unit.get("team") == team:
				continue
			var second_pos: Vector2 = unit.global_position
			if unit.has_method("get_combat_position"):
				second_pos = unit.get_combat_position()
			var d2: float = second_pos.distance_squared_to(pos)
			if d2 <= best_d2:
				best_d2 = d2
				best = unit
		if best != null:
			best.take_damage(damage, source)
	if not is_fireball:
		return
	# Splash also damages buildings within the same area.
	for building in get_tree().get_nodes_in_group("buildings"):
		if building.get("team") == team:
			continue
		if building.global_position.distance_to(pos) <= hit_radius:
			building.call("take_damage", damage)
	# Crystal Forge (Revamp Phase 6): wizard fireballs (not dragon breath)
	# scorch the impact area, leaving a patch of burning ground.
	if not is_dragon_flame and ResearchManager.has_branch(team, "crystal_forge"):
		var patch: Node2D = _BURNING_GROUND_SCENE.instantiate()
		patch.set("team", team)
		patch.set("radius", aoe_radius)
		patch.global_position = pos
		get_node("/root/Main/Projectiles").add_child(patch)


func _draw() -> void:
	if is_dragon_flame:
		_draw_dragon_flame()
	elif is_fireball:
		var blast_size: Vector2 = _BLAST_TEXTURE.get_size()
		draw_texture(_BLAST_TEXTURE, -blast_size / 2.0, tint)
	else:
		var arrow_size: Vector2 = _ARROW_TEXTURE.get_size()
		draw_texture(_ARROW_TEXTURE, -arrow_size / 2.0, tint)


## Fire breath: a fading ember trail behind a layered, flickering flame head.
## The node faces its target (look_at), so +X is the direction of flight.
func _draw_dragon_flame() -> void:
	# Trail: older embers shrink and fade from orange to deep red.
	for p in _trail:
		var t: float = p.age / _TRAIL_LIFETIME
		var radius: float = lerpf(6.5, 1.5, t)
		var col := Color(1.0, lerpf(0.5, 0.15, t), 0.05, (1.0 - t) * 0.55)
		draw_circle(to_local(p.pos), radius, col)
	# Flame head: dark red body, orange mid, hot yellow-white core, with a
	# tongue of flame licking forward that flickers in length.
	var flick: float = sin(_flicker * 45.0) * 1.5 + sin(_flicker * 27.0) * 0.8
	draw_circle(Vector2.ZERO, 8.0 + flick * 0.4, Color(0.85, 0.22, 0.04, 0.9))
	draw_circle(Vector2(3.0, 0), 6.0 + flick * 0.3, Color(1.0, 0.5, 0.08, 0.95))
	draw_circle(Vector2(5.5, 0), 3.5, Color(1.0, 0.85, 0.45))
	draw_circle(Vector2(9.0 + flick, 0), 2.5, Color(1.0, 0.7, 0.2, 0.9))
