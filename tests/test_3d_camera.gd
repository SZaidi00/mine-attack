extends GutTest

# 3D rework Phase 2 (roadmap/3d-rework/phase-2-camera-and-scale--k2.8.md):
# narrow 45deg FOV, retuned dolly range (start 12, min 3, max 16), proxy
# scale-up at the proxy roots (units 1.4x, structures 1.08x so a wall still
# fits its cell, ladders unscaled), HP bars and range discs counter-scaled,
# and wheel zoom that dolls toward the cursor's terrain point instead of the
# screen center.

class FakeUnit:
	extends Node2D
	var team: int = GameManager.Team.PLAYER
	var data: UnitData = null
	var hp: int = 50
	var is_underground: bool = false
	var selected: bool = false
	var hovered: bool = false
	signal died(unit)

	func get_flight_altitude() -> float:
		return 0.0


class FakeWall:
	extends Node2D
	var team: int = GameManager.Team.PLAYER
	var hp: int = 100
	var max_hp: int = 100

	func get_cell() -> Vector2i:
		return Vector2i(-26, 0)


class FakeTower:
	extends Node2D
	var team: int = GameManager.Team.PLAYER
	var hp: int = 100
	var max_hp: int = 100
	var selected: bool = true
	var attack_range: float = 200.0
	signal hp_changed(current, maximum)
	signal destroyed


class FakeLantern:
	extends Node2D
	var team: int = GameManager.Team.PLAYER
	var tier: int = 1
	var is_underground_lantern: bool = false
	signal upgraded(tier)


class FakeLadder:
	extends Node2D
	var top_position: Vector2 = Vector2(-592.0, -240.0)
	var bottom_position: Vector2 = Vector2(-592.0, -80.0)


var _shell: Node
var _main: Node
var _start_focus: Vector3
var _start_dolly: float


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(7)
	_shell = load("res://scenes/main_3d.tscn").instantiate()
	get_tree().root.add_child(_shell)
	# The sim mounts deferred; wait for it, then adopt it as current_scene
	# (same pattern as tests/test_3d_port.gd).
	for i in range(60):
		await get_tree().process_frame
		_main = get_node_or_null("/root/Main")
		if _main != null:
			break
	get_tree().current_scene = _main
	get_viewport().warp_mouse(get_viewport().get_visible_rect().size * 0.5)
	await get_tree().process_frame
	_start_focus = _shell.get("_focus")
	_start_dolly = float(_shell.get("_dolly"))


func after_all() -> void:
	# Free immediately (not queue_free): the next test script instantiates
	# its own main.tscn and every hard-coded /root/Main lookup breaks if the
	# name is still taken. The shell frees the root-mounted sim itself in
	# _exit_tree; the extra Main check is belt-and-braces.
	_shell.free()
	_main = get_node_or_null("/root/Main")
	if _main != null:
		_main.free()
	GameManager.clear_map_seed()


func after_each() -> void:
	# Tests move the rig and may switch layers; restore the boot framing and
	# cancel any active transition so later tests start on the surface.
	_shell.set_process(true)
	var pc: PlayerController = _main.get_node("PlayerController")
	pc.set_view(false)
	_shell.pose_camera(_start_focus, _start_dolly, _shell.SURFACE_PITCH_DEGREES)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


# ─── Camera FOV and dolly constants ───


func test_camera_fov_is_narrowed_to_45_degrees() -> void:
	await _frames(30)
	var cam: Camera3D = _shell.get_node("CameraRig/Camera3D")
	assert_almost_eq(cam.fov, 45.0, 0.01, "Camera3D FOV is 45 (was Godot's 75 default)")


func test_dolly_constants_frame_units_and_the_half_map() -> void:
	assert_almost_eq(_start_dolly, 12.0, 0.001, "rig boots at the retuned default dolly")
	# Apparent-size contract: a 1.4x-scaled swordsman (0.36 units tall) fills
	# at least 24 px of a 1080p frame at the default dolly and view pitch.
	var fov_half := deg_to_rad(45.0 * 0.5)
	var pitch := deg_to_rad(55.0)
	var slant: float = _start_dolly / cos(pitch)
	var unit_h: float = 0.36 * UnitProxy3D.PROXY_SCALE
	var px := 1080.0 * unit_h / (2.0 * slant * tan(fov_half))
	assert_gte(px, 24.0, "swordsman is >= 24 px tall at 1080p/default dolly (got %.1f)" % px)
	assert_lte(px, 40.0, "swordsman is not grotesquely huge at default dolly (got %.1f)" % px)
	# Max zoom-out (dolly 16) still shows the full width of a player's half
	# (~13.1 world units at the 55deg pitch).
	var ground_width := 2.0 * (16.0 / cos(pitch)) * tan(fov_half) * (1920.0 / 1080.0)
	assert_gte(ground_width, 13.1, "max zoom-out covers a player's half width (got %.1f)" % ground_width)


