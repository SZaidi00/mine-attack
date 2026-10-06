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
##   Brute red, Industrial brass).
class_name ArtStyle3D
extends RefCounted

enum Quality { POTATO, STANDARD, FANCY }

const PALETTE := {
	"snow": Color(0.93, 0.96, 0.98),
	"ice": GameManager.COLOR_ICE,
	"deep_ice": GameManager.COLOR_DEEP_ICE,
	"rock": Color(0.29, 0.31, 0.34),
	"rock_dark": Color(0.18, 0.19, 0.22),
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

## Faction identity accents (§2.2): Arcane violet, Brute red, Industrial brass.
const FACTION_ACCENTS := {
	"arcane": Color(0.55, 0.36, 0.96),
	"brute": Color(0.86, 0.15, 0.15),
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
static func get_material(color: Color, emission: Color = Color(0, 0, 0), emission_energy: float = 0.0, alpha: float = 1.0) -> StandardMaterial3D:
	var key := "%s|%s|%f|%f" % [color.to_html(), emission.to_html(), emission_energy, alpha]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = alpha
	_materials[key] = mat
	return mat


static func make_box(size: Vector3, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.set_material_override(get_material(color))
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
	mi.set_material_override(get_material(color))
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
	mi.set_material_override(get_material(color))
	return mi


## Team material for the body of a unit/structure: player blue / enemy red,
## darkened slightly so faction accents read on top.
static func team_color(team: int) -> Color:
	return GameManager.COLOR_PLAYER if team == GameManager.Team.PLAYER else GameManager.COLOR_ENEMY


## Faction accent for a team (§2.2): Arcane violet, Brute red, Industrial
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
