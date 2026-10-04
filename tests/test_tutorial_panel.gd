extends GutTest

## Smoke tests for the main-menu tutorial panel: it builds, pages render with
## content, and Back/Next navigation walks the full deck and wraps up correctly.

const TutorialPanel = preload("res://scripts/ui/tutorial_panel.gd")

var _panel: Control = null


func before_each() -> void:
	_panel = TutorialPanel.create()
	add_child_autofree(_panel)


func test_panel_starts_hidden() -> void:
	assert_false(_panel.visible, "panel should start hidden")


func test_first_page_renders() -> void:
	var labels: Array = _find_labels()
	var has_welcome: bool = false
	for label: Label in labels:
		if label.text == "WELCOME TO MINEATTACK":
			has_welcome = true
	assert_true(has_welcome, "first page title should be rendered")
	assert_true(_find_button("Finish") == null, "Finish should not appear on page 1")


func test_next_walks_all_pages_and_finish_closes() -> void:
	_panel.visible = true
	var seen_titles: Dictionary = {}
	var nav: Button = _find_nav_button()
	assert_not_null(nav, "Next button should exist on page 1")
	while nav != null and _panel.visible:
		seen_titles[_page_title()] = true
		nav.pressed.emit()
		await get_tree().process_frame
		nav = _find_nav_button()
	var expected: Array = [
		"WELCOME TO MINEATTACK", "ECONOMY & MINERS", "UNITS", "STRUCTURES",
		"RESEARCH", "WEATHER & THE MOUNTAIN", "CONTROLS & TIPS",
	]
	for title: String in expected:
		assert_true(seen_titles.has(title), "should have visited page: %s" % title)
	assert_false(_panel.visible, "Finish should hide the panel")


## The footer nav button reads "Next" until the last page, where it reads
## "Finish" and closes the panel instead of advancing.
func _find_nav_button() -> Button:
	var found: Array = []
	_collect(_panel, found, Button)
	for btn: Button in found:
		if btn.text == "Next" or btn.text == "Finish":
			return btn
	return null


func test_back_disabled_on_first_page() -> void:
	var back: Button = _find_button("Back")
	assert_not_null(back)
	assert_true(back.disabled, "Back should be disabled on the first page")


func _page_title() -> String:
	# The title Label is added first, so it is the first label a DFS finds.
	var labels: Array = _find_labels()
	return labels[0].text if labels.size() > 0 else ""


func _find_labels() -> Array:
	var found: Array = []
	_collect(_panel, found, Label)
	return found


func _find_button(text: String) -> Button:
	var found: Array = []
	_collect(_panel, found, Button)
	for btn: Button in found:
		if btn.text == text:
			return btn
	return null


func _collect(node: Node, out: Array, type) -> void:
	if is_instance_of(node, type):
		out.append(node)
	for child in node.get_children():
		_collect(child, out, type)
