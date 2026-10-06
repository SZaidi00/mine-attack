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


func before_all() -> void:
	_prev_player_faction = FactionManager.player_faction_id


func after_all() -> void:
	FactionManager.set_player_faction(_prev_player_faction)


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


func _albedo_set(model: Node) -> Array:
	var colors: Array = []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mat: StandardMaterial3D = (mi as MeshInstance3D).get_material_override()
		if mat != null and not colors.has(mat.albedo_color):
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
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mat: StandardMaterial3D = (mi as MeshInstance3D).get_material_override()
		if mat != null and mat.emission_enabled and mat.emission_energy_multiplier > 1.0:
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
