class_name NecroChannelFX
extends Node2D

## Sickly-green rising energy shown over a corpse while a wizard channels a
## raise (Necromancy). Purely code-drawn (precedent: burning_ground.gd):
## a pulsing ground glow, a summoning ring, and a few motes drifting upward.
## Spawned as a child of the corpse by unit_necromancy.gd; frees itself when
## the channel ends for any reason (interruption, completion, wizard death).

const _MOTES: int = 7
const _CYCLE_SEC: float = 1.6

var _corpse: Corpse = null
var _wizard: Unit = null
var _age: float = 0.0


func setup(corpse: Corpse, wizard: Unit) -> void:
	_corpse = corpse
	_wizard = wizard


func _ready() -> void:
	add_to_group("necro_channel_fx")


func _process(delta: float) -> void:
	# The channel can end without this node being told (corpse consumed or
	# expired, wizard killed mid-channel): follow the wizard's channel state
	# and free ourselves the moment it no longer points at our corpse.
	if _corpse == null or not is_instance_valid(_corpse):
		queue_free()
		return
	if _wizard == null or not is_instance_valid(_wizard) \
			or _wizard._state == Unit.State.DEAD or _wizard._necromancy._channel_target != _corpse:
		queue_free()
		return
	_age += delta
	queue_redraw()


func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_age * 6.0)
	# Pulsing ground glow and summoning ring over the body.
	draw_circle(Vector2.ZERO, 16.0, Color(0.45, 0.85, 0.3, 0.12 + 0.08 * pulse))
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 32, Color(0.55, 0.95, 0.4, 0.3 + 0.2 * pulse), 2.0)
	# Motes spiraling up out of the corpse, fading as they rise.
	for i in _MOTES:
		var t: float = fmod(_age * (0.7 + 0.15 * i) + float(i) * _CYCLE_SEC / _MOTES, _CYCLE_SEC) / _CYCLE_SEC
		var sway: float = sin(_age * 3.0 + i * 2.4) * 4.0 * t
		var alpha: float = (1.0 - t) * 0.7
		var r: float = 2.2 * (1.0 - t * 0.6)
		draw_circle(Vector2(sway, -4.0 - 26.0 * t), r, Color(0.6, 1.0, 0.45, alpha))
