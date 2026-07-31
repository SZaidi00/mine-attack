extends SceneTree

# Headless pause/research-panel smoke check: boots main.tscn, opens the
# research panel, pauses and unpauses, then quits. Any engine error during
# these transitions prints to stderr.

var _frame: int = 0


func _init() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		20:
			var hud: CanvasLayer = root.get_node("Main/UI/HUD")
			hud.toggle_research_panel()
			print("frame %d: research panel opened (visible=%s)" % [_frame, hud.get_node("ResearchPanel").visible])
		40:
			paused = true
			print("frame %d: paused = true" % _frame)
		80:
			print("frame %d: still alive while paused" % _frame)
			paused = false
			print("frame %d: paused = false" % _frame)
		120:
			print("frame %d: done, quitting" % _frame)
			quit()
	return false
