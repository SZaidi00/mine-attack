extends GutTest

# HUD feedback fixes: the training-queue panel scrolls instead of overflowing
# the screen, the build menu's pigeon card shows a generated pixel icon, the
# sentry-tower placement ghost shows a range indicator matching the tower's
# (research-adjusted) attack range, and research completions pop a transient
# toast naming the finished tech.

const PLAYER: int = 0
const ENEMY: int = 1

var _main: Node
var _hud: CanvasLayer


func before_all() -> void:
	seed(12345)
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	_hud = _main.get_node("UI/HUD")


func after_all() -> void:
	# Free immediately, not queue_free(): a queued free would still be pending
	# when the next test script instantiates its own main.tscn.
	ResearchManager.reset()
	EconomyManager.reset()
	_main.free()


func before_each() -> void:
	# Autoload state persists across tests — start every test clean.
	ResearchManager.reset()
	EconomyManager.reset()
	GameManager.game_active = true
	# Toasts linger for seconds after their test; clear them so counts are exact.
	for toast in _hud._toast_container.get_children():
		toast.free()


# ─── Training queue scrolling ───

func test_queue_list_is_inside_a_scroll_container() -> void:
	var panel: PanelContainer = _hud.get_node("QueuePanel")
	assert_not_null(panel._queued_container, "queue panel exposes its rows container")
	assert_true(panel._queued_container.get_parent() is ScrollContainer,
		"queued rows sit in a ScrollContainer so long queues scroll instead of overflowing")
	var scroll: ScrollContainer = panel._queued_container.get_parent()
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
		"only vertical scrolling")


# ─── Pigeon build-card icon ───

func test_pigeon_build_card_has_a_texture_icon() -> void:
	var pigeon_card = null
	for card in _hud._menus._build_cards:
		if card.kind == "pigeon":
			pigeon_card = card
			break
	assert_not_null(pigeon_card, "build menu has a pigeon card")
	assert_not_null(pigeon_card.icon_rect, "pigeon card uses a texture icon, not a glyph")
	assert_not_null(pigeon_card.icon_rect.texture, "pigeon icon texture is generated")
	assert_eq(pigeon_card.icon_rect.texture.get_width(), 42, "icon scaled to card icon size")


# ─── Tower placement range indicator ───

func test_tower_ghost_shows_attack_range_indicator() -> void:
	var pc: PlayerController = _main.get_node("PlayerController")
	pc.start_build_placement("tower")
	assert_not_null(pc._build_ghost)
	var indicator: Node2D = _find_range_indicator(pc._build_ghost)
	assert_not_null(indicator, "tower ghost includes a range indicator")
	var expected: float = Constants.TOWER_RANGE_CELLS * GridWorld.CELL_SIZE
	assert_almost_eq(indicator.get("radius"), expected, 0.01, "indicator matches base tower range")
	pc.cancel_build_mode()


func test_tower_ghost_range_includes_surface_war_bonus() -> void:
	ResearchManager._levels[PLAYER]["surface_war"] = 1
	var pc: PlayerController = _main.get_node("PlayerController")
	pc.start_build_placement("tower")
	var indicator: Node2D = _find_range_indicator(pc._build_ghost)
	assert_not_null(indicator)
	var expected: float = Constants.TOWER_RANGE_CELLS * Constants.SURFACE_WAR_TOWER_RANGE_MULT * GridWorld.CELL_SIZE
	assert_almost_eq(indicator.get("radius"), expected, 0.01, "indicator matches researched tower range")
	pc.cancel_build_mode()


func test_wall_ghost_has_no_range_indicator() -> void:
	var pc: PlayerController = _main.get_node("PlayerController")
	pc.start_build_placement("wall")
	assert_null(_find_range_indicator(pc._build_ghost), "walls have no radius to preview")
	pc.cancel_build_mode()


func _find_range_indicator(ghost: Node2D) -> Node2D:
	for child in ghost.get_children():
		if child.get("radius") != null:
			return child
	return null


# ─── Research completion toasts ───

func _toast_texts() -> Array[String]:
	var texts: Array[String] = []
	for toast in _hud._toast_container.get_children():
		_collect_labels(toast, texts)
	return texts


func _collect_labels(node: Node, texts: Array[String]) -> void:
	for child in node.get_children():
		if child is Label:
			texts.append(child.text)
		_collect_labels(child, texts)


func test_player_research_completion_shows_toast() -> void:
	ResearchManager._levels[PLAYER]["deep_delve"] = 1
	ResearchManager.research_completed.emit(PLAYER, "deep_delve")
	var texts: Array[String] = _toast_texts()
	assert_eq(texts.size(), 2, "toast has an eyebrow caption and a title")
	assert_has(texts, "RESEARCH COMPLETE", "eyebrow caption")
	assert_has(texts, "Deep Delve", "toast names the finished tech")


func test_toasts_stack_top_left_below_the_top_bar() -> void:
	assert_eq(_hud._toast_container.anchor_left, 0.0, "left edge")
	assert_eq(_hud._toast_container.anchor_top, 0.0, "top edge")
	assert_true(_hud._toast_container.position.y >= 100.0, "below the top bar")


func test_enemy_research_completion_shows_no_toast() -> void:
	ResearchManager._levels[ENEMY]["deep_delve"] = 1
	ResearchManager.research_completed.emit(ENEMY, "deep_delve")
	assert_eq(_toast_texts().size(), 0, "enemy research does not toast the player")


func test_toast_stack_is_capped() -> void:
	for i in 6:
		_hud.show_toast("toast %d" % i)
	var live: int = 0
	for toast in _hud._toast_container.get_children():
		if not toast.is_queued_for_deletion():
			live += 1
	assert_eq(live, _hud._TOAST_MAX_VISIBLE, "oldest toasts are dropped when the stack is full")
	var texts: Array[String] = _toast_texts()
	assert_has(texts, "toast 5", "newest toast is kept")
