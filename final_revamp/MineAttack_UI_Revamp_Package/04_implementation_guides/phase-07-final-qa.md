# Phase 07 — Final QA and Release Checklist

## Goal

Verify that the complete UI revamp is readable, performant, consistent, and safe to release across Godot editor, Web, macOS, and Windows targets.

## Scope

This phase covers:

- Visual regression review.
- Gameplay readability.
- Weather/event clipping.
- Input and shortcut behavior.
- Resolution and scaling.
- Performance.
- Web export compatibility.
- Existing test suite.
- Final package cleanup.

## 1. Visual Consistency Review

Compare the production implementation against the approved mockup:

- Snowstorm: `../02_approved_mockup/index.html`
- Meteor: `../02_approved_mockup/meteor.html`
- Main menu: `../02_approved_mockup/main-menu.html`
- HUD: `../02_approved_mockup/hud.html`
- Build menu: `../02_approved_mockup/build-menu.html`
- Research menu: `../02_approved_mockup/research-menu.html`

Confirm:

- All screens share the frosted steel design language.
- Gold, blue, red, and faction accents are used consistently.
- No screen still uses obviously old flat placeholder styling.
- Main menu and HUD look like parts of the same game.
- Warning banners feel related to the rest of the console UI.

## 2. Color and Palette Regression

Verify exact preserved colors:

```text
Player       #3B82F6
Enemy        #B91C1C
Arcane       #AF84FB
Brute        #DF6B6B
Industrial   #FBBF24
```

Also verify:

- Gold text remains `#FBBF24`.
- Primary text remains `#E2E8F0`.
- Dim text remains `#94A3B8`.
- Warning colors remain distinct from normal UI accents.
- Enemy UI remains red and player UI remains blue.

## 3. Weather and Event QA

### Snowstorm

Trigger a snowstorm and verify:

- Warning countdown appears correctly.
- Active storm renders only above ground.
- No fog, snow, or cloud banks appear underground.
- Fog moves horizontally.
- Fog has irregular density.
- Snow streaks follow the wind direction.
- Shelter pockets are readable.
- Shelter pockets do not appear as black holes.
- No snow accumulation appears at the ground line.
- HUD remains readable during the storm.
- Storm ends cleanly and all overlay state resets.

### Meteor shower / volcano

Trigger an eruption and verify:

- Warning countdown appears correctly.
- Meteors render only above ground.
- Embers render only above ground.
- Crater plume remains tied to the volcano mouth.
- Heat grading affects only the surface.
- No impact-marker rings appear.
- Meteor density and ember density are visibly high but readable.
- Effects stop cleanly when the event ends.
- Overlapping snowstorm behavior remains correct.

### Other events

Verify that the new UI did not regress:

- Lava warning.
- Lava rise/recede presentation.
- Cave-in warning/effects.
- Faction-identified popup.
- Victory/defeat panels.

## 4. HUD QA

Verify top bar:

- Coin amount.
- Miner level.
- Player faction icon.
- Unit total and breakdown.
- Player building HP.
- Enemy building HP.
- Hidden enemy faction state.
- Identified enemy faction state.

Verify controls:

- Surface/Underground toggle.
- Pause.
- Speed 1×, 2×, 3×, 5×, 10×.
- Selection readout.

Verify bottom bar:

- Upgrade Miner.
- Train Miner.
- Train Swordsman.
- Train Archer.
- Train Wizard.
- Train Dragon.
- Fighter upgrades.
- Attack stance.
- Defend stance.
- Garrison stance.
- Rally stance.
- Kill/disband.
- Research.
- Build.

Verify keyboard shortcuts:

- `1–5` training.
- `Tab` view toggle.
- `R` research.
- `K` / `Delete` disband.
- `Space` / `Esc` pause.

## 5. Training Queue QA

Verify:

- Empty state.
- One active item.
- Multiple queued items.
- Correct order.
- Correct remaining time.
- Correct percent/progress.
- Correct capacity display.
- Pause state.
- Clear action.
- Cancellation behavior if supported.
- Locked or unavailable rows.
- Queue behavior after building destruction, restart, or quit-to-menu.

## 6. Main Menu QA

Verify:

