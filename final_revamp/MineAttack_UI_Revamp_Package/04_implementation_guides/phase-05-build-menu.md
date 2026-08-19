# Phase 05 — Build Menu Option A · Blueprint Tray

## Goal

Implement the approved **A · Blueprint Tray** build menu. The menu should feel like a compact industrial tray of construction blueprints while preserving the current build placement flow.

## Source References

- Build-menu mockup: `../../02_approved_mockup/build-menu.html`
- Shared styles: `../../02_approved_mockup/styles.css`
- Variant metadata: `../../02_approved_mockup/variants.js`
- Design tokens: `../../03_design_tokens/design_tokens.json`
- Current build menu code: `scripts/ui/hud_menus.gd`
- Existing build assets: `../../02_approved_mockup/assets/icons/`
- Existing prop sprites: `../../02_approved_mockup/assets/props/`

## Current Problem

The current build menu is functional but visually plain and does not strongly communicate blueprint-like structure, cost, availability, or selection state.

## Scope

Cover all existing build options:

- Lantern
- Mine Lantern
- Tower
- Wall
- Trap
- Pigeon

Preserve:

- Existing costs.
- Existing count/max rules.
- Existing affordability logic.
- Existing placement ghost and validation behavior.
- Existing build-mode entry and exit behavior.

## Approved Layout

The menu should present options as compact blueprint cards inside a metal tray.

### Required card content

Each card should show:

1. Build icon or prop sprite.
2. Name.
3. Cost.
4. Current count / max count where applicable.
5. Availability state.
6. Selected state while build placement is active.

### Card states

Required states:

- **Available** — normal steel blueprint card.
- **Hovered** — blue/gold edge highlight.
- **Selected** — stronger gold or blue accent.
- **Unaffordable** — muted cost and dimmed icon.
- **At max count** — visibly locked or capped.
- **Locked / unavailable** — greyed with reduced contrast.

## Visual Treatment

Use the shared Phase 02 foundation:

- Outer tray: dark frosted steel.
- Cards: recessed blue-grey panels.
- Cost: gold text with coin icon.
- Count/max: dim text unless capped.
- Available hover: `#4A86C8` border.
- Selected: gold or blue accent, but not both so strongly that state becomes unclear.
- Disabled: low-contrast background and icon modulation.

The cards should read as blueprints rather than generic inventory slots. Subtle grid lines, corner ticks, or blueprint-paper accents may be used if they do not obscure the icons.

## Layout Requirements

The current build menu is approximately 720×420 at logical resolution. Preserve a similar compact footprint.

Recommended arrangement:

- Header with title and close hint.
- Three-column grid.
- Two rows for six options.
- Footer hint or selected placement instruction.
- Clear close/cancel behavior.

Do not let the tray become so large that it hides more battlefield than necessary.

## Icons

Use existing production icons and prop sprites first.

Available copied references:

```text
assets/icons/button_build_lantern.png
assets/icons/button_build_tower.png
assets/icons/button_build_wall.png
assets/props/lantern_t1.png
assets/props/lantern_underground.png
assets/props/tower_player.png
assets/props/wall_player.png
assets/props/mine_entry.png
```

If a dedicated trap or pigeon icon is missing, use the existing gameplay sprite or a simple code-drawn placeholder consistent with the current game. Do not introduce external icon packs.

## Interaction Requirements

- Clicking an available card enters build mode exactly as current behavior does.
- Clicking unavailable cards does nothing or provides the existing rejection feedback.
- Build menu closes or remains open according to existing expected flow; do not change it unless necessary.
- Placement ghost remains unchanged.
- Escape/right-click cancellation behavior remains unchanged.
- Menu controls must remain clickable; decorative layers must not intercept input.

## Implementation Steps

1. Review the build-menu code in `scripts/ui/hud_menus.gd`.
2. Replace flat panel construction with the shared Phase 02 tray style.
3. Create a reusable build-card control or factory method.
4. Populate cards with icon, name, cost, and count/max.
5. Add hover, selected, unaffordable, capped, and locked styles.
6. Wire card clicks to the existing build selection callbacks.
7. Keep the placement ghost and validation flow unchanged.
8. Test all six options.
9. Test affordability changes as coin increases/decreases.
10. Test max-count state.
11. Test menu behavior during pause and at different game speeds.
12. Test at 1920×1080 and 2560×1440.

## Readability Requirements

- Cost must be readable immediately.
- Capped and unaffordable states must be distinct.
- Selected card must remain obvious while placement mode is active.
- Card icons must remain crisp with pixel-art scaling.
- Text must not overflow at small card sizes.

## Acceptance Criteria

- Build menu visibly matches the approved Blueprint Tray direction.
- All six build options are present.
- Existing costs, limits, and placement behavior are unchanged.
- Available, hover, selected, unaffordable, capped, and locked states are visually distinct.
- Menu remains readable over surface and underground views.
- No external dependencies or non-PNG assets are introduced.
- Existing GUT tests pass.
