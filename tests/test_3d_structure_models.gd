extends GutTest

# Phase 2 art pass (roadmap/3d-conversion/phase-2-art-pass.md §2.3):
# structure proxies are procedural low-poly models, not box stand-ins —
# the building carries faction identity (accent trims re-tint when the enemy
# faction is identified), towers/walls expose damage states driven by the
# live entity's hp, and lanterns are dynamic-light heroes whose OmniLight3D
# radius/energy scale with tier.
#
# R4 (roadmap/3d-visual-revamp/02-asset-pipeline.md): on Standard/Fancy the
# bases, towers, surface lanterns, and mine entries build the imported
# textured GLBs from model_manifest.json instead; Potato keeps exercising
# the procedural recipes. The starter GLBs ship a single material with the
# window glow baked into the albedo texture (no emissive slot), so the
# enemy base's pre-reveal "???" read is asserted as a body-color dim here.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _grid: GridWorld
var _structures: Node
var _saved_player_faction: String
var _saved_enemy_faction: String


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(7)
	_saved_player_faction = FactionManager.player_faction_id
	_saved_enemy_faction = FactionManager.enemy_faction_id
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_grid = _main.get_node("World/GridWorld")
	_structures = _main.get_node("Structures")
	# Warm-up: the first test after boot gets ~0.4s of node _process starvation
	# in the headless harness, so let the scene settle first.
	await wait_seconds(0.6)


func after_all() -> void:
	# Free immediately, not queue_free(): a queued free could still be pending
	# when the next test script instantiates its own main.tscn and every
	# hard-coded /root/Main lookup would break.
	_main.free()
	FactionManager.player_faction_id = _saved_player_faction
	FactionManager.enemy_faction_id = _saved_enemy_faction
	FactionManager.reset()
	GameManager.clear_map_seed()


func after_each() -> void:
	for group in ["towers", "walls", "lanterns"]:
		for s in get_tree().get_nodes_in_group(group):
			s.free()


func _accent_color(proxy: StructureProxy3D) -> Color:
	var part := proxy.get_node("Accent") as MeshInstance3D
	assert_not_null(part, "proxy has an accent part")
	if part == null:
		return Color.BLACK
	return (part.get_material_override() as StandardMaterial3D).albedo_color


func _body_color(proxy: StructureProxy3D) -> Color:
	var part := proxy.get_node("Body") as MeshInstance3D
	assert_not_null(part, "proxy has a body part")
	if part == null:
		return Color.BLACK
	return (part.get_material_override() as StandardMaterial3D).albedo_color


# R4: imported-model proxies have no "Body"/"Accent" MeshInstance3D children
# — tint state lives in the proxy's tracked per-proxy material arrays.
func _first_body_mat(proxy: StructureProxy3D) -> StandardMaterial3D:
	assert_gt(proxy._body_mats.size(), 0, "proxy tracks body materials")
	return proxy._body_mats[0]


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


# ─── Building: faction identity ───


# Procedural path (Potato): accent trims carry the faction identity.
func test_procedural_keep_accents_reveal_enemy_faction_on_identification() -> void:
	var saved := ArtStyle3D.quality
	ArtStyle3D.apply_quality(ArtStyle3D.Quality.POTATO)
	FactionManager.set_player_faction("arcane")
	FactionManager.enemy_faction_id = "brute"
	FactionManager.reset()
	var player_proxy := StructureProxy3D.create(_main.get_node("World/PlayerBuilding"), _grid)
	var enemy_proxy := StructureProxy3D.create(_main.get_node("World/EnemyBuilding"), _grid)
	autofree(player_proxy)
	autofree(enemy_proxy)

	assert_eq(_accent_color(player_proxy), ArtStyle3D.FACTION_ACCENTS["arcane"],
		"player keep shows its faction accent immediately")
	assert_eq(_accent_color(enemy_proxy), Color(0.42, 0.43, 0.47),
		"enemy keep accent is neutral grey until identified")

	FactionManager.identify_faction(GameManager.Team.ENEMY)

	assert_eq(_accent_color(enemy_proxy), ArtStyle3D.FACTION_ACCENTS["brute"],
		"enemy keep accent re-tints when the faction is identified")
	ArtStyle3D.apply_quality(saved)


