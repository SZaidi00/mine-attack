class_name Backdrop3D
extends Node3D

const CELL_WORLD: float = 0.32
const GROUND_Y: float = -0.28
const RIDGE_LAYERS: int = 3

var layout_log: Array[Dictionary] = []
var detail_log: Array[Dictionary] = []
var _seed: int = 0
var _underground: bool = false
var _large_forms: Node3D
var _details: Node3D
var _vertex_material: StandardMaterial3D


func setup(grid: GridWorld) -> void:
	_seed = maxi(grid.map_seed, 0)
	for child in get_children():
		child.free()
	layout_log.clear()
	detail_log.clear()
	_large_forms = Node3D.new()
	_large_forms.name = "LargeForms"
	add_child(_large_forms)
	_details = Node3D.new()
	_details.name = "Details"
	add_child(_details)
	_vertex_material = StandardMaterial3D.new()
	_vertex_material.vertex_color_use_as_albedo = true
	_vertex_material.roughness = ArtStyle3D.MATERIAL_ROUGHNESS
	_vertex_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rear_z := (GridWorld.SURFACE_TOP - 1) * CELL_WORLD - 0.6
	var min_x := (GridWorld.X_MIN - 1) * CELL_WORLD
	var max_x := (GridWorld.X_MAX + 2) * CELL_WORLD
	_build_ground(min_x, max_x, rear_z)
	_build_ridges(min_x, max_x, rear_z)
	_build_distant_pines(min_x, max_x, rear_z)
	apply_quality()
	set_underground_view(_underground)


func set_underground_view(underground: bool) -> void:
	_underground = underground
	visible = not underground


func apply_quality() -> void:
	if _details != null:
		_details.visible = ArtStyle3D.detail_enabled()


func layout_signature() -> Dictionary:
	return {"mountains": layout_log.duplicate(true), "pines": detail_log.duplicate(true)}


func _build_ground(min_x: float, max_x: float, rear_z: float) -> void:
	var ground := MeshInstance3D.new()
	ground.name = "GroundSkirt"
	var plane := PlaneMesh.new()
	plane.size = Vector2(max_x - min_x + 44.0, 44.0)
	ground.mesh = plane
	ground.position = Vector3((min_x + max_x) * 0.5, GROUND_Y, rear_z - 12.0)
	var color := ArtStyle3D.PALETTE.night.lerp(ArtStyle3D.PALETTE.snow_shadow, 0.12)
	ground.set_material_override(ArtStyle3D.get_material(color))
	_large_forms.add_child(ground)


func _build_ridges(min_x: float, max_x: float, rear_z: float) -> void:
	for layer in range(RIDGE_LAYERS):
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed + 700 + layer * 101
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var x := min_x - 9.0
		while x < max_x + 9.0:
			var radius_x := rng.randf_range(1.0, 2.2) * (1.0 + layer * 0.12)
			var radius_z := rng.randf_range(0.7, 1.3)
			var height := rng.randf_range(0.65, 1.1) + layer * 0.5
			var center_z := rear_z - 3.2 - layer * 2.2 - radius_z
			var peak := Vector3(x + rng.randf_range(-0.35, 0.35) * radius_x, GROUND_Y + height, center_z + rng.randf_range(-0.25, 0.25))
			var base: Array[Vector3] = []
			var snow_line: Array[Vector3] = []
			for side in range(5):
				var angle := TAU * side / 5.0
				var point := Vector3(x + cos(angle) * radius_x, GROUND_Y, center_z + sin(angle) * radius_z)
				base.append(point)
				snow_line.append(point.lerp(peak, 0.72))
			for side in range(5):
				var next := (side + 1) % 5
				var rock := ArtStyle3D.PALETTE.rock.lerp(ArtStyle3D.PALETTE.night, 0.28 + layer * 0.12 + side * 0.035)
				var snow := ArtStyle3D.PALETTE.snow_shadow.lerp(ArtStyle3D.PALETTE.night, 0.30 + layer * 0.15 + side * 0.025) if height >= 1.05 else rock.lightened(0.08)
				_add_triangle(st, base[side], base[next], snow_line[side], rock)
				_add_triangle(st, base[next], snow_line[next], snow_line[side], rock.darkened(0.06))
				_add_triangle(st, snow_line[side], snow_line[next], peak, snow)
			layout_log.append({
				"layer": layer, "x": x, "z": center_z, "height": height,
				"front_z": center_z + radius_z, "back_z": center_z - radius_z,
			})
			x += radius_x * rng.randf_range(1.45, 1.95)
		st.generate_normals()
		var ridge := MeshInstance3D.new()
		ridge.name = "Ridge_%d" % layer
		ridge.mesh = st.commit()
		ridge.set_material_override(_vertex_material)
		_large_forms.add_child(ridge)


func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for point in [a, b, c]:
		st.set_color(color)
		st.add_vertex(point)


func _build_distant_pines(min_x: float, max_x: float, rear_z: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + 1701
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for index in range(40):
		var x := rng.randf_range(min_x - 5.0, max_x + 5.0)
		var z := rear_z - rng.randf_range(2.0, 6.5)
		var height := rng.randf_range(0.45, 0.95)
		var radius := height * rng.randf_range(0.22, 0.34)
		var basis := Basis.from_euler(Vector3(0.0, rng.randf() * TAU, 0.0)).scaled(Vector3(radius, height, radius))
		transforms.append(Transform3D(basis, Vector3(x, GROUND_Y + height * 0.5, z)))
		colors.append(ArtStyle3D.PALETTE.deep_ice.lerp(ArtStyle3D.PALETTE.rock_dark, rng.randf() * 0.45))
		detail_log.append({"x": x, "z": z, "height": height})
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	mesh.radial_segments = 5
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
		multimesh.set_instance_color(index, colors[index])
	var pines := MultiMeshInstance3D.new()
	pines.name = "DistantPines"
	pines.multimesh = multimesh
	pines.set_material_override(_vertex_material)
	_details.add_child(pines)
