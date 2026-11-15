extends GutTest

class FakeUnit:
	extends Node2D
	var team: int = GameManager.Team.PLAYER
	var data: UnitData
	var hp: int = 50
	var is_underground: bool = false
	var _state: int = Unit.State.IDLE
	var _attack_timer: float = 0.5
	var _mine_timer: float = 0.25
	var _mine_target_angle: float = 0.0
	var _hit_flash_timer: float = 0.0
	var _target_unit: Node2D = null
	var _target_building: Node2D = null
	var _repair_target: Node2D = null
	var _target_position: Vector2 = Vector2.ZERO
	var _path: PackedVector2Array = PackedVector2Array()
	var _path_index: int = 0
	var _repair: Variant = null
	signal died(unit)

	func get_flight_altitude() -> float:
		return 0.0


class FakeRepairTarget:
	extends Node2D
	var allowed := false

	func can_be_repaired() -> bool:
		return allowed


var _quality: ArtStyle3D.Quality = ArtStyle3D.Quality.FANCY
var _player_faction := ""
var _enemy_faction := ""


func before_all() -> void:
	_quality = ArtStyle3D.quality
	_player_faction = FactionManager.player_faction_id
	_enemy_faction = FactionManager.enemy_faction_id
	ArtStyle3D.apply_quality(ArtStyle3D.Quality.FANCY)


func after_all() -> void:
	ArtStyle3D.apply_quality(_quality)
	FactionManager.set_player_faction(_player_faction)
	FactionManager.enemy_faction_id = _enemy_faction
	FactionManager.reset()


func _spawn(kind: String) -> FakeUnit:
	var unit := FakeUnit.new()
	unit.data = load("res://scripts/resources/units/%s.tres" % kind).duplicate(true)
	unit.hp = unit.data.max_hp
	autofree(unit)
	return unit


func _model(kind: String) -> UnitModel3D:
	var model := UnitModel3D.create(_spawn(kind))
	get_tree().root.add_child(model)
	autofree(model)
	return model


func _palette_material(model: UnitModel3D, mesh_name: String) -> ShaderMaterial:
	var mesh := model.find_child(mesh_name, true, false) as MeshInstance3D
	if mesh == null:
		return null
	return mesh.get_active_material(0) as ShaderMaterial


func test_five_native_rigs_have_skins_clips_and_bone_attachments() -> void:
	for kind in ["miner", "swordsman", "archer", "wizard", "engineer"]:
		var key: String = "unit_kaykit_" + kind
		var entry := ModelManifest.entry_for(key)
		var result := UnitModelLoader.instantiate(key)
		assert_false(result.is_empty(), "%s imports through the native path" % kind)
		if result.is_empty():
			continue
		var root := result["root"] as Node3D
		get_tree().root.add_child(root)
		autofree(root)
		var skeleton := result["skeleton"] as Skeleton3D
		var player := result["animation_player"] as AnimationPlayer
		assert_true(result["skeletal"], "%s selects the skeletal contract" % kind)
		assert_gt(skeleton.get_bone_count(), 20, "%s has its complete Rig_Medium" % kind)
		assert_almost_eq(float(result["model_height"]), float(entry["height"]), 0.001,
			"%s body normalization matches its manifest height" % kind)
		assert_eq(player.playback_process_mode, AnimationPlayer.ANIMATION_PROCESS_MANUAL,
			"%s has no independent player processing" % kind)
		for clip in entry["skeletal_clips"]:
			assert_true(player.has_animation(clip), "%s has %s" % [kind, clip])
			assert_gt(player.get_animation(clip).length, 0.0, "%s %s has authored keys" % [kind, clip])
		for clip in entry["skeletal_loops"]:
			assert_eq(player.get_animation(clip).loop_mode, Animation.LOOP_LINEAR, "%s loops %s" % [kind, clip])
		assert_eq(player.get_animation(&"death").loop_mode, Animation.LOOP_NONE, "%s death is a one-shot" % kind)
		var skinned_meshes := 0
		for mesh in root.find_children("*", "MeshInstance3D", true, false):
			if (mesh as MeshInstance3D).skin != null:
				skinned_meshes += 1
		assert_eq(skinned_meshes, 1, "%s body is one merged mesh with a real Skin" % kind)
		var attachments := root.find_children("*", "BoneAttachment3D", true, false)
		assert_gt(attachments.size(), 0, "%s has bone-mounted equipment" % kind)
		for attachment in attachments:
			var bone := (attachment as BoneAttachment3D).bone_name
			assert_true(["handslot.r", "handslot.l", "head", "chest"].has(bone),
				"%s attachment uses an inspected bone" % kind)
		var legacy := UnitModelLoader.instantiate("unit_" + kind, GameManager.Team.PLAYER, false)
		assert_false(bool(legacy["skeletal"]), "%s retains its generated fallback" % kind)
		(legacy["root"] as Node3D).free()
		if kind == "wizard":
			var has_staff_glow := false
			for mesh in root.find_children("*", "MeshInstance3D", true, false):
				var mat := (mesh as MeshInstance3D).get_active_material(0) as StandardMaterial3D
				if mat != null and mat.resource_name == "glow_staff" and mat.emission_enabled:
					has_staff_glow = mat.emission_energy_multiplier > 0.0 and mat.emission != Color.BLACK
			assert_true(has_staff_glow, "wizard retains the emissive staff accent")