func test_zoom_clamps_to_the_dolly_range() -> void:
	await _frames(30)
	for i in range(40):
		_shell.call("_zoom_toward", null, 1.1)
	assert_almost_eq(float(_shell.get("_dolly")), 16.0, 0.001,
		"zooming out clamps at DOLLY_MAX (16)")
	for i in range(60):
		_shell.call("_zoom_toward", null, 1.0 / 1.1)
	assert_almost_eq(float(_shell.get("_dolly")), 3.0, 0.001,
		"zooming in clamps at DOLLY_MIN (3)")


func test_zoom_in_glides_focus_toward_the_cursor_terrain_point() -> void:
	await _frames(30)
	var vp_size: Vector2 = get_tree().root.get_visible_rect().size
	# Slightly left/below center: the anchor lands inside the pan clamp box
	# (the surface bookmark sits on the z clamp edge, so an upward-looking
	# cursor would push the anchor outside it).
	var screen_pos := vp_size * Vector2(0.35, 0.6)
	var anchor: Variant = _shell.call("_terrain_point_at", screen_pos)
	assert_not_null(anchor, "cursor ray meets the sculpted terrain")
	if anchor == null:
		return
	var before: Vector3 = _shell.get("_focus")
	var before_dolly := float(_shell.get("_dolly"))
	# No awaits between the zoom and the assertions: edge-pan _process ticks
	# must not move the focus mid-measurement.
	_shell.call("_zoom_toward", screen_pos, 0.5)
	assert_almost_eq(float(_shell.get("_dolly")), before_dolly * 0.5, 0.001, "dolly halved")
	var after: Vector3 = _shell.get("_focus")
	var anchor_xz := Vector2(anchor.x, anchor.z)
	assert_lt(Vector2(after.x, after.z).distance_to(anchor_xz),
		Vector2(before.x, before.z).distance_to(anchor_xz),
		"zooming in glides the focus toward the cursor's terrain point")
	# And back out: the same anchor returns the focus (the anchor stays
	# anchored across the whole in/out cycle).
	_shell.call("_zoom_toward", screen_pos, 2.0)
	var restored: Vector3 = _shell.get("_focus")
	assert_almost_eq(float(_shell.get("_dolly")), before_dolly, 0.001, "dolly restored")
	assert_almost_eq(restored.x, before.x, 0.001, "focus x restored after the in/out cycle")
	assert_almost_eq(restored.z, before.z, 0.001, "focus z restored after the in/out cycle")


func test_keyboard_zoom_anchors_on_the_viewport_center() -> void:
	await _frames(30)
	var before: Vector3 = _shell.get("_focus")
	_shell.call("_zoom_toward", null, 0.8)
	var after: Vector3 = _shell.get("_focus")
	# The view-center ray passes through the rig focus by construction, so a
	# center-anchored zoom barely glides — but it must stay in the pan clamp.
	var x_min := (GridWorld.X_MIN - 2) * GridWorld.CELL_SIZE * Presentation3D.WORLD_SCALE
	var x_max := (GridWorld.X_MAX + 3) * GridWorld.CELL_SIZE * Presentation3D.WORLD_SCALE
	var z_max := (GridWorld.Y_MAX + 4) * GridWorld.CELL_SIZE * Presentation3D.WORLD_SCALE
	assert_gte(after.x, x_min, "focus stays inside the pan clamp (x min)")
	assert_lte(after.x, x_max, "focus stays inside the pan clamp (x max)")
	assert_gte(after.z, -3.0, "focus stays inside the pan clamp (z min)")
	assert_lte(after.z, z_max, "focus stays inside the pan clamp (z max)")
	var moved := Vector2(after.x - before.x, after.z - before.z).length()
	assert_lt(moved, 2.0, "center-anchored zoom barely glides (got %.2f)" % moved)


# ─── Proxy scale-up ───


func _spawn_fake_unit(unit_id: String) -> FakeUnit:
	var u := FakeUnit.new()
	u.data = load("res://scripts/resources/units/%s.tres" % unit_id)
	u.hp = u.data.max_hp
	autofree(u)
	return u


