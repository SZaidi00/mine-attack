## 3D rework Phase 1 (roadmap/3d-rework/phase-1-selection-and-combat-feedback--k3.md §5).
##
## Flat ground-projected range/vision disc: a translucent fill plus a crisp
## outline ring, the 3D counterpart of the 2D gold discs in tower.gd and
## player_build_placement.gd's _RangeIndicator. Used by StructureProxy3D for
## the selected tower's attack range and by the build placement ghost for
## tower range / lantern vision previews.
extends Node3D
class_name RangeDisc3D

const FILL_ALPHA: float = 0.08
const OUTLINE_ALPHA: float = 0.5
## Outline stroke thickness in world units (absolute, so a big tower disc
## gets the same crisp stroke as a small lantern disc).
const OUTLINE_THICKNESS: float = 0.05

var _fill: MeshInstance3D
var _outline: MeshInstance3D
var _radius: float = 0.0


static func create(radius: float, color: Color = Color(1.0, 0.85, 0.4)) -> RangeDisc3D:
	var disc := RangeDisc3D.new()
	disc._fill = FlatGeo3D.make_disc(1.0, Color(color, FILL_ALPHA))
	disc._outline = FlatGeo3D.make_ring(1.0, Color(color, OUTLINE_ALPHA), Presentation3D.GROUND_LIFT + 0.01)
	disc.add_child(disc._fill)
	disc.add_child(disc._outline)
	disc.set_radius(radius)
	return disc


func set_radius(radius: float) -> void:
	_radius = radius
	_fill.scale = Vector3(radius, 1.0, radius)
	# Absolute-thickness outline: derive the annulus inner ratio from the
	# radius (rounded so the FlatGeo3D mesh cache stays bounded).
	var inner := clampf(snappedf(1.0 - OUTLINE_THICKNESS / maxf(radius, OUTLINE_THICKNESS), 0.001), 0.5, 0.98)
	_outline.mesh = FlatGeo3D.ring_mesh(inner)
	_outline.scale = Vector3(radius, 1.0, radius)
