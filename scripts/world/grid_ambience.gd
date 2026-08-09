class_name GridAmbience
extends RefCounted

var grid: GridWorld

func _init(g: GridWorld) -> void:
	grid = g


## Phase 5.1: ambient particle hooks — falling snow on the surface and slow
## dust motes underground. Deliberately subtle; polish passes live in Phase 8.
func _spawn_ambient_particles() -> void:
	var dot: Texture2D = _make_dot_texture()
	var world_left: float = (grid.X_MIN - 1) * grid.CELL_SIZE
	var world_right: float = (grid.X_MAX + 2) * grid.CELL_SIZE
	var world_center_x: float = (world_left + world_right) / 2.0
	var world_half_w: float = (world_right - world_left) / 2.0

	# Snow: tiny, slow flakes over the sky/surface band at 30% opacity.
	var snow: GPUParticles2D = GPUParticles2D.new()
	snow.name = "SnowParticles"
	snow.amount = 180
	snow.lifetime = 14.0
	snow.texture = dot
	snow.modulate = Color(1, 1, 1, 0.3)
	snow.position = Vector2(world_center_x, -300)
	snow.visibility_rect = Rect2(-world_half_w - 100, -100, (world_half_w + 100) * 2, 450)
	var snow_mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	snow_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	snow_mat.emission_box_extents = Vector3(world_half_w, 10, 1)
	snow_mat.direction = Vector3(0.15, 1, 0)
	snow_mat.spread = 15.0
	snow_mat.gravity = Vector3(0, 6, 0)
	snow_mat.initial_velocity_min = 12.0
	snow_mat.initial_velocity_max = 24.0
	snow_mat.scale_min = 0.15
	snow_mat.scale_max = 0.3
	snow.process_material = snow_mat
	grid.add_child(snow)

	# Dust motes: slow drifting specks across the whole underground.
	var dust: GPUParticles2D = GPUParticles2D.new()
	dust.name = "DustMoteParticles"
	dust.amount = 120
	dust.lifetime = 12.0
	dust.texture = dot
	dust.modulate = Color(0.85, 0.8, 0.7, 0.18)
	dust.position = Vector2(world_center_x, (grid.Y_MAX * grid.CELL_SIZE) / 2.0)
	dust.visibility_rect = Rect2(-world_half_w - 50, -(grid.Y_MAX * grid.CELL_SIZE) / 2.0 - 50, (world_half_w + 50) * 2, grid.Y_MAX * grid.CELL_SIZE + 100)
	var dust_mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	dust_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dust_mat.emission_box_extents = Vector3(world_half_w, grid.Y_MAX * grid.CELL_SIZE / 2.0, 1)
	dust_mat.direction = Vector3(1, 0.2, 0)
	dust_mat.spread = 180.0
	dust_mat.gravity = Vector3.ZERO
	dust_mat.initial_velocity_min = 2.0
	dust_mat.initial_velocity_max = 6.0
	dust_mat.scale_min = 0.1
	dust_mat.scale_max = 0.25
	dust.process_material = dust_mat
	grid.add_child(dust)


## Small soft white dot used as the particle sprite (no art dependency).
func _make_dot_texture() -> Texture2D:
	var img: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for x in range(8):
		for y in range(8):
			var d: float = Vector2(x - 3.5, y - 3.5).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d / 4.0, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
