## Phase 1 shell (roadmap/3d-conversion/phase-1-25d-port.md).
##
## Launched as the main scene; hosts the untouched 2D simulation — mounted
## at "/root/Main" so every hard-coded path resolves exactly as shipped — and
## the 3D presentation (World3D: terrain, entity proxies, effects container)
## on top of it. The sim's CanvasItem layers are hidden; the simulation runs
## untouched (presentation reads sim state, never writes it).
##
## The camera rig replaces player_camera.gd's visible role: PlayerController
## stays the single input authority (its Tab handling emits view_mode_changed,
## which this rig follows), while pan/zoom are applied to the 3D camera. The
## 2D Camera2D keeps receiving the same input invisibly — harmless, and it
## keeps player_camera.gd's bookmarks/logic exercised for the GUT suite.
## Because the two cameras diverge (edge pan and zoom-to-cursor exist only on
## this rig), sim-side screen→world mapping routes through this rig's camera
## ray instead (player_commands._screen_to_world via Presentation3D.shell).
extends Node3D

const SIM_SCENE: PackedScene = preload("res://scenes/main.tscn")
const EFFECTS_3D_SCRIPT: GDScript = preload("res://scripts/three_d/effects_3d.gd")

## 3D units per 2D pixel. The map is ~2560x800 px, i.e. ~26x8 units.
const WORLD_SCALE: float = 0.01
const SURFACE_PITCH_DEGREES: float = 55.0
const UNDERGROUND_PITCH_DEGREES: float = 82.5
## 3D rework Phase 2: narrow vertical FOV (Godot's default is 75). The SC2/
## TAB trick — apparent size at the same dolly jumps ~1.6x and the board
## stops reading like a tilted diorama. Same for every quality preset;
## main_3d.gd re-asserts it in _ready so scene edits can't silently revert.
const CAMERA_FOV: float = 45.0
## Dolly retuned for the narrow FOV: DOLLY_START puts a 1.4x-scaled humanoid
## at ~31 px on a 1080p frame, DOLLY_MAX still covers a player's half
## (~13 units of ground width need dolly ~5.2; 16 shows the whole map).
const DOLLY_MIN: float = 3.0
const DOLLY_MAX: float = 16.0
const UNDERGROUND_DOLLY_MAX: float = 10.0
const DOLLY_WHEEL_STEP: float = 1.1
const DOLLY_START: float = 12.0
const VIEW_TWEEN_DURATION: float = 0.25
const PAN_SPEED: float = 10.0
const EDGE_PAN_MARGIN: float = 24.0

var _sim: Node2D
var _pc: Node
var _camera: Camera3D
var _terrain: Node3D
var _proxies: Node3D
var _effects: Node3D
var _lighting: Lighting3D
var _listener: AudioListener3D
var _selection_rings: SelectionRings3D
var _projectile_proxies: ProjectileProxies3D
var _event_proxies: EventProxies3D
var _fog: Fog3D
var _focus: Vector3 = Vector3.ZERO
var _surface_focus: Vector3
var _underground_focus: Vector3
var _dolly: float = DOLLY_START
var _pitch_degrees: float = SURFACE_PITCH_DEGREES
var _underground_view: bool = false
var _view_tween: Tween
var _shake: float = 0.0
var _breach_played: bool = false


