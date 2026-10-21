## Phase 2 art direction (roadmap/3d-conversion/phase-2-art-pass.md §2.1).
##
## Shared style tokens for the 3D presentation: the Frostpunk-adjacent
## palette, faction accent colors, cached flat-shaded materials, low-poly
## primitive builders, and the global quality preset (Potato / Standard /
## Fancy) that every 3D system consults for particle counts, shadows and
## model detail. Pure presentation — never touches the sim.
##
## Style rules (see roadmap/3d-conversion/style-guide.md):
## - Flat-shaded stylized low-poly; roughness 1, no textures.
## - A unit must read by silhouette at max zoom-out.
## - Cold blues/greys on the surface, warm ore oranges underground,
##   sickly greens for necromancy, faction accents (Arcane violet,
##   Brute ember, Industrial brass).
##
## 3D rework phase 4 (roadmap/3d-rework/phase-4): a luminance ladder —
## terrain darkest, structures mid, units brightest. Team colors are
## value-lifted 3D variants of the 2D palette and route through
## team_color(), which mirrors the colorblind swap (enemy scarlet ->
## ember orange) live from SettingsManager. Entity materials carry a
## subtle sky-side rim so dark units separate from dark ground even on
## Potato (where no shadows/SSAO exist).
class_name ArtStyle3D
extends RefCounted

enum Quality { POTATO, STANDARD, FANCY }

const PALETTE := {
	"snow": Color(0.96, 0.98, 1.0),
	"ice": GameManager.COLOR_ICE,
	"deep_ice": GameManager.COLOR_DEEP_ICE,
	"rock": Color(0.24, 0.25, 0.29),
	"rock_dark": Color(0.14, 0.15, 0.18),
	"wood": Color(0.36, 0.26, 0.16),
	"wood_dark": Color(0.24, 0.17, 0.11),
	"steel": GameManager.COLOR_STEEL,
	"rust": GameManager.COLOR_RUST,
	"ore_bright": Color(0.94, 0.7, 0.22),
	"coal": Color(0.12, 0.12, 0.14),
	"cloth": Color(0.32, 0.34, 0.38),
	"cloth_dark": Color(0.2, 0.21, 0.25),
	"skin": Color(0.78, 0.62, 0.5),
	"lava": Color(0.91, 0.22, 0.05),
	"magma": Color(0.16, 0.12, 0.11),
	"necro": Color(0.62, 1.0, 0.62),
	"lamp_warm": Color(1.0, 0.82, 0.45),
}

## 3D rework phase 4: value-lifted team colors (the 2D palette's #3B82F6 /
## #B91C1C sat too close to the terrain value range). The colorblind enemy
## mirrors UIThemeTokens' red -> orange swap, lifted the same way.
const TEAM_PLAYER := Color("#4A90F5")
const TEAM_ENEMY := Color("#E03232")
const TEAM_ENEMY_COLORBLIND := Color("#E88A2E")

## Entity rim light (unit/structure materials, not terrain): a subtle
## sky-side edge so bodies detach from the ground at every quality tier.
const RIM_STRENGTH: float = 0.5
const RIM_TINT: float = 0.6

## Faction identity accents (§2.2): Arcane violet, Brute ember, Industrial
## brass. Phase 4 moved Brute off red — it collided with the enemy team
## scarlet; ember orange fits "raw power" and the lava world instead.
const FACTION_ACCENTS := {
	"arcane": Color(0.55, 0.36, 0.96),
	"brute": Color(0.93, 0.42, 0.11),
	"industrial": Color(0.79, 0.64, 0.15),
}

const UNDEAD_TINT := Color(0.62, 1.0, 0.62)

static var quality: Quality = Quality.FANCY

static var _materials: Dictionary = {}


## Web builds default to Standard; desktop to Fancy.
static func auto_detect_quality() -> Quality:
	if OS.has_feature("web"):
		return Quality.STANDARD
	return Quality.FANCY


static func apply_quality(q: Quality) -> void:
	quality = q


## Shadows exist only on Fancy.
static func shadows_enabled() -> bool:
	return quality == Quality.FANCY


## Directional shadow frustum depth: covers the visible board (max-zoom
## viewport span) rather than the whole map, so the shadow pass stays cheap.
static func shadow_distance() -> float:
	return 40.0


