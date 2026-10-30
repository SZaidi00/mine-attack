extends GutTest

# Phase 2 art pass — procedural unit models (roadmap/3d-conversion/
# phase-2-art-pass.md §2.2): UnitModel3D builds a flat-shaded low-poly rig
# for every unit type from UnitData identity (silhouette per the style
# guide), faction accents come from ArtStyle3D, undead get the sickly
# material pass, and sync_animation poses the rig from the sim's
# state/timers. Duck-typed fakes stand in for units; no sim scene needed.

class FakeUnit:
	extends Node2D
	var team: int = GameManager.Team.PLAYER
	var data: UnitData = null
	var hp: int = 50
	var is_underground: bool = false
	var _state: int = Unit.State.IDLE
	var _attack_timer: float = 0.5
	var _mine_timer: float = 0.25
	var _mine_target_angle: float = 0.0
	var _hit_flash_timer: float = 0.0
	var _target_unit: Node2D = null
	var _target_building: Node2D = null
	var _target_position: Vector2 = Vector2.ZERO
	signal died(unit)

	func get_flight_altitude() -> float:
		if data == null or data.flight_altitude <= 0.0 or is_underground:
			return 0.0
		return data.flight_altitude


var _prev_player_faction: String = ""
var _prev_enemy_faction: String = ""
var _prev_quality: ArtStyle3D.Quality = ArtStyle3D.Quality.FANCY


func before_all() -> void:
	_prev_player_faction = FactionManager.player_faction_id
	_prev_enemy_faction = FactionManager.enemy_faction_id
	_prev_quality = ArtStyle3D.quality
	ArtStyle3D.apply_quality(ArtStyle3D.Quality.FANCY)


func after_all() -> void:
	FactionManager.set_player_faction(_prev_player_faction)
	FactionManager.enemy_faction_id = _prev_enemy_faction
	FactionManager.reset()
	ArtStyle3D.apply_quality(_prev_quality)


func _spawn(unit_id: String, undead := false) -> FakeUnit:
	var u := FakeUnit.new()
	u.data = load("res://scripts/resources/units/%s.tres" % unit_id).duplicate(true)
	if undead:
		u.data.is_undead = true
	u.hp = u.data.max_hp
	autofree(u)
	return u


func _mesh_count(model: Node) -> int:
	return model.find_children("*", "MeshInstance3D", true, false).size()


func _all_materials(model: Node) -> Array[StandardMaterial3D]:
	var materials: Array[StandardMaterial3D] = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for surface in range(mi.mesh.get_surface_count()):
			var mat := mi.get_active_material(surface) as StandardMaterial3D
			if mat != null:
				materials.append(mat)
	return materials


func _material_named(model: Node, slot: String) -> StandardMaterial3D:
	for mat in _all_materials(model):
		if mat.resource_name == slot:
			return mat
	return null


func _albedo_set(model: Node) -> Array:
	var colors: Array = []
	for mat in _all_materials(model):
		if not colors.has(mat.albedo_color):
			colors.append(mat.albedo_color)
	return colors


func test_create_builds_a_rig_for_every_unit_type() -> void:
	for unit_id in ["miner", "swordsman", "archer", "wizard", "dragon", "pigeon", "engineer", "crawler"]:
		var u := _spawn(unit_id)
		var model := UnitModel3D.create(u)
		autofree(model)
		assert_gt(_mesh_count(model), 3, "%s model has primitives" % unit_id)
		assert_gt(model.model_height, 0.05, "%s model height set" % unit_id)


func test_models_match_style_guide_scale_bands() -> void:
	var dragon := UnitModel3D.create(_spawn("dragon"))
	var pigeon := UnitModel3D.create(_spawn("pigeon"))
	var miner := UnitModel3D.create(_spawn("miner"))
	var crawler := UnitModel3D.create(_spawn("crawler"))
	autofree(dragon)
	autofree(pigeon)
	autofree(miner)
	autofree(crawler)
	assert_gt(dragon.model_height, 0.5, "dragon is the big silhouette")
	assert_lt(pigeon.model_height, 0.2, "pigeon is tiny")
	assert_gt(miner.model_height, 0.28, "humanoid stands ~0.3+ tall")
	assert_lt(miner.model_height, 0.45, "humanoid fits the cell scale")
	assert_lt(crawler.model_height, 0.25, "crawler reads low and long")


func test_miner_has_a_glowing_helmet_lamp() -> void:
	var model := UnitModel3D.create(_spawn("miner"))
	autofree(model)
	var has_emissive := false
	for mat in _all_materials(model):
		if mat.emission_enabled and mat.emission_energy_multiplier > 1.0:
			has_emissive = true
	assert_true(has_emissive, "miner model carries the glowing lamp")


