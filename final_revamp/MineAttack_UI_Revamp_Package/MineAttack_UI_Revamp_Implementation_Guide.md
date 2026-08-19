# MineAttack UI Revamp — Master Implementation Guide

This package is the implementation handoff for the approved MineAttack UI revamp. It contains the interactive approved mockup, reference captures, reusable game assets, design tokens, and seven phase-specific implementation guides.

## 1. Approved Direction

The approved visual language is a **frosted steel command console**: stamped metal, frost edges, rivets, worn paint, warning stripes, emergency lights, and glowing readouts. It should feel like industrial equipment from the same frozen volcanic world as the battlefield.

Preserve the existing game’s readability and faction/team identity. The redesign is UI, menu, and event presentation only; do not redesign units or terrain tiles.

### Approved selections

| Area | Approved option | Notes |
|---|---|---|
| Snowstorm | **B · Ground Whiteout** | 100% intensity, +16 wind, 100% visibility loss, 23% shelter pockets, 100% fog softness, no ground accumulation. Fog should drift horizontally like cloud banks. Surface only. |
| Meteor shower | **B · Volcanic Siege** | 100% meteor density, 100% ember glow, 0% impact markers, 45% crater plume, 68% heat grade. Surface only. |
| Main menu | **A · Command Console** | Enriched animated background rather than a plain static backdrop. |
| HUD | **A · Frosted Steel** | Training queue redesigned into an active production module. |
| Build menu | **A · Blueprint Tray** | Compact blueprint-card build menu. |
| Research menu | **B+C · Doctrine Deck** | Doctrine-map branch structure plus card/detail/queue treatment. |

## 2. Package Layout

```text
MineAttack_UI_Revamp_Package/
├── MineAttack_UI_Revamp_Implementation_Guide.md
├── 01_reference/
│   ├── ui_revamp_context.md
│   ├── AGENTS.md
│   └── project.godot
├── 02_approved_mockup/
│   ├── index.html                  # Snowstorm mockup
│   ├── meteor.html                 # Meteor shower mockup
│   ├── main-menu.html              # Main-menu mockup
│   ├── hud.html                    # HUD mockup
│   ├── build-menu.html             # Build-menu mockup
│   ├── research-menu.html          # Research-menu mockup
│   ├── styles.css                  # Shared mockup styling
│   ├── app.js                      # Snowstorm renderer
│   ├── meteor.js                   # Meteor renderer
│   ├── variants.js                 # Shared screen metadata
│   └── assets/                     # Reference captures and copied game assets
├── 03_design_tokens/
│   └── design_tokens.json
└── 04_implementation_guides/
    ├── phase-01-weather-overlays.md
    ├── phase-02-shared-ui-foundation.md
    ├── phase-03-hud.md
    ├── phase-04-main-menu.md
    ├── phase-05-build-menu.md
    ├── phase-06-research-menu.md
    └── phase-07-final-qa.md
```

## 3. Production Constraints

- Engine: **Godot 4.7 standard build**, not .NET.
- Renderer: **`gl_compatibility`**.
- Language: **GDScript**, with static typing preferred.
- Targets: **Web, macOS, Windows**.
- Logical UI: **1920×1080**.
- Project viewport: **2560×1440**.
- Stretch: `canvas_items`, `expand`, scale `1.333333`.
- Production assets must be **PNG only**.
- Do **not** introduce new external dependencies or package managers.
- Do **not** add fonts unless they are open-licensed and web-safe; the current plan uses Godot’s default font.
- Panels and buttons should remain **9-slice friendly** when converted to `StyleBoxTexture`.
- Keep pixel-art scaling crisp.
- Preserve all gameplay-critical team and faction colors.
- Do not redesign units, terrain tiles, or gameplay balance unless explicitly requested.

## 4. Critical Color Tokens

