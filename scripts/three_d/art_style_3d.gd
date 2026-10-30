## Shared art tokens for the 3D presentation. R2 of the visual revamp
## (roadmap/3d-visual-revamp/01-art-direction.md) grades the world onto cold
## indigo-slate and blue-white snow, with warmth reserved for practical fire.
## Primitive rigs keep their silhouettes and sky-side rim until later model
## phases; team colors and the live colorblind swap remain unchanged.
##
## Bloom is restrained to warm emissives. Cool team/faction magic remains
## emissive for readability but is clamped below the HDR bloom threshold.
class_name ArtStyle3D
extends RefCounted

enum Quality { POTATO, STANDARD, FANCY }

const PALETTE := {
	"night": Color("#232C3A"),
	"fog_void": Color("#10141C"),
	"snow": Color("#DDE8F2"),
	"snow_shadow": Color("#8FA3B8"),
	"ice": Color("#8FA3B8"),
	"deep_ice": Color("#232C3A"),
	"rock": Color("#3A3F4A"),
	"rock_dark": Color("#1C2029"),
	"wood": Color("#5C4632"),
	"wood_dark": Color("#40352C"),
	"steel": Color("#4E5A66"),
	"brass": Color("#C9A227"),
	"rust": Color("#C45C26"),
	"ore_bright": Color("#F0B23C"),
	"coal": Color("#1C2029"),
	"cloth": Color("#536171"),
	"cloth_dark": Color("#2B3442"),
	"skin": Color("#C4A88F"),
	"lava": Color("#E8380D"),
	"magma": Color("#29252A"),
	"necro": Color("#9EDF9E"),
	"lamp_warm": Color("#FFB85C"),
	"witch_light": Color("#A8E6C8"),
	"storm_gloom": Color("#B9C6D4"),
}

const TEAM_PLAYER := Color("#4A90F5")
const TEAM_ENEMY := Color("#E03232")
const TEAM_ENEMY_COLORBLIND := Color("#E88A2E")

const RIM_STRENGTH: float = 0.5
const RIM_TINT: float = 0.6
const MATERIAL_ROUGHNESS: float = 0.92
const BLOOM_HDR_THRESHOLD: float = 1.4
const BLOOM_INTENSITY: float = 0.35
const BLOOM_STRENGTH: float = 0.65
const COOL_EMISSION_CAP: float = 0.65

const FACTION_ACCENTS := {
	"arcane": Color("#8C5CF6"),
	"brute": Color("#EE6B1C"),
	"industrial": Color("#C9A227"),
}

const UNDEAD_TINT := Color("#9EDF9E")

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


## 3D render scale per preset (applied to the root viewport's scaling_3d).
## Potato renders at 3/4 resolution — on weak GPUs this buys more than every
## other Potato cut combined. Standard stays native on desktop but drops to
## 0.85 on web, where fill-rate is the usual bottleneck. Fancy is native.
static func render_scale() -> float:
	match quality:
		Quality.POTATO:
			return 0.75
		Quality.STANDARD:
			return 0.85 if OS.has_feature("web") else 1.0
	return 1.0


## MSAA 2x only on desktop Fancy — on gl_compatibility/web the multisample
## cost outweighs the edge cleanup.
static func msaa_enabled() -> bool:
	return quality == Quality.FANCY and not OS.has_feature("web")


## Resolve a settings-panel value ("auto" | "potato" | "standard" | "fancy")
## to a preset; "auto" falls back to the platform detect.
static func quality_from_string(value: String) -> Quality:
	match value:
		"potato":
			return Quality.POTATO
		"standard":
			return Quality.STANDARD
		"fancy":
			return Quality.FANCY
	return auto_detect_quality()


static func emission_energy(color: Color, requested: float) -> float:
	var warm := color.r > color.b and color.r >= color.g
	return requested if warm else minf(requested, COOL_EMISSION_CAP)


static func apply_emission(mat: StandardMaterial3D, color: Color, requested: float) -> void:
	mat.emission_enabled = requested > 0.0
	mat.emission = color
	mat.emission_energy_multiplier = emission_energy(color, requested)


## Cached high-roughness material. Emissive materials get their own cache
## slot; vertex colors are NOT used here (callers assign albedo). Entity rim
## is opt-in so terrain, glow, and UI-like materials stay rimless.
static func get_material(color: Color, emission: Color = Color(0, 0, 0), emission_energy_requested: float = 0.0, alpha: float = 1.0, rim: bool = false) -> StandardMaterial3D:
	var key := "%s|%s|%f|%f|%d" % [color.to_html(), emission.to_html(), emission_energy_requested, alpha, int(rim)]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = MATERIAL_ROUGHNESS
	mat.metallic = 0.0
	if rim:
		mat.rim_enabled = true
		mat.rim = RIM_STRENGTH
		mat.rim_tint = RIM_TINT
	if emission_energy_requested > 0.0:
		apply_emission(mat, emission, emission_energy_requested)
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
