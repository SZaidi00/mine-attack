## Original programmatic clips for the R7 rigid-pivot unit rigs. Tracks are
## authored against each instance's actual pivot paths and preserve authored
## base rotations; no external animation library or skeleton is required.
class_name UnitAnimationClips
extends RefCounted

const IDLE: StringName = &"idle"
const WALK: StringName = &"walk"
const ATTACK: StringName = &"attack"
const DEATH: StringName = &"death"

const IDLE_DURATION: float = 1.6
const WALK_DURATION: float = 0.8
const ATTACK_DURATION: float = 0.45
const DEATH_DURATION: float = 0.5

const HUMANOID_PIVOTS: Array[StringName] = [&"ArmL", &"ArmR", &"LegL", &"LegR", &"Tool"]


static func attach(model: Node3D, kind: StringName, pivots: Dictionary) -> AnimationPlayer:
	if kind != &"miner" and kind != &"swordsman":
		return null
	for pivot_name in HUMANOID_PIVOTS:
		if not pivots.get(pivot_name) is Node3D:
			return null

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_MANUAL
	model.add_child(player)
	player.root_node = player.get_path_to(model)

	var library := AnimationLibrary.new()
	library.add_animation(IDLE, _make_idle(model, pivots))
	library.add_animation(WALK, _make_walk(model, pivots))
	library.add_animation(ATTACK, _make_attack(model, pivots, kind))
	library.add_animation(DEATH, _make_death(model, pivots))
	player.add_animation_library(&"", library)
	return player


static func _new_animation(duration: float, loops: bool) -> Animation:
	var animation := Animation.new()
	animation.length = duration
	animation.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
	return animation


static func _add_rotation_track(animation: Animation, model: Node3D, pivot: Node3D,
		times: Array[float], angles: Array[float], axis := Vector3.RIGHT) -> void:
	var track := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, model.get_path_to(pivot))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	var base := pivot.quaternion
	for i in range(times.size()):
		animation.rotation_track_insert_key(track, times[i], base * Quaternion(axis, angles[i]))


static func _make_idle(model: Node3D, pivots: Dictionary) -> Animation:
	var animation := _new_animation(IDLE_DURATION, true)
	var times: Array[float] = [0.0, 0.4, 0.8, 1.2, 1.6]
	var still: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	_add_rotation_track(animation, model, pivots[&"ArmL"], times, [0.0, 0.08, 0.0, -0.08, 0.0])
	_add_rotation_track(animation, model, pivots[&"ArmR"], times, [0.0, -0.08, 0.0, 0.08, 0.0])
	_add_rotation_track(animation, model, pivots[&"LegL"], times, still)
	_add_rotation_track(animation, model, pivots[&"LegR"], times, still)
	_add_rotation_track(animation, model, pivots[&"Tool"], times, [0.0, 0.05, 0.0, -0.05, 0.0])
	return animation


static func _make_walk(model: Node3D, pivots: Dictionary) -> Animation:
	var animation := _new_animation(WALK_DURATION, true)
	var times: Array[float] = [0.0, 0.2, 0.4, 0.6, 0.8]
	_add_rotation_track(animation, model, pivots[&"ArmL"], times, [0.0, 0.6, 0.0, -0.6, 0.0])
	_add_rotation_track(animation, model, pivots[&"ArmR"], times, [0.0, -0.6, 0.0, 0.6, 0.0])
	_add_rotation_track(animation, model, pivots[&"LegL"], times, [0.0, -0.55, 0.0, 0.55, 0.0])
	_add_rotation_track(animation, model, pivots[&"LegR"], times, [0.0, 0.55, 0.0, -0.55, 0.0])
	_add_rotation_track(animation, model, pivots[&"Tool"], times, [0.0, 0.15, 0.0, -0.15, 0.0])
	return animation


static func _make_attack(model: Node3D, pivots: Dictionary, kind: StringName) -> Animation:
	var animation := _new_animation(ATTACK_DURATION, false)
	var times: Array[float] = [0.0, 0.1, 0.2, 0.45]
	var still: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var strike: float = 1.15 if kind == &"miner" else 0.95
	_add_rotation_track(animation, model, pivots[&"ArmL"], times, [0.0, -0.2, 0.35, 0.0])
	_add_rotation_track(animation, model, pivots[&"ArmR"], times, [0.0, 0.55, -0.9, 0.0])
	_add_rotation_track(animation, model, pivots[&"LegL"], times, still)
	_add_rotation_track(animation, model, pivots[&"LegR"], times, still)
	_add_rotation_track(animation, model, pivots[&"Tool"], times, [0.0, 0.65, -strike, 0.0])
	return animation


static func _make_death(model: Node3D, pivots: Dictionary) -> Animation:
	var animation := _new_animation(DEATH_DURATION, false)
	var times: Array[float] = [0.0, 0.25, 0.5]
	_add_rotation_track(animation, model, pivots[&"ArmL"], times, [0.0, -0.45, -0.9])
	_add_rotation_track(animation, model, pivots[&"ArmR"], times, [0.0, 0.55, 1.0])
	_add_rotation_track(animation, model, pivots[&"LegL"], times, [0.0, 0.35, 0.75])
	_add_rotation_track(animation, model, pivots[&"LegR"], times, [0.0, -0.2, -0.5])
	_add_rotation_track(animation, model, pivots[&"Tool"], times, [0.0, -0.55, -1.2])
	return animation