# Imported path (Standard/Fancy): the GLB keep/fortress replaces the recipe.
# The starter GLBs bake the window glow into the albedo texture (single
# material, no emissive slot), so the unidentified enemy base is read as a
# whole-body grey damp — and full color returns on identification.
func test_imported_building_reveal_dimming() -> void:
	var saved := ArtStyle3D.quality
	ArtStyle3D.apply_quality(ArtStyle3D.Quality.FANCY)
	FactionManager.set_player_faction("arcane")
	FactionManager.enemy_faction_id = "brute"
	FactionManager.reset()
	var player_proxy := StructureProxy3D.create(_main.get_node("World/PlayerBuilding"), _grid)
	var enemy_proxy := StructureProxy3D.create(_main.get_node("World/EnemyBuilding"), _grid)
	autofree(player_proxy)
	autofree(enemy_proxy)
	assert_not_null(player_proxy._model_wrapper, "Fancy builds the imported player keep")
	assert_not_null(enemy_proxy._model_wrapper, "Fancy builds the imported enemy fortress")

	player_proxy.refresh(false)
	enemy_proxy.refresh(false)
	var player_mat := _first_body_mat(player_proxy)
	var enemy_mat := _first_body_mat(enemy_proxy)
	var enemy_base: Color = enemy_proxy._body_colors[0]

	assert_eq(player_mat.albedo_color, player_proxy._body_colors[0],
		"player keep shows full color immediately")
	assert_almost_eq(enemy_mat.albedo_color.r, enemy_base.r * enemy_proxy._reveal_mult.r, 0.001,
		"unidentified fortress body is damped toward grey (witch-glow baked in albedo)")
	assert_true(enemy_proxy._glow_mats.is_empty(),
		"starter GLBs ship no emissive glow material (glow is baked into the albedo)")

	FactionManager.identify_faction(GameManager.Team.ENEMY)

	assert_almost_eq(enemy_mat.albedo_color.r, enemy_base.r, 0.001,
		"identification restores the fortress body color")
	assert_eq(player_mat.albedo_color, player_proxy._body_colors[0],
		"player keep tint is untouched by the enemy reveal")
	ArtStyle3D.apply_quality(saved)


# ─── Tower / wall damage states ───


func test_tower_damage_states_track_hp() -> void:
	var tower: Node2D = load("res://scenes/tower.tscn").instantiate()
	tower.set("team", GameManager.Team.PLAYER)
	tower.position = _grid.grid_to_world(Vector2i(-25, 0))
	_structures.add_child(tower)
	tower.set("_is_built", true)
	var proxy := StructureProxy3D.create(tower, _grid)
	autofree(proxy)

	var cap := proxy.get_node("CapPivot") as Node3D
	var rubble := proxy.get_node("Rubble") as Node3D
	assert_not_null(cap)
	assert_not_null(rubble)
	if cap == null or rubble == null:
		return
	assert_not_null(proxy._model_wrapper, "Fancy builds the imported watchtower")
	proxy.refresh(false)

	var shaft := _first_body_mat(proxy)
	var base: Color = proxy._body_colors[0]
	assert_eq(shaft.albedo_color, base, "undamaged tower shows its base albedo")

	var max_hp: int = tower.get("max_hp")
	assert_almost_eq(cap.rotation.z, 0.0, 0.001, "undamaged tower stands straight")
	assert_false(rubble.visible, "no rubble at full HP")

	tower.call("take_damage", roundi(max_hp * 0.45))  # 55%: below the 60% threshold.
	assert_almost_eq(absf(cap.rotation.z), 0.07, 0.001, "cap tilts below 60% HP")
	assert_false(rubble.visible, "rubble appears only below 30% HP")
	assert_almost_eq(shaft.albedo_color.r, base.r * 0.75, 0.02,
		"imported body material darkens once damaged")

	tower.call("take_damage", roundi(max_hp * 0.3))  # 25%: below the 30% threshold.
	assert_almost_eq(absf(cap.rotation.z), 0.17, 0.001, "cap tilts further below 30% HP")
	assert_true(rubble.visible, "broken rubble at the base below 30% HP")
	assert_almost_eq(shaft.albedo_color.r, base.r * 0.55, 0.03,
		"imported body material darkens further near destruction")


