# Phase 01 — Snowstorm + Meteor Production Pass

## Goal

Replace the current flat radial event vignettes with the approved layered, surface-only weather presentations.

- **Snowstorm:** B · Ground Whiteout
- **Meteor shower:** B · Volcanic Siege

This phase is first because it delivers the most visible improvement and establishes the reusable surface-clipping pattern used by later UI work.

## Source References

- Snowstorm mockup: `../../02_approved_mockup/index.html`
- Snowstorm renderer: `../../02_approved_mockup/app.js`
- Meteor mockup: `../../02_approved_mockup/meteor.html`
- Meteor renderer: `../../02_approved_mockup/meteor.js`
- Current HUD/vignette code: `scripts/ui/hud.gd`
- Weather state: `scripts/autoload/weather_manager.gd`
- Project conventions: `../../01_reference/AGENTS.md`

## Current Problem

### Snowstorm

The existing snowstorm presentation is generated as a radial blue alpha vignette:

```gdscript
var alpha: float = clampf((d - 0.45) / 0.55, 0.0, 1.0) ** 1.6 * 0.55
img.set_pixel(x, y, Color(0.08, 0.16, 0.42, alpha))
```

It reads as a blue bubble around the perimeter rather than active weather.

### Volcano / meteor shower

The existing volcano presentation is similarly radial and red:

```gdscript
var alpha: float = clampf((d - 0.45) / 0.55, 0.0, 1.0) ** 1.6 * 0.5
img.set_pixel(x, y, Color(0.65, 0.15, 0.05, alpha))
```

It lacks meteors, ember movement, plume, and surface heat.

## Surface-Only Mask

All weather and volcanic rendering must be clipped to the above-ground region.

```gdscript
const SURFACE_TOP: float = 0.095
const SURFACE_BOTTOM: float = 0.382
```

At draw time:

```gdscript
var viewport_size: Vector2 = get_viewport_rect().size
var top: float = viewport_size.y * SURFACE_TOP
var bottom: float = viewport_size.y * SURFACE_BOTTOM
```

Recommended implementation options:

1. A dedicated `Control` overlay with clipping enabled.
2. A custom `_draw()` renderer that only draws inside the surface rectangle.
3. A `CanvasLayer` overlay with child controls clipped to the surface band.

Do not draw particles or fog below `SURFACE_BOTTOM`.

## Snowstorm Target

### Approved settings

| Setting | Value |
|---|---:|
| Storm intensity | 100% |
| Wind direction | +16 |
| Visibility loss | 100% |
| Shelter pocket size | 23% |
| Fog edge softness | 100% |
| Ground accumulation | Off |
| Snow streaks | On |

### Renderer values

| Parameter | Value |
|---|---:|
| Fog color | `rgb(226, 240, 247)` |
| Base fog alpha | `0.34` |
| Fog blobs | `42` |
| Horizontal cloud banks | `12` |
| Snow particles | `360` |
| Ground alpha | `0` |
| Streak bias | `1.25` |

### Required layers

Draw in this order:

1. **Cold surface grade** — subtle blue/cyan screen tint clipped to the surface.
2. **Base fog wash** — low-alpha irregular white-blue fog.
3. **Cloud banks** — wide, soft horizontal ellipses drifting with the wind.
4. **Fog blobs** — smaller irregular density patches to break up symmetry.
5. **Snow streaks** — directional angled streaks, not just circular dots.
6. **Shelter cutouts** — soft holes around lanterns using subtractive/destination-out behavior or equivalent alpha shaping.
7. **Warm shelter glow** — soft amber glow inside the cutout so shelters do not become black holes.

### Cloud-bank behavior

The fog must move horizontally like clouds. The mockup uses 12 large cloud banks with:

- Normalized `x` drift.
- Small vertical sine bob.
- Wide horizontal radius.
- Narrow vertical radius.
- Wind-scaled movement speed.
- Alpha pulsing.

Port this concept to Godot with deterministic particle structs or lightweight nodes. Avoid per-pixel texture generation every frame.

### Shelter behavior

Shelter pockets should remain legible at 100% visibility loss. Avoid full-strength cutouts. The approved mockup uses softened cutout stops equivalent to:

