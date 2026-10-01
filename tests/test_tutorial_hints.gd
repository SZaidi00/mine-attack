extends GutTest

# TutorialHints: contextual cards appear when their condition fires, only one
# at a time, and dismissing marks the hint seen in SettingsManager.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _hints: Control


func before_all() -> void:
	seed(12345)
	GameManager.set_map_seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	await wait_seconds(0.6)
	_hints = _main.get_node("UI/HUD/TutorialHints")
	SettingsManager.reset_tutorial_seen()
	SettingsManager.set_show_tutorial(true)


func after_all() -> void:
	_main.free()
	GameManager.clear_map_seed()
	SettingsManager.reset_tutorial_seen()
	SettingsManager.set_show_tutorial(true)


func before_each() -> void:
	EconomyManager.reset()
	SettingsManager.reset_tutorial_seen()
	GameManager.game_active = true
	# Clear any card a previous test left active (without marking it seen).
	if is_instance_valid(_hints._current_card):
		_hints._current_card.queue_free()
	_hints._current_card = null
	_hints._current_id = ""


## Marks every hint seen except `target_id` so the poll can only pick it.
func _mark_all_seen_except(target_id: String) -> void:
	for hint: Dictionary in _hints._hints:
		if hint.id != target_id:
			SettingsManager.mark_tutorial_seen(hint.id)


func test_hint_card_appears_for_triggered_condition() -> void:
	_mark_all_seen_except("first_miner")
	EconomyManager.train_unit(PLAYER)
	_hints.poll_hints()
	assert_true(_hints.has_active_hint(), "first_miner card should show after training a unit")
	var card: PanelContainer = _hints._current_card
	assert_not_null(card)
	assert_eq(_hints._current_id, "first_miner")
	var title: Label = card.find_children("*", "Label", true, false)[1]
	assert_eq(title.text, "Miners fuel everything")


func test_dismiss_marks_hint_seen_and_frees_card() -> void:
	_mark_all_seen_except("first_deposit")
	EconomyManager.mine_coin(PLAYER, 25)
	_hints.poll_hints()
	assert_true(_hints.has_active_hint())
	_hints.dismiss_current()
	assert_false(_hints.has_active_hint())
	assert_true("first_deposit" in SettingsManager.get_tutorial_seen())
	# A fresh poll must not re-show the seen hint.
	_hints.poll_hints()
	assert_false(_hints.has_active_hint())


func test_no_card_when_tutorial_disabled() -> void:
	_mark_all_seen_except("first_miner")
	EconomyManager.train_unit(PLAYER)
	SettingsManager.set_show_tutorial(false)
	_hints.poll_hints()
	assert_false(_hints.has_active_hint())
	SettingsManager.set_show_tutorial(true)


func test_no_card_when_game_inactive() -> void:
	_mark_all_seen_except("first_miner")
	EconomyManager.train_unit(PLAYER)
	GameManager.game_active = false
	_hints.poll_hints()
	assert_false(_hints.has_active_hint())
	GameManager.game_active = true


func test_only_one_card_at_a_time() -> void:
	# Two conditions true (units trained + coin mined); only the first unseen
	# hint in table order may show.
	_mark_all_seen_except("first_deposit")
	EconomyManager.train_unit(PLAYER)
	EconomyManager.mine_coin(PLAYER, 10)
	_hints.poll_hints()
	assert_true(_hints.has_active_hint())
	assert_eq(_hints._current_id, "first_deposit")
	_hints.dismiss_current()


func test_miner_upgrade_hint_triggers_when_affordable() -> void:
	_mark_all_seen_except("miner_upgrade")
	# Reset leaves level 0; ensure the player can afford the upgrade.
	var cost: int = EconomyManager.get_miner_upgrade_cost(PLAYER)
	if cost < 0:
		pass  # Already maxed (not at level 0); the assert below will fail loudly.
	else:
		EconomyManager.add_coin(PLAYER, maxi(0, cost - EconomyManager.get_coin(PLAYER)))
	_hints.poll_hints()
	assert_true(_hints.has_active_hint(), "miner_upgrade hint should show when affordable at level 0")
	assert_eq(_hints._current_id, "miner_upgrade")


func test_base_damaged_hint_triggers_below_60_pct() -> void:
	_mark_all_seen_except("base_damaged")
	var building: Node = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.get("team") == PLAYER:
			building = b
	assert_not_null(building, "player building must exist")
	building.take_damage(int(building.max_hp * 0.5))
	_hints.poll_hints()
	assert_true(_hints.has_active_hint(), "base_damaged hint should show under 60% HP")
	assert_eq(_hints._current_id, "base_damaged")
	_hints.dismiss_current()
