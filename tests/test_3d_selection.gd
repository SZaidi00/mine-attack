extends GutTest

# 3D rework Phase 1 (roadmap/3d-rework/phase-1-selection-and-combat-feedback--k3.md):
# selection rings, HP-bar visibility, projectile tracers, and the 3D branches
# of the order-marker / damage-popup spawn points.

var _shell: Node
var _main: Node


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(7)
	_shell = load("res://scenes/main_3d.tscn").instantiate()
	get_tree().root.add_child(_shell)
	# The sim mounts deferred; wait for it, then adopt it as current_scene so
	# the sim's 2D feedback paths keep parenting somewhere valid (real 3D play
	# has the shell as current_scene; tests flip it explicitly where needed).
	for i in range(60):
		await get_tree().process_frame
		_main = get_node_or_null("/root/Main")
		if _main != null:
			break
	get_tree().current_scene = _main


func after_all() -> void:
	_shell.free()
	_main = get_node_or_null("/root/Main")
	if _main != null:
		_main.free()
	GameManager.clear_map_seed()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _player_units() -> Array:
	return get_tree().get_nodes_in_group("player")


## Waits until at least one player unit is on the surface (miners spend most
## of their time underground, surfacing for deposit trips).
func _surface_units(max_frames: int = 600) -> Array:
	var units: Array = []
	for i in range(max_frames):
		units = _player_units().filter(func(u): return not u.is_underground)
		if not units.is_empty():
			break
		await get_tree().process_frame
	return units


func test_selection_ring_appears_for_selected_unit() -> void:
	var units: Array = await _surface_units()
	assert_gt(units.size(), 0, "precondition: player has surface units")
	if units.is_empty():
		return
	var rings: SelectionRings3D = _shell.get_node("World3D/SelectionRings3D")
	# Park the cursor in the screen corner so the hover ring cannot add a
	# stray instance to the count.
	get_viewport().warp_mouse(Vector2(2, 2))
	var pc: PlayerController = _main.get_node("PlayerController")
	pc._select_units([units[0]])
	await _frames(3)
	assert_eq(rings._multimesh.instance_count, 1, "one ring for one selected unit")
	pc._select_units(units)
	await _frames(3)
	assert_eq(rings._multimesh.instance_count, units.size(), "one ring per selected unit")
	pc._select_units([])
	await _frames(3)
	assert_eq(rings._multimesh.instance_count, 0, "no rings with an empty selection")


func test_rings_follow_the_viewed_layer() -> void:
	await _frames(10)
	var units: Array = _player_units()
	if units.is_empty():
		return
	var rings: SelectionRings3D = _shell.get_node("World3D/SelectionRings3D")
	get_viewport().warp_mouse(Vector2(2, 2))
	var pc: PlayerController = _main.get_node("PlayerController")
	var underground: Array = units.filter(func(u): return u.is_underground)
	if underground.is_empty():
		pass_test("no underground units yet; nothing to check")
		return
	pc._select_units(underground)
	await _frames(3)
	assert_eq(rings._multimesh.instance_count, 0, "surface view hides underground units' rings")
	rings.set_underground_view(true)
	await _frames(3)
	assert_eq(rings._multimesh.instance_count, underground.size(), "underground view shows them")
	rings.set_underground_view(false)
	pc._select_units([])


func test_selected_full_hp_unit_shows_hp_bar() -> void:
	await _frames(10)
	var units: Array = _player_units()
	if units.is_empty():
		return
	var unit: Unit = units[0]
	assert_eq(unit.hp, unit.data.max_hp, "precondition: fresh unit at full HP")
	var pc: PlayerController = _main.get_node("PlayerController")
	pc._select_units([unit])
	await _frames(3)
	var proxy: UnitProxy3D = null
	for p in _shell.get_node("World3D/Units3D").get_children():
		if (p as UnitProxy3D).unit == unit:
			proxy = p
			break
	assert_not_null(proxy, "unit has a 3D proxy")
	if proxy == null:
		return
	assert_true(proxy._hp_bar.visible, "selected full-HP unit shows its HP bar")
	pc._select_units([])
	await _frames(3)
	assert_false(proxy._hp_bar.visible, "unselected full-HP unit hides it again")