func test_faction_accent_colors_differ_per_faction() -> void:
	FactionManager.set_player_faction("arcane")
	var arcane: Color = ArtStyle3D.faction_accent_color(GameManager.Team.PLAYER)
	FactionManager.set_player_faction("brute")
	var brute: Color = ArtStyle3D.faction_accent_color(GameManager.Team.PLAYER)
	FactionManager.set_player_faction("industrial")
	var industrial: Color = ArtStyle3D.faction_accent_color(GameManager.Team.PLAYER)
	assert_ne(arcane, brute, "arcane vs brute accents differ")
	assert_ne(brute, industrial, "brute vs industrial accents differ")
	assert_ne(arcane, industrial, "arcane vs industrial accents differ")
	FactionManager.set_player_faction("arcane")
	var body: Color = ArtStyle3D.team_color(GameManager.Team.PLAYER)
	assert_ne(ArtStyle3D.faction_accent_color(GameManager.Team.PLAYER), body,
		"the accent reads on top of the team body color")


func test_undead_tint_changes_body_materials() -> void:
	var living := UnitModel3D.create(_spawn("swordsman"))
	var undead := UnitModel3D.create(_spawn("swordsman", true))
	autofree(living)
	autofree(undead)
	assert_ne(_albedo_set(living), _albedo_set(undead),
		"undead material pass alters the palette")
	var has_sickly := false
	for c in _albedo_set(undead):
		if c.g > 0.7 and c.g >= c.b:
			has_sickly = true
	assert_true(has_sickly, "undead body trends sickly green")


func test_sync_animation_drives_all_states_without_crashing() -> void:
	var u := _spawn("miner")
	var model := UnitModel3D.create(u)
	autofree(model)
	var states: Array[int] = [
		Unit.State.IDLE, Unit.State.MOVE, Unit.State.ATTACK, Unit.State.MINE,
		Unit.State.CLIMB_DOWN, Unit.State.DEAD,
	]
	for state in states:
		u._state = state
		u._attack_timer = 0.3
		u._mine_timer = 0.1
		u._hit_flash_timer = 0.05 if state == Unit.State.ATTACK else 0.0
		for i in range(5):
			u.global_position += Vector2(3.0, 0.0)  # moving: swing phase advances
			model.sync_animation(u, 0.016)
	assert_true(true, "sync_animation survived IDLE/MOVE/ATTACK/MINE/CLIMB/DEAD")


func test_flyer_flaps_and_hits_flash() -> void:
	var u := _spawn("dragon")
	var model := UnitModel3D.create(u)
	autofree(model)
	u._hit_flash_timer = 0.1
	u._state = Unit.State.MOVE
	for i in range(10):
		u.global_position += Vector2(2.0, 0.0)
		model.sync_animation(u, 0.016)
	assert_true(true, "dragon animation path (flight + flash) survived")


func test_proxy_contract_still_holds() -> void:
	var u := _spawn("swordsman")
	u.global_position = Vector2(120.0, -240.0)
	var proxy := UnitProxy3D.create(u)
	get_tree().root.add_child(proxy)
	autofree(proxy)
	assert_not_null(proxy.unit, "proxy keeps the unit ref")
	assert_false(proxy.dead, "proxy starts alive")
	assert_true(proxy._model != null, "proxy carries a UnitModel3D")
	proxy.sync_from_entity(false, 0.5)
	assert_almost_eq(proxy.global_position.x, 1.2, 0.001, "position mirrored at WORLD_SCALE")
	assert_almost_eq(proxy.global_position.z, -2.4, 0.001, "position mirrored at WORLD_SCALE")
	assert_true(proxy.visible, "surface unit visible in surface view")
	proxy.sync_from_entity(true, 0.5)
	assert_false(proxy.visible, "surface unit hidden in underground view")
	u.died.emit(u)
	assert_true(proxy.dead, "died -> dead")


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
				out.bounds = out.bounds.merge(sub.bounds) if out.has else sub.bounds
				out.has = true
	return out