func _ready() -> void:
	# §2.7: the quality preset gates shadows/post/particles globally. The
	# Settings panel can override the platform auto-detect (persisted as
	# [video] graphics_quality); changes apply live via _on_setting_changed.
	ArtStyle3D.apply_quality(ArtStyle3D.quality_from_string(SettingsManager.get_graphics_quality()))
	_camera = $CameraRig/Camera3D
	_camera.fov = CAMERA_FOV
	_terrain = $World3D/Terrain3D
	_proxies = $World3D/EntityProxies

	# §2.6: positional audio pans against the live 2D Camera2D, which mirrors
	# this rig (it still receives the same input invisibly), so a 3D listener
	# parented to the rig keeps world-attached sounds positioned correctly.
	_listener = AudioListener3D.new()
	_listener.name = "AudioListener3D"
	$CameraRig.add_child(_listener)
	_listener.make_current()

	# §2.4: weather-reactive mood driver, live next to the light rig it owns.
	_lighting = Lighting3D.new()
	_lighting.name = "Lighting3D"
	$World3D.add_child(_lighting)
	_lighting.setup(_camera)

	# Mount the untouched 2D game at "/root/Main" (deferred so the whole
	# scene enters the tree normally), then hide its CanvasItem layers: the
	# sim keeps running, only its 2D drawing is suppressed. The HUD
	# (CanvasLayer) intentionally stays visible — Controls overlay a 3D
	# viewport unchanged. current_scene stays this shell: Play Again
	# (reload_current_scene) and Quit to Menu reload/free the shell, and
	# _exit_tree takes the root-mounted sim down with it.
	_sim = SIM_SCENE.instantiate()
	get_tree().root.add_child.call_deferred(_sim)
	await _sim.ready
	if not is_inside_tree():
		return
	_sim.get_node("World").visible = false
	_sim.get_node("Units").visible = false
	_sim.get_node("Projectiles").visible = false
	_sim.get_node("Structures").visible = false
	# The HUD stays for controls, but its 2D weather renderer clips snow and
	# eruption effects to a screen band. The 3D weather volume replaces it.
	var weather_overlay := _sim.get_node_or_null("UI/HUD/WeatherOverlay") as Control
	if weather_overlay != null:
		weather_overlay.hide()
		weather_overlay.set_process(false)

	# View bookmarks mirror the 2D camera defaults: surface start position
	# and the own mine entry's underground position.
	var cam2d: Camera2D = _sim.get_node("Camera2D")
	_surface_focus = _to_ground(cam2d.position)
	var entry: Node2D = _sim.get_node("World/PlayerMineEntry")
	_underground_focus = _to_ground(entry.call("get_underground_position"))
	_focus = _surface_focus

	var grid: GridWorld = _sim.get_node("World/GridWorld") as GridWorld
	_terrain.setup(grid)
	# Structure proxies arriving/leaving re-stamp the dune clearances.
	_proxies.structure_set_changed.connect(_terrain.notify_structures_changed)
	# §2.5: art-directed effects attach the stub script onto the existing
	# Effects3D container (node paths stay stable for tests/proxies); wire it
	# after terrain, before the proxies reconcile.
	_effects = $World3D/Effects3D
	_effects.set_script(EFFECTS_3D_SCRIPT)
	(_effects as Effects3D).setup(grid, _camera)
	_proxies.setup($World3D/Units3D, $World3D/Structures3D, grid, $World3D/Effects3D, _camera)
	# 3D rework Phase 1: selection rings and projectile tracers (read-only
	# mirrors of sim state, like the entity proxies).
	_selection_rings = $World3D/SelectionRings3D
	_projectile_proxies = $World3D/ProjectileProxies3D
	_projectile_proxies.setup(grid)
	# 3D rework Phase 5: meteors/burning-ground decals/event-zone warnings.
	_event_proxies = $World3D/EventProxies3D
	_event_proxies.setup(grid)
	# Fog-of-war mist overlay (scene-stubbed like the other subsystems).
	_fog = $World3D/Fog3D
	_fog.setup(grid)

	# §2.5 juice: world events shake the rig (max-wins, reduced-motion aware).
	grid.cave_in_occurred.connect(_on_cave_in_occurred)
	grid.lava_risen.connect(_on_lava_risen)
	grid.cell_destroyed.connect(_on_cell_destroyed)
	# Phase 5 volcano presence: a low rumble on the eruption warning, a hard
	# jolt when the meteors start falling (the same signals the HUD banners
	# use; add_shake honors the reduced-motion setting). WeatherManager
	# outlives the shell — disconnected in _exit_tree.
	WeatherManager.volcano_warning_started.connect(_on_volcano_warning_started)
	WeatherManager.volcano_started.connect(_on_volcano_started)

	# PlayerController is the single input authority for view switching.
	_pc = _sim.get_node("PlayerController")
	_pc.view_mode_changed.connect(_on_view_mode_changed)
	_selection_rings.setup(_pc)
	_apply_view(_pc.get_current_view_mode() == PlayerController.ViewMode.UNDERGROUND, true)

	# 3D rework phase 4: colorblind toggle re-skins the board live — team
	# colors are baked into proxy materials at build time, so rebuild them.
	SettingsManager.setting_changed.connect(_on_setting_changed)


