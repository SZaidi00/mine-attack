extends Node

# Headless pause/research-panel smoke check (run as main scene, autoloads
# active): boots main.tscn, opens the research panel, pauses and unpauses,
# then quits. Any engine error during these transitions prints to stderr.

var _frame: int = 0


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	get_tree().set_deferred("current_scene", main)


func _process(_delta: float) -> void:
	_frame += 1
	match _frame:
		20:
			var hud: CanvasLayer = get_tree().root.get_node("Main/UI/HUD")
			hud.toggle_research_panel()
			print("frame %d: research panel opened (visible=%s)" % [_frame, hud.get_node("ResearchPanel").visible])
		40:
			get_tree().paused = true
			print("frame %d: paused = true" % _frame)
		80:
			print("frame %d: still alive while paused" % _frame)
			get_tree().paused = false
			print("frame %d: paused = false" % _frame)
		120:
			print("frame %d: done, quitting" % _frame)
			get_tree().quit()
