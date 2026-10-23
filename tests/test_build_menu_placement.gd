extends GutTest

# Build-menu placement flow: picking a blueprint card hides the tray so the
# confirming left-click reaches the world (a visible STOP-filtered tray would
# eat it), placement success/cancel keep the tray closed, and reopening the
# menu mid-placement cancels the armed ghost.

const PLAYER: int = 0

var _main: Node
var _hud: HUD


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_hud = _main.get_node("UI/HUD")


func after_all() -> void:
	# Free immediately, not queue_free(): a queued free would still be pending
	# when the next test script instantiates its own main.tscn.
	_main.free()


func before_each() -> void:
	EconomyManager.reset()
	GameManager.game_active = true
	EconomyManager.add_coin(PLAYER, 5000)
	var pc: PlayerController = _main.get_node("PlayerController")
	pc.cancel_build_mode()
	_hud._menus._close_build_menu()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _open_menu_and_press_card(kind: String) -> void:
	_hud._menus._toggle_build_menu()
	assert_true(_hud._build_menu.visible, "precondition: tray open")
	for card in _hud._menus._build_cards:
		if card.kind == kind:
			assert_false(card.button.disabled, "precondition: %s card is available" % kind)
			_hud._menus._on_build_card_pressed(card)
			return
	fail_test("build menu has no %s card" % kind)


func test_picking_a_card_hides_the_menu() -> void:
	var pc: PlayerController = _main.get_node("PlayerController")
	_open_menu_and_press_card("wall")
	assert_false(_hud._build_menu.visible, "tray hides while placing")
	assert_true(pc.is_build_mode_active(), "placement mode armed")
	pc.cancel_build_mode()


func test_successful_placement_keeps_the_menu_closed() -> void:
	var pc: PlayerController = _main.get_node("PlayerController")
	var grid: GridWorld = _main.get_node("World/GridWorld")
	_open_menu_and_press_card("wall")
	var placed: bool = pc._build_placement.try_place_structure("wall", grid.grid_to_world(Vector2i(-10, -2)))
	assert_true(placed, "placement succeeds on a valid cell")
	pc.cancel_build_mode()  # what _handle_input does after a successful click
	await _frames(3)
	assert_false(_hud._build_menu.visible, "tray stays closed after placement")
	assert_false(_hud._menus.is_menu_in_placement_mode(), "menu placement state cleared")


func test_cancel_keeps_the_menu_closed() -> void:
	var pc: PlayerController = _main.get_node("PlayerController")
	_open_menu_and_press_card("wall")
	pc.cancel_build_mode()  # right-click / Esc path
	await _frames(3)
	assert_false(_hud._build_menu.visible, "tray stays closed after cancel")
	assert_false(_hud._menus.is_menu_in_placement_mode(), "menu placement state cleared")


func test_reopening_menu_during_placement_cancels_ghost() -> void:
	var pc: PlayerController = _main.get_node("PlayerController")
	_open_menu_and_press_card("wall")
	assert_true(pc.is_build_mode_active(), "precondition: ghost armed")
	_hud._menus._toggle_build_menu()  # tray is hidden, so this reopens it
	assert_true(_hud._build_menu.visible, "tray reopens")
	assert_false(pc.is_build_mode_active(), "reopening the tray disarms the ghost")
	_hud._menus._close_build_menu()
