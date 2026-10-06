extends GutTest

# Phase 2 art pass (roadmap/3d-conversion/phase-2-art-pass.md §2.3):
# structure proxies are procedural low-poly models, not box stand-ins —
# the building carries faction identity (accent trims re-tint when the enemy
# faction is identified), towers/walls expose damage states driven by the
# live entity's hp, and lanterns are dynamic-light heroes whose OmniLight3D
# radius/energy scale with tier.

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


# ─── Building: faction identity ───


func test_building_accents_reveal_enemy_faction_on_identification() -> void:
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

	var max_hp: int = tower.get("max_hp")
	assert_almost_eq(cap.rotation.z, 0.0, 0.001, "undamaged tower stands straight")
	assert_false(rubble.visible, "no rubble at full HP")

	tower.call("take_damage", roundi(max_hp * 0.45))  # 55%: below the 60% threshold.
	assert_almost_eq(absf(cap.rotation.z), 0.07, 0.001, "cap tilts below 60% HP")
	assert_false(rubble.visible, "rubble appears only below 30% HP")
	assert_ne(_body_color(proxy), ArtStyle3D.team_color(GameManager.Team.PLAYER),
		"shaft darkens once damaged")

	tower.call("take_damage", roundi(max_hp * 0.3))  # 25%: below the 30% threshold.
	assert_almost_eq(absf(cap.rotation.z), 0.17, 0.001, "cap tilts further below 30% HP")
	assert_true(rubble.visible, "broken rubble at the base below 30% HP")


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
	assert_false(light.shadow_enabled, "underground lanterns never cast shadows")
	assert_true(proxy.visible, "underground lantern shows in the underground view")
	proxy.refresh(false)
	assert_false(proxy.visible, "underground lantern hides on the surface view")