- Background atmosphere is visible but subtle.
- No hard vertical beam or distracting gradient appears.
- Title and subtitle remain readable.
- Difficulty selector works.
- Resolution selector works on desktop.
- Resolution selector is hidden or disabled appropriately on web.
- Next/Play flow works.
- Quit flow works on desktop.
- Faction cards are balanced and readable.
- Selected faction state is clear.
- Faction particles tint correctly.
- Background animation does not hurt menu usability.

## 7. Build Menu QA

Verify all options:

- Lantern.
- Mine Lantern.
- Tower.
- Wall.
- Trap.
- Pigeon.

For each option, verify:

- Icon.
- Name.
- Cost.
- Count/max.
- Available state.
- Unaffordable state.
- Max-count state.
- Hover state.
- Selected state.
- Placement ghost.
- Placement validation.
- Cancel behavior.

## 8. Research Menu QA

Verify:

- Panel opens/closes with `R`.
- Branch map layout is readable.
- Connector lines are visible and behind cards.
- Available state.
- Active state.
- Queued state if supported.
- Completed state.
- Locked state.
- Excluded state.
- Detail rail updates on selection.
- Cost and time are correct.
- Research starts correctly.
- Research completes correctly.
- Cancellation works as intended.
- Respec cost and one-time behavior remain correct.
- Ore Sonar scan remains correct.
- Mutually exclusive alternatives lock correctly.

## 9. Resolution and Scaling QA

Test at:

- Logical UI: 1920×1080.
- Project viewport: 2560×1440.
- Common desktop window sizes.
- Web full-bleed sizing.

Confirm:

- No clipped text.
- No overlapping top/bottom bar content.
- No oversized training queue.
- Build and research panels fit on screen.
- Pixel-art textures remain crisp.
- 9-slice panels do not distort.
- Weather masks scale correctly.

## 10. Input and Mouse Filter QA

Verify decorative overlays do not block gameplay:

- Weather overlay.
- Warning banners.
- Background atmospheric layers.
- Panel decorative elements.
- Connector lines.
- Fog/cloud/snow visuals.

Use `MOUSE_FILTER_IGNORE` for noninteractive overlays. Buttons and interactive cards must remain clickable.

## 11. Performance QA

Test on the weakest practical target, especially web.

Watch for:

- Excessive particle counts.
- Full-screen texture regeneration every frame.
- Excessive draw calls.
- Unbounded queue row creation.
- Large transparent overlays with expensive blending.
- Memory growth during repeated event triggers.
- Frame drops during snowstorm + volcano overlap.

Recommended targets:

- Weather overlays should use bounded particle pools.
- UI panels should cache styles.
- Queue rows should be reused or bounded.
- No expensive per-pixel image generation should occur every frame.

## 12. Automated and Headless Testing

Run the existing GUT suite from the project root:

```bash
/Users/shumail/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

All tests must pass before release.

If UI changes affect test harness setup or scene lifetimes, update tests carefully without weakening gameplay assertions.

## 13. Export QA

Export all configured presets:

```bash
GODOT=/Users/shumail/Downloads/Godot.app/Contents/MacOS/Godot tools/export_all.sh
```

Expected outputs:

- Web: `build/MineAttack.html`
- macOS: `build/MineAttack.app`
- Windows: `build/MineAttack.exe`

For each export, verify:

- Game launches.
- Main menu appears.
- Match starts.
- HUD appears.
- Build menu opens.
- Research menu opens.
- Snowstorm appears.
- Volcano appears.
- Victory/defeat panel appears.
- No missing textures or script errors occur.

## 14. Final Cleanup

Before handoff:

- Remove temporary debug UI.
- Remove unused generated files.
- Remove dead code paths from the old vignette if fully replaced.
- Keep comments concise and in English.
- Use static typing where practical.
- Keep file and function names in `snake_case`.
- Keep class and scene node names in `PascalCase`.
- Do not rename `/root/Main` or its expected children.
- Confirm all new assets are PNGs.
- Confirm no new external dependencies were added.

## Release Definition of Done

The revamp is release-ready only when:

- All approved visual treatments are implemented.
- All original gameplay behavior works.
- Weather effects remain surface-only.
- Team and faction colors are preserved.
- UI remains readable during all events.
- All target resolutions scale correctly.
- GUT tests pass.
- Web, macOS, and Windows exports pass a manual smoke test.
