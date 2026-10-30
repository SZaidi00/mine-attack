## R4 structure GLB loader (roadmap/3d-visual-revamp/02-asset-pipeline.md
## conventions 1-3): instantiate a manifest entry's imported .glb, normalize
## its scale/origin to the sim footprint, rebind accent/glow materials, and
## hand the proxy per-proxy material copies so damage darkening, fog-memory
## tinting and construction alpha never leak across proxies or quality
## switches (GLB instances share imported materials by default).
##
## Returns a Dictionary on success:
## {
##   "root": Node3D              # wrapper named "Model", min-y at 0, XZ centered
##   "body_mats": Array[StandardMaterial3D]    # tinted per refresh() (damage,
##                                 fog memory, construction alpha) — albedo is
##                                 multiplied, never the texture
##   "body_colors": Array[Color] # per-material base albedo before tinting
##   "accent_mats": Array[StandardMaterial3D]  # faction re-tint on reveal
##   "glow_mats": Array[StandardMaterial3D]    # emissive, toggled on reveal
##   "tri_count": int            # summed surface triangle count
## }
## Returns {} on any failure (missing file, parse error) — the caller falls
## back to the procedural recipe.
class_name StructureModelLoader
extends RefCounted


## Instantiate the GLB for a manifest key. team drives the accent rebind
## (hidden-enemy grey until the faction is identified).
static func instantiate(key: String, team: int = GameManager.Team.PLAYER) -> Dictionary:
	var entry := ModelManifest.entry_for(key)
	if entry.is_empty():
		return {}
	var path := str(entry.get("path", ""))
	var packed: Variant = load(path)
	if packed == null or not packed is PackedScene:
		push_warning("StructureModelLoader: %s failed to load as a scene (%s)" % [key, path])
		return {}
	var instance: Node3D = (packed as PackedScene).instantiate()
	if instance == null:
		push_warning("StructureModelLoader: %s instantiated to null" % key)
		return {}

	# Combined mesh-space AABB + tri count over all descendants.
	var acc := _MeshScan.new()
	_scan(instance, Transform3D.IDENTITY, acc)
	if not acc.has_bounds:
		push_warning("StructureModelLoader: %s has no meshes" % key)
		instance.free()
		return {}
	var bounds: AABB = acc.bounds

	# Convention 2: Y-up, origin at base. The starter GLBs are unit cubes
	# centered on the origin (min-y = -0.5), so the base never sits at y=0 —
	# warn and auto-fix via the AABB recenter instead of failing.
	if absf(bounds.position.y) > 0.001 or bounds.size.y <= 0.0:
		push_warning("StructureModelLoader: %s origin not at base (min-y %f); recentering" \
			% [key, bounds.position.y])

	# Convention 1: uniform scale so XZ bounds match the footprint.
	var fp: Array = entry.get("footprint", [1, 1])
	var fw: float = float(fp[0]) * StructureProxy3D.CELL
	var fh: float = float(fp[1]) * StructureProxy3D.CELL
	var scale := minf(fw / maxf(bounds.size.x, 0.0001), fh / maxf(bounds.size.z, 0.0001))

	var wrapper := Node3D.new()
	wrapper.name = "Model"
	wrapper.add_child(instance)
	instance.scale = Vector3.ONE * scale
	var center := bounds.get_center()
	# XZ center at origin, min-y on the ground plane (wrapper space).
	instance.position = Vector3(-center.x * scale, -bounds.position.y * scale, -center.z * scale)

	# Convention 3: per-proxy material copies + accent/glow slot rebind.
	var accent_slots: Array = entry.get("accent_slots", [])
	var glow_slots: Array = entry.get("glow_slots", [])
	var body_mats: Array[StandardMaterial3D] = []
	var body_colors: Array[Color] = []
	var accent_mats: Array[StandardMaterial3D] = []
	var glow_mats: Array[StandardMaterial3D] = []
	_rebind_materials(instance, accent_slots, glow_slots, team,
		body_mats, body_colors, accent_mats, glow_mats)

	return {
		"root": wrapper,
		"body_mats": body_mats,
		"body_colors": body_colors,
		"accent_mats": accent_mats,
		"glow_mats": glow_mats,
		"tri_count": acc.tri_count,
	}


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
		for s in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(s)
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


static func _rebind_materials(node: Node3D, accent_slots: Array, glow_slots: Array,
		team: int, body_mats: Array[StandardMaterial3D], body_colors: Array[Color],
		accent_mats: Array[StandardMaterial3D], glow_mats: Array[StandardMaterial3D]) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.get_active_material(s)
			if mat == null or not mat is StandardMaterial3D:
				continue
			var lname := mat.resource_name.to_lower()
			var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			dup.resource_name = mat.resource_name
			mi.set_surface_override_material(s, dup)
			if _matches_any(lname, accent_slots):
				dup.roughness = ArtStyle3D.MATERIAL_ROUGHNESS
				dup.rim_enabled = true
				dup.rim = ArtStyle3D.RIM_STRENGTH
				dup.rim_tint = ArtStyle3D.RIM_TINT
				dup.albedo_color = ArtStyle3D.faction_accent_color(team, false)
				accent_mats.append(dup)
			elif _matches_any(lname, glow_slots):
				if dup.emission_enabled:
					ArtStyle3D.apply_emission(dup, dup.emission, dup.emission_energy_multiplier)
				glow_mats.append(dup)
			else:
				body_mats.append(dup)
				body_colors.append(dup.albedo_color)
	for child in node.get_children():
		if child is Node3D:
			_rebind_materials(child, accent_slots, glow_slots, team,
				body_mats, body_colors, accent_mats, glow_mats)


static func _matches_any(name: String, slots: Array) -> bool:
	for slot in slots:
		if name.contains(str(slot).to_lower()):
			return true
	return false
