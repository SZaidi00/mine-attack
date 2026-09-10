class_name Corpse
extends Node2D

## A raisable corpse left on the surface by a dead swordsman, archer, or
## dragon (Necromancy research, Constants.NECRO_*). Self-expires after
## Constants.NECRO_CORPSE_DURATION seconds. Any team's wizard with the
## Necromancy branch can channel on it (see unit_necromancy.gd) to summon an
## undead copy; a claimed corpse is reserved by the channeling wizard so two
## necromancers never raise the same body.

var unit_data: UnitData
## "ground" (swordsman/archer corpse) or "dragon" — which raise toggle accepts it.
var corpse_category: String = "ground"
# Channel reservation: the wizard currently raising this corpse, if any.
var _claimed_by: Unit = null
var _lifetime: float = 0.0


func _init() -> void:
	add_to_group("corpses")


func setup(data: UnitData, category: String, life: float) -> void:
	unit_data = data
	corpse_category = category
	_lifetime = life


func is_claimed() -> bool:
	return _claimed_by != null and is_instance_valid(_claimed_by) and _claimed_by._state != Unit.State.DEAD


func claim(wizard: Unit) -> void:
	_claimed_by = wizard


func release(wizard: Unit) -> void:
	if _claimed_by == wizard:
		_claimed_by = null


## The raise completed: the undead takes the body.
func consume() -> void:
	queue_free()


func _process(delta: float) -> void:
	if not GameManager.game_active:
		return
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
	else:
		queue_redraw()  # keeps the necromantic shimmer pulsing


func _draw() -> void:
	var scale_factor: float = unit_data.draw_scale if unit_data != null and unit_data.draw_scale > 0.0 else 1.0
	# Sunken body: a flattened dark silhouette lying on the ground.
	var body_w: float = 22.0 * scale_factor
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, body_w / 2.0, Color(0.16, 0.2, 0.16, 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Necromantic shimmer so raisable corpses read at a glance.
	var pulse: float = 0.35 + 0.15 * sin(Time.get_ticks_msec() / 300.0 + get_instance_id() % 100)
	draw_circle(Vector2(0, -3), 3.0, Color(0.55, 0.95, 0.45, pulse))
	# Fading out over the last 3 seconds of the window.
	if _lifetime < 3.0:
		modulate.a = maxf(0.0, _lifetime / 3.0)
