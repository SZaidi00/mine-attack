class_name ThreatAlertLayer
extends Control

## Threat-alert arrows (attack/threat alerts feature): a full-HUD overlay that
## draws one screen-edge arrow per active threat reported via HUD.report_threat
## — the point is to surface surface threats (miners raided, base sieged) while
## the player is looking underground. Positions convert world → logical screen
## via the viewport canvas transform (the inverse of PlayerCommands'
## _screen_to_world), then divide by the HUD root's UI scale so drawing happens
## in this layer's local (virtual-rect) space like every other HUD element.
## Threats fade out after HUD._THREAT_LIFETIME seconds; a new alert throbs once
## unless the reduced-flash accessibility setting is on.

const _EDGE_INSET: float = 46.0
const _THROB_SEC: float = 0.35

var hud: HUD = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if hud != null and not hud._threats.is_empty():
		queue_redraw()


func _draw() -> void:
	if hud == null:
		return
	# The layer can be drawn before its full-rect layout lands (size 0), which
	# would make the inset rect negative.
	if size.x < _EDGE_INSET * 2.0 or size.y < _EDGE_INSET * 2.0:
		return
	var edge: Rect2 = Rect2(Vector2.ZERO, size).grow(-_EDGE_INSET)
	var center: Vector2 = edge.get_center()
	var reduced_flash: bool = SettingsManager.get_reduced_flash()
	for threat in hud._threats:
		var screen_pos: Vector2 = get_viewport().get_canvas_transform() * threat.pos
		var local: Vector2 = screen_pos / maxf(hud._ui_scale, 0.01)
		var color: Color = UIThemeTokens.COLOR_ENEMY
		color.a = 1.0 - clampf((threat.age - (HUD._THREAT_LIFETIME - 1.2)) / 1.2, 0.0, 1.0)
		var dir: Vector2 = local - center
		if dir.length_squared() < 1.0:
			dir = Vector2.RIGHT
		dir = dir.normalized()
		var pulse_scale: float = 1.0
		if not reduced_flash and threat.age < _THROB_SEC:
			pulse_scale = 1.0 + 0.6 * (1.0 - threat.age / _THROB_SEC)
		if edge.has_point(local):
			# Threat on screen: a small diamond marker at its position.
			var s: float = 9.0 * pulse_scale
			draw_colored_polygon(PackedVector2Array([
				local + Vector2(0, -s), local + Vector2(s, 0),
				local + Vector2(0, s), local + Vector2(-s, 0),
			]), color)
		else:
			# Off screen: clamp to the edge and point the arrow at the threat.
			var c: Vector2 = Vector2(
				clampf(local.x, edge.position.x, edge.end.x),
				clampf(local.y, edge.position.y, edge.end.y))
			var tip: Vector2 = c + dir * 15.0 * pulse_scale
			var left: Vector2 = c + dir.rotated(2.5) * 12.0 * pulse_scale
			var right: Vector2 = c + dir.rotated(-2.5) * 12.0 * pulse_scale
			draw_colored_polygon(PackedVector2Array([tip, left, right]), color)
