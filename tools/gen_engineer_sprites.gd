extends SceneTree

## One-off generator for the Engineer unit sprites and HUD icon (generated
## pixel art has precedent: the pigeon card icon in hud_menus.gd). The unit
## sprites match the existing 32x48 unit format (swordsman_player.png etc.);
## the icon matches the 16x16 HUD icon format (icon_miner.png etc.).
## Run: godot --headless --path . -s tools/gen_engineer_sprites.gd

const _SKIN: Color = Color(0.95, 0.78, 0.6)
const _STEEL: Color = Color(0.7, 0.72, 0.78)
const _BOOTS: Color = Color(0.16, 0.16, 0.2)
const _PLAYER_BODY: Color = Color(0.3, 0.5, 0.95)
const _ENEMY_BODY: Color = Color(0.88, 0.3, 0.24)
const _PLAYER_HAT: Color = Color(1.0, 0.82, 0.2)
const _ENEMY_HAT: Color = Color(0.95, 0.5, 0.15)


func _init() -> void:
	_make_unit_sprite("res://frost_mines_assets/units/engineer_player.png", _PLAYER_BODY, _PLAYER_HAT)
	_make_unit_sprite("res://frost_mines_assets/units/engineer_enemy.png", _ENEMY_BODY, _ENEMY_HAT)
	_make_icon("res://frost_mines_assets/icons/icon_engineer.png")
	print("engineer sprites generated")
	quit()


func _fill(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for px in range(x, x + w):
		for py in range(y, y + h):
			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				img.set_pixel(px, py, c)


## 32x48 engineer: hard hat + wrench silhouette (distinct from the miner's
## pickaxe), team-colored overalls.
func _make_unit_sprite(path: String, body: Color, hat: Color) -> void:
	var img: Image = Image.create(32, 48, false, Image.FORMAT_RGBA8)
	# Hard hat: dome plus a wider brim, with a darker ridge on top.
	_fill(img, 12, 6, 8, 2, hat.darkened(0.25))   # ridge
	_fill(img, 10, 8, 12, 5, hat)                  # dome
	_fill(img, 8, 13, 16, 2, hat.darkened(0.1))    # brim
	# Head.
	_fill(img, 11, 15, 10, 7, _SKIN)
	_fill(img, 13, 18, 2, 2, Color(0.1, 0.1, 0.12))  # eye
	_fill(img, 18, 18, 2, 2, Color(0.1, 0.1, 0.12))  # eye
	# Torso (overalls) with straps and a belt.
	_fill(img, 10, 22, 12, 13, body)
	_fill(img, 12, 22, 2, 8, body.darkened(0.3))   # strap
	_fill(img, 18, 22, 2, 8, body.darkened(0.3))   # strap
	_fill(img, 10, 30, 12, 2, _BOOTS)              # belt
	# Arms.
	_fill(img, 8, 23, 2, 9, body.darkened(0.15))
	_fill(img, 23, 23, 2, 9, body.darkened(0.15))
	_fill(img, 8, 32, 2, 2, _SKIN)                 # hand
	_fill(img, 23, 32, 2, 2, _SKIN)                # hand
	# Wrench in the right hand: open jaw on top, long handle.
	_fill(img, 25, 20, 4, 2, _STEEL)               # jaw top
	_fill(img, 28, 22, 2, 3, _STEEL)               # jaw side (open gap reads as a wrench)
	_fill(img, 25, 23, 2, 15, _STEEL.darkened(0.15))  # handle
	# Legs and boots.
	_fill(img, 11, 35, 4, 10, Color(0.2, 0.22, 0.3))
	_fill(img, 17, 35, 4, 10, Color(0.2, 0.22, 0.3))
	_fill(img, 10, 45, 6, 3, _BOOTS)
	_fill(img, 16, 45, 6, 3, _BOOTS)
	img.save_png(path)


## 16x16 HUD icon: hard hat above a small wrench, neutral colors (the train
## button is team-agnostic, like the other unit icons).
func _make_icon(path: String) -> void:
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	_fill(img, 6, 2, 4, 1, _PLAYER_HAT.darkened(0.25))  # ridge
	_fill(img, 5, 3, 6, 3, _PLAYER_HAT)                 # dome
	_fill(img, 3, 6, 10, 2, _PLAYER_HAT.darkened(0.1))  # brim
	_fill(img, 6, 8, 4, 3, _SKIN)                       # face
	# Wrench: diagonal handle with a jaw at the top-right.
	_fill(img, 10, 9, 2, 2, _STEEL)
	_fill(img, 8, 11, 2, 2, _STEEL.darkened(0.15))
	_fill(img, 6, 13, 2, 2, _STEEL.darkened(0.15))
	img.save_png(path)