| Purpose | Value |
|---|---|
| Player / ally | `#3B82F6` |
| Enemy | `#B91C1C` |
| Arcane | `#AF84FB` |
| Brute | `#DF6B6B` |
| Industrial | `#FBBF24` |
| Panel background | `rgba(12, 17, 27, 0.94)` |
| Panel border | `rgba(255, 255, 255, 0.08)` |
| Button normal | `#1A2434` |
| Button hover | `#253650` |
| Button pressed | `#111927` |
| Hover border | `#4A86C8` |
| Upgrade border | `#8A6D1F` |
| Gold text | `#FBBF24` |
| Primary text | `#E2E8F0` |
| Dim text | `#94A3B8` |
| Snowstorm warning | `#FF4D3F` |
| Lava warning | `#FF7F26` |
| Volcano warning | `#FF5926` |

A machine-readable version is included at `03_design_tokens/design_tokens.json`.

## 5. Surface-Only Weather Mask

Both approved weather/event directions must render **only above ground**. Use the normalized surface band:

```gdscript
const SURFACE_TOP: float = 0.095
const SURFACE_BOTTOM: float = 0.382
```

Convert those values into viewport coordinates at draw time:

```gdscript
var top: float = viewport_size.y * SURFACE_TOP
var bottom: float = viewport_size.y * SURFACE_BOTTOM
```

All fog, cloud banks, snow streaks, meteors, embers, crater plume, and heat grading must be clipped to `top...bottom`. Nothing should bleed into the underground portion of the screen.

## 6. Snowstorm Production Target

The current snowstorm vignette is a flat radial blue bubble. Replace it with a layered procedural effect:

1. Cold surface color grade.
2. Low-opacity base fog.
3. Large, horizontally moving cloud banks.
4. Smaller irregular fog blobs.
5. Directional snow streaks.
6. Soft-edged lantern shelter cutouts.
7. Warm lantern glow inside the shelter pockets.
8. No ground-line snow accumulation.

Use `02_approved_mockup/index.html` and `02_approved_mockup/app.js` as the visual source of truth.

### Locked values

- Storm intensity: `100`
- Wind direction: `+16`
- Visibility loss: `100`
- Shelter pocket size: `23%`
- Fog edge softness: `100%`
- Ground accumulation: `off`
- Fog color: `rgb(226, 240, 247)`
- Cloud banks: `12`
- Fog blobs: `42`
- Snow particles: `360`

## 7. Meteor Shower Production Target

Replace the simple red radial vignette with a surface-clipped volcanic siege effect:

1. Warm heat grade across the surface sky.
2. Smoke/glow rising from the volcano mouth.
3. Diagonal meteor trails.
4. Ground impact flashes.
5. Rising ember field.
6. No impact-marker rings.

Use `02_approved_mockup/meteor.html` and `02_approved_mockup/meteor.js` as the visual source of truth.

### Locked values

- Meteor density: `100`
- Ember glow: `100`
- Impact marker strength: `0`
- Crater plume: `45`
- Heat color grade: `68`
- Meteor particles: `82`
- Ember particles: `220`

## 8. Screen Implementation Targets

### Main menu — A · Command Console

- Strengthen the background with animated cloud drift, aurora light, distant base glows, volcanic warmth, and subtle ice shimmer.
- Retain the existing menu flow and code-driven scene structure where practical.
- Upgrade the title card, buttons, faction cards, and selected-state glow to share the frosted steel language.
- Do not make the background so busy that the title, difficulty controls, faction cards, or buttons become hard to read.

Reference: `main-menu.html`.

### HUD — A · Frosted Steel

- Apply the shared metal/frost treatment to the top bar, bottom bar, buttons, HP readouts, tabs, warning banners, and side module.
- Keep all gameplay readouts glanceable.
- Replace the old sparse “Queue Empty” treatment with a production queue module:
  - Header with active count and capacity.
  - Large active item row.
  - Icon, unit name, ready time, percent, and progress bar.
  - Compact rows for queued units.
  - Locked/ghost state.
  - Pause and clear actions.

Reference: `hud.html`.

### Build menu — A · Blueprint Tray

- Present build choices as blueprint cards in a compact industrial tray.
- Use icons, cost, count/max, and disabled states consistently.
- Keep placement flow unchanged.

Reference: `build-menu.html`.

### Research menu — B+C · Doctrine Deck

