## 3D rework Phase 1 (roadmap/3d-rework/phase-1-selection-and-combat-feedback--k3.md §4).
##
## 3D equivalent of effects/damage_popup.gd: a billboarded Label3D that rises
## and fades over one second. Same content and colors as the 2D popup
## (damage red, heal green, IMMUNE grey, fire orange with a dark outline),
## same fog honesty (a popup at a position the player cannot see stays
## hidden). Spawned only when the 3D shell runs the scene.
extends Node3D
class_name DamagePopup3D

const RISE_SPEED: float = 0.4
const LIFETIME: float = 1.0
const SPAWN_HEIGHT: float = 0.6

var _timer: float = LIFETIME
var _label: Label3D
var _grid_pos2d: Vector2
var _grid: GridWorld


## Spawns a 3D popup under the shell's Effects3D container. Returns false when
## the 3D shell is not running the scene — callers keep their 2D path.
static func spawn(tree: SceneTree, at: Vector2, text: String, color: Color, fire_style: bool = false) -> bool:
	var parent := Presentation3D.effects_parent(tree)
	if parent == null:
		return false
	var popup := DamagePopup3D.new()
	popup.position = Presentation3D.to_3d(at, SPAWN_HEIGHT)
	popup._grid_pos2d = at
	parent.add_child(popup)
	popup._build(text, color, fire_style)
	return true


static func spawn_damage(tree: SceneTree, at: Vector2, amount: int, is_healing: bool = false) -> bool:
	return spawn(tree, at, ("+" if is_healing else "-") + str(amount),
		Color.GREEN if is_healing else Color.RED)


static func spawn_immune(tree: SceneTree, at: Vector2) -> bool:
	return spawn(tree, at, "IMMUNE", Color(0.75, 0.78, 0.85, 1.0))


static func spawn_fire(tree: SceneTree, at: Vector2, amount: int) -> bool:
	return spawn(tree, at, "-" + str(amount), Color(1.0, 0.55, 0.15, 1.0), true)


func _build(text: String, color: Color, fire_style: bool) -> void:
	_label = Label3D.new()
	_label.text = text
	_label.modulate = color
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.01
	_label.font_size = 32
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.outline_size = 8
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	if fire_style:
		_label.font_size = 26
		_label.outline_modulate = Color(0.05, 0.02, 0.0, 0.9)
	add_child(_label)
	_grid = get_node_or_null("/root/Main/World/GridWorld") as GridWorld


func _process(delta: float) -> void:
	# Fog of War: a popup at a position the player cannot see must not leak
	# enemy combat (or healing) activity — same rule as the 2D popup.
	if _grid != null:
		visible = _grid.is_visible_to(GameManager.Team.PLAYER, _grid_pos2d)
	position.y += RISE_SPEED * delta
	_timer -= delta
	_label.modulate.a = clampf(_timer / 0.3, 0.0, 1.0)
	if _timer <= 0.0:
		queue_free()