func test_unit_proxy_scales_1_4x_with_counter_scaled_hp_bar() -> void:
	var proxy := UnitProxy3D.create(_spawn_fake_unit("swordsman"))
	autofree(proxy)
	assert_almost_eq(proxy.scale.x, 1.4, 0.001, "unit proxy root is scaled 1.4x")
	assert_almost_eq(proxy.scale.x, UnitProxy3D.PROXY_SCALE, 0.001, "scale matches PROXY_SCALE")
	var bar: Node3D = proxy.get("_hp_bar")
	assert_not_null(bar, "proxy built its HP bar")
	if bar == null:
		return
	assert_almost_eq(bar.scale.x, 1.0 / UnitProxy3D.PROXY_SCALE, 0.001,
		"HP bar is counter-scaled so it keeps its world size")
	assert_almost_eq(bar.scale.x * proxy.scale.x, 1.0, 0.001,
		"bar world scale nets to 1")
	assert_almost_eq(bar.position.y * proxy.scale.y,
		float(proxy.get("_model_height")) + UnitProxy3D.HP_BAR_LIFT, 0.001,
		"bar world lift still crowns the (scaled) silhouette")


func test_structure_proxy_scale_keeps_a_wall_inside_its_cell() -> void:
	var grid: GridWorld = _main.get_node("World/GridWorld")
	var wall := FakeWall.new()
	wall.add_to_group("walls")
	autofree(wall)
	# Never tree-added, so the shell's reconcile pass can't adopt the fake;
	# group membership only routes StructureProxy3D.create to the wall kind.
	var proxy := StructureProxy3D.create(wall, grid)
	autofree(proxy)
	assert_almost_eq(proxy.scale.x, StructureProxy3D.PROXY_SCALE, 0.001,
		"structure proxy root carries the capped scale")
	assert_lte(StructureProxy3D.PROXY_SCALE * 0.92, 1.0 + 0.001,
		"capstone (0.92*CELL) fits its cell at PROXY_SCALE")
	var cell: float = 32.0 * Presentation3D.WORLD_SCALE
	var widest := 0.0
	for mi in proxy.find_children("*", "MeshInstance3D", true, false):
		widest = maxf(widest, (mi as MeshInstance3D).mesh.get_aabb().size.x)
	assert_gt(widest, 0.0, "wall proxy has measurable meshes")
	assert_lte(widest * proxy.scale.x, cell + 0.001,
		"widest wall mesh, scaled, stays within one cell (%.3f <= %.3f)" % [widest * proxy.scale.x, cell])


func test_structure_scale_is_capped_below_the_unit_scale() -> void:
	assert_lt(StructureProxy3D.PROXY_SCALE, UnitProxy3D.PROXY_SCALE,
		"structure scale is capped by the wall footprint, below the unit 1.4x")


func test_ladder_proxy_keeps_unit_scale_for_exact_endpoints() -> void:
	var grid: GridWorld = _main.get_node("World/GridWorld")
	var ladder := FakeLadder.new()
	ladder.add_to_group("ladders")
	autofree(ladder)
	var proxy := StructureProxy3D.create(ladder, grid)
	autofree(proxy)
	assert_almost_eq(proxy.scale.x, 1.0, 0.001, "ladders skip the proxy scale-up")


func test_tower_range_disc_world_radius_survives_the_proxy_scale() -> void:
	var grid: GridWorld = _main.get_node("World/GridWorld")
	var tower := FakeTower.new()
	tower.add_to_group("towers")
	tower.position = grid.grid_to_world(Vector2i(-25, 0))
	autofree(tower)
	var proxy := StructureProxy3D.create(tower, grid)
	autofree(proxy)
	proxy.refresh(false)
	var disc: RangeDisc3D = proxy.get("_range_disc")
	assert_not_null(disc, "tower proxy carries its range disc")
	if disc == null:
		return
	assert_true(disc.visible, "selected tower shows the disc")
	assert_almost_eq(float(disc.get("_radius")), 200.0 * Presentation3D.WORLD_SCALE, 0.001,
		"disc radius is authored from attack_range in world units")
	var fill: MeshInstance3D = disc.get("_fill")
	assert_almost_eq(fill.scale.x * disc.scale.x * proxy.scale.x, 200.0 * Presentation3D.WORLD_SCALE, 0.001,
		"disc world radius nets out the proxy-root scale")


func test_lantern_omni_range_stays_in_world_units() -> void:
	var grid: GridWorld = _main.get_node("World/GridWorld")
	var lantern := FakeLantern.new()
	lantern.add_to_group("lanterns")
	lantern.position = grid.grid_to_world(Vector2i(-24, 0))
	autofree(lantern)
	var proxy := StructureProxy3D.create(lantern, grid)
	autofree(proxy)
	proxy.refresh(false)
	var light: OmniLight3D = proxy.get_node("LanternLight") as OmniLight3D
	assert_not_null(light, "lantern proxy carries its OmniLight")
	if light == null:
		return
	assert_almost_eq(light.omni_range,
		Constants.LANTERN_T1_VISION * GridWorld.CELL_SIZE * StructureProxy3D.WORLD_SCALE, 0.001,
		"light radius matches T1 vision in world units (never scaled)")