func test_walk_deforms_a_bone_without_root_translation() -> void:
	var unit := _spawn("swordsman")
	var model := UnitModel3D.create(unit)
	get_tree().root.add_child(model)
	autofree(model)
	var skeleton := model._skeleton
	var root_bone := skeleton.find_bone("root")
	var arm_bone := skeleton.find_bone("upperarm.r")
	var root_before := skeleton.get_bone_global_pose(root_bone)
	var arm_before := skeleton.get_bone_global_pose(arm_bone)
	unit._state = Unit.State.MOVE
	model.sync_animation(unit, 0.016)
	assert_eq(model._current_clip, UnitAnimationClips.WALK)
	for i in range(8):
		model.sync_animation(unit, 0.05)
	assert_false(skeleton.get_bone_global_pose(arm_bone).is_equal_approx(arm_before),
		"walk changes the actual skeletal arm pose")
	assert_true(skeleton.get_bone_global_pose(root_bone).origin.is_equal_approx(root_before.origin),
		"root never drives locomotion")
	unit._state = Unit.State.IDLE
	model.sync_animation(unit, 0.016)
	assert_eq(model._current_clip, UnitAnimationClips.IDLE)
	assert_eq(model._animation_player.get_animation(&"idle").loop_mode, Animation.LOOP_LINEAR)


func test_mining_and_attacks_scale_to_simulation_timers() -> void:
	var unit := _spawn("miner")
	var model := UnitModel3D.create(unit)
	get_tree().root.add_child(model)
	autofree(model)
	unit._state = Unit.State.MINE
	unit._mine_target_angle = 0.0
	model.sync_animation(unit, 0.016)
	assert_eq(model._current_clip, UnitModel3D.MINE_CLIP)
	assert_almost_eq(model._animation_player.speed_scale,
		model._animation_player.get_animation(UnitModel3D.MINE_CLIP).length * unit.data.mining_swings_per_sec,
		0.0001, "one authored mining cycle fits one sim swing")
	unit._path = PackedVector2Array([Vector2(64.0, 32.0)])
	model.sync_animation(unit, 0.016)
	assert_eq(model._current_clip, UnitAnimationClips.WALK, "a travelling miner walks before digging")
	unit._path = PackedVector2Array()
	unit._state = Unit.State.ATTACK
	unit._attack_timer = 0.3
	model.sync_animation(unit, 0.016)
	assert_eq(model._current_clip, UnitAnimationClips.ATTACK)
	assert_almost_eq(model._animation_player.speed_scale,
		model._animation_player.get_animation(UnitAnimationClips.ATTACK).length / unit.data.attack_cooldown,
		0.0001, "one authored attack fits the real cooldown")
	unit._attack_timer = 0.05
	model.sync_animation(unit, 0.05)
	var before_reset := model._animation_player.current_animation_position
	unit._attack_timer = unit.data.attack_cooldown
	model.sync_animation(unit, 0.05)
	assert_lt(model._animation_player.current_animation_position, before_reset,
		"a fresh sim cooldown restarts the one-shot attack")


func test_engineer_repair_travel_and_lockout() -> void:
	var unit := _spawn("engineer")
	var target := FakeRepairTarget.new()
	autofree(target)
	unit._repair_target = target
	var model := UnitModel3D.create(unit)
	get_tree().root.add_child(model)
	autofree(model)
	unit._state = Unit.State.REPAIR
	unit._path = PackedVector2Array([Vector2(32.0, 0.0)])
	model.sync_animation(unit, 0.016)
	assert_eq(model._current_clip, UnitAnimationClips.WALK, "an approaching engineer walks")
	unit._path = PackedVector2Array()
	model.sync_animation(unit, 0.016)
	assert_eq(model._current_clip, UnitAnimationClips.IDLE, "recent-damage lockout holds an idle pose")
	target.allowed = true
	model.sync_animation(unit, 0.016)
	assert_eq(model._current_clip, UnitModel3D.REPAIR_CLIP, "an available repair plays the native work loop")
	assert_eq(model._animation_player.get_animation(UnitModel3D.REPAIR_CLIP).loop_mode, Animation.LOOP_LINEAR)