- Preserve the branch-map clarity of option B.
- Add the card-level detail, state badges, icons, descriptions, and queue controls from option C.
- Show mutually exclusive choices and locked paths clearly.
- Include a persistent detail rail for cost, timing, exclusion, and progress.
- Keep branch colors aligned with Arcane, Brute, and Industrial.

Reference: `research-menu.html`.

## 9. Implementation Order

Implement in the following order. Each phase has a dedicated guide in `04_implementation_guides/`.

1. **Snowstorm + meteor production pass** — highest visual impact and establishes surface clipping.
2. **Shared UI foundation** — tokens, helpers, panel/button/progress styling, reusable scene patterns.
3. **HUD Option A** — apply foundation and add the new training queue.
4. **Main menu Option A** — background atmosphere and console treatment.
5. **Build menu Option A** — blueprint tray and card states.
6. **Research menu B+C** — Doctrine Deck hybrid.
7. **Final QA** — performance, readability, scaling, exports, and regression testing.

## 10. Recommended Godot Structure

Keep the existing scene and script architecture. Add UI-specific helpers only where they reduce duplication.

Suggested additions or modifications:

```text
scripts/ui/
├── hud.gd
├── hud_styling.gd
├── hud_menus.gd
├── hud_updates.gd
├── training_queue_panel.gd
├── research_panel.gd
├── main_menu.gd
├── ui_theme_tokens.gd          # Optional shared color/size constants
├── weather_overlay_renderer.gd # Optional procedural overlay renderer
└── doctrine_deck_panel.gd      # Optional if research panel becomes too large
```

If new panel textures are produced later, place them under:

```text
frost_mines_assets/ui/
```

If production icon upgrades are produced later, place them under:

```text
frost_mines_assets/icons/
```

## 11. Current Code Touch Points

- Main menu: `scripts/ui/main_menu.gd`
- HUD shell: `scripts/ui/hud.gd`
- HUD styles: `scripts/ui/hud_styling.gd`
- Pause/build menus: `scripts/ui/hud_menus.gd`
- HUD synchronization: `scripts/ui/hud_updates.gd`
- Training queue: `scripts/ui/training_queue_panel.gd`
- Research panel: `scripts/ui/research_panel.gd`
- Weather state: `scripts/autoload/weather_manager.gd`
- Palette/game state: `scripts/autoload/game_manager.gd`
- Research data/state: `scripts/autoload/research_manager.gd`

Current snowstorm vignette generation lives in `scripts/ui/hud.gd`; current volcano vignette generation also lives there. These are the first code areas to replace with the approved layered overlays.

## 12. Acceptance Criteria

The revamp is complete when all of the following are true:

- Snowstorm no longer reads as a symmetric blue edge bubble.
- Snowstorm fog moves horizontally with visible cloud-like banks.
- Lantern shelter pockets are readable but do not become black holes.
- Meteor shower has dense meteors, embers, heat grading, and crater plume.
- Neither snowstorm nor meteor effects render underground.
- Main menu background has visible atmosphere while preserving menu readability.
- HUD uses a consistent frosted steel treatment.
- Training queue shows active production, queued items, progress, and actions.
- Build menu uses the approved Blueprint Tray.
- Research menu uses the approved Doctrine Deck hybrid.
- Team and faction colors remain unchanged.
- All UI remains readable at 1920×1080 and scales correctly at 2560×1440.
- Web, macOS, and Windows exports still run.
- Existing GUT tests still pass.

## 13. Local Mockup Preview

The approved mockup is plain HTML/CSS/JavaScript. From the `02_approved_mockup/` directory:

```bash
python3 -m http.server 8080
```

Then open:

```text
http://127.0.0.1:8080/index.html
```

Use the navigation at the top to switch between snowstorm, meteor, main menu, HUD, build menu, and research menu.

## 14. Final Definition of Done

The production pass should not be treated as a visual approximation of the mockup. It should reproduce the approved structure, hierarchy, motion behavior, clipping, and readability while fitting Godot’s `Control`, `StyleBoxFlat`, `StyleBoxTexture`, procedural drawing, and performance constraints.
