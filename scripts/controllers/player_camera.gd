class_name PlayerCamera
extends RefCounted

var pc: PlayerController


func _init(p: PlayerController) -> void:
	pc = p


## Resolution-adaptive base zoom: the stretch setup (canvas_items/expand +
## stretch/scale) keeps the UI at a fixed logical 1920x1080, but the world
## should use every pixel the window offers — a 2560x1440 window shows a
## 2560x1440 world area (nearly the whole map), a 1280x720 window a
## 1280x720 area. Note `content_scale_factor` does NOT track window size in
## canvas_items mode (it only carries the stretch scale), so the ratio is
## computed from the visible rect vs. the actual window size instead.
## The wheel zoom multiplies on top of this base.
func _base_zoom() -> float:
	var win_size: Vector2i = pc.get_window().size
	if win_size.x <= 0:
		return 1.0
	var logical: Vector2 = pc.get_viewport().get_visible_rect().size
	return logical.x / win_size.x


func _apply_zoom() -> void:
	if pc.camera == null:
		return
	pc.camera.zoom = Vector2.ONE * (_base_zoom() * pc._zoom_factor)


func _init_view_positions() -> void:
	if pc.camera == null:
		return
	# The scene author can set a starting camera position; if it looks like a
	# surface position, treat it as the saved surface view, otherwise default.
	if pc.camera.position.y < 100:
		pc._last_surface_cam_pos = pc.camera.position
	else:
		pc._last_surface_cam_pos = Vector2(pc.camera.position.x, -150)
	var entry: Node2D = pc._player_mine_entry()
	if entry:
		pc._last_underground_cam_pos = entry.call("get_underground_position")
	else:
		pc._last_underground_cam_pos = Vector2(pc._last_surface_cam_pos.x, 400)
	# Apply the initial view mode so the camera is consistent on first frame.
	if pc._view_mode == PlayerController.ViewMode.SURFACE:
		pc.camera.position = pc._last_surface_cam_pos
	else:
		pc.camera.position = pc._last_underground_cam_pos


func _toggle_view() -> void:
	set_view(pc._view_mode == PlayerController.ViewMode.SURFACE)


## Both layers are always rendered, so the view toggle is a camera bookmark:
## it saves the camera position of the view being left and jumps to the last
## position of the requested view (surface base / own mine underground).
func set_view(underground: bool) -> void:
	var new_mode: PlayerController.ViewMode = PlayerController.ViewMode.UNDERGROUND if underground else PlayerController.ViewMode.SURFACE
	if new_mode == pc._view_mode or pc.camera == null:
		return
	if pc._view_mode == PlayerController.ViewMode.SURFACE:
		pc._last_surface_cam_pos = pc.camera.position
	else:
		pc._last_underground_cam_pos = pc.camera.position
	pc._view_mode = new_mode
	# Slide to the bookmark instead of snapping (Phase 8 game feel).
	pc._view_slide_target = pc._last_underground_cam_pos if underground else pc._last_surface_cam_pos
	DebugLog.log_command("PlayerController", "set_view", "UNDERGROUND" if underground else "SURFACE")
	pc.view_mode_changed.emit(pc._view_mode)


func is_underground_view() -> bool:
	return pc._view_mode == PlayerController.ViewMode.UNDERGROUND


func get_current_view_mode() -> PlayerController.ViewMode:
	return pc._view_mode


func _zoom_in() -> void:
	pc._zoom_factor = clampf(pc._zoom_factor * 1.1, pc._zoom_min, pc._zoom_max)
	_apply_zoom()


func _zoom_out() -> void:
	pc._zoom_factor = clampf(pc._zoom_factor / 1.1, pc._zoom_min, pc._zoom_max)
	_apply_zoom()


func _process_camera(delta: float) -> void:
	if pc.camera == null:
		return
	var move: Vector2 = Vector2.ZERO
	if Input.is_action_pressed(pc._Constants.INPUT_CAMERA_RIGHT):
		move.x += 1
	if Input.is_action_pressed(pc._Constants.INPUT_CAMERA_LEFT):
		move.x -= 1
	if Input.is_action_pressed(pc._Constants.INPUT_CAMERA_DOWN):
		move.y += 1
	if Input.is_action_pressed(pc._Constants.INPUT_CAMERA_UP):
		move.y -= 1
	pc.camera.position += move.normalized() * pc._camera_speed * delta / pc.camera.zoom
	# Camera slide after a view toggle; any manual pan cancels it.
	if pc._view_slide_target != Vector2.INF:
		if move != Vector2.ZERO:
			pc._view_slide_target = Vector2.INF
		else:
			pc.camera.position = pc.camera.position.lerp(pc._view_slide_target, minf(1.0, delta * 6.0))
			if pc.camera.position.distance_to(pc._view_slide_target) < 4.0:
				pc.camera.position = pc._view_slide_target
				pc._view_slide_target = Vector2.INF
	# Screen shake decays back to a clean zero offset.
	if pc._shake_strength > 0.2:
		pc.camera.offset = Vector2(randf_range(-pc._shake_strength, pc._shake_strength), randf_range(-pc._shake_strength, pc._shake_strength))
		pc._shake_strength = move_toward(pc._shake_strength, 0.0, delta * 30.0)
	elif pc.camera.offset != Vector2.ZERO:
		pc.camera.offset = Vector2.ZERO
	# Clamp camera within world bounds. When the view is larger than the
	# bounds on an axis (e.g. a 1440p+ window where the whole world fits),
	# pin the camera to the bounds center on that axis instead of leaving it
	# free to drift past the world into empty space.
	var half_size: Vector2 = pc.get_viewport().get_visible_rect().size / (2.0 * pc.camera.zoom)
	var min_pos: Vector2 = Vector2((GridWorld.X_MIN - 2) * GridWorld.CELL_SIZE, -300)
	var max_pos: Vector2 = Vector2((GridWorld.X_MAX + 3) * GridWorld.CELL_SIZE, (GridWorld.Y_MAX + 4) * GridWorld.CELL_SIZE)
	var lo: Vector2 = min_pos + half_size
	var hi: Vector2 = max_pos - half_size
	if lo.x <= hi.x:
		pc.camera.position.x = clampf(pc.camera.position.x, lo.x, hi.x)
	else:
		pc.camera.position.x = (min_pos.x + max_pos.x) / 2.0
	if lo.y <= hi.y:
		pc.camera.position.y = clampf(pc.camera.position.y, lo.y, hi.y)
	else:
		pc.camera.position.y = (min_pos.y + max_pos.y) / 2.0
