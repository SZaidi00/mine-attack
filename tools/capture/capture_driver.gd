extends Node
## Capture driver entry point.
##
## Run INSTEAD of the main menu to start a deterministic match and dump
## screenshots at fixed sim timestamps:
##
##   godot --path . res://tools/capture/capture_driver.tscn -- \
##       --out /tmp/shots --difficulty 1 --faction arcane --seed 12345 \
##       --shots "10:start;30:zoomout;50:underground;70:storm;90:volcano"
##
## Arguments (all after `--`, i.e. OS.get_cmdline_user_args()):
##   --out <dir>        output directory for PNGs (created if missing)
##   --difficulty <0-4> GameManager.Difficulty (default 1 = NORMAL)
##   --faction <id>     player faction id: arcane | brute | industrial
##   --seed <int>       map seed (default 12345)
##   --speed <float>    game speed multiplier (default 1.0)
##   --shots "<spec>"   semicolon-separated list of time:name poses, where
##                      time is sim-seconds and name is one of:
##                        start     - spawn camera, untouched
##                        surface   - surface view bookmark, recentered
##                        zoomout   - surface, camera centered, 0.5x zoom
##                        underground - own-mine underground bookmark
##                        storm     - surface + forced snowstorm
##                        volcano   - surface + forced volcano eruption
##                        custom:X:Y:Z - explicit camera position (X, Y) and
##                                      zoom factor Z (e.g. custom:0:-150:0.5)
##
## The driver configures the autoloads exactly like the main menu's Play
## flow, swaps in the gameplay scene, and hands control to a CapturePilot
## node that survives the scene swap (it is parented to the root, not to
## the freed menu scene). On main that's scenes/main.tscn; on the 3D
## branch (feat/3d-conversion) the menu enters scenes/main_3d.tscn and so
## does the driver — keep this in sync with main_menu.gd's Play flow.
##
## Determinism: run with --fixed-fps 60 so sim-seconds == frames / 60.
## Headless rendering additionally needs --rendering-driver opengl3 under
## Xvfb (software Vulkan renders blank frames); see tools/capture/README.md.
##
## This tool is presentation-only: it never writes to sim state beyond the
## same setters the menu uses (difficulty / faction / seed / speed), and it
## is inert unless launched as the scene — nothing here runs during normal
## play or in the GUT suite.

const CapturePilot := preload("res://tools/capture/capture_pilot.gd")

const DEFAULT_SEED := 12345
const VALID_FACTIONS: Array[String] = ["arcane", "brute", "industrial"]
const VALID_POSES: Array[String] = [
	"start", "surface", "zoomout", "underground", "storm", "volcano",
]


func _ready() -> void:
	var config := parse_args(OS.get_cmdline_user_args())
	if config.is_empty():
		# Not launched in capture mode (e.g. accidentally opened) — bail out
		# without touching anything.
		return
	_apply_game_config(config)

	# The pilot must survive the scene swap, so parent it to the root window
	# (change_scene_to_file only frees the current scene). Deferred: the root
	# is busy setting up children while our own _ready runs.
	var pilot := CapturePilot.new()
	pilot.setup(config)
	get_tree().root.add_child.call_deferred(pilot)
	# Also deferred: change_scene_to_file manipulates the root's children and
	# errors with "busy" when invoked from inside _ready.
	get_tree().change_scene_to_file.call_deferred("res://scenes/main_3d.tscn")


func _apply_game_config(config: Dictionary) -> void:
	GameManager.set_difficulty(config.difficulty as GameManager.Difficulty)
	GameManager.set_adaptive_difficulty(false)
	GameManager.set_map_seed(config.seed)
	GameManager.set_game_speed(config.speed)
	FactionManager.set_player_faction(config.faction)
	FactionManager.pick_random_enemy_faction()


## Parse user args into a config Dictionary, or return {} when the args do
## not request capture (no --shots / --out present). Pure/static for tests.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var config := {
		"out": "",
		"difficulty": 1,
		"faction": "arcane",
		"seed": DEFAULT_SEED,
		"speed": 1.0,
		"shots": [],
	}
	var i := 0
	while i < args.size():
		match args[i]:
			"--out":
				i += 1
				if i < args.size():
					config.out = args[i]
			"--difficulty":
				i += 1
				if i < args.size():
					config.difficulty = args[i].to_int()
			"--faction":
				i += 1
				if i < args.size():
					config.faction = args[i]
			"--seed":
				i += 1
				if i < args.size():
					config.seed = args[i].to_int()
			"--speed":
				i += 1
				if i < args.size():
					config.speed = args[i].to_float()
			"--shots":
				i += 1
				if i < args.size():
					config.shots = parse_shots(args[i])
		i += 1
	if config.out.is_empty() or (config.shots as Array).is_empty():
		return {}
	config.difficulty = clampi(config.difficulty, 0, 4)
	if not VALID_FACTIONS.has(config.faction):
		config.faction = "arcane"
	if config.seed <= 0:
		config.seed = DEFAULT_SEED
	return config


## Parse a "--shots" spec into an ordered Array of shot Dictionaries:
## {"t": float, "pose": String, "pos": Vector2, "zoom": float}.
## pos/zoom are only set for "custom" poses. Pure/static for tests.
static func parse_shots(spec: String) -> Array:
	var shots: Array = []
	for raw in spec.split(";", false):
		var parts := raw.split(":", false)
		if parts.size() < 2:
			continue
		var t := parts[0].to_float()
		var pose := parts[1].strip_edges()
		var shot := {"t": t, "pose": pose, "pos": Vector2.ZERO, "zoom": 0.0}
		if pose == "custom":
			# Malformed entries are skipped silently so CI runs stay clean;
			# the produced PNG count reveals a typo'd spec.
			if parts.size() < 5:
				continue
			shot.pos = Vector2(parts[2].to_float(), parts[3].to_float())
			shot.zoom = parts[4].to_float()
		elif not VALID_POSES.has(pose):
			continue
		shots.append(shot)
	shots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
	return shots