func test_r7_manifest_models_load_within_scale_and_triangle_budgets() -> void:
	for unit_id in ["miner", "swordsman", "archer", "wizard", "dragon", "pigeon", "engineer", "crawler"]:
		var key: String = "unit_" + unit_id
		var entry := ModelManifest.entry_for(key)
		assert_false(entry.is_empty(), "%s has a manifest entry" % key)
		var result := UnitModelLoader.instantiate(key)
		assert_false(result.is_empty(), "%s imports" % key)
		if result.is_empty():
			continue
		var root := result["root"] as Node3D
		var scan := _combined_aabb(root, Transform3D.IDENTITY)
		assert_true(scan.has, "%s has mesh bounds" % key)
		if scan.has:
			assert_almost_eq(scan.bounds.position.y, 0.0, 0.001, "%s is grounded" % key)
		assert_almost_eq(float(result["model_height"]), float(entry["height"]), 0.001,
			"%s matches its authored height" % key)
		assert_lte(int(result["tri_count"]), int(entry["tri_gate"]), "%s meets its tri gate" % key)
		assert_true(result["pivots"] is Dictionary, "%s exposes its rig pivots" % key)
		root.free()


func test_r7_standard_imports_and_potato_fallback() -> void:
	ArtStyle3D.apply_quality(ArtStyle3D.Quality.STANDARD)
	var imported := UnitModel3D.create(_spawn("swordsman"))
	autofree(imported)
	assert_true(imported._using_imported, "Standard uses the sculpted GLB")
	assert_not_null(imported._arm_r, "imported rig exposes animation pivots")
	var has_texture := false
	for mi in imported.find_children("*", "MeshInstance3D", true, false):
		var mat := (mi as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		if mat != null and mat.albedo_texture != null:
			has_texture = true
	assert_true(has_texture, "imported unit keeps its painted texture atlas")

	ArtStyle3D.apply_quality(ArtStyle3D.Quality.POTATO)
	var fallback := UnitModel3D.create(_spawn("swordsman"))
	autofree(fallback)
	assert_false(fallback._using_imported, "Potato keeps the procedural fallback")
	ArtStyle3D.apply_quality(ArtStyle3D.Quality.FANCY)


func test_r7_materials_are_isolated_per_instance() -> void:
	var first := UnitModel3D.create(_spawn("miner"))
	var second := UnitModel3D.create(_spawn("miner"))
	autofree(first)
	autofree(second)
	var first_team := _material_named(first, "team")
	var second_team := _material_named(second, "team")
	var first_accent := _material_named(first, "accent")
	var second_accent := _material_named(second, "accent")
	assert_not_null(first_team)
	assert_not_null(second_team)
	assert_not_null(first_accent)
	assert_not_null(second_accent)
	assert_ne(first_team.get_instance_id(), second_team.get_instance_id(), "team materials do not leak between units")
	assert_ne(first_accent.get_instance_id(), second_accent.get_instance_id(), "accent materials do not leak between units")


func test_r7_player_faction_variants_share_the_base_rig() -> void:
	for faction in ["arcane", "brute", "industrial"]:
		FactionManager.set_player_faction(faction)
		var model := UnitModel3D.create(_spawn("swordsman"))
		autofree(model)
		for candidate in ["Arcane", "Brute", "Industrial"]:
			var attachment := model.find_child("Faction" + candidate, true, false) as Node3D
			assert_not_null(attachment, "%s attachment exists" % candidate)
			if attachment != null:
				assert_eq(attachment.visible, candidate.capitalize() == faction.capitalize(),
					"only the active faction attachment shows")


func test_r7_enemy_variant_and_accent_reveal_on_identification() -> void:
	FactionManager.enemy_faction_id = "brute"
	FactionManager.reset()
	var u := _spawn("swordsman")
	u.team = GameManager.Team.ENEMY
	var model := UnitModel3D.create(u)
	autofree(model)
	var brute := model.find_child("FactionBrute", true, false) as Node3D
	assert_not_null(brute)
	assert_false(brute.visible, "hidden enemy has no faction silhouette")
	assert_eq(model._accent_mats[0].albedo_color, Color(0.42, 0.43, 0.47),
		"hidden enemy accent is neutral")
	FactionManager.identify_faction(GameManager.Team.ENEMY)
	assert_true(brute.visible, "identification reveals the sculpted faction variant")
	assert_eq(model._accent_mats[0].albedo_color, ArtStyle3D.FACTION_ACCENTS["brute"],
		"identification reveals the faction accent")


func test_r7_imported_pivots_follow_sim_attack_state() -> void:
	var u := _spawn("miner")
	var model := UnitModel3D.create(u)
	autofree(model)
	assert_not_null(model._tool)
	u._state = Unit.State.ATTACK
	u._attack_timer = 0.3
	model.sync_animation(u, 0.016)
	assert_gt(absf(model._tool.rotation.x), 0.01, "attack timer poses the imported tool pivot")


func test_humanoid_proxies_have_four_clips_on_every_quality_tier() -> void:
	for quality in [ArtStyle3D.Quality.POTATO, ArtStyle3D.Quality.STANDARD, ArtStyle3D.Quality.FANCY]:
		ArtStyle3D.apply_quality(quality)
		for unit_id in ["miner", "swordsman"]:
			var proxy := UnitProxy3D.create(_spawn(unit_id))
			get_tree().root.add_child(proxy)
			autofree(proxy)
			var player := proxy._model._animation_player
			assert_not_null(player, "%s tier %s proxy has an AnimationPlayer" % [quality, unit_id])
			if player == null:
				continue
			assert_eq(player.playback_process_mode, AnimationPlayer.ANIMATION_PROCESS_MANUAL,
				"proxy sync owns playback advancement")
			assert_eq(player.get_animation_list().size(), 4, "exactly the four authored clips")
			for clip in [UnitAnimationClips.IDLE, UnitAnimationClips.WALK,
					UnitAnimationClips.ATTACK, UnitAnimationClips.DEATH]:
				assert_true(player.has_animation(clip), "%s has %s" % [unit_id, clip])
	ArtStyle3D.apply_quality(ArtStyle3D.Quality.FANCY)


func test_walk_moves_a_pivot_and_idle_loop_restores_its_base_pose() -> void:
	for unit_id in ["miner", "swordsman"]:
		var model := UnitModel3D.create(_spawn(unit_id))
		get_tree().root.add_child(model)
		autofree(model)
		var player := model._animation_player
		var pivot := model._arm_l
		var base := pivot.transform
		player.play(UnitAnimationClips.WALK)
		player.advance(0.25)
		assert_false(pivot.transform.is_equal_approx(base), "%s walk changes the arm transform" % unit_id)
		player.play(UnitAnimationClips.IDLE)
		player.advance(0.0)
		player.advance(UnitAnimationClips.IDLE_DURATION)
		assert_true(pivot.transform.is_equal_approx(base), "%s idle loop returns to the base transform" % unit_id)


func test_sim_states_select_walk_attack_and_procedural_mining() -> void:
	var u := _spawn("swordsman")
	var model := UnitModel3D.create(u)
	get_tree().root.add_child(model)
	autofree(model)
	u._state = Unit.State.MOVE
	model.sync_animation(u, 0.016)
	assert_eq(model._animation_player.current_animation, UnitAnimationClips.WALK)
	u._state = Unit.State.ATTACK
	u._attack_timer = 0.3
	model.sync_animation(u, 0.016)
	assert_eq(model._animation_player.current_animation, UnitAnimationClips.ATTACK)
	u._state = Unit.State.MINE
	u._mine_timer = 0.1
	model.sync_animation(u, 0.016)
	assert_true(model._current_clip.is_empty(), "mining keeps its dedicated procedural motion")
	assert_gt(absf(model._tool.rotation.x), 0.01, "procedural mining still poses the tool")


func test_death_clip_plays_and_existing_topple_and_sink_complete() -> void:
	var u := _spawn("swordsman")
	var model := UnitModel3D.create(u)
	get_tree().root.add_child(model)
	autofree(model)
	u._state = Unit.State.DEAD
	model.sync_animation(u, 0.016)
	assert_eq(model._animation_player.current_animation, UnitAnimationClips.DEATH)
	assert_true(model._animation_player.is_playing(), "death clip starts on the dead state")
	for i in range(24):
		model.sync_animation(u, 0.05)
	assert_false(model._animation_player.is_playing(), "death clip finishes and holds its final pose")
	assert_almost_eq(model._body.rotation.x, -PI * 0.5, 0.001, "existing topple still completes")
	assert_almost_eq(model._body.position.y, model._body_base_y - 0.06, 0.001,
		"existing post-topple sink still completes")


func test_unclipped_crawler_keeps_procedural_movement_on_potato() -> void:
	ArtStyle3D.apply_quality(ArtStyle3D.Quality.POTATO)
	var u := _spawn("crawler")
	var model := UnitModel3D.create(u)
	get_tree().root.add_child(model)
	autofree(model)
	assert_null(model._animation_player, "unclipped kinds do not allocate an AnimationPlayer")
	u._state = Unit.State.MOVE
	model.sync_animation(u, 0.016)
	u.global_position += Vector2(3.0, 0.0)
	model.sync_animation(u, 0.016)
	assert_gt(absf(model._body.rotation.z), 0.001, "crawler body still skitters procedurally")
	ArtStyle3D.apply_quality(ArtStyle3D.Quality.FANCY)