func test_potato_falls_back_to_procedural_models() -> void:
	var saved := ArtStyle3D.quality
	ArtStyle3D.apply_quality(ArtStyle3D.Quality.POTATO)
	var tower: Node2D = load("res://scenes/tower.tscn").instantiate()
	tower.set("team", GameManager.Team.PLAYER)
	tower.position = _grid.grid_to_world(Vector2i(-25, 0))
	_structures.add_child(tower)
	tower.set("_is_built", true)
	var tower_proxy := StructureProxy3D.create(tower, _grid)
	var building_proxy := StructureProxy3D.create(_main.get_node("World/PlayerBuilding"), _grid)
	autofree(tower_proxy)
	autofree(building_proxy)

	assert_null(tower_proxy._model_wrapper, "Potato tower uses the procedural recipe")
	assert_null(building_proxy._model_wrapper, "Potato keep uses the procedural recipe")
	assert_true(tower_proxy.get_node_or_null("Model") == null,
		"no imported-model wrapper child on Potato")
	assert_not_null(tower_proxy.get_node_or_null("CapPivot"),
		"procedural damage pivot still exists on Potato")
	assert_gt(tower_proxy._body_meshes.size(), 0, "procedural tower has body parts")
	ArtStyle3D.apply_quality(saved)


func test_wall_damage_states_track_hp() -> void:
	var wall: Node2D = load("res://scenes/wall_segment.tscn").instantiate()
	wall.position = _grid.grid_to_world(Vector2i(-26, 0))
	_structures.add_child(wall)
	wall.set("_is_built", true)
	var proxy := StructureProxy3D.create(wall, _grid)
	autofree(proxy)

	var pivot := proxy.get_node("WallPivot") as Node3D
	var rubble := proxy.get_node("Rubble") as Node3D
	assert_not_null(pivot)
	assert_not_null(rubble)
	if pivot == null or rubble == null:
		return

	assert_almost_eq(pivot.rotation.z, 0.0, 0.001, "undamaged wall stands straight")
	assert_false(rubble.visible, "no rubble at full HP")

	var max_hp: int = wall.get("max_hp")
	wall.call("take_damage", roundi(max_hp * 0.5))  # 50%: cracked, leaning.
	assert_gt(absf(pivot.rotation.z), 0.001, "wall leans once below 60% HP")
	assert_false(rubble.visible, "rubble appears only below 30% HP")

	wall.call("take_damage", roundi(max_hp * 0.25))  # 25%: broken.
	assert_true(rubble.visible, "rubble at the base below 30% HP")


# ─── Lanterns: dynamic-light heroes ───


func _build_lantern(underground: bool) -> Lantern:
	var lantern: Lantern = load("res://scenes/lantern.tscn").instantiate()
	lantern.team = GameManager.Team.PLAYER
	lantern.is_underground_lantern = underground
	lantern.position = _grid.grid_to_world(Vector2i(-24, 2 if underground else 0))
	_structures.add_child(lantern)
	lantern._build_progress = 999.0
	lantern._process(0.1)
	return lantern


func test_lantern_light_scales_with_tier() -> void:
	var lantern := _build_lantern(false)
	assert_true(lantern.is_built(), "precondition: lantern finished construction")
	var proxy := StructureProxy3D.create(lantern, _grid)
	autofree(proxy)
	proxy.refresh(false)

	var light := proxy.get_node("LanternLight") as OmniLight3D
	assert_not_null(light)
	if light == null:
		return
	assert_true(light.visible, "built lantern shines")
	var world_scale: float = StructureProxy3D.WORLD_SCALE
	assert_almost_eq(light.omni_range, Constants.LANTERN_T1_VISION * GridWorld.CELL_SIZE * world_scale,
		0.001, "T1 light radius matches T1 vision")
	assert_almost_eq(light.light_energy, 0.8, 0.001, "T1 energy")

	lantern.upgraded.emit(3)
	assert_almost_eq(light.omni_range, Constants.LANTERN_T3_VISION * GridWorld.CELL_SIZE * world_scale,
		0.001, "upgraded light radius matches T3 vision")
	assert_almost_eq(light.light_energy, 1.6, 0.001, "T3 energy")
	assert_almost_eq(light.light_color.r, ArtStyle3D.PALETTE.lamp_warm.r, 0.001,
		"light burns warm")


func test_unbuilt_lantern_gives_no_light() -> void:
	var lantern: Lantern = load("res://scenes/lantern.tscn").instantiate()
	lantern.team = GameManager.Team.PLAYER
	lantern.position = _grid.grid_to_world(Vector2i(-22, 0))
	_structures.add_child(lantern)
	var proxy := StructureProxy3D.create(lantern, _grid)
	autofree(proxy)
	proxy.refresh(false)

	var light := proxy.get_node("LanternLight") as OmniLight3D
	assert_not_null(light)
	if light == null:
		return
	assert_false(lantern.is_built(), "precondition: lantern still under construction")
	assert_false(light.visible, "unbuilt lantern gives no light")


