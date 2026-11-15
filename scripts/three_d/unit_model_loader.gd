## R7 unit GLB loader with optional native skeletal imports. Body bounds are
## normalized to an authored height with a footprint cap; bone-mounted tools
## do not distort that scale. Valid skeletal entries expose a Skeleton3D and
## manual AnimationPlayer. Generated named pivots, faction attachments, and
## per-instance material rebinding remain available on the fallback path.
class_name UnitModelLoader
extends RefCounted

const PIVOT_NAMES: Array[StringName] = [
	&"ArmL", &"ArmR", &"LegL", &"LegR", &"Tool", &"WingL", &"WingR", &"Tail",
]
const CELL: float = 0.32


static func instantiate(key: String, team: int = GameManager.Team.PLAYER, allow_skeletal := true) -> Dictionary:
	var entry := ModelManifest.entry_for(key)
	if entry.is_empty():
		return {}
	if allow_skeletal and not entry.get("skeletal", false) and key.begins_with("unit_"):
		var skeletal := instantiate(key.replace("unit_", "unit_kaykit_"), team)
		if not skeletal.is_empty():
			return skeletal
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

	var skeletal: Dictionary = {}
	if entry.get("skeletal", false):
		skeletal = UnitSkeletal3D.prepare(instance, entry)
		if skeletal.is_empty():
			instance.free()
			return {}

	var wrapper := Node3D.new()
	wrapper.name = "ImportedModel"
	wrapper.add_child(instance)
	instance.scale = Vector3.ONE * model_scale
	instance.rotation.y = float(entry.get("yaw", 0.0))
	var center := bounds.get_center()
	instance.position = Vector3(-center.x * model_scale, -bounds.position.y * model_scale, -center.z * model_scale)

	var team_slots: Array = entry.get("team_slots", [])
	var accent_slots: Array = entry.get("accent_slots", [])
	var glow_slots: Array = entry.get("glow_slots", [])
	var palette: Dictionary = entry.get("palette", {})
	var team_mats: Array[Material] = []
	var accent_mats: Array[Material] = []
	var glow_mats: Array[StandardMaterial3D] = []
	var pivots: Dictionary = {}
	_rebind_materials(instance, team_slots, accent_slots, glow_slots, team,
		team_mats, accent_mats, glow_mats, palette)
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
		"skeletal": not skeletal.is_empty(),
		"skeleton": skeletal.get("skeleton"),
		"animation_player": skeletal.get("animation_player"),
	}


static func apply_faction(instance: Node3D, team: int, accent_mats: Array[Material]) -> void:
	var faction_name := ""
	var identified := team != GameManager.Team.ENEMY \
		or FactionManager.is_faction_identified(GameManager.Team.ENEMY)
	var faction: Resource = FactionManager.get_faction(team)
	if identified and faction != null:
		faction_name = str(faction.get("faction_id")).capitalize()
	_apply_faction_nodes(instance, faction_name)
	var accent := ArtStyle3D.faction_accent_color(team, false)
	for mat in accent_mats:
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter("accent_color", accent)
		else:
			(mat as StandardMaterial3D).albedo_color = accent


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


static func _scan(node: Node3D, parent_xform: Transform3D, acc: _MeshScan, include_bounds := true) -> void:
	var xform := parent_xform * node.transform
	var measure := include_bounds and not String(node.name).begins_with("Attachment")
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		if measure:
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
			_scan(child, xform, acc, measure)


static func _collect_pivots(node: Node3D, pivots: Dictionary) -> void:
	if PIVOT_NAMES.has(node.name):
		pivots[node.name] = node
	for child in node.get_children():
		if child is Node3D:
			_collect_pivots(child, pivots)


static func _rebind_materials(node: Node3D, team_slots: Array, accent_slots: Array,
		glow_slots: Array, team: int, team_mats: Array[Material],
		accent_mats: Array[Material], glow_mats: Array[StandardMaterial3D], palette: Dictionary) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for surface in range(mi.mesh.get_surface_count()):
			var mat := mi.get_active_material(surface)
			if mat == null or not mat is StandardMaterial3D:
				continue
			var lname := mat.resource_name.to_lower()
			if _matches_any(lname, palette.get("materials", [])):
				var palette_mat := _palette_override(mat as StandardMaterial3D, palette, team)
				if palette_mat != null:
					mi.set_surface_override_material(surface, palette_mat)
					team_mats.append(palette_mat)
					accent_mats.append(palette_mat)
					continue
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
					glow_color = ArtStyle3D.faction_accent_color(team, false)
				elif lname.contains("eyes"):
					glow_color = ArtStyle3D.PALETTE["ore_bright"]
				ArtStyle3D.apply_emission(dup, glow_color, energy)
				glow_mats.append(dup)
	for child in node.get_children():
		if child is Node3D:
			_rebind_materials(child, team_slots, accent_slots, glow_slots, team,
				team_mats, accent_mats, glow_mats, palette)


static func _palette_override(mat: StandardMaterial3D, palette: Dictionary, team: int) -> ShaderMaterial:
	var shader := load(str(palette.get("shader", ""))) as Shader
	if shader == null:
		return null
	var dup := ShaderMaterial.new()
	dup.shader = shader
	dup.resource_name = mat.resource_name
	dup.set_shader_parameter("palette_texture", mat.albedo_texture)
	dup.set_shader_parameter("team_color", ArtStyle3D.team_color(team))
	dup.set_shader_parameter("accent_color", ArtStyle3D.faction_accent_color(team, false))
	var regions: Array = palette.get("team_regions", [])
	dup.set_shader_parameter("team_region_a", _region(regions, 0))
	dup.set_shader_parameter("team_region_b", _region(regions, 1))
	dup.set_shader_parameter("accent_region", _region(palette.get("accent_regions", []), 0))
	dup.set_shader_parameter("tint_color", ArtStyle3D.UNDEAD_TINT)
	return dup


static func _region(regions: Array, index: int) -> Vector4:
	if index < 0 or index >= regions.size() or not regions[index] is Array or regions[index].size() != 4:
		return Vector4.ZERO
	var rect: Array = regions[index]
	return Vector4(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))


static func _matches_any(name: String, slots: Array) -> bool:
	for slot in slots:
		if name.contains(str(slot).to_lower()):
			return true
	return false
