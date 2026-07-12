extends CanvasLayer

@onready var _coin_label: Label = $TopBar/HBoxContainer/CoinLabel
@onready var _pop_label: Label = $TopBar/HBoxContainer/PopLabel
@onready var _miner_level_label: Label = $TopBar/HBoxContainer/MinerLevelLabel
@onready var _queue_label: Label = $TopBar/HBoxContainer/QueueLabel
@onready var _selection_label: Label = $TopBar/HBoxContainer/SelectionLabel
@onready var _game_over_panel: PanelContainer = $GameOverPanel


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
	$GameOverPanel/MarginContainer/VBoxContainer/QuitButton.pressed.connect(func(): get_tree().quit())

	EconomyManager.coin_changed.connect(_on_economy_changed)
	EconomyManager.population_changed.connect(_on_economy_changed)
	EconomyManager.miner_level_changed.connect(_on_economy_changed)

	var player_building: Node2D = _get_player_building()
	if player_building:
		player_building.queue_changed.connect(_on_queue_changed)

	GameManager.game_over.connect(_on_game_over)
	_on_economy_changed(GameManager.Team.PLAYER)


func _process(_delta: float) -> void:
	var pc: PlayerController = _get_player_controller()
	if pc:
		_selection_label.text = "Selected: %d" % pc.get_selected_units().size()


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


func _on_economy_changed(team: GameManager.Team) -> void:
	if team != GameManager.Team.PLAYER:
		return
	_coin_label.text = "Coin: %d" % EconomyManager.get_coin(team)
	_pop_label.text = "Pop: %d/%d" % [EconomyManager.get_population(team), GameManager.POPULATION_CAP]
	_miner_level_label.text = "Miner Lv: %d" % EconomyManager.get_miner_level(team)


func _on_queue_changed(_entries: Array) -> void:
	var building: Node2D = _get_player_building()
	if building:
		var queue: Array = building.call("get_queue")
		var names: Array = queue.map(func(e): return e.id)
		_queue_label.text = "Queue: " + ", ".join(names)


func _get_player_controller() -> PlayerController:
	return get_node_or_null("/root/Main/PlayerController")


func _get_player_building() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == GameManager.Team.PLAYER:
			return b
	return null


func _on_game_over(winner: GameManager.Team) -> void:
	_game_over_panel.visible = true
	var label: Label = $GameOverPanel/MarginContainer/VBoxContainer/ResultLabel
	if winner == GameManager.Team.PLAYER:
		label.text = "VICTORY"
		label.modulate = Color.GREEN
	else:
		label.text = "DEFEAT"
		label.modulate = Color.RED