## Live settings reactions (phase 4 + perf pass): colorblind re-skins the
## board, graphics_quality re-lands the whole preset.
func _on_setting_changed(what: StringName) -> void:
	if what == &"colorblind" and _proxies != null:
		_proxies.rebuild_all()
	elif what == &"graphics_quality":
		_apply_quality_live(ArtStyle3D.quality_from_string(SettingsManager.get_graphics_quality()))


## Live quality switch (Settings panel): re-land shadows/post/render-scale,
## drop every entity proxy so model fidelity and lantern light tiers rebuild
## against the new preset (the proven colorblind-swap path), and force the
## terrain/fog to repaint (snow cover, detail density, drift shader).
func _apply_quality_live(q: ArtStyle3D.Quality) -> void:
	if q == ArtStyle3D.quality:
		return
	ArtStyle3D.apply_quality(q)
	_lighting.apply_quality_settings()
	if _proxies != null:
		_proxies.rebuild_all()
	if _terrain != null:
		_terrain.force_full_rebuild()
	if _fog != null:
		_fog.apply_quality()


func _to_ground(pos2d: Vector2) -> Vector3:
	return Vector3(pos2d.x * WORLD_SCALE, 0.0, pos2d.y * WORLD_SCALE)


func _process(delta: float) -> void:
	_pan(delta)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - 4.0 * delta)
	_sync_camera()


func _sync_camera() -> void:
	# Dolly is the horizontal distance; pitch controls the derived height and
	# tweens from the surface dolly to the near-top-down underground plane.
	var height: float = _dolly * tan(deg_to_rad(_pitch_degrees))
	$CameraRig.position = _focus + _shake_offset()
	_camera.position = Vector3(0.0, height, _dolly)
	_camera.rotation_degrees = Vector3(-_pitch_degrees, 0.0, 0.0)


## §2.5 juice: register a world-event rumble. Max-wins like the 2D
## PlayerController shake; a no-op under the reduced-motion accessibility
## setting (which also silences the invisible 2D shake). R5 halves ordinary
## event shake; cave-ins pass 1.0 to retain their original 0.5 impulse.
func add_shake(strength: float) -> void:
	if SettingsManager.get_reduced_motion():
		return
	_shake = maxf(_shake, strength * 0.5)


func _shake_offset() -> Vector3:
	if _shake <= 0.0:
		return Vector3.ZERO
	var amplitude: float = _shake * 0.05
	return Vector3(randf() - 0.5, (randf() - 0.5) * 0.5, randf() - 0.5) * amplitude * 2.0


func _on_cave_in_occurred(_center: Vector2i) -> void:
	add_shake(1.0)


func _on_cell_destroyed(center: Vector2i) -> void:
	if _breach_played:
		return
	var grid := _sim.get_node("World/GridWorld") as GridWorld
	if grid.get_wall_hp() > 0:
		return
	_breach_played = true
	(_effects as Effects3D).play_wall_breach(center)
	add_shake(0.45)


func _on_lava_risen(_layers: int) -> void:
	add_shake(0.3)


func _on_volcano_warning_started(_seconds: float) -> void:
	add_shake(0.35)


func _on_volcano_started() -> void:
	add_shake(1.0)