## 3D rework phase 3: bloom on Standard and up — only true emissives
## (energy > glow threshold) halo; Potato stays flat to protect fps.
static func glow_enabled() -> bool:
	return quality != Quality.POTATO


## Screen-space ambient occlusion, Fancy only (gentlest depth cueing tier).
static func ssao_enabled() -> bool:
	return quality == Quality.FANCY


## Atmospheric depth fog is nearly free, so it runs on every preset — the
## fog-of-war darkening stays a separate, unmistakably darker read.
static func fog_enabled() -> bool:
	return true


## Particle emission count multiplier per preset.
static func particle_mult() -> float:
	match quality:
		Quality.POTATO:
			return 0.35
		Quality.STANDARD:
			return 0.7
	return 1.0


## False on Potato: small decorative details (drifts, trims, rungs) hide.
static func detail_enabled() -> bool:
	return quality != Quality.POTATO


## Cached flat-shaded StandardMaterial3D. Emissive materials get their own
## cache slot; vertex colors are NOT used here (callers assign albedo).
## rim adds the sky-side entity rim (RIM_STRENGTH/RIM_TINT) — unit and
## structure bodies only; terrain, glow, and UI-ish materials stay rimless.
static func get_material(color: Color, emission: Color = Color(0, 0, 0), emission_energy: float = 0.0, alpha: float = 1.0, rim: bool = false) -> StandardMaterial3D:
	var key := "%s|%s|%f|%f|%d" % [color.to_html(), emission.to_html(), emission_energy, alpha, int(rim)]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	if rim:
		mat.rim_enabled = true
		mat.rim = RIM_STRENGTH
		mat.rim_tint = RIM_TINT
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = alpha
	_materials[key] = mat
	return mat


## Entity primitive builders: every make_* material gets the rim pass, so
## unit/structure silhouettes separate from the darker terrain (phase 4).
static func make_box(size: Vector3, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.set_material_override(get_material(color, Color(0, 0, 0), 0.0, 1.0, true))
	return mi


## Low-poly cone/pyramid (flat-shaded by the few radial sides).
static func make_cone(radius: float, height: float, color: Color, sides := 4, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mi.mesh = mesh
	mi.position = pos
	mi.set_material_override(get_material(color, Color(0, 0, 0), 0.0, 1.0, true))
	return mi


static func make_cylinder(radius: float, height: float, color: Color, sides := 6, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mi.mesh = mesh
	mi.position = pos
	mi.set_material_override(get_material(color, Color(0, 0, 0), 0.0, 1.0, true))
	return mi


## Team material color for the body of a unit/structure (phase 4): the
## value-lifted 3D variants TEAM_PLAYER / TEAM_ENEMY. Mirrors the colorblind
## accessibility swap (UIThemeTokens.apply_colorblind_palette): with
## colorblind mode on, the enemy reads as ember orange instead of scarlet.
## Live re-skin on toggle is handled by EntityProxies3D.rebuild_all().
static func team_color(team: int) -> Color:
	if team == GameManager.Team.PLAYER:
		return TEAM_PLAYER
	if SettingsManager.get_colorblind():
		return TEAM_ENEMY_COLORBLIND
	return TEAM_ENEMY


## Faction accent for a team (§2.2): Arcane violet, Brute ember, Industrial
## brass. Falls back to the plain team color when no faction is picked
## (tests, main menu) or the enemy faction is not identified yet — callers
## gating on FactionManager.is_faction_identified() pass allow_hidden=false
## to get the neutral "???" grey instead.
static func faction_accent_color(team: int, allow_hidden: bool = true) -> Color:
	if not allow_hidden and team == GameManager.Team.ENEMY and not FactionManager.is_faction_identified(GameManager.Team.ENEMY):
		return Color(0.42, 0.43, 0.47)
	var faction: Resource = FactionManager.get_faction(team)
	if faction != null:
		var fid: String = str(faction.get("faction_id"))
		if FACTION_ACCENTS.has(fid):
			return FACTION_ACCENTS[fid]
	return team_color(team)


## Deterministic per-cell hash in [0,1) — sculpted terrain heights, drift
## placement etc. must be stable across rebuilds and independent of RNG state.
static func cell_hash(pos: Vector2i, salt: int = 0) -> float:
	var h := pos.x * 374761393 + pos.y * 668265263 + salt * 1442695041
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0x1000000)