func test_palette_team_reveal_and_instance_isolation() -> void:
	var living := _model("swordsman")
	var material := _palette_material(living, "Knight_Body")
	assert_not_null(material, "native body uses a palette material")
	assert_not_null(material.get_shader_parameter("palette_texture"), "painted atlas remains bound")
	assert_eq(material.get_shader_parameter("team_color"), ArtStyle3D.team_color(GameManager.Team.PLAYER))
	var region: Vector4 = material.get_shader_parameter("team_region_a")
	assert_gt(region.z, region.x, "team recoloring is restricted to garment regions")
	var other := _model("swordsman")
	var other_material := _palette_material(other, "Knight_Body")
	assert_ne(material.get_instance_id(), other_material.get_instance_id(), "palette materials are per-proxy")
	var original: Color = other_material.get_shader_parameter("team_color")
	material.set_shader_parameter("team_color", Color.WHITE)
	assert_eq(other_material.get_shader_parameter("team_color"), original, "one proxy cannot recolor another")
	FactionManager.enemy_faction_id = "brute"
	FactionManager.reset()
	var enemy := _spawn("swordsman")
	enemy.team = GameManager.Team.ENEMY
	var enemy_model := UnitModel3D.create(enemy)
	get_tree().root.add_child(enemy_model)
	autofree(enemy_model)
	var enemy_material := _palette_material(enemy_model, "Knight_Body")
	assert_eq(enemy_material.get_shader_parameter("accent_color"), Color(0.42, 0.43, 0.47),
		"an unidentified enemy has neutral palette accents")
	FactionManager.identify_faction(GameManager.Team.ENEMY)
	assert_eq(enemy_material.get_shader_parameter("accent_color"), ArtStyle3D.FACTION_ACCENTS["brute"],
		"identification updates the native palette accent")


func test_undead_tint_and_hit_flash_restore_palette() -> void:
	var unit := _spawn("swordsman")
	unit.data.is_undead = true
	var model := UnitModel3D.create(unit)
	get_tree().root.add_child(model)
	autofree(model)
	var material := _palette_material(model, "Knight_Body")
	assert_almost_eq(float(material.get_shader_parameter("tint_weight")), 0.55, 0.0001,
		"native body receives the undead tint")
	model._set_flashing(true)
	assert_true(model.find_child("Knight_Body", true, false).get_active_material(0) is StandardMaterial3D,
		"hit flash replaces the native palette material")
	model._set_flashing(false)
	var restored := _palette_material(model, "Knight_Body")
	assert_eq(restored.get_instance_id(), material.get_instance_id(), "flash restores the original material")
	assert_almost_eq(float(restored.get_shader_parameter("tint_weight")), 0.55, 0.0001,
		"restoration preserves the undead tint")
	FactionManager.enemy_faction_id = "brute"
	FactionManager.reset()
	var enemy := _spawn("swordsman")
	enemy.team = GameManager.Team.ENEMY
	enemy.data.is_undead = true
	var enemy_model := UnitModel3D.create(enemy)
	get_tree().root.add_child(enemy_model)
	autofree(enemy_model)
	FactionManager.identify_faction(GameManager.Team.ENEMY)
	var revealed := _palette_material(enemy_model, "Knight_Body")
	assert_eq(revealed.get_shader_parameter("accent_color"), ArtStyle3D.FACTION_ACCENTS["brute"],
		"reveal updates the duplicated undead palette material")
	assert_almost_eq(float(revealed.get_shader_parameter("tint_weight")), 0.55, 0.0001,
		"reveal does not discard the undead tint")


func test_native_death_finishes_and_sinks_without_double_topple() -> void:
	var unit := _spawn("swordsman")
	var model := UnitModel3D.create(unit)
	get_tree().root.add_child(model)
	autofree(model)
	unit._state = Unit.State.DEAD
	model.sync_animation(unit, 0.016)
	assert_eq(model._current_clip, UnitAnimationClips.DEATH)
	assert_true(model._animation_player.is_playing())
	for i in range(30):
		model.sync_animation(unit, 0.05)
	assert_false(model._animation_player.is_playing(), "the authored death clip finishes and holds")
	assert_almost_eq(model._body.rotation.x, 0.0, 0.0001, "the native fall is not toppled a second time")
	assert_almost_eq(model._body.position.y, model._body_base_y - 0.06, 0.0001,
		"the existing death sink still completes")


func test_hidden_proxy_does_not_advance_native_playback() -> void:
	var unit := _spawn("swordsman")
	var proxy := UnitProxy3D.create(unit)
	get_tree().root.add_child(proxy)
	autofree(proxy)
	proxy.sync_from_entity(false, 0.0, 0.1)
	var player := proxy._model._animation_player
	assert_gt(player.current_animation_position, 0.0)
	unit.visible = false
	proxy.sync_from_entity(false, 0.0, 0.1)
	var paused_at := player.current_animation_position
	proxy.sync_from_entity(false, 0.0, 0.1)
	assert_eq(player.current_animation_position, paused_at, "hidden proxies skip animation advancement")
	unit.visible = true
	proxy.sync_from_entity(false, 0.0, 0.1)
	assert_gt(player.current_animation_position, paused_at, "visible proxies resume animation")
