extends GutTest

# Plan 06 (plans/06-asset-import-pipeline.md): the prop GLB import pipeline.
# Neutral surface dressing comes from tools/gen_prop_glbs.py and the curated
# pack imports in models/packs. Tests discover both directories through the
# manifest and load every entry through StructureModelLoader; scene-free prop
# checks stay separate from plan-07/09 scatter behavior.
#
# Structure-side coverage (wrapper name, ground plane, footprint binding,
# per-instance material duplication) already flows through
# test_3d_structure_models.gd::test_every_manifest_entry_loads_and_normalize
# for every non-unit manifest key; this file asserts the prop-specific
# contract on top: registration, honest metadata, and load robustness.

# Plan 13 (plans/13-underground-and-sentry-vision.md): the three curated
# Quaternius pebbles are sparse underground rubble at the 0.12 world-unit
# band — below the plan-06 surface-dressing floor on purpose.
const PEBBLE_KEYS: Array[String] = [
	"pack_pebble_round_1",
	"pack_pebble_round_3",
	"pack_pebble_square_2",
]

func _prop_keys() -> Array[String]:
	var out: Array[String] = []
	for key in ModelManifest.keys():
		var path := str(ModelManifest.entry_for(key).get("path", ""))
		if (path.contains("/models/props/") or path.contains("/models/packs/")) and not key.begins_with("unit_"):
			out.append(key)
	return out


func _combined_aabb(node: Node3D, parent_xform: Transform3D) -> Dictionary:
	var xform := parent_xform * node.transform
	var out := {"bounds": AABB(), "has": false}
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		out.bounds = xform * mi.mesh.get_aabb()
		out.has = true
	for child in node.get_children():
		if child is Node3D:
			var sub := _combined_aabb(child, xform)
			if sub.has:
				if out.has:
					out.bounds = out.bounds.merge(sub.bounds)
				else:
					out.bounds = sub.bounds
					out.has = true
	return out


func test_prop_entries_are_registered_and_manifest_validates() -> void:
	var problems := ModelManifest.validate()
	assert_eq(problems.size(), 0, "model manifest validates clean: %s" % [", ".join(problems)])
	for key in _prop_keys():
		var entry := ModelManifest.entry_for(key)
		assert_false(entry.is_empty(), "%s is registered in the manifest" % key)
		if entry.is_empty():
			continue
		assert_eq(str(entry.get("origin", "")), "center", "%s uses center origin" % key)
		assert_eq(int(entry.get("tri_gate", 0)), 6000, "%s uses the lowest valid tri gate" % key)
		assert_true((entry.get("accent_slots", []) as Array).is_empty(),
			"%s ships no accent slots (neutral dressing)" % key)
		assert_true((entry.get("glow_slots", []) as Array).is_empty(),
			"%s ships no glow slots" % key)


func test_every_prop_loads_within_footprint_on_ground() -> void:
	for key in _prop_keys():
		var entry := ModelManifest.entry_for(key)
		if entry.is_empty():
			continue
		var result := StructureModelLoader.instantiate(key)
		assert_false(result.is_empty(), "%s loads via StructureModelLoader" % key)
		if result.is_empty():
			continue
		var wrapper: Node3D = result["root"]
		autofree(wrapper)
		assert_eq(wrapper.name, "Model", "%s returns the 'Model' wrapper" % key)

		var scan := _combined_aabb(wrapper, Transform3D.IDENTITY)
		assert_true(scan.has, "%s exposes mesh bounds" % key)
		if not scan.has:
			continue
		var fp: Array = entry["footprint"]
		var fw := float(fp[0]) * StructureProxy3D.CELL
		var fh := float(fp[1]) * StructureProxy3D.CELL
		assert_almost_eq(scan.bounds.position.y, 0.0, 0.001,
			"%s sits on the ground plane after normalization" % key)
		assert_lte(scan.bounds.size.x, fw * 1.05, "%s fits its footprint width" % key)
		assert_lte(scan.bounds.size.z, fh * 1.05, "%s fits its footprint depth" % key)
		var x_binding := absf(scan.bounds.size.x - fw) <= fw * 0.05
		var z_binding := absf(scan.bounds.size.z - fh) <= fh * 0.05
		assert_true(x_binding or z_binding,
			"%s binding XZ axis matches the measured footprint" % key)
		assert_almost_eq(scan.bounds.size.y, float(entry["height"]), 0.01,
			"%s matches its manifest height" % key)
		assert_lt(int(result["tri_count"]), int(entry["tri_gate"]),
			"%s is under its tri gate" % key)

		# Per-proxy material duplication contract holds for props too.
		var again := StructureModelLoader.instantiate(key)
		assert_false(again.is_empty(), "%s second instance loads" % key)
		if not again.is_empty():
			assert_ne((again["body_mats"] as Array)[0], (result["body_mats"] as Array)[0],
				"%s body materials are duplicated per instance" % key)
			(again["root"] as Node3D).free()


func test_prop_heights_sit_between_terrain_and_units() -> void:
	# Documented plan-06 bands: props ≈ 0.15..0.45 world units at WORLD_SCALE
	# 0.01 (a humanoid is ~0.36 tall, 1 cell = 0.32) — short dressing, with
	# only the pine reaching above knee height. Plan-13 pebble rubble is the
	# documented exception: a 0.12 band that reads as debris, not blockers.
	for key in _prop_keys():
		var entry := ModelManifest.entry_for(key)
		if entry.is_empty():
			continue
		var height := float(entry["height"])
		if key in PEBBLE_KEYS:
			assert_almost_eq(height, 0.12, 0.005, "%s sits in the 0.12 pebble rubble band" % key)
		else:
			assert_gte(height, 0.15, "%s is at least 0.15 tall" % key)
			assert_lte(height, 0.45, "%s stays within the 0.45 prop ceiling" % key)


func test_pebble_rubble_keys_load_through_prop_path() -> void:
	# Plan 13 acceptance: the three pebbles are manifest-registered and load
	# through the same StructureModelLoader path as every other prop,
	# normalized onto the ground plane inside the 0.12 rubble band.
	for key in PEBBLE_KEYS:
		assert_true(_prop_keys().has(key), "%s is discovered as a prop key" % key)
		var entry := ModelManifest.entry_for(key)
		assert_false(entry.is_empty(), "%s is registered in the manifest" % key)
		if entry.is_empty():
			continue
		assert_true((entry.get("accent_slots", []) as Array).is_empty(),
			"%s ships no accent slots (neutral rubble)" % key)
		assert_true((entry.get("glow_slots", []) as Array).is_empty(),
			"%s ships no glow slots" % key)

		var result := StructureModelLoader.instantiate(key)
		assert_false(result.is_empty(), "%s loads via StructureModelLoader" % key)
		if result.is_empty():
			continue
		var wrapper: Node3D = result["root"]
		autofree(wrapper)
		var scan := _combined_aabb(wrapper, Transform3D.IDENTITY)
		assert_true(scan.has, "%s exposes mesh bounds" % key)
		if not scan.has:
			continue
		assert_almost_eq(scan.bounds.position.y, 0.0, 0.001,
			"%s sits on the ground plane after normalization" % key)
		assert_almost_eq(scan.bounds.size.y, 0.12, 0.01,
			"%s normalizes to the 0.12 rubble height" % key)
		assert_lt(int(result["tri_count"]), int(entry["tri_gate"]),
			"%s is under its tri gate" % key)
