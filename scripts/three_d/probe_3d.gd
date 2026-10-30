## Opt-in script-time instrumentation for the 3D presentation layer (perf
## pass / BENCH mode). Hot nodes wrap their expensive sections in:
##
##     if Probe3D.enabled:
##         var probe_start := Time.get_ticks_usec()
##     ... work ...
##     if Probe3D.enabled:
##         Probe3D.add("unit_sync", (Time.get_ticks_usec() - probe_start) / 1000.0)
##
## When disabled the flag check is the only cost. Averages feed the F3 debug
## overlay on device and the headless BENCH report (GPU frame times under
## software GL are meaningless, but script milliseconds are real everywhere).
class_name Probe3D
extends RefCounted

static var enabled: bool = false
static var _accum_ms: Dictionary = {}  # label -> total milliseconds
static var _counts: Dictionary = {}  # label -> sample count


static func add(label: String, ms: float) -> void:
	_accum_ms[label] = float(_accum_ms.get(label, 0.0)) + ms
	_counts[label] = int(_counts.get(label, 0)) + 1


## Average milliseconds per sample since the last reset, per label.
static func averages() -> Dictionary:
	var result := {}
	for label in _accum_ms:
		var calls: int = int(_counts.get(label, 0))
		if calls > 0:
			result[label] = float(_accum_ms[label]) / calls
	return result


static func reset() -> void:
	_accum_ms.clear()
	_counts.clear()


## One-line-per-label report for stdout (BENCH mode).
static func report() -> String:
	var lines: Array[String] = []
	var avgs := averages()
	var labels: Array = avgs.keys()
	labels.sort()
	for label in labels:
		lines.append("%s: %.3f ms avg over %d samples" % [label, avgs[label], int(_counts.get(label, 0))])
	return "\n".join(lines)
