extends Node

enum Team { PLAYER, ENEMY }

const COLOR_PLAYER: Color = Color("#3B82F6")
const COLOR_ENEMY: Color = Color("#B91C1C")
const COLOR_ICE: Color = Color("#DCECF5")
const COLOR_STEEL: Color = Color("#5A6570")
const COLOR_RUST: Color = Color("#C45C26")
const COLOR_DEEP_ICE: Color = Color("#3E5A6E")
const COLOR_SHADOW: Color = Color("#1E252B")
const COLOR_DIRT_1: Color = Color("#8B6F47")
const COLOR_DIRT_2: Color = Color("#6B5637")
const COLOR_DIRT_3: Color = Color("#4A3B26")

signal game_over(winner: Team)

var game_active: bool = true
var match_time: float = 0.0


func _process(delta: float) -> void:
	if game_active:
		match_time += delta


func declare_winner(winner: Team) -> void:
	if not game_active:
		return
	game_active = false
	game_over.emit(winner)


func reset() -> void:
	game_active = true
	match_time = 0.0