func test_damaged_unselected_unit_keeps_hp_bar() -> void:
	await _frames(10)
	var units: Array = _player_units()
	if units.is_empty():
		return
	var unit: Unit = units[0]
	unit.hp = maxi(1, unit.data.max_hp - 10)  # sim state write for the test only
	await _frames(3)
	var proxy: UnitProxy3D = null
	for p in _shell.get_node("World3D/Units3D").get_children():
		if (p as UnitProxy3D).unit == unit:
			proxy = p
			break
	if proxy == null:
		return
	assert_true(proxy._hp_bar.visible, "damaged unselected unit still shows its HP bar")


func test_projectile_tracers_mirror_sim_projectiles() -> void:
	await _frames(10)
	var building: Node2D = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == GameManager.Team.PLAYER:
			building = b
			break
	assert_not_null(building, "precondition: player building exists")
	if building == null:
		return
	var proxies: ProjectileProxies3D = _shell.get_node("World3D/ProjectileProxies3D")
	var start: int = proxies._active.size()
	var proj: Node2D = load("res://scenes/projectile.tscn").instantiate()
	proj.set("team", GameManager.Team.ENEMY)
	proj.set("speed", 5.0)  # slow enough to stay in flight across the asserts
	proj.global_position = building.global_position + Vector2(60, 0)
	proj.set("target_position", proj.global_position + Vector2(2000, 0))
	_main.get_node("Projectiles").add_child(proj)
	await _frames(3)
	assert_eq(proxies._active.size(), start + 1, "live projectile gets a 3D tracer")
	proj.queue_free()
	await _frames(3)
	assert_eq(proxies._active.size(), start, "dead projectile's tracer returns to the pool")


func test_order_marker_branches_to_3d_under_the_shell() -> void:
	var pc: PlayerController = _main.get_node("PlayerController")
	get_tree().current_scene = _shell
	pc._commands._spawn_order_marker(Vector2(-500, 0), Color("#3B82F6"))
	var found := false
	for child in _shell.get_node("World3D/Effects3D").get_children():
		if child is OrderMarker3D:
			found = true
			assert_almost_eq((child as OrderMarker3D).position.x, -5.0, 0.001,
				"marker sits at the 3D projection of the 2D order position")
			break
	get_tree().current_scene = _main
	assert_true(found, "3D order marker spawned under the shell's Effects3D")


func test_order_marker_stays_2d_without_the_shell() -> void:
	var pc: PlayerController = _main.get_node("PlayerController")
	var before: int = _main.get_child_count()
	pc._commands._spawn_order_marker(Vector2(-500, 0), Color("#3B82F6"))
	assert_eq(_main.get_child_count(), before + 1, "2D marker parents to current_scene as before")
	var marker: Node = _main.get_child(_main.get_child_count() - 1)
	assert_true(marker is OrderMarker, "2D marker type unchanged")
	marker.queue_free()


func test_damage_popup_branches_to_3d_under_the_shell() -> void:
	var units: Array = _player_units()
	if units.is_empty():
		return
	get_tree().current_scene = _shell
	(units[0] as Unit)._combat._spawn_damage_popup(5)
	var found := false
	for child in _shell.get_node("World3D/Effects3D").get_children():
		if child is DamagePopup3D:
			found = true
			break
	get_tree().current_scene = _main
	assert_true(found, "3D damage popup spawned under the shell's Effects3D")


func test_range_disc_scales_fill_and_outline() -> void:
	var disc := RangeDisc3D.create(2.0)
	add_child(disc)
	assert_almost_eq(disc._fill.scale.x, 2.0, 0.001, "fill scales to the radius")
	assert_almost_eq(disc._outline.scale.x, 2.0, 0.001, "outline scales to the radius")
	disc.set_radius(3.5)
	assert_almost_eq(disc._fill.scale.x, 3.5, 0.001, "radius updates live (research bonuses)")
	disc.free()
