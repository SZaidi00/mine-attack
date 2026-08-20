# Phase 03 — HUD Option A · Frosted Steel

## Goal

Implement the approved **A · Frosted Steel** HUD, including the redesigned training queue. The HUD should feel like an industrial command console while remaining fast to read during RTS play.

## Source References

- HUD mockup: `../../02_approved_mockup/hud.html`
- Shared styles: `../../02_approved_mockup/styles.css`
- Variant metadata: `../../02_approved_mockup/variants.js`
- Design tokens: `../../03_design_tokens/design_tokens.json`
- Current HUD shell: `scripts/ui/hud.gd`
- Current HUD styles: `scripts/ui/hud_styling.gd`
- Current HUD updates: `scripts/ui/hud_updates.gd`
- Current build/pause menus: `scripts/ui/hud_menus.gd`
- Current training queue: `scripts/ui/training_queue_panel.gd`

## Current Problem

The current HUD is functional but visually flat and assembled from one-off code styles. The training queue is especially sparse and does not communicate production status at the same level as the approved concept.

## Scope

Apply the shared frosted steel foundation to:

- Full-width top bar.
- Resource and faction readouts.
- Unit-count breakdown.
- Building HP readouts.
- Surface/Underground tabs.
- Pause and game-speed controls.
- Selection readout.
- Bottom command bar.
- Unit training buttons.
- Unit upgrade buttons.
- Stance buttons.
- Kill/Research/Build actions.
- Warning banners.
- Redesigned training queue panel.

Do not change input shortcuts, command behavior, unit costs, train times, or gameplay balance.

## Layout Requirements

### Top bar

Preserve the existing information hierarchy:

- Left: coin, miner level, player faction.
- Center: total unit count and unit breakdown.
- Right: player building HP, enemy building HP, enemy faction state.
- Below: Surface/Underground, Pause, speed controls, and selection readout.

Visual changes:

- Use a recessed steel backing.
- Group related readouts into compact modules.
- Use small icons and short labels.
- Use gold for economy, blue for player state, red for enemy state, and dim grey for unknown/scouted-limited information.

### Bottom bar

Preserve the existing command hierarchy:

- Upgrade Miner.
- Unit training.
- Fighter upgrades.
- Stances.
- Kill.
- Research.
- Build.

Visual changes:

- Use a consistent command-button grid.
- Make cost and train time visible without crowding.
- Add clear affordable/unaffordable and selected states.
- Use upgrade styling for upgrade buttons and secondary steel styling for standard commands.

### Warning banners

- Snowstorm: red emergency strip with snowstorm icon.
- Lava: orange emergency strip with lava icon.
- Volcano: red-orange emergency strip with lava/volcano icon.
- Banners must remain readable over the new weather overlays.
- Decorative backing must not intercept world clicks.

## Training Queue Redesign

The approved queue is a right-side production module, not a passive list.

### Required structure

1. **Header**
   - Label: `Training queue`
   - Status: number currently in production
   - Capacity: `current/max`

2. **Active item**
   - Unit icon.
   - Unit name.
   - Ready countdown.
   - Percent complete.
   - Progress bar.

3. **Queued list**
   - Compact row per queued unit.
   - Icon.
   - Name.
   - Remaining time or queued position.

4. **Locked/ghost state**
   - Show locked or unavailable entries without making them look clickable.

5. **Actions**
   - Pause button.
   - Clear button.

### Mockup structure

The approved mockup uses this hierarchy:

```text
Training queue
2 in production                                      2/5

[icon] Swordsman                                     62%
       Ready in 5.0s
       [progress bar]

[icon] Miner                                         3.0s
[icon] Archer                                        6.0s
[icon] Wizard                                        Locked

Pause                                                Clear
```

### Functional requirements

- Update every frame or on queue events without rebuilding the whole panel unnecessarily.
- Show active progress accurately.
- Show queued items in order.
- Support cancellation if the existing queue supports it.
- Reflect pause state.
- Show empty state cleanly when nothing is training.
- Keep panel width compact enough not to cover excessive battlefield space.
- Use blue progress fill for training.

## Visual Details

Use the shared foundation from Phase 02:

- Outer panel: semi-opaque dark steel.
- Queue module: slightly recessed.
- Active row: brighter border and progress treatment.
- Queued rows: lower contrast.
- Locked row: muted with grey/ghost styling.
- Progress bar: dark blue background with blue fill.
- Action buttons: Pause as secondary, Clear as danger or muted danger.

## Implementation Notes

### Existing files

Start with:

- `scripts/ui/hud.gd`
- `scripts/ui/hud_styling.gd`
- `scripts/ui/hud_updates.gd`
- `scripts/ui/training_queue_panel.gd`

### Suggested approach

1. Keep the existing node names and signal wiring where possible.
2. Replace one-off panel styles with Phase 02 shared styles.
3. Rebuild the queue panel layout using `VBoxContainer`, `HBoxContainer`, and `TextureProgressBar` or `ProgressBar`.
4. Preserve icon loading from `frost_mines_assets/icons/`.
5. Ensure queue rows do not intercept selection or world clicks unexpectedly.
6. Add a clear empty state such as `Queue clear` or `No active training`.

### Possible queue row structure

```text
QueuePanel (PanelContainer)
└── MarginContainer
    └── VBoxContainer
        ├── QueueHeader (HBoxContainer)
        ├── ActiveItem (PanelContainer)
        │   └── HBoxContainer
        │       ├── TextureRect
        │       ├── VBoxContainer
        │       │   ├── Label
        │       │   └── Label
        │       └── Label (percent)
        ├── ProgressBar
        ├── QueuedItems (VBoxContainer)
        └── Actions (HBoxContainer)
```

## Readability Requirements

- Coin and HP must remain visible during snowstorm and volcano overlays.
- Queue should be readable at a glance but not dominate the right edge.
- Disabled training buttons must not look available.
- Enemy faction must remain hidden as `???` until identified.
- Text must remain legible at logical 1920×1080 and scaled 2560×1440.

## Testing Steps

1. Start a match and confirm top/bottom bars appear correctly.
2. Train one unit and verify active queue display.
3. Queue multiple units and verify ordering and capacity.
4. Pause training and verify state.
5. Clear queue and verify empty state.
6. Trigger snowstorm and verify HUD contrast.
7. Trigger volcano and verify HUD contrast.
8. Switch Surface/Underground and verify layout.
9. Test all game speeds.
10. Test enemy faction hidden and identified states.
11. Test victory/defeat overlay over the new HUD.
12. Run the GUT test suite.

## Acceptance Criteria

- HUD visibly matches the approved Frosted Steel concept.
- Top and bottom bars share the same visual system.
- Training queue matches the redesigned active/queued/action structure.
- Queue progress and times are accurate.
- All original commands and shortcuts still work.
- No HUD element becomes unreadable during weather overlays.
- No decorative HUD element blocks world input.
- Existing tests pass.