func test_selection_ring_radius_tracks_the_scaled_footprint() -> void:
	# Starting miners spawn deferred from each building's _ready.
	await _frames(90)
	var units := get_tree().get_nodes_in_group("units")
	assert_gt(units.size(), 0, "sim has live units to ring")
	if units.is_empty():
		return
	var unit: Node2D = units[0]
	var data: UnitData = unit.get("data")
	var rings: Node = _shell.get_node("World3D/SelectionRings3D")
	var radius: float = rings.call("_ring_radius", unit)
	var expected := 0.24 * UnitProxy3D.PROXY_SCALE * clampf(data.draw_scale, 0.8, 1.4)
	assert_almost_eq(radius, expected, 0.001, "ring radius tracks the 1.4x proxy footprint")


# ─── R5: perspective surface / near-top-down underground ───


func test_view_toggle_tweens_between_mode_endpoints() -> void:
	await _frames(2)
	_shell.set_process(false)  # Headless edge-pan must not move the bookmark assertions.
	var pc: PlayerController = _main.get_node("PlayerController")
	var surface_focus: Vector3 = _shell.get("_focus")
	assert_lt(_shell.VIEW_TWEEN_DURATION, 0.3, "Tab transition stays below 0.3 seconds")
	pc.set_view(true)
	assert_almost_eq(float(_shell.get("_pitch_degrees")), _shell.SURFACE_PITCH_DEGREES, 0.001,
		"underground transition starts from the surface pitch instead of snapping")
	var tween: Tween = _shell.get("_view_tween")
	assert_not_null(tween, "view switch owns a camera tween")
	if tween == null:
		return
	await tween.finished
	_shell.call("_sync_camera")
	assert_almost_eq(float(_shell.get("_pitch_degrees")), _shell.UNDERGROUND_PITCH_DEGREES, 0.001,
		"underground endpoint is near-top-down")
	assert_almost_eq(float(_shell.get("_dolly")), _shell.UNDERGROUND_DOLLY_MAX, 0.001,
		"surface dolly clamps to the underground local-area maximum")
	assert_almost_eq((_shell.get("_focus") as Vector3).distance_to(_shell.get("_underground_focus")), 0.0, 0.001,
		"transition lands on the underground bookmark")
	var cam: Camera3D = _shell.get_node("CameraRig/Camera3D")
	assert_almost_eq(cam.rotation_degrees.x, -_shell.UNDERGROUND_PITCH_DEGREES, 0.001,
		"Camera3D transform follows the underground pitch")
	pc.set_view(false)
	tween = _shell.get("_view_tween")
	await tween.finished
	assert_almost_eq(float(_shell.get("_pitch_degrees")), _shell.SURFACE_PITCH_DEGREES, 0.001,
		"returning to the surface restores its perspective pitch")
	assert_almost_eq((_shell.get("_focus") as Vector3).distance_to(surface_focus), 0.0, 0.001,
		"surface bookmark survives the round trip")


func test_underground_zoom_uses_the_local_area_dolly_range() -> void:
	_shell.set_process(false)
	var pc: PlayerController = _main.get_node("PlayerController")
	pc.set_view(true)
	var tween: Tween = _shell.get("_view_tween")
	await tween.finished
	for i in range(40):
		_shell.call("_zoom_toward", null, 1.1)
	assert_almost_eq(float(_shell.get("_dolly")), _shell.UNDERGROUND_DOLLY_MAX, 0.001,
		"underground zoom-out clamps at 10")
	for i in range(60):
		_shell.call("_zoom_toward", null, 1.0 / 1.1)
	assert_almost_eq(float(_shell.get("_dolly")), _shell.DOLLY_MIN, 0.001,
		"underground close-up keeps the shared minimum dolly")


func test_pose_camera_is_immediate_and_cancels_view_tween() -> void:
	_shell.set_process(false)
	var pc: PlayerController = _main.get_node("PlayerController")
	pc.set_view(true)
	var pose := Vector3(1.0, 0.0, 2.0)
	_shell.pose_camera(pose, 6.0, 70.0)
	var tween: Tween = _shell.get("_view_tween")
	assert_false(tween.is_running(), "posing cancels the active Tab transition")
	var cam: Camera3D = _shell.get_node("CameraRig/Camera3D")
	assert_almost_eq(cam.rotation_degrees.x, -70.0, 0.001, "posing synchronously updates the Camera3D")
	await _frames(20)
	assert_almost_eq((_shell.get("_focus") as Vector3).distance_to(pose), 0.0, 0.001,
		"posed focus is not overwritten by the old tween")
	assert_almost_eq(float(_shell.get("_dolly")), 6.0, 0.001, "posed dolly is exact")
	assert_almost_eq(float(_shell.get("_pitch_degrees")), 70.0, 0.001, "posed pitch is exact")
