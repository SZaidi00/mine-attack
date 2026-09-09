extends SceneTree

## One-off generator for the Crawler unit sprites and HUD icon (generated
## pixel art has precedent: gen_engineer_sprites.gd and the pigeon card icon
## in hud_menus.gd). The crawler is a low quadruped burrower — wide shell,
## four legs, big digging claws — deliberately distinct from the biped unit
## silhouettes. The unit sprites match the existing 32x48 unit format; the
## icon matches the 16x16 HUD icon format.
## Run: godot --headless --path . -s tools/gen_crawler_sprites.gd

const _PLAYER_SHELL: Color = Color(0.3, 0.5, 0.95)
const _ENEMY_SHELL: Color = Color(0.88, 0.3, 0.24)
const _BELLY: Color = Color(0.55, 0.5, 0.45)
const _CLAW: Color = Color(0.82, 0.8, 0.72)
const _LEG: Color = Color(0.16, 0.16, 0.2)
const _EYE: Color = Color(1.0, 0.85, 0.3)


func _init() -> void:
	_make_unit_sprite("res://frost_mines_assets/units/crawler_player.png", _PLAYER_SHELL)
	_make_unit_sprite("res://frost_mines_assets/units/crawler_enemy.png", _ENEMY_SHELL)
	_make_icon("res://frost_mines_assets/icons/icon_crawler.png")
	print("crawler sprites generated")
	quit()


func _fill(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for px in range(x, x + w):
		for py in range(y, y + h):
			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				img.set_pixel(px, py, c)


## 32x48 crawler (faces right): a low-slung burrowing quadruped — domed shell,
## segmented back ridges, shovel claws up front, stubby tail behind.
func _make_unit_sprite(path: String, shell: Color) -> void:
	var img: Image = Image.create(32, 48, false, Image.FORMAT_RGBA8)
	# Tail: tapered stub pointing left.
	_fill(img, 3, 30, 3, 2, shell.darkened(0.35))
	_fill(img, 2, 31, 1, 1, shell.darkened(0.35))
	# Shell: wide low dome (rows 22-33), darker rim at the belly line.
	_fill(img, 8, 24, 16, 9, shell)
	_fill(img, 6, 27, 20, 6, shell)
	_fill(img, 6, 33, 20, 2, shell.darkened(0.3))
	# Back ridges: segmented plates across the dome.
	_fill(img, 11, 22, 3, 3, shell.lightened(0.15))
	_fill(img, 16, 22, 3, 3, shell.lightened(0.15))
	_fill(img, 21, 23, 2, 2, shell.lightened(0.15))
	# Head: protrudes right and slightly down, with a snout and glowing eye.
	_fill(img, 24, 27, 5, 5, shell.darkened(0.15))
	_fill(img, 28, 30, 3, 3, _BELLY)               # snout
	_fill(img, 25, 28, 2, 2, _EYE)                 # eye
	# Digging claws: two big shovel blades under the head, lighter than the shell.
	_fill(img, 27, 34, 4, 3, _CLAW)                # front claw blade
	_fill(img, 29, 37, 3, 4, _CLAW.darkened(0.15)) # front claw tip
	_fill(img, 22, 35, 4, 2, _CLAW.darkened(0.25)) # rear claw blade
	# Legs: four stubby legs with dark feet.
	_fill(img, 8, 35, 3, 8, _LEG)
	_fill(img, 14, 35, 3, 8, _LEG)
	_fill(img, 8, 43, 4, 2, _LEG.darkened(0.3))
	_fill(img, 14, 43, 4, 2, _LEG.darkened(0.3))
	img.save_png(path)


## 16x16 HUD icon: side-profile shell + claw, neutral-ish team blue (the train
## button is team-agnostic, like the other unit icons).
func _make_icon(path: String) -> void:
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	_fill(img, 4, 6, 8, 5, _PLAYER_SHELL)          # shell
	_fill(img, 3, 8, 10, 3, _PLAYER_SHELL)         # shell skirt
	_fill(img, 4, 11, 9, 1, _PLAYER_SHELL.darkened(0.3))  # rim
	_fill(img, 6, 5, 2, 2, _PLAYER_SHELL.lightened(0.15)) # ridge
	_fill(img, 9, 5, 2, 2, _PLAYER_SHELL.lightened(0.15)) # ridge
	_fill(img, 12, 8, 2, 2, _PLAYER_SHELL.darkened(0.15)) # head
	_fill(img, 12, 8, 1, 1, _EYE)                  # eye
	_fill(img, 12, 12, 3, 2, _CLAW)                # claw blade
	_fill(img, 14, 13, 1, 2, _CLAW.darkened(0.15)) # claw tip
	_fill(img, 5, 12, 2, 3, _LEG)                  # leg
	_fill(img, 9, 12, 2, 3, _LEG)                  # leg
	img.save_png(path)
