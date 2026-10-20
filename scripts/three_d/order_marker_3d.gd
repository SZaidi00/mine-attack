## 3D rework Phase 1 (roadmap/3d-rework/phase-1-selection-and-combat-feedback--k3.md §4).
##
## 3D equivalent of effects/order_marker.gd: a flat expanding ring on the
## terrain at the order destination (blue move / red attack / gold mine —
## the sim passes the same colors it gives the 2D marker). Spawned only when
## the 3D shell runs the scene; the 2D marker stays the fallback elsewhere.
extends Node3D
class_name OrderMarker3D

const LIFETIME: float = 0.5
const RADIUS_START: float = 0.06
const RADIUS_END: float = 0.24

var _timer: float = LIFETIME
var _scale_mult: float = 1.0
var _mat: StandardMaterial3D
var _ring: MeshInstance3D


## Spawns a 3D order ring under the shell's Effects3D container. Returns false
## when the 3D shell is not running the scene — callers keep their 2D path.
static func spawn(tree: SceneTree, at: Vector2, color: Color, scale_mult: float = 1.0) -> bool:
	var parent := Presentation3D.effects_parent(tree)
	if parent == null:
		return false
	var marker := OrderMarker3D.new()
	marker.position = Presentation3D.to_3d(at, 0.0)
	marker._scale_mult = scale_mult
	marker._mat = FlatGeo3D.material(color).duplicate()
	marker._ring = FlatGeo3D.make_ring(RADIUS_START * scale_mult, color)
	marker._ring.set_material_override(marker._mat)
	marker.add_child(marker._ring)
	parent.add_child(marker)
	return true


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		queue_free()
		return
	var t: float = 1.0 - clampf(_timer / LIFETIME, 0.0, 1.0)
	var radius: float = lerpf(RADIUS_START, RADIUS_END, t) * _scale_mult
	_ring.scale = Vector3(radius, 1.0, radius)
	_mat.albedo_color.a = 1.0 - t