func _pan(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed(Constants.INPUT_CAMERA_RIGHT):
		dir.x += 1.0
	if Input.is_action_pressed(Constants.INPUT_CAMERA_LEFT):
		dir.x -= 1.0
	if Input.is_action_pressed(Constants.INPUT_CAMERA_DOWN):
		dir.y += 1.0
	if Input.is_action_pressed(Constants.INPUT_CAMERA_UP):
		dir.y -= 1.0
	if dir == Vector2.ZERO:
		dir = _edge_pan_dir()
	if dir == Vector2.ZERO:
		return
	# Pan speed scales with dolly so zoomed-out traversal isn't tedious.
	var speed: float = PAN_SPEED * (_dolly / DOLLY_START)
	_focus.x += dir.x * speed * delta
	_focus.z += dir.y * speed * delta
	_clamp_focus()


## Same clamp rect player_camera.gd uses for the 2D camera, in 3D units —
## shared by edge/arrow panning and zoom-to-cursor.
func _clamp_focus() -> void:
	var x_range := Vector2(
		(GridWorld.X_MIN - 2) * GridWorld.CELL_SIZE,
		(GridWorld.X_MAX + 3) * GridWorld.CELL_SIZE) * WORLD_SCALE
	var z_range := Vector2(
		(GridWorld.SURFACE_TOP - 4) * GridWorld.CELL_SIZE,
		(GridWorld.Y_MAX + 4) * GridWorld.CELL_SIZE) * WORLD_SCALE
	_focus.x = clampf(_focus.x, x_range.x, x_range.y)
	_focus.z = clampf(_focus.z, z_range.x, z_range.y)


func _edge_pan_dir() -> Vector2:
	# Hovering an interactive HUD control (buttons, menus) must not pan.
	if get_viewport().gui_get_hovered_control() != null:
		return Vector2.ZERO
	var window_size: Vector2i = get_window().size
	if window_size.x <= 0:
		return Vector2.ZERO
	var mouse: Vector2 = get_viewport().get_mouse_position()
	if mouse.x < 0.0 or mouse.y < 0.0 or mouse.x > window_size.x or mouse.y > window_size.y:
		return Vector2.ZERO
	var dir := Vector2.ZERO
	if mouse.x < EDGE_PAN_MARGIN:
		dir.x -= 1.0
	elif mouse.x > window_size.x - EDGE_PAN_MARGIN:
		dir.x += 1.0
	if mouse.y < EDGE_PAN_MARGIN:
		dir.y -= 1.0
	elif mouse.y > window_size.y - EDGE_PAN_MARGIN:
		dir.y += 1.0
	return dir


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Wheel events double as the camera_zoom_in/out actions in the input
		# map; handling the raw button covers both bindings in one branch and
		# hands us the cursor position for zoom-to-cursor.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_toward(event.position, 1.0 / DOLLY_WHEEL_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_toward(event.position, DOLLY_WHEEL_STEP)
	elif event.is_action_pressed(Constants.INPUT_CAMERA_ZOOM_IN):
		_zoom_toward(null, 1.0 / DOLLY_WHEEL_STEP)
	elif event.is_action_pressed(Constants.INPUT_CAMERA_ZOOM_OUT):
		_zoom_toward(null, DOLLY_WHEEL_STEP)


func _dolly_max_for_view() -> float:
	return UNDERGROUND_DOLLY_MAX if _underground_view else DOLLY_MAX


## Wheel zoom dolls toward the cursor's terrain point (the SC2/TAB
## convention) instead of the screen center: the focus glides along the line
## to the anchor in proportion to the dolly change, so the ground point under
## the cursor keeps its screen position across the zoom. Keyboard zoom (the
## camera_zoom actions) passes a null screen pos and anchors on the viewport
## center instead.
func _zoom_toward(screen_pos: Variant, factor: float) -> void:
	var new_dolly := clampf(_dolly * factor, DOLLY_MIN, _dolly_max_for_view())
	if is_equal_approx(new_dolly, _dolly):
		return
	var anchor: Variant = _terrain_point_at(screen_pos)
	if anchor != null:
		var t := 1.0 - new_dolly / _dolly
		_focus.x += (anchor.x - _focus.x) * t
		_focus.z += (anchor.z - _focus.z) * t
		_clamp_focus()
	_dolly = new_dolly


## World-space ground point under a screen position (null = viewport
## center): the camera ray is iterated a few times against the dune-field
## heights, which vary gently (dunes to ~0.13, wall ridges to 0.2) so the
## fixed-point loop converges almost immediately. Null when the
## ray never meets the ground (looking at the sky) or the rig isn't up yet.
func _terrain_point_at(screen_pos: Variant) -> Variant:
	if _camera == null or _terrain == null:
		return null
	var vp: Viewport = get_viewport()
	if vp == null:
		return null
	var pos: Vector2 = vp.get_visible_rect().size * 0.5 if screen_pos == null else screen_pos
	var origin := _camera.project_ray_origin(pos)
	var dir := _camera.project_ray_normal(pos)
	if dir.y > -0.001:
		return null
	var ground_y := 0.0
	var hit := Vector3.ZERO
	for i in range(3):
		var t := (ground_y - origin.y) / dir.y
		if t <= 0.0:
			return null
		hit = origin + dir * t
		ground_y = float(_terrain.call("world_height_at", hit.x, hit.z))
	return hit


## PlayerController (input authority) says the Tab view changed; the rig
## glides to the bookmark of the requested layer, remembering where the view
## being left was parked (mirrors player_camera.set_view).
func _on_view_mode_changed(mode: PlayerController.ViewMode) -> void:
	_apply_view(mode == PlayerController.ViewMode.UNDERGROUND, false)


## Immediate deterministic posing for the capture harness. An active view
## tween must not overwrite the requested shot on its next process frame.
func pose_camera(focus: Vector3, dolly: float, pitch: float = SURFACE_PITCH_DEGREES) -> void:
	if is_instance_valid(_view_tween):
		_view_tween.kill()
	_focus = focus
	_dolly = clampf(dolly, DOLLY_MIN, _dolly_max_for_view())
	_pitch_degrees = pitch
	_clamp_focus()
	_sync_camera()


func _apply_view(underground: bool, initial: bool) -> void:
	_underground_view = underground
	var target_focus := _underground_focus if underground else _surface_focus
	if not initial:
		if underground:
			_surface_focus = _focus
		else:
			_underground_focus = _focus
	var target_pitch := UNDERGROUND_PITCH_DEGREES if underground else SURFACE_PITCH_DEGREES
	var target_dolly := clampf(_dolly, DOLLY_MIN, _dolly_max_for_view())
	if is_instance_valid(_view_tween):
		_view_tween.kill()
	if initial:
		_focus = target_focus
		_dolly = target_dolly
		_pitch_degrees = target_pitch
	else:
		_view_tween = create_tween().set_parallel(true)
		_view_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_view_tween.tween_property(self, "_focus", target_focus, VIEW_TWEEN_DURATION)
		_view_tween.tween_property(self, "_dolly", target_dolly, VIEW_TWEEN_DURATION)
		_view_tween.tween_property(self, "_pitch_degrees", target_pitch, VIEW_TWEEN_DURATION)
	_terrain.set_underground_view(underground)
	_proxies.set_underground_view(underground)
	_selection_rings.set_underground_view(underground)
	_projectile_proxies.set_underground_view(underground)
	_event_proxies.set_underground_view(underground)
	if _fog != null:
		_fog.set_underground_view(underground)
	if _lighting != null:
		_lighting.set_underground_view(underground)


func _exit_tree() -> void:
	# WeatherManager is an autoload and outlives the shell; drop the volcano
	# shake hooks or the next match's signals would call into a freed shell.
	if WeatherManager.volcano_warning_started.is_connected(_on_volcano_warning_started):
		WeatherManager.volcano_warning_started.disconnect(_on_volcano_warning_started)
	if WeatherManager.volcano_started.is_connected(_on_volcano_started):
		WeatherManager.volcano_started.disconnect(_on_volcano_started)
	# Same for the settings listener (SettingsManager outlives the shell).
	if SettingsManager.setting_changed.is_connected(_on_setting_changed):
		SettingsManager.setting_changed.disconnect(_on_setting_changed)
	# The sim is a child of the window root (so /root/Main resolves), not of
	# this shell — free it or scene switches would leak it and leave a stale
	# sim running under the next scene. Deferred: the root is busy propagating
	# the tree exit right now, and the weakref makes a double-free (tests
	# freeing Main themselves) a no-op. Runs before the next shell's deferred
	# sim mount, so /root/Main is free by then.
	if _sim == null or not is_instance_valid(_sim):
		return
	var sim_ref: WeakRef = weakref(_sim)
	(func() -> void:
		var s: Node = sim_ref.get_ref()
		if s != null:
			s.free()).call_deferred()
