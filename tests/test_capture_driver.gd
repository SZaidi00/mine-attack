extends GutTest
## Parsing coverage for the capture harness (tools/capture/). The runtime
## pilot needs a live match, so only the pure static parsers are tested here.

const CaptureDriver := preload("res://tools/capture/capture_driver.gd")


func test_no_capture_args_returns_empty() -> void:
	assert_eq(CaptureDriver.parse_args(PackedStringArray()), {})
	assert_eq(
		CaptureDriver.parse_args(PackedStringArray(["--seed", "7"])), {})


func test_minimal_args_fill_defaults() -> void:
	var config := CaptureDriver.parse_args(
		PackedStringArray(["--out", "/tmp/x", "--shots", "1:start"]))
	assert_eq(config.out, "/tmp/x")
	assert_eq(config.difficulty, 1)
	assert_eq(config.faction, "arcane")
	assert_eq(config.seed, CaptureDriver.DEFAULT_SEED)
	assert_eq(config.speed, 1.0)
	assert_eq(config.shots.size(), 1)


func test_invalid_faction_and_seed_fall_back() -> void:
	var config := CaptureDriver.parse_args(PackedStringArray([
		"--out", "/tmp/x", "--shots", "1:start",
		"--faction", "nonsense", "--seed", "-4",
	]))
	assert_eq(config.faction, "arcane")
	assert_eq(config.seed, CaptureDriver.DEFAULT_SEED)


func test_difficulty_is_clamped() -> void:
	var low := CaptureDriver.parse_args(PackedStringArray([
		"--out", "/tmp/x", "--shots", "1:start", "--difficulty", "-3",
	]))
	var high := CaptureDriver.parse_args(PackedStringArray([
		"--out", "/tmp/x", "--shots", "1:start", "--difficulty", "99",
	]))
	assert_eq(low.difficulty, 0)
	assert_eq(high.difficulty, 4)


func test_parse_shots_orders_by_time_and_parses_fields() -> void:
	var shots := CaptureDriver.parse_shots("30:zoomout;10:start;5:custom:1:2:0.5")
	assert_eq(shots.size(), 3)
	assert_eq(shots[0].pose, "custom")
	assert_eq(shots[0].t, 5.0)
	assert_eq(shots[0].pos, Vector2(1, 2))
	assert_eq(shots[0].zoom, 0.5)
	assert_eq(shots[1].pose, "start")
	assert_eq(shots[2].pose, "zoomout")


func test_parse_shots_skips_garbage() -> void:
	var shots := CaptureDriver.parse_shots("bogus;;10:start;custom:1:2")
	assert_eq(shots.size(), 1)
	assert_eq(shots[0].pose, "start")


func test_parse_shots_accepts_breach_pose() -> void:
	var shots := CaptureDriver.parse_shots("12:breach")
	assert_eq(shots.size(), 1)
	assert_eq(shots[0].pose, "breach")
	assert_eq(shots[0].t, 12.0)


func test_parse_shots_accepts_r7_unit_lineups() -> void:
	var shots := CaptureDriver.parse_shots("4:units;8:units_underground")
	assert_eq(shots.size(), 2)
	assert_eq(shots[0].pose, "units")
	assert_eq(shots[1].pose, "units_underground")


func test_parse_shots_accepts_r8_showcase_poses() -> void:
	var shots := CaptureDriver.parse_shots("8:base;16:dunes;24:fortress")
	assert_eq(shots.size(), 3)
	assert_eq(shots[0].pose, "base")
	assert_eq(shots[1].pose, "dunes")
	assert_eq(shots[2].pose, "fortress")
