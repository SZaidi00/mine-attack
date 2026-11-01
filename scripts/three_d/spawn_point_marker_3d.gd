## Building spawn point: a persistent gold flag on the terrain marking where
## newly trained units gather. Created only when the main_3d shell runs the
## scene (Presentation3D.effects_parent() non-null); the 2D building sprite
## draws its own flag in _draw otherwise. Presentation only — the sim-side
## state lives on building.gd, which owns the marker's lifetime.
extends Node3D
class_name SpawnPointMarker3D

const RING_RADIUS: float = 0.30
const POLE_HEIGHT: float = 0.55
const POLE_WIDTH: float = 0.025
const FLAG_COLOR: Color = Color("#FBBF24")


## Ground-snapped flag at the spawn point. Returns null when no 3D shell runs
## the scene — callers keep their 2D feedback.
static func create(tree: SceneTree, at: Vector2) -> SpawnPointMarker3D:
	var parent: Node3D = Presentation3D.effects_parent(tree)
	if parent == null:
		return null
	var marker := SpawnPointMarker3D.new()
	marker.position = Presentation3D.to_3d(at, Presentation3D.ground_height(tree,
		at.x * Presentation3D.WORLD_SCALE, at.y * Presentation3D.WORLD_SCALE))
	marker.add_child(FlatGeo3D.make_ring(RING_RADIUS, FLAG_COLOR))
	var pole := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(POLE_WIDTH, POLE_HEIGHT, POLE_WIDTH)
	pole.mesh = box
	pole.position.y = POLE_HEIGHT * 0.5
	pole.set_material_override(FlatGeo3D.material(FLAG_COLOR))
	marker.add_child(pole)
	var pennant := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(FLAG_COLOR)
	st.add_vertex(Vector3.ZERO)
	st.add_vertex(Vector3(0.20, -0.055, 0.0))
	st.add_vertex(Vector3(0.0, -0.11, 0.0))
	pennant.mesh = st.commit()
	pennant.position.y = POLE_HEIGHT
	pennant.set_material_override(FlatGeo3D.material(FLAG_COLOR))
	marker.add_child(pennant)
	parent.add_child(marker)
	return marker
