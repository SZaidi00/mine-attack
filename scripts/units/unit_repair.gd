class_name UnitRepair
extends RefCounted

## Engineer support behavior: repairs STRUCTURES only (walls, towers,
## lanterns, and the team's main building) — never units (units regen out of
## combat via UNIT_REGEN_*). The channel restores
## Constants.ENGINEER_REPAIR_HP_PER_SEC and charges
## Constants.ENGINEER_REPAIR_COIN_PER_HP from the team's wallet as each point
## lands; it pauses in place when the team cannot afford the next point, and
## holds while the structure sits inside the recent-damage lockout
## (ENGINEER_REPAIR_LOCKOUT_SEC — a live siege can never be out-repaired).
## Idle engineers auto-seek the nearest damaged friendly structure, like idle
## miners auto-seek ore.

var unit: Unit

# Channel accumulators: fractional HP/coin carried between frames (the wallet
# is integer coin, so sub-coin repair debt accumulates until a full coin is
# due).
var _hp_accum: float = 0.0
var _coin_owed: float = 0.0
# Throttle for the channel work sound.
var _sound_timer: float = 0.0


# Throttle auto-seek after an unreachable target so the idle handler does not
# repath (and reject-popup spam) every frame. Explicit orders reset it via
# _reset_channel.
var _seek_failed_ms: int = -10000


func _init(u: Unit) -> void:
	unit = u


## Idle behavior: seek the nearest damaged friendly structure and repair it.
## An engineer that ended up underground climbs back out — repairs are a
## surface job.
func _handle_idle_engineer() -> void:
	if unit.is_underground:
		unit._commands.climb_up_ladder()
		return
	if Time.get_ticks_msec() - _seek_failed_ms < 2000:
		return
	var target: Node2D = _find_repair_target()
	if target == null:
		return
	unit._commands.repair_structure(target)
	if unit._state != Unit.State.REPAIR:
		_seek_failed_ms = Time.get_ticks_msec()


## Nearest damaged friendly structure (placeables and the main building). The
## recent-damage lockout is ignored here — the engineer walks over and waits
## the window out next to the structure. Underground lanterns are skipped:
## the engineer never enters the mine, so they are unreachable by design.
func _find_repair_target() -> Node2D:
	var best: Node2D = null
	var best_d2: float = INF
	for group: String in ["towers", "walls", "lanterns", "buildings"]:
		for structure in unit.get_tree().get_nodes_in_group(group):
			if structure.get("team") != unit.team:
				continue
			if structure.global_position.y > GridWorld.CELL_SIZE:
				continue  # underground lantern — engineers work the surface only
			if not structure.has_method("needs_repair") or not structure.needs_repair():
				continue
			var d2: float = unit.global_position.distance_squared_to(structure.global_position)
			if d2 < best_d2:
				best_d2 = d2
				best = structure
	return best


## Fresh channel state for a new repair order (called by the command).
func _reset_channel() -> void:
	_hp_accum = 0.0
	_coin_owed = 0.0
	_seek_failed_ms = -10000


func _process_repair(delta: float) -> void:
	var target: Node2D = unit._repair_target
	if target == null or not is_instance_valid(target) or not target.has_method("needs_repair"):
		unit._clear_target()
		unit._set_state(Unit.State.IDLE, "repair target lost")
		return
	if not target.needs_repair():
		unit._clear_target()
		unit._set_state(Unit.State.IDLE, "repair complete")
		return

	# Stand at the structure's base, like a siege order does.
	var stand: Vector2 = unit._navigation._building_stand_point(target)
	var path_done: bool = not unit._path.is_empty() and unit._path_index >= unit._path.size()
	if unit.global_position.distance_to(stand) > GridWorld.CELL_SIZE * 1.5 and not path_done:
		# Repath only when there is no path in flight (see _process_climb_up).
		if unit._path.is_empty():
			unit._navigation._repath(stand)
			if unit._path.is_empty():
				unit._set_state(Unit.State.IDLE, "repair target unreachable")
				return
		unit._navigation._follow_path(delta)
		return
	unit._path.clear()

	# Recent-damage lockout: hold position until the window passes.
	if not target.can_be_repaired():
		return

	# Channel: fractional HP accrues; each whole point costs COIN_PER_HP,
	# charged from the team's wallet as it lands. Out of coin -> pause in place.
	_hp_accum += Constants.ENGINEER_REPAIR_HP_PER_SEC * delta
	var whole: int = int(_hp_accum)
	var healed: int = 0
	while whole > 0 and target.needs_repair():
		_coin_owed += Constants.ENGINEER_REPAIR_COIN_PER_HP
		if _coin_owed >= 1.0:
			if not EconomyManager.spend_coin(unit.team, 1):
				_coin_owed -= Constants.ENGINEER_REPAIR_COIN_PER_HP
				break  # paused until the team can afford the next point
			_coin_owed -= 1.0
		healed += target.repair(1)
		_hp_accum -= 1.0
		whole -= 1
	if healed > 0:
		_sound_timer -= delta
		if _sound_timer <= 0.0:
			_sound_timer = 0.6
			AudioManager.play("pickaxe", unit.global_position, -14.0)
