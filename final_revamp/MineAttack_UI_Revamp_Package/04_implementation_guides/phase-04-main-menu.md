# Phase 04 — Main Menu Option A · Command Console

## Goal

Implement the approved **A · Command Console** main-menu direction and enrich the background so it no longer feels plain. Preserve the existing menu flow while upgrading the atmosphere, panel treatment, buttons, and faction-select presentation.

## Source References

- Main-menu mockup: `../../02_approved_mockup/main-menu.html`
- Shared styles: `../../02_approved_mockup/styles.css`
- Variant metadata: `../../02_approved_mockup/variants.js`
- Design tokens: `../../03_design_tokens/design_tokens.json`
- Current menu code: `scripts/ui/main_menu.gd`
- Current main scene config: `../../01_reference/project.godot`

## Current Flow to Preserve

The current flow remains:

```text
Title card → Difficulty select → Faction select → Play
```

Existing controls to preserve:

- Title: `MINEATTACK`
- Subtitle: `FROST MINES`
- Difficulty dropdown: Easy / Normal / Hard / Nightmare / Godly
- Resolution dropdown on desktop
- Next / Play button
- Quit button
- Faction select cards
- Selected faction glow
- Faction-colored background particles

## Approved Direction

The menu should look like a command console standing in a frozen volcanic battlefield. The background should have more depth and motion, but the menu controls must remain the focus.

Required background improvements:

1. Broad animated cloud drift.
2. Cool aurora or ice-light shimmer.
3. Distant blue player-base glow on the left.
4. Distant red enemy-base glow on the right.
5. Subtle warm volcanic glow near the horizon.
6. Soft vignette to keep edges dark.
7. Existing falling snow retained or refined.

Avoid a centered vertical beam or any effect that looks artificial. The glows should be broad and atmospheric.

## Main Card

Apply the shared frosted steel panel style.

### Required hierarchy

- Small industrial header or top edge accent.
- `MINEATTACK` title.
- `FROST MINES` subtitle in gold.
- Difficulty selector.
- Resolution selector on desktop only.
- Primary `Next` / `Play` button.
- Secondary `Quit` button.
- Short hint/footer line.

### Visual treatment

- Dark semi-opaque metal panel.
- Frosted top edge or rim highlight.
- Subtle inner shadow.
- Gold accent for primary action.
- Steel-blue hover state for secondary controls.
- Text must remain readable over the animated background.

## Faction Select

Preserve the current three-card layout and gameplay colors:

- Arcane: `#AF84FB`
- Brute: `#DF6B6B`
- Industrial: `#FBBF24`

### Card requirements

- Distinct faction heraldry.
- Name and one-line description.
- Three bullet highlights.
- Select button.
- Clear selected state.
- Consistent card height and spacing.

### Selected state

- Gold border and glow remain acceptable.
- The selected card should feel active without changing faction hue.
- Keep unselected cards dimmer but still readable.

### Hidden enemy heraldry

If the main menu or HUD requires an unknown-faction visual, use a greyed mystery icon rather than plain `???` where possible. Do not change the existing hidden-faction gameplay behavior.

## Background Implementation

The mockup uses layered CSS gradients and animation. In Godot, implement the same idea with one or more of:

- Layered `TextureRect` backgrounds.
- `ColorRect` overlays with gradient textures.
- Lightweight `CPUParticles2D` for snow/embers/sparks.
- Procedural `Control._draw()` for soft atmospheric bands.
- Existing `surface_sky.png` and `surface_ground.png`.

Do not add a heavy shader dependency. The target renderer is `gl_compatibility`.

### Suggested layer order

1. Existing night sky.
2. Distant volcanic warmth.
3. Cloud bank layer.
4. Blue and red base glows.
5. Ground strip.
6. Falling snow.
7. Vignette.
8. Menu card.

## Faction Particle Tinting

Preserve or refine existing faction particles:

- Arcane: purple sparks, approximately `rgba(196, 133, 253, 0.55)`.
- Brute: red embers, approximately `rgba(247, 112, 112, 0.55)`.
- Industrial: yellow steam, approximately `rgba(250, 202, 54, 0.45)`.

Keep particle counts modest for web performance.

## Implementation Steps

1. Review `scripts/ui/main_menu.gd` and identify current background, panel, button, and faction-card creation.
2. Apply shared panel/button tokens from Phase 02.
3. Add atmospheric background layers.
4. Add cloud drift and subtle shimmer using lightweight animation.
5. Keep existing difficulty and resolution logic unchanged.
6. Update faction-card layout to avoid large empty lower regions.
7. Push each faction card’s Select button to the bottom for equal card structure.
8. Verify selected-card glow and faction particle tint.
9. Test all difficulties.
10. Test Play, Quit, resolution selection, and faction selection.
11. Test at logical 1920×1080 and project 2560×1440.

## Readability Requirements

- The title must remain the strongest element.
- The background cannot compete with dropdowns or buttons.
- Animated layers must be slow and subtle.
- No background element should resemble a warning state during normal menu use.
- Faction cards must be readable without relying solely on color.

## Performance Requirements

- Keep particle and overlay counts low.
- Avoid generating full-screen textures every frame.
- Use static textures or cached gradients where possible.
- Maintain compatibility with web export.

## Acceptance Criteria

- Main menu clearly matches the approved Command Console direction.
- Background has visible atmosphere and no longer feels plain.
- No unnatural vertical beam or hard gradient seam appears.
- Existing menu flow and settings behavior are unchanged.
- Faction cards have balanced content and clear selected states.
- Faction colors are preserved.
- Menu remains readable over all background animation states.
- Existing tests pass.
