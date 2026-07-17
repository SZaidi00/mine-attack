extends Node

## Ring-buffer logger for Phase 0 debug instrumentation.
## Fully disabled unless Constants.DEBUG is true: no buffer, no console output.
## When enabled, lines are kept in memory for the debug overlay and echoed to
## the editor output with a color prefix per category.

const MAX_LINES: int = 400

var _buffer: Array[String] = []
var _categories_enabled: Dictionary = {
	"command": true,
	"state": true,
	"reject": true,
	"economy": true,
	"combat": true,
	"mine": true,
	"ai": true,
	"general": true,
}


# Named "_log" rather than "log": "log" collides with the global-scope math
# function log(float), which the analyzer resolves instead of this method.
func _log(message: String, category: String = "general") -> void:
	if not Constants.DEBUG:
		return
	if not _categories_enabled.get(category, true):
		return
	var stamp: String = "%d" % Engine.get_frames_drawn()
	var line: String = "[%s] %s" % [stamp, message]
	_buffer.append(line)
	if _buffer.size() > MAX_LINES:
		_buffer.remove_at(0)
	print_rich(_colored(category, line))


func log_command(who: String, action: String, detail: String = "") -> void:
	var msg: String = who + " -> " + action
	if detail != "":
		msg += " | " + detail
	_log(msg, "command")


func log_state(who: String, from: String, to: String, reason: String = "") -> void:
	var msg: String = who + ": " + from + " -> " + to
	if reason != "":
		msg += " (" + reason + ")"
	_log(msg, "state")


func log_reject(who: String, action: String, reason: String) -> void:
	_log(who + " REJECTED " + action + ": " + reason, "reject")


func get_recent(count: int = 80) -> String:
	var start: int = maxi(0, _buffer.size() - count)
	return "\n".join(_buffer.slice(start))


func clear() -> void:
	_buffer.clear()


func _colored(category: String, line: String) -> String:
	match category:
		"command":
			return "[color=cyan]" + line + "[/color]"
		"state":
			return "[color=yellow]" + line + "[/color]"
		"reject":
			return "[color=red]" + line + "[/color]"
		"economy":
			return "[color=gold]" + line + "[/color]"
		"combat":
			return "[color=salmon]" + line + "[/color]"
		"mine":
			return "[color=lime]" + line + "[/color]"
		"ai":
			return "[color=plum]" + line + "[/color]"
		_:
			return "[color=gray]" + line + "[/color]"