- Center cutout opacity: approximately `0.74`
- Mid cutout opacity: approximately `0.38`
- Warm glow center: approximately `rgba(251, 191, 36, 0.28)`
- Warm glow mid: approximately `rgba(251, 191, 36, 0.12)`

The result should reveal shelter and lantern warmth without exposing harsh black sky.

### Snow behavior

- Snowflakes respawn above the surface band.
- Flakes disappear at the terrain line instead of continuing underground.
- Wind affects horizontal velocity and streak angle.
- Streak length and opacity vary by flake depth.

## Meteor Shower Target

### Approved settings

| Setting | Value |
|---|---:|
| Meteor density | 100 |
| Ember glow | 100 |
| Impact marker strength | 0 |
| Crater plume | 45 |
| Heat color grade | 68 |

### Renderer values

| Parameter | Value |
|---|---:|
| Meteor particles | 82 |
| Ember particles | 220 |
| Impact zone alpha | 0 |
| Meteor reset cutoff | `0.395` normalized Y |
| Ember respawn band | `0.375–0.395` normalized Y |

### Required layers

Draw in this order:

1. **Surface heat grade** — warm red/orange grading clipped to the surface.
2. **Crater plume** — smoke and glow rising from the volcano mouth.
3. **Meteor trails** — diagonal streaks with brighter heads and fading tails.
4. **Impact flashes** — short-lived flashes where meteors reach ground level.
5. **Ember field** — rising orange sparks concentrated near the surface.
6. **No impact rings** — impact marker strength is locked at 0.

### Meteor behavior

- Meteors travel diagonally across the surface.
- Reset after they pass the surface impact line.
- Do not draw meteor bodies or trails underground.
- Keep trails bright but avoid covering units and structures.

### Ember behavior

- Embers rise from near the ground line.
- Use variable size, drift, flicker, and alpha.
- Respawn just above the surface band.
- Do not allow ember motion to continue visibly into underground space.

## Suggested Godot Implementation

Create a dedicated overlay script if `hud.gd` becomes too large:

```text
scripts/ui/weather_overlay_renderer.gd
```

Suggested responsibilities:

```gdscript
class_name WeatherOverlayRenderer
extends Control

func set_snowstorm_active(active: bool, intensity: float = 1.0) -> void
func set_volcano_active(active: bool, intensity: float = 1.0) -> void
func set_lantern_shelters(shelters: Array[Rect2]) -> void
func _process(delta: float) -> void
func _draw() -> void
```

Use existing `WeatherManager` signals to toggle modes rather than polling every frame where practical.

## Performance Notes

- Prefer a bounded pool of particles: about 360 snowflakes and 220 embers.
- Precompute particle structs at overlay initialization.
- Use `_draw()` batching or a small number of `CPUParticles2D` nodes.
- Do not generate a full-screen `ImageTexture` every frame.
- Keep blend operations moderate for `gl_compatibility`.
- Ensure web export remains smooth.

## Integration Steps

1. Add constants for the surface mask and approved event parameters.
2. Create the overlay control in `scenes/ui/hud.tscn` or instantiate it from `hud.gd`.
3. Wire `WeatherManager` snowstorm and volcano signals to overlay mode changes.
4. Replace the existing generated snowstorm vignette.
5. Replace the existing generated volcano vignette.
6. Add cloud-bank, fog-blob, snow-streak, meteor, ember, and plume drawing.
7. Feed lantern shelter positions into the snowstorm renderer.
8. Verify pause behavior freezes or appropriately slows the effect.
9. Verify restart/quit resets overlay state.
10. Test at logical 1920×1080 and project 2560×1440.

## Acceptance Criteria

- Snowstorm no longer looks like a symmetric blue perimeter bubble.
- Snowstorm has irregular fog density, horizontal cloud drift, directional snow, and soft shelter pockets.
- Snowstorm renders only above ground.
- Snow accumulation is absent at the ground line.
- Meteor shower has dense meteors, rising embers, warm heat grade, and crater plume.
- Meteor shower renders only above ground.
- No impact-marker rings appear.
- Gameplay units, structures, HP bars, and warning banners remain readable.
- Existing warning countdown behavior remains intact.
- No new dependencies are added.
- Existing GUT tests pass.
