## R7 unit GLB loader. Imports share the structure manifest, but normalize to
## an authored height with a footprint cap instead of binding an XZ axis.
## Named glTF nodes become the pivots consumed by UnitModel3D's sim-driven
## animator; faction attachment nodes share the same base rig.
class_name UnitModelLoader
extends RefCounted

const PIVOT_NAMES: Array[StringName] = [
	&"ArmL", &"ArmR", &"LegL", &"LegR", &"Tool", &"WingL", &"WingR", &"Tail",
]
const CELL: float = 0.32


static func instantiate(key: String, team: int = GameManager.Team.PLAYER) -> Dictionary:
	var entry := ModelManifest.entry_for(key)
	if entry.is_empty():
		return {}
	var path := str(entry.get("path", ""))
	var packed: Variant = load(path)
	if packed == null or not packed is PackedScene:
		push_warning("UnitModelLoader: %s failed to load as a scene (%s)" % [key, path])
		return {}
	var instance: Node3D = (packed as PackedScene).instantiate()
	if instance == null:
		push_warning("UnitModelLoader: %s instantiated to null" % key)
		return {}

	var acc := _MeshScan.new()
	_scan(instance, Transform3D.IDENTITY, acc)
	if not acc.has_bounds or acc.bounds.size.y <= 0.0:
		push_warning("UnitModelLoader: %s has no usable meshes" % key)
		instance.free()
		return {}
	var bounds: AABB = acc.bounds
	var target_height := float(entry.get("height", 0.34))
	var model_scale := target_height / bounds.size.y
	var fp: Array = entry.get("footprint", [1.0, 1.0])
	var max_width := float(fp[0]) * CELL
	var max_depth := float(fp[1]) * CELL
	model_scale = minf(model_scale, max_width / maxf(bounds.size.x, 0.0001))
	model_scale = minf(model_scale, max_depth / maxf(bounds.size.z, 0.0001))

	var wrapper := Node3D.new()
	wrapper.name = "ImportedModel"
	wrapper.add_child(instance)
	instance.scale = Vector3.ONE * model_scale
	var center := bounds.get_center()
	instance.position = Vector3(-center.x * model_scale, -bounds.position.y * model_scale, -center.z * model_scale)

	var team_slots: Array = entry.get("team_slots", [])
	var accent_slots: Array = entry.get("accent_slots", [])
	var glow_slots: Array = entry.get("glow_slots", [])
	var team_mats: Array[StandardMaterial3D] = []
	var accent_mats: Array[StandardMaterial3D] = []
	var glow_mats: Array[StandardMaterial3D] = []
	var pivots: Dictionary = {}
	_rebind_materials(instance, team_slots, accent_slots, glow_slots, team,
		team_mats, accent_mats, glow_mats)
	_collect_pivots(instance, pivots)
	apply_faction(instance, team, accent_mats)

	return {
		"root": wrapper,
		"instance": instance,
		"model_height": bounds.size.y * model_scale,
		"team_mats": team_mats,
		"accent_mats": accent_mats,
		"glow_mats": glow_mats,
		"pivots": pivots,
		"tri_count": acc.tri_count,
	}


static func apply_faction(instance: Node3D, team: int, accent_mats: Array[StandardMaterial3D]) -> void:
	var faction_name := ""
	var identified := team != GameManager.Team.ENEMY \
		or FactionManager.is_faction_identified(GameManager.Team.ENEMY)
	var faction: Resource = FactionManager.get_faction(team)
	if identified and faction != null:
		faction_name = str(faction.get("faction_id")).capitalize()
	_apply_faction_nodes(instance, faction_name)
	var accent := ArtStyle3D.faction_accent_color(team, false)
	for mat in accent_mats:
		mat.albedo_color = accent


static func _apply_faction_nodes(node: Node3D, faction_name: String) -> void:
	var node_name := String(node.name)
	if node_name.begins_with("Faction"):
		node.visible = not faction_name.is_empty() and node_name == "Faction" + faction_name
	for child in node.get_children():
		if child is Node3D:
			_apply_faction_nodes(child, faction_name)


class _MeshScan:
	var bounds := AABB()
	var has_bounds := false
	var tri_count := 0


static func _scan(node: Node3D, parent_xform: Transform3D, acc: _MeshScan) -> void:
	var xform := parent_xform * node.transform
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		var local: AABB = xform * mi.mesh.get_aabb()
		if acc.has_bounds:
			acc.bounds = acc.bounds.merge(local)
		else:
			acc.bounds = local
			acc.has_bounds = true
		for surface in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(surface)
			if arrays.is_empty():
				continue
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.size() > 0:
				acc.tri_count += indices.size() / 3
			else:
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				acc.tri_count += verts.size() / 3
	for child in node.get_children():
		if child is Node3D:
			_scan(child, xform, acc)


static func _collect_pivots(node: Node3D, pivots: Dictionary) -> void:
	if PIVOT_NAMES.has(node.name):
		pivots[node.name] = node
	for child in node.get_children():
		if child is Node3D:
			_collect_pivots(child, pivots)


static func _rebind_materials(node: Node3D, team_slots: Array, accent_slots: Array,
		glow_slots: Array, team: int, team_mats: Array[StandardMaterial3D],
		accent_mats: Array[StandardMaterial3D], glow_mats: Array[StandardMaterial3D]) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for surface in range(mi.mesh.get_surface_count()):
			var mat := mi.get_active_material(surface)
			if mat == null or not mat is StandardMaterial3D:
				continue
			var lname := mat.resource_name.to_lower()
			var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			dup.resource_name = mat.resource_name
			dup.roughness = ArtStyle3D.MATERIAL_ROUGHNESS
			dup.metallic = 0.0
			dup.rim_enabled = true
			dup.rim = ArtStyle3D.RIM_STRENGTH
			dup.rim_tint = ArtStyle3D.RIM_TINT
			mi.set_surface_override_material(surface, dup)
			if _matches_any(lname, team_slots):
				dup.albedo_color = ArtStyle3D.team_color(team)
				team_mats.append(dup)
			elif _matches_any(lname, accent_slots):
				dup.albedo_color = ArtStyle3D.faction_accent_color(team, false)
				accent_mats.append(dup)
			elif _matches_any(lname, glow_slots):
				var energy := 1.4
				var glow_color := dup.emission
				if lname.contains("lamp"):
					energy = 1.8
					glow_color = ArtStyle3D.PALETTE["lamp_warm"]
				elif lname.contains("staff"):
					energy = 1.6
				elif lname.contains("eyes"):
					glow_color = ArtStyle3D.PALETTE["ore_bright"]
				ArtStyle3D.apply_emission(dup, glow_color, energy)
				glow_mats.append(dup)
	for child in node.get_children():
		if child is Node3D:
			_rebind_materials(child, team_slots, accent_slots, glow_slots, team,
				team_mats, accent_mats, glow_mats)


static func _matches_any(name: String, slots: Array) -> bool:
	for slot in slots:
		if name.contains(str(slot).to_lower()):
			return true
	return false