func test_underground_lantern_burns_smaller_and_shadowless() -> void:
	var lantern := _build_lantern(true)
	var proxy := StructureProxy3D.create(lantern, _grid)
	autofree(proxy)
	proxy.refresh(true)

	var light := proxy.get_node("LanternLight") as OmniLight3D
	assert_not_null(light)
	if light == null:
		return
	assert_almost_eq(light.omni_range, Constants.UNDERGROUND_LANTERN_VISION * GridWorld.CELL_SIZE * StructureProxy3D.WORLD_SCALE,
		0.001, "underground radius matches underground lantern vision")
	assert_almost_eq(light.light_energy, 2.4, 0.001, "underground light reads against the near-dark mood")
	assert_false(light.shadow_enabled, "underground lanterns never cast shadows")
	var pool := proxy.get_node_or_null("LanternPool") as MeshInstance3D
	assert_not_null(pool, "a cheap ground glow makes the pool readable over empty tunnels")
	if pool != null:
		assert_true(pool.visible, "built lantern shows its ground pool")
		var diameter: float = Constants.UNDERGROUND_LANTERN_VISION * GridWorld.CELL_SIZE * StructureProxy3D.WORLD_SCALE * 2.0 / StructureProxy3D.PROXY_SCALE
		assert_almost_eq((pool.mesh as QuadMesh).size.x, diameter, 0.001,
			"ground pool follows the sim lantern's vision radius")
	assert_true(proxy.visible, "underground lantern shows in the underground view")
	proxy.refresh(false)
	assert_false(proxy.visible, "underground lantern hides on the surface view")


# ─── R4: imported GLB pipeline ───


func test_manifest_has_no_validation_errors() -> void:
	assert_eq(ModelManifest.validate().size(), 0, "model manifest validates clean")


func test_every_manifest_entry_loads_and_normalizes() -> void:
	for key in ModelManifest.keys():
		if key.begins_with("unit_"):
			continue  # R7 units are covered by test_3d_unit_models.gd + UnitModelLoader.
		var entry := ModelManifest.entry_for(key)
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
			"%s binding XZ axis matches the footprint" % key)
		assert_lt(int(result["tri_count"]), int(entry["tri_gate"]),
			"%s is under its tri gate" % key)

		# GLB instances share imported materials; every instantiate must hand
		# out its own copies so per-proxy tinting never leaks across proxies.
		var again := StructureModelLoader.instantiate(key)
		assert_false(again.is_empty(), "%s second instance loads" % key)
		if not again.is_empty():
			assert_ne((again["body_mats"] as Array)[0], (result["body_mats"] as Array)[0],
				"%s body materials are duplicated per instance" % key)
			(again["root"] as Node3D).free()


func test_surface_lantern_uses_imported_lamp() -> void:
	var lantern := _build_lantern(false)
	var proxy := StructureProxy3D.create(lantern, _grid)
	autofree(proxy)
	assert_not_null(proxy._model_wrapper, "Fancy builds the imported surface lamp")
	assert_eq(proxy._lantern_head, proxy._model_wrapper,
		"tier scaling drives the whole imported lamp (T2/T3 are scale variants)")
	proxy.refresh(false)
	var light := proxy.get_node("LanternLight") as OmniLight3D
	assert_not_null(light)
	if light == null:
		return
	assert_true(light.visible, "built imported lamp shines")
	lantern.upgraded.emit(3)
	assert_almost_eq(proxy._model_wrapper.scale.x, 1.0 + 0.18 * 2.0, 0.001,
		"T3 grows the imported lamp")

	# Underground lanterns keep the procedural bracket (no GLB exists).
	var u_lantern := _build_lantern(true)
	var u_proxy := StructureProxy3D.create(u_lantern, _grid)
	autofree(u_proxy)
	assert_null(u_proxy._model_wrapper, "underground lantern keeps the procedural recipe")
	assert_not_null(u_proxy.get_node_or_null("Head"),
		"procedural head contract preserved underground")


func test_mine_entry_imported_headframe_straddles_the_shaft() -> void:
	var proxy := StructureProxy3D.create(_main.get_node("World/PlayerMineEntry"), _grid)
	autofree(proxy)
	assert_not_null(proxy._model_wrapper, "Fancy builds the imported headframe")
	var half := StructureProxy3D.CELL * 0.5
	assert_almost_eq(proxy._model_wrapper.position.x, half, 0.001,
		"corner-origin model shifts half a cell onto the shaft column")
	assert_almost_eq(proxy._model_wrapper.position.z, half, 0.001,
		"corner-origin model shifts half a cell onto the shaft column")
