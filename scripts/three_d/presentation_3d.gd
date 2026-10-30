## 3D rework Phase 1 (roadmap/3d-rework/phase-1-selection-and-combat-feedback--k3.md).
##
## Shared detection + conversion helpers for sim-side feedback spawn points
## (order markers, damage popups, placement discs): when the 3D shell
## (scenes/main_3d.tscn) is the running scene, those spawn points branch to
## their 3D equivalents; standalone main.tscn (and the GUT suite, which
## adopts the sim as current_scene) keeps the original 2D path untouched.
## Pure presentation — these helpers only read scene-tree state.
class_name Presentation3D
extends RefCounted

## 3D units per 2D pixel (same constant as main_3d.gd / unit_proxy_3d.gd).
const WORLD_SCALE: float = 0.01
## Flat feedback (rings, markers, discs) hovers this far above the terrain:
## past the sculpted surface bumps (up to ~0.04) so plain depth testing never
## clips it, and still hugging the flat underground floor.
const GROUND_LIFT: float = 0.05

## Resolution cache: shell()/terrain()/effects_parent() used to re-walk the
## scene tree (has_node + get_node_or_null string lookups) on EVERY call, and
## per-frame callers (selection rings, burn decals, telegraphs) invoke them
## dozens of times a frame. The shell rig is static for a scene's lifetime,
## so resolve once per current_scene and only re-resolve when the scene
## changes (Play Again / Quit to Menu / test harness scene swaps).
static var _cached_scene: Node = null
static var _shell: Node3D = null
static var _terrain: Node = null
static var _effects_parent: Node3D = null


## The live 3D shell when it runs the show, else null. Detection mirrors how
## the shell itself is identified: the current scene is a Node3D hosting the
## World3D presentation rig (never true for the 2D main.tscn). A null tree
## (nodes inspected outside the scene tree, as GUT does) reads as no shell.
static func shell(tree: SceneTree) -> Node3D:
	if tree == null:
		return null
	var cs: Node = tree.current_scene
	if cs == _cached_scene and (cs == null or is_instance_valid(cs)):
		return _shell
	# New current scene: drop everything resolved against the old one.
	_cached_scene = cs
	_shell = null
	_terrain = null
	_effects_parent = null
	if cs is Node3D and cs.has_node("World3D"):
		_shell = cs as Node3D
	return _shell


## World-space parent for transient 3D feedback (order markers, popups).
static func effects_parent(tree: SceneTree) -> Node3D:
	var s: Node3D = shell(tree)
	if s == null:
		return null
	if _effects_parent != null and is_instance_valid(_effects_parent):
		return _effects_parent
	_effects_parent = s.get_node_or_null("World3D/Effects3D") as Node3D
	return _effects_parent


## The shell's terrain node (duck-typed: it answers world_height_at), else
## null. Ground-projected feedback (rings, markers, decals) rides the R3
## dune field through this so nothing floats over dips or sinks under crests.
static func terrain(tree: SceneTree) -> Node:
	var s: Node3D = shell(tree)
	if s == null:
		return null
	if _terrain != null and is_instance_valid(_terrain):
		return _terrain
	_terrain = s.get_node_or_null("World3D/Terrain3D")
	return _terrain


## Ground height in world units at a world XZ position (0 when the shell or
## its terrain isn't up — standalone 2D runs and tests stay flat).
static func ground_height(tree: SceneTree, world_x: float, world_z: float) -> float:
	var t := terrain(tree)
	if t == null:
		return 0.0
	return float(t.call("world_height_at", world_x, world_z))


static func to_3d(pos2d: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(pos2d.x * WORLD_SCALE, y, pos2d.y * WORLD_SCALE)
