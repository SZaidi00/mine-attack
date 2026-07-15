extends CanvasLayer

@onready var _coin_label: Label = $TopBar/HBoxContainer/CoinLabel
@onready var _pop_label: Label = $TopBar/HBoxContainer/PopLabel
@onready var _miner_level_label: Label = $TopBar/HBoxContainer/MinerLevelLabel
@onready var _queue_panel: HBoxContainer = $TopBar/HBoxContainer/QueuePanel
@onready var _queue_label: Label = $TopBar/HBoxContainer/QueuePanel/QueueLabel
@onready var _progress_bar: ProgressBar = $TopBar/HBoxContainer/QueuePanel/ProgressBar
@onready var _selection_label: Label = $TopBar/HBoxContainer/SelectionLabel
@onready var _game_over_panel: PanelContainer = $GameOverPanel
@onready var _surface_button: Button = $BottomBar/HBoxContainer/SurfaceButton
@onready var _underground_button: Button = $BottomBar/HBoxContainer/UndergroundButton

var _queue_buttons: Array[Button] = []


func _ready() -> void:
	_style_panel($TopBar)
	_style_panel($BottomBar)
	_style_panel(_game_over_panel)

	$BottomBar/HBoxContainer/MinerButton.pressed.connect(_train.bind("miner"))
	$BottomBar/HBoxContainer/SwordsmanButton.pressed.connect(_train.bind("swordsman"))
	$BottomBar/HBoxContainer/ArcherButton.pressed.connect(_train.bind("archer"))
	$BottomBar/HBoxContainer/WizardButton.pressed.connect(_train.bind("wizard"))
	$BottomBar/HBoxContainer/UpgradeMinerButton.pressed.connect(_upgrade_miner)
	$BottomBar/HBoxContainer/AttackButton.pressed.connect(_stance.bind("attack"))
	$BottomBar/HBoxContainer/DefendButton.pressed.connect(_stance.bind("defend"))
	$BottomBar/HBoxContainer/GarrisonButton.pressed.connect(_stance.bind("garrison"))
	_surface_button.pressed.connect(_set_view.bind(false))
	_underground_button.pressed.connect(_set_view.bind(true))
	$GameOverPanel/MarginContainer/VBoxContainer/QuitButton.pressed.connect(func(): get_tree().quit())
	$GameOverPanel/MarginContainer/VBoxContainer/PlayAgainButton.pressed.connect(_play_again)

	EconomyManager.coin_changed.connect(_on_economy_changed)
	EconomyManager.population_changed.connect(_on_economy_changed)
	EconomyManager.miner_level_changed.connect(_on_economy_changed)

	var player_building: Node2D = _get_player_building()
	if player_building:
		player_building.queue_changed.connect(_on_queue_changed)

	GameManager.game_over.connect(_on_game_over)
	_on_economy_changed(GameManager.Team.PLAYER)
	_sync_view_buttons()


func _process(_delta: float) -> void:
	var pc: PlayerController = _get_player_controller()
	if pc:
		_selection_label.text = "Selected: %d" % pc.get_selected_units().size()
		_sync_view_buttons()
	_update_queue_progress()


func _style_panel(panel: PanelContainer) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = GameManager.COLOR_SHADOW
	style.bg_color.a = 0.85
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)


func _train(unit_id: String) -> void:
	var pc: PlayerController = _get_player_controller()
	if pc:
		pc.train_unit(unit_id)


func _upgrade_miner() -> void:
	var pc: PlayerController = _get_player_controller()
	if pc:
		pc.upgrade_miner()


func _stance(stance: String) -> void:
	var pc: PlayerController = _get_player_controller()
	if pc:
		pc.set_stance(stance)


func _set_view(underground: bool) -> void:
	var pc: PlayerController = _get_player_controller()
	if pc:
		pc.set_view(underground)
	_sync_view_buttons()


func _sync_view_buttons() -> void:
	var pc: PlayerController = _get_player_controller()
	var underground: bool = pc.is_underground_view() if pc else false
	if _surface_button.button_pressed != (not underground):
		_surface_button.set_pressed_no_signal(not underground)
	if _underground_button.button_pressed != underground:
		_underground_button.set_pressed_no_signal(underground)


func _on_economy_changed(team: GameManager.Team) -> void:
	if team != GameManager.Team.PLAYER:
		return
	_coin_label.text = "Coin: %d" % EconomyManager.get_coin(team)
	_pop_label.text = "Pop: %d/%d" % [EconomyManager.get_population(team), GameManager.POPULATION_CAP]
	_miner_level_label.text = "Miner Lv: %d" % EconomyManager.get_miner_level(team)


func _update_queue_progress() -> void:
	var building: Node2D = _get_player_building()
	if building == null:
		_progress_bar.value = 0.0
		return
	var queue: Array = building.call("get_queue")
	if queue.is_empty():
		_progress_bar.value = 0.0
		return
	var current = queue[0]
	var pct: float = 1.0 - (current.remaining / current.data.train_time)
	_progress_bar.value = clampf(pct, 0.0, 1.0)


func _on_queue_changed(_entries: Array) -> void:
	var building: Node2D = _get_player_building()
	if building == null:
		return
	var queue: Array = building.call("get_queue")

	for btn in _queue_buttons:
		btn.queue_free()
	_queue_buttons.clear()

	for i in range(queue.size()):
		var entry = queue[i]
		var btn: Button = Button.new()
		var short: String = entry.id.capitalize().substr(0, 3)
		btn.text = short
		btn.tooltip_text = "Click to cancel and refund %d coin" % entry.data.cost
		btn.custom_minimum_size = Vector2(40, 28)
		btn.pressed.connect(_cancel_queue.bind(i))
		_queue_panel.add_child(btn)
		_queue_buttons.append(btn)

	_queue_label.text = "Queue (%d): " % queue.size()


func _cancel_queue(index: int) -> void:
	var building: Node2D = _get_player_building()
	if building:
		building.call("cancel_queue", index)


func _get_player_controller() -> PlayerController:
	return get_node_or_null("/root/Main/PlayerController")


func _get_player_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == GameManager.Team.PLAYER:
			return b
	return null


func _on_game_over(winner: GameManager.Team) -> void:
	_game_over_panel.visible = true
	var container: VBoxContainer = $GameOverPanel/MarginContainer/VBoxContainer
	var label: Label = $GameOverPanel/MarginContainer/VBoxContainer/ResultLabel
	if winner == GameManager.Team.PLAYER:
		label.text = "VICTORY"
		label.modulate = Color.GREEN
	else:
		label.text = "DEFEAT"
		label.modulate = Color.RED

	var stats: Label = Label.new()
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var total_seconds: int = int(GameManager.match_time)
	var minutes: int = total_seconds / 60
	var seconds: int = total_seconds % 60
	stats.text = "Time: %d:%02d\nUnits Trained: %d\nCoin Mined: %d" % [
		minutes,
		seconds,
		EconomyManager.get_units_trained(GameManager.Team.PLAYER),
		EconomyManager.get_coin_mined(GameManager.Team.PLAYER)
	]
	container.add_child(stats)
	container.move_child(stats, 1)


func _play_again() -> void:
	get_tree().reload_current_scene()
