## Phase 1 entity proxy manager (roadmap/3d-conversion/phase-1-25d-port.md §1.3).
##
## Reconciles 3D proxies against the live sim: scans the unit/structure
## groups on a short interval and spawns missing proxies (keyed by instance
## id, so a unit leaving its group on death — _die() removes it before the
## 1s fade — cues a cull without polling liveness). Units also sync every
## frame (position/altitude/fog/layer/HP bar); structures refresh at
## reconcile time (static, but construction alpha and fog visibility
## change). Layer (Tab) switches come in via set_underground_view().
extends Node3D

const RECONCILE_INTERVAL: float = 0.2
const STRUCTURE_GROUPS: Array[StringName] = [
	&"buildings", &"towers", &"lanterns", &"walls", &"traps", &"mine_entries", &"ladders",
]

var _units_container: Node3D
var _structures_container: Node3D
var _grid: GridWorld
var _effects_container: Node3D
var _camera: Camera3D

var _unit_proxies: Array[UnitProxy3D] = []
var _unit_proxy_ids: Dictionary = {}  # unit instance id -> proxy
var _structure_proxies: Array[StructureProxy3D] = []
var _structure_proxy_ids: Dictionary = {}  # structure instance id -> proxy
var _reconcile_accum := 0.0
var _underground_view := false


func setup(units_c: Node3D, structures_c: Node3D, grid: GridWorld, effects_c: Node3D, camera: Camera3D) -> void:
	_units_container = units_c
	_structures_container = structures_c
	_grid = grid
	_effects_container = effects_c
	_camera = camera


func set_underground_view(underground: bool) -> void:
	_underground_view = underground
	for p in _structure_proxies:
		p.refresh(_underground_view)


func _process(delta: float) -> void:
	_reconcile_accum += delta
	if _reconcile_accum >= RECONCILE_INTERVAL:
		_reconcile_accum = 0.0
		_reconcile()
	var camera_yaw: float = _camera.global_rotation.y
	for p in _unit_proxies:
		if not p.dead:
			p.sync_from_entity(_underground_view, camera_yaw)


func _reconcile() -> void:
	# Units.
	var seen_units := {}
	for unit in get_tree().get_nodes_in_group("units"):
		seen_units[unit.get_instance_id()] = true
		if not _unit_proxy_ids.has(unit.get_instance_id()):
			var proxy := UnitProxy3D.create(unit)
			proxy.source_id = unit.get_instance_id()
			_units_container.add_child(proxy)
			_unit_proxies.append(proxy)
			_unit_proxy_ids[unit.get_instance_id()] = proxy
	for i in range(_unit_proxies.size() - 1, -1, -1):
		var p: UnitProxy3D = _unit_proxies[i]
		var uid := p.source_id
		if p.unit != null and is_instance_valid(p.unit):
			uid = p.unit.get_instance_id()
		if p.dead or not seen_units.has(uid):
			_unit_proxies.remove_at(i)
			_unit_proxy_ids.erase(uid)
			p.queue_free()

	# Structures.
	var seen_structures := {}
	for group in STRUCTURE_GROUPS:
		for s in get_tree().get_nodes_in_group(group):
			seen_structures[s.get_instance_id()] = true
			if not _structure_proxy_ids.has(s.get_instance_id()):
				var proxy := StructureProxy3D.create(s, _grid)
				proxy.source_id = s.get_instance_id()
				_structures_container.add_child(proxy)
				_structure_proxies.append(proxy)
				_structure_proxy_ids[s.get_instance_id()] = proxy
	for i in range(_structure_proxies.size() - 1, -1, -1):
		var p: StructureProxy3D = _structure_proxies[i]
		var sid := p.source_id
		if p.entity != null and is_instance_valid(p.entity):
			sid = p.entity.get_instance_id()
		if p.dead or not seen_structures.has(sid):
			_structure_proxies.remove_at(i)
			_structure_proxy_ids.erase(sid)
			p.queue_free()
		else:
			p.refresh(_underground_view)
