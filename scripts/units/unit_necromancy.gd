class_name UnitNecromancy
extends RefCounted

## Necromancy (Deep Delve tier-3 capstone): a wizard whose raise toggle
## (_raise_mode "troops"/"dragon", off = disabled) seeks corpses within
## Constants.NECRO_SEEK_RADIUS, walks to one, and channels
## Constants.NECRO_RAISE_CHANNEL_TIME seconds within
## Constants.NECRO_RAISE_RANGE to summon an undead copy (see corpse.gd and
## Unit._spawn_undead_from). Per-wizard caps: NECRO_MAX_GROUND_UNDEAD undead
## swordsmen/archers, or NECRO_MAX_DRAGON_UNDEAD undead dragon (which needs a
## real dragon corpse). The behavior only claims IDLE ticks — any command,
## engagement, or flee breaks the channel — and it never overrides a rally
## hunt. Raising requires the team's Necromancy research.

var unit: Unit

# Channel state: the corpse being raised and the remaining channel time.
var _channel_target: Corpse = null
var _channel_timer: float = 0.0


func _init(u: Unit) -> void:
	unit = u


## Per-frame upkeep: breaks the channel when the wizard left IDLE (an order or
## an engagement interrupted it) and accumulates channel time while standing
## at the corpse. Called every frame for wizards, before state processing.
func _process_necromancy(delta: float) -> void:
	if _channel_target == null:
		return
	if unit._state != Unit.State.IDLE:
		_stop_channel("interrupted by " + Unit.State.keys()[unit._state])
		return
	if not is_instance_valid(_channel_target):
		_stop_channel("corpse expired")
		return
	_channel_timer -= delta
	if _channel_timer <= 0.0:
		var corpse: Corpse = _channel_target
		_channel_target = null
		unit._spawn_undead_from(corpse)


## Idle behavior. Returns true when necromancy claimed the tick (channeling or
## moving to a corpse), so the generic idle fighter handler is skipped.
func _handle_idle_necromancer() -> bool:
	if unit._raise_mode == "off" or unit._rally_active:
		return false
	if not ResearchManager.has_branch(unit.team, "necromancy"):
		return false
	if _channel_target != null:
		# Channel in progress (_process_necromancy advances the timer).
		return true
	var corpse: Corpse = _find_corpse()
	if corpse == null:
		return false
	var cap: int = Constants.NECRO_MAX_DRAGON_UNDEAD if _wanted_category() == "dragon" else Constants.NECRO_MAX_GROUND_UNDEAD
	if _count_undead(_wanted_category()) >= cap:
		return false  # at the cap — let the generic idle handler take over
	if unit.global_position.distance_to(corpse.global_position) <= Constants.NECRO_RAISE_RANGE:
		_start_channel(corpse)
	else:
		unit._navigation._repath(corpse.global_position)
		if unit._path.is_empty():
			return false  # unreachable for now — the generic idle handler takes over
		unit._set_state(Unit.State.MOVE, "seek corpse")
	return true


## Nearest unclaimed corpse of the toggle's category within the seek radius.
func _find_corpse() -> Corpse:
	var best: Corpse = null
	var best_d2: float = Constants.NECRO_SEEK_RADIUS * Constants.NECRO_SEEK_RADIUS
	for node in unit.get_tree().get_nodes_in_group("corpses"):
		var corpse: Corpse = node as Corpse
		if corpse == null or corpse.corpse_category != _wanted_category() or corpse.is_claimed():
			continue
		var d2: float = unit.global_position.distance_squared_to(corpse.global_position)
		if d2 <= best_d2:
			best_d2 = d2
			best = corpse
	return best


func _wanted_category() -> String:
	return "dragon" if unit._raise_mode == "dragon" else "ground"


## Live undead bound to this wizard, split by category.
func _count_undead(category: String) -> int:
	var n: int = 0
	for node in unit.get_tree().get_nodes_in_group("units"):
		var u: Unit = node as Unit
		if u == null or u.team != unit.team or u._state == Unit.State.DEAD:
			continue
		if u.data == null or not u.data.is_undead or u._necro_owner != unit:
			continue
		if ("dragon" if u.data.unit_name.to_lower() == "dragon" else "ground") == category:
			n += 1
	return n


func _start_channel(corpse: Corpse) -> void:
	_channel_target = corpse
	_channel_timer = Constants.NECRO_RAISE_CHANNEL_TIME
	corpse.claim(unit)
	unit._path.clear()
	DebugLog.log_command("Unit %d" % unit.get_instance_id(), "necro_channel", "corpse=%d" % corpse.get_instance_id())


func _stop_channel(reason: String) -> void:
	if _channel_target != null and is_instance_valid(_channel_target):
		_channel_target.release(unit)
	_channel_target = null
	_channel_timer = 0.0
	DebugLog.log_command("Unit %d" % unit.get_instance_id(), "necro_channel_stop", reason)
