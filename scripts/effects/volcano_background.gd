class_name VolcanoBackground
extends Node2D

## Decorative background volcano (Revamp Phase 9). Drawn by GridWorld between
## the surface sky and ground so it sits behind gameplay. Shows a silhouetted
## mountain, glowing crater, and animated magma streams that brighten and flow
## faster during warnings and eruptions.

const BASE_COLOR: Color = Color(0.22, 0.14, 0.12, 0.82)
const SHADOW_COLOR: Color = Color(0.16, 0.10, 0.08, 0.82)
const MAGMA_BASE: Color = Color("#C4421A")
const MAGMA_HOT: Color = Color("#EEBB44")
const CRATER_GLOW_BASE: Color = Color(0.85, 0.22, 0.04, 0.14)
const CRATER_GLOW_ACTIVE: Color = Color(0.95, 0.38, 0.08, 0.32)

const WIDTH: float = 260.0
const HEIGHT: float = 340.0
const CRATER_WIDTH: float = 64.0
const CRATER_DEPTH: float = 22.0

var _flow_time: float = 0.0
var _glow_pulse: float = 0.0


func _ready() -> void:
	# Register with GridWorld so it can draw us between the sky and the ground.
	var grid: Node = get_node_or_null("/root/Main/World/GridWorld")
	if grid != null:
		grid.volcano_background = self
	queue_redraw()


func _process(delta: float) -> void:
	var intensity: float = _get_intensity()
	# Slower, distant animation.
	_flow_time += delta * (0.35 + intensity * 0.7)
	_glow_pulse += delta * (1.0 + intensity * 2.0)
	queue_redraw()


func _get_intensity() -> float:
	if WeatherManager.is_volcano_active():
		return 1.0
	if WeatherManager.is_volcano_warning():
		return 0.55
	return 0.15


func _draw() -> void:
	draw_onto(self)


## Public entry point used by GridWorld: draws the volcano onto the supplied
## CanvasItem (the GridWorld node) so it layers correctly behind gameplay.
func draw_onto(canvas: CanvasItem) -> void:
	var intensity: float = _get_intensity()
	_draw_mountain_body(canvas)
	_draw_magma_streams(canvas, intensity)
	_draw_crater_glow(canvas, intensity)


func _draw_mountain_body(canvas: CanvasItem) -> void:
	var half_w: float = WIDTH * 0.5
	var peak: Vector2 = Vector2(0.0, -HEIGHT)
	var base_left: Vector2 = Vector2(-half_w, 0.0)
	var base_right: Vector2 = Vector2(half_w, 0.0)
	var crater_left: Vector2 = Vector2(-CRATER_WIDTH * 0.5, -HEIGHT + CRATER_DEPTH)
	var crater_right: Vector2 = Vector2(CRATER_WIDTH * 0.5, -HEIGHT + CRATER_DEPTH)
	var crater_bottom: Vector2 = Vector2(0.0, -HEIGHT + CRATER_DEPTH + 24.0)

	# Main silhouette.
	var body: PackedVector2Array = PackedVector2Array([
		base_left,
		Vector2(-half_w * 0.75, -HEIGHT * 0.35),
		crater_left,
		crater_bottom,
		crater_right,
		Vector2(half_w * 0.75, -HEIGHT * 0.35),
		base_right,
	])
	canvas.draw_colored_polygon(body, BASE_COLOR)

	# Shadowed left face for depth.
	var shadow: PackedVector2Array = PackedVector2Array([
		base_left,
		Vector2(-half_w * 0.45, -HEIGHT * 0.62),
		Vector2(0.0, -HEIGHT * 0.55),
		Vector2(0.0, 0.0),
	])
	canvas.draw_colored_polygon(shadow, SHADOW_COLOR)


func _draw_magma_streams(canvas: CanvasItem, intensity: float) -> void:
	var stream_count: int = 3
	var half_w: float = WIDTH * 0.5
	var start_y: float = -HEIGHT + CRATER_DEPTH + 8.0
	var colors: Array[Color] = [
		MAGMA_BASE.lerp(MAGMA_HOT, intensity),
		MAGMA_BASE.lerp(MAGMA_HOT, intensity * 0.85),
		MAGMA_BASE.lerp(MAGMA_HOT, intensity * 0.7),
	]
	for i in range(stream_count):
		var t: float = float(i) / maxf(1.0, stream_count - 1)
		var start_x: float = lerp(-CRATER_WIDTH * 0.35, CRATER_WIDTH * 0.35, t)
		# Each stream meanders down the mountain face.
		var points: PackedVector2Array = PackedVector2Array()
		var segments: int = 24
		for s in range(segments + 1):
			var st: float = float(s) / segments
			var y: float = lerp(start_y, 0.0, st)
			# Widen the stream as it descends, with a sine meander.
			var spread: float = lerp(8.0, half_w * 0.7, st)
			var meander: float = sin(st * TAU * 2.5 + _flow_time + i) * spread * 0.25
			points.append(Vector2(start_x + meander + spread * (t - 0.5) * 0.5, y))
		# Draw the stream as a thick polyline.
		var width: float = lerp(3.0, 6.0, intensity) * (1.0 + 0.25 * sin(_flow_time * 3.0 + i))
		canvas.draw_polyline(points, colors[i], width, true)


func _draw_crater_glow(canvas: CanvasItem, intensity: float) -> void:
	var glow: Color = CRATER_GLOW_BASE.lerp(CRATER_GLOW_ACTIVE, intensity)
	var pulse: float = 0.9 + 0.1 * sin(_glow_pulse)
	# Outer aura.
	canvas.draw_circle(Vector2(0.0, -HEIGHT + CRATER_DEPTH * 0.5), CRATER_WIDTH * 0.9 * pulse, glow)
	# Bright core.
	var core: Color = MAGMA_HOT
	core.a = 0.45 + intensity * 0.35
	canvas.draw_circle(Vector2(0.0, -HEIGHT + CRATER_DEPTH + 4.0), CRATER_WIDTH * 0.35, core)
