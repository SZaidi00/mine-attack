## 3D rework Phase 1 (roadmap/3d-rework/phase-1-selection-and-combat-feedback--k3.md).
##
## Shared flat geometry for ground-projected feedback (selection rings, order
## markers, range discs): a unit-radius annulus and disc mesh built once, plus
## a cache of unshaded alpha materials. Unshaded so the feedback reads at any
## lighting; depth testing stays ON with a small ground lift
## (Presentation3D.GROUND_LIFT) so terrain, walls and structures occlude the
## decals honestly — with no_depth_test the rings would bleed through the
## sculpted surface and read as screen-space UI instead of ground decals.
class_name FlatGeo3D
extends RefCounted

const RING_SEGMENTS: int = 40

static var _ring_meshes: Dictionary = {}
static var _disc_mesh: CylinderMesh
static var _materials: Dictionary = {}


## Unit-radius flat annulus in the XZ plane; scale the instance transform to
## the desired world radius. inner_ratio sets the ring thickness (default
## 0.78 reads well at selection-ring sizes; large discs pass a ratio near 1
## so the outline stays a thin stroke). Meshes are cached per ratio.
static func ring_mesh(inner_ratio: float = 0.78) -> ArrayMesh:
	if _ring_meshes.has(inner_ratio):
		return _ring_meshes[inner_ratio]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(RING_SEGMENTS):
		var a0: float = TAU * float(i) / float(RING_SEGMENTS)
		var a1: float = TAU * float(i + 1) / float(RING_SEGMENTS)
		var i0 := Vector3(cos(a0) * inner_ratio, 0.0, sin(a0) * inner_ratio)
		var o0 := Vector3(cos(a0), 0.0, sin(a0))
		var i1 := Vector3(cos(a1) * inner_ratio, 0.0, sin(a1) * inner_ratio)
		var o1 := Vector3(cos(a1), 0.0, sin(a1))
		st.add_vertex(i0)
		st.add_vertex(o0)
		st.add_vertex(o1)
		st.add_vertex(i0)
		st.add_vertex(o1)
		st.add_vertex(i1)
	var mesh := st.commit()
	_ring_meshes[inner_ratio] = mesh
	return mesh


## Unit-radius flat disc in the XZ plane (a squat cylinder: cheap, and the
## hair-thin side wall hides any gap at the silhouette edge).
static func disc_mesh() -> CylinderMesh:
	if _disc_mesh == null:
		_disc_mesh = CylinderMesh.new()
		_disc_mesh.top_radius = 1.0
		_disc_mesh.bottom_radius = 1.0
		_disc_mesh.height = 0.004
		_disc_mesh.radial_segments = RING_SEGMENTS
	return _disc_mesh


## Unshaded, alpha-blended, vertex-color-driven material. vertex_color_as_albedo
## makes it work for both plain albedo (single meshes) and MultiMesh per-instance
## colors. Cached per exact color so shared meshes stay cheap.
static func material(color: Color) -> StandardMaterial3D:
	var key: String = color.to_html(true)
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = mat
	return mat


## A flat ring mesh instance: unit annulus scaled to radius, lifted off the
## ground, in the given color.
static func make_ring(radius: float, color: Color, lift: float = Presentation3D.GROUND_LIFT, inner_ratio: float = 0.78) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ring_mesh(inner_ratio)
	mi.scale = Vector3(radius, 1.0, radius)
	mi.position.y = lift
	mi.set_material_override(material(color))
	return mi


## A flat disc mesh instance (fill + separate outline ring read better than a
## fill alone on bright terrain).
static func make_disc(radius: float, color: Color, lift: float = Presentation3D.GROUND_LIFT) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = disc_mesh()
	mi.scale = Vector3(radius, 1.0, radius)
	mi.position.y = lift
	mi.set_material_override(material(color))
	return mi
