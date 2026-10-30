## 3D build-placement ghost (companion to RangeDisc3D).
##
## While the 3D shell runs the scene, the 2D placement ghost sprite would
## draw in the sim's 2D canvas space — the 2D camera no longer tracks the rig
## (edge pan / zoom-to-cursor are rig-only), so the sprite floats nowhere
## near the cursor's ground point. This translucent low-poly stand-in
## previews the structure at the snapped cell, centered inside the gold
## range/vision disc, and carries the green/red placement-validity tint the
## 2D ghost's modulate used to. Pure presentation: player_build_placement.gd
## owns its lifetime; it never touches the sim.
extends Node3D
class_name BuildGhost3D

## Same validity tint + alpha as the 2D ghost's modulate.
const VALID_COLOR := Color(0.4, 1.0, 0.4)
const INVALID_COLOR := Color(1.0, 0.35, 0.35)
const GHOST_ALPHA: float = 0.55
## Same proxy-root scale the placed structure gets (StructureProxy3D), so the
## ghost previews the real silhouette.
const GHOST_SCALE: float = 1.08

const CELL: float = GridWorld.CELL_SIZE * Presentation3D.WORLD_SCALE

## Current validity state (set_valid() retints; read by tests).
var is_valid := true


static func create(kind: String) -> BuildGhost3D:
	var g := BuildGhost3D.new()
	g.name = "BuildGhost3D"
	match kind:
		"tower":
			# Squat shaft + crenellated cap, mirroring StructureProxy3D.
			var r := CELL * 0.8
			g.add_child(ArtStyle3D.make_cylinder(r, 0.9, Color.WHITE, 8, Vector3(0.0, 0.45, 0.0)))
			g.add_child(ArtStyle3D.make_box(Vector3(r * 2.4, 0.12, r * 2.4), Color.WHITE, Vector3(0.0, 0.96, 0.0)))
		"wall":
			g.add_child(ArtStyle3D.make_box(Vector3(CELL * 0.9, 0.5, CELL * 0.42), Color.WHITE, Vector3(0.0, 0.25, 0.0)))
			g.add_child(ArtStyle3D.make_box(Vector3(CELL * 0.92, 0.08, CELL * 0.46), Color.WHITE, Vector3(0.0, 0.54, 0.0)))
		"trap":
			g.add_child(ArtStyle3D.make_box(Vector3(CELL * 0.8, 0.05, CELL * 0.8), Color.WHITE, Vector3(0.0, 0.02, 0.0)))
		_:
			# Lanterns (surface + underground): post, arm, head.
			g.add_child(ArtStyle3D.make_cylinder(0.03, 0.6, Color.WHITE, 5, Vector3(0.0, 0.3, 0.0)))
			g.add_child(ArtStyle3D.make_box(Vector3(0.16, 0.03, 0.03), Color.WHITE, Vector3(0.07, 0.6, 0.0)))
			g.add_child(ArtStyle3D.make_box(Vector3(0.15, 0.15, 0.15), Color.WHITE, Vector3(0.13, 0.52, 0.0)))
	g.scale = Vector3.ONE * GHOST_SCALE
	g.set_valid(true)
	return g


## Green = the snapped cell accepts the structure, red = _placement_error().
func set_valid(valid: bool) -> void:
	is_valid = valid
	var mat := ArtStyle3D.get_material(VALID_COLOR if valid else INVALID_COLOR, Color(0, 0, 0), 0.0, GHOST_ALPHA)
	for part in get_children():
		(part as MeshInstance3D).set_material_override(mat)
