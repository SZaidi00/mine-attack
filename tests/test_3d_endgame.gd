extends GutTest

# Endgame cinematic (main_3d.gd): on game_over the camera rig swoops to the
# collapsing base and pushes in while GameManager's win slow-mo owns the time
# scale. Wall-clock driven, reduced-motion aware, and cancelled by the
# capture harness's pose_camera.

var _shell: Node
var _main: Node
var _prev_reduced_motion: bool


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(7)
	_prev_reduced_motion = SettingsManager.get_reduced_motion()
	_shell = load("res://scenes/main_3d.tscn").instantiate()
	get_tree().root.add_child(_shell)
	# The sim mounts deferred; adopt it as current_scene (test_3d_port pattern).
	for i in range(60):
		await get_tree().process_frame
		_main = get_node_or_null("/root/Main")
		if _main != null:
			break
	get_tree().current_scene = _main
	await _frames(10)


func after_all() -> void:
	SettingsManager.set_reduced_motion(_prev_reduced_motion)
	GameManager.reset()  # Restore game_active + Engine.time_scale.
	_shell.free()
	_main = get_node_or_null("/root/Main")
	if _main != null:
		_main.free()
	GameManager.clear_map_seed()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func test_no_cinematic_while_the_match_runs() -> void:
	assert_false(_shell._cine_active, "no swoop before a base falls")
	assert_null(_shell._collapse_point, "no collapse site recorded yet")


func test_reduced_motion_skips_the_swoop() -> void:
	SettingsManager.set_reduced_motion(true)
	var enemy_base: Node2D = _main.get_node("World/EnemyBuilding")
	# Same signal path as a real collapse, minus the destruction (the real
	# one fires in the next test; the match must survive this one).
	_shell._on_building_destroyed(GameManager.Team.ENEMY, enemy_base)
	GameManager.declare_winner(GameManager.Team.PLAYER)
	assert_false(_shell._cine_active, "reduced motion: no camera swoop")
	GameManager.reset()  # Undo declare_winner's slow-mo + game_active flip.
	SettingsManager.set_reduced_motion(false)


func test_base_collapse_starts_the_swoop_to_the_site() -> void:
	var enemy_base: Node2D = _main.get_node("World/EnemyBuilding")
	var expected_focus := Vector3(
		enemy_base.global_position.x * 0.01, 0.0, enemy_base.global_position.y * 0.01)
	enemy_base.take_damage(9999999)  # destroyed -> declare_winner -> game_over
	assert_true(_shell._cine_active, "game_over starts the cinematic")
	assert_not_null(_shell._collapse_point, "the collapse site was captured")
	var target: Vector3 = _shell._cine_to_focus
	assert_almost_eq(target.x, expected_focus.x, 0.01,
		"the swoop targets the collapsing base (x)")
	assert_almost_eq(target.z, expected_focus.z, 0.01,
		"the swoop targets the collapsing base (z)")
	await _frames(3)
	assert_true(_shell._focus.distance_to(target) < _shell._cine_from_focus.distance_to(target),
		"the rig is gliding toward the collapse")
	GameManager.reset()  # Restore time scale for the rest of the suite.


func test_cinematic_finishes_on_wall_clock() -> void:
	_shell._cine_active = true
	_shell._cine_start_msec = Time.get_ticks_msec() - 10000  # Long past the duration.
	_shell._cine_from_focus = Vector3.ZERO
	_shell._cine_to_focus = Vector3(1.0, 0.0, 1.0)
	_shell._cine_from_dolly = 12.0
	_shell._process(0.016)
	assert_false(_shell._cine_active, "the swoop completes after its duration")
	assert_eq(_shell._focus, Vector3(1.0, 0.0, 1.0), "the focus lands on the target")


func test_pose_camera_cancels_the_cinematic() -> void:
	_shell._cine_active = true
	_shell._cine_start_msec = Time.get_ticks_msec()
	_shell.pose_camera(Vector3.ZERO, 12.0)
	assert_false(_shell._cine_active, "capture posing wins over the cinematic")
	assert_eq(_shell._focus, Vector3.ZERO, "the requested pose applies")
