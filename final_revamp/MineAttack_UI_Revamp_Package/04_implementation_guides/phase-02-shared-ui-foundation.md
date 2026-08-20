# Phase 02 — Shared UI Foundation

## Goal

Create the reusable visual foundation for the revamp before implementing individual screens. This phase turns the approved “frosted steel console” language into shared colors, spacing, panel styles, button states, progress styles, and helper functions.

## Source References

- Design context: `../../01_reference/ui_revamp_context.md`
- Project conventions: `../../01_reference/AGENTS.md`
- Design tokens: `../../03_design_tokens/design_tokens.json`
- Shared mockup styles: `../../02_approved_mockup/styles.css`
- Main-menu mockup: `../../02_approved_mockup/main-menu.html`
- HUD mockup: `../../02_approved_mockup/hud.html`

## Current Problem

The main menu uses textured UI assets, but most in-game UI uses flat code-generated `StyleBoxFlat` panels. The result is a visual split between the menu and HUD. Research, build, pause, game-over, warning, and queue panels also vary in treatment.

## Visual Foundation

The shared UI language should combine:

- Dark blue-grey steel panels.
- Subtle frost rim highlights.
- Inset shadows and recessed regions.
- Rivets or small industrial corner details.
- Gold accents for economy, upgrades, and selected states.
- Blue accents for player interaction and hover states.
- Red/orange accents for danger and emergency warnings.
- Readable off-white text with dim secondary text.

Keep the treatment restrained enough for RTS readability.

## Required Tokens

Use the values in `03_design_tokens/design_tokens.json` as the source of truth.

### Team and faction colors

Do not change these values:

```text
Player       #3B82F6
Enemy        #B91C1C
Arcane       #AF84FB
Brute        #DF6B6B
Industrial   #FBBF24
```

### Core UI colors

```text
Panel background        rgba(12, 17, 27, 0.94)
Panel border            rgba(255, 255, 255, 0.08)
Button normal           #1A2434
Button hover            #253650
Button pressed          #111927
Button disabled         #151C29
Button hover border     #4A86C8
Tab active              #1F3A5C
Tab active border       #4A86C8
Upgrade background      #272210
Upgrade border          #8A6D1F
Gold text               #FBBF24
Primary text            #E2E8F0
Dim text                #94A3B8
```

### Warning colors

```text
Snowstorm warning       #FF4D3F
Lava warning            #FF7F26
Volcano warning         #FF5926
```

## Recommended Code Structure

Keep the existing UI scripts, but centralize repeated styling.

Possible addition:

```text
scripts/ui/ui_theme_tokens.gd
```

Suggested responsibilities:

- Named color constants.
- Shared corner radius/border width/content margin constants.
- Factory methods for standard panel `StyleBoxFlat`.
- Factory methods for primary, secondary, upgrade, danger, and disabled buttons.
- Factory methods for gold, blue, red, and green progress styles.
- Helpers for warning banner styles.
- Optional texture-based style loading if new PNGs are created later.

If this remains small, it can be folded into `hud_styling.gd` instead of adding a new file.

## Shared Components to Standardize

### 1. Primary panel

Used by main menu, pause menu, build menu, research panel, and game-over panel.

Visual properties:

- Semi-opaque dark background.
- Subtle light top edge.
- Dark lower edge.
- Thin outer border.
- Small corner radius.
- Optional rivets/corner plates.

### 2. Recessed panel

Used inside HUD modules, training queue, build tray, and research detail rail.

Visual properties:

- Darker than outer panel.
- Slight inset shadow.
- Low-contrast border.

### 3. Primary button

Used for Play, Next, Select, Start Research, and major confirmations.

Visual properties:

- Gold accent.
- Strong hover feedback.
- Pressed/inset state.
- Disabled state.

### 4. Secondary button

Used for standard commands and menu actions.

Visual properties:

- Steel blue normal state.
- Blue hover border.
- Pressed dark state.

### 5. Danger button

Used for Kill/disband, clear queue, cancel research, and destructive actions.

Visual properties:

- Muted red base.
- Brighter red hover.
- Clear disabled state.

### 6. Progress bars

Required variants:

- Gold: research/upgrades.
- Blue: training queue.
- Green: friendly HP.
- Red: enemy HP/danger.

Keep bars readable at small sizes and compatible with current HP bar textures if they remain in use.

### 7. Warning banners

Required variants:

- Snowstorm warning.
- Lava warning.
- Volcano warning.
- Faction identified popup.

Banners should feel like industrial emergency strips without covering too much of the battlefield.

## Texture Strategy

The immediate implementation can continue using code-generated `StyleBoxFlat` styles. If texture production follows, create 9-slice PNGs according to Section 9.1 of `ui_revamp_context.md`.

Recommended future files:

```text
frost_mines_assets/ui/panel_metal.png
frost_mines_assets/ui/panel_metal_dark.png
frost_mines_assets/ui/button_primary_normal.png
frost_mines_assets/ui/button_primary_hover.png
frost_mines_assets/ui/button_primary_pressed.png
frost_mines_assets/ui/button_secondary_normal.png
frost_mines_assets/ui/button_secondary_hover.png
frost_mines_assets/ui/button_secondary_pressed.png
frost_mines_assets/ui/button_upgrade_normal.png
frost_mines_assets/ui/button_upgrade_hover.png
frost_mines_assets/ui/button_upgrade_pressed.png
frost_mines_assets/ui/button_danger_normal.png
frost_mines_assets/ui/tab_inactive.png
frost_mines_assets/ui/tab_active.png
frost_mines_assets/ui/progress_bar_bg.png
frost_mines_assets/ui/progress_bar_fill_gold.png
frost_mines_assets/ui/progress_bar_fill_blue.png
frost_mines_assets/ui/progress_bar_fill_red.png
frost_mines_assets/ui/progress_bar_fill_green.png
```

All production assets must be PNG and 9-slice friendly.

## Spacing and Sizing

Use the current logical resolution of 1920×1080.

Recommended spacing:

- Outer panel padding: 12–16 px.
- Dense HUD module padding: 8–10 px.
- Button horizontal padding: 10–14 px.
- Icon/text gap: 6–8 px.
- Card gaps: 10–16 px.
- Small icons: 18–24 px.
- Faction card icons: 64 px minimum, 128 px source preferred.
- Warning banner height: 48–64 px.

## Accessibility and Readability

- Preserve high text contrast over busy scenes.
- Do not use faction color alone to communicate state; pair it with labels/icons.
- Keep disabled states visibly muted but legible enough to understand.
- Ensure hover, pressed, focused, selected, locked, active, completed, and disabled states are distinct.
- Do not block gameplay clicks with decorative overlays; use `MOUSE_FILTER_IGNORE` where needed.

## Integration Steps

1. Review `hud_styling.gd` and identify repeated panel/button creation.
2. Add shared color constants or a token helper.
3. Create standard style factories for panels, buttons, tabs, progress bars, and warning banners.
4. Refactor one existing HUD panel to prove the shared styles.
5. Refactor main-menu panel/button styling to use the same tokens.
6. Keep all existing gameplay layout anchors and input behavior unchanged.
7. Add optional texture loading hooks only if final PNGs are available.
8. Validate at 1920×1080 and 2560×1440.

## Acceptance Criteria

- One shared token source exists for all revamp screens.
- Panel, button, tab, progress, and warning styles are no longer one-off duplicates.
- Main menu and HUD visibly belong to the same design system.
- Existing click behavior, shortcuts, and gameplay state remain unchanged.
- Styles remain readable over surface and underground views.
- No new dependencies or fonts are introduced.
- Existing GUT tests pass.
