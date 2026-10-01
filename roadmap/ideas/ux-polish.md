# UX Polish Ideas

Controls, UI, feedback, and accessibility. These compound with the 3D
conversion — camera and selection UX especially.

## Controls & camera

- [x] **Control groups (Ctrl+1–9)** — tracked in `improvements/IDEAS.md`;
      natural home is `player_selection.gd`. Do before the 3D port so
      selection architecture is settled first. (Implemented 2026-09:
      Ctrl+digit assigns in `player_controller.gd`, Alt+digit recalls —
      digits 1–8 stay train hotkeys; `tests/test_control_groups.gd`.)
- [x] **Attack-move** — also in IDEAS.md. Same note: land
      before Phase 1 so the 3D ray-picking layer inherits it.
      (Implemented 2026-09: **Q+click**, not A — A is camera pan; armed-mode
      in `player_controller.gd`/`player_commands.gd`, unit-side flag in
      `unit_commands.gd`/`unit_idle.gd`; `tests/test_attack_move.gd`.)
- [x] **Minimap** — tracked in IDEAS.md; canvas-drawn from `GridWorld`
      fog maps. In 2.5D it stays a 2D Control — cheap. In full 3D it
      needs a depth indicator. (Implemented 2026-09: `scripts/ui/minimap.gd`
      + `scenes/ui/minimap.tscn`, terrain/fog/unit dots + camera rect,
      click-to-move camera; `tests/test_minimap.gd`.)
- [x] **Hotkey remapping** — the scheme is growing (1–8 train keys,
      Ctrl+A/M/F/D, R, K, Tab, F3); rebindable keys belong in
      `settings_manager.gd`. (Implemented 2026-09: `[input]` bindings in
      `settings_manager.gd`, capture-UI in `settings_panel.gd`,
      `Constants.REMAPPABLE_ACTIONS`; `tests/test_key_remap.gd`.)
- [x] **Ground-target marker on orders** — subtle click ripple at the
      order destination; cheap depth cue, listed as a Phase 1 item too.
      (Implemented 2026-09: `scripts/effects/order_marker.gd`, tinted per
      order type from `player_commands.gd`.)

## Feedback & onboarding

- [x] **First-time tutorial / contextual tooltips** — stances, layers,
      factions, research, and weather interact; a lightweight guided
      first match teaches the loop without a wall of text.
      (Implemented 2026-09: `scripts/ui/tutorial_hints.gd`, ~10 contextual
      hints persisted via `SettingsManager` seen-list; `tests/test_tutorial_hints.gd`.)
- [x] **Floating damage numbers / hit feedback** — makes combat legible
      at a glance. (Already existed: `damage_popup.gd`; verified during
      this pass.)
- [x] **Post-game coaching hints** — surface 2–3 concrete observations
      from `MatchStats` logs ("out-mined 2:1 after minute 5", "base
      took 60% damage in the first siege"). The logging exists; this
      is mostly UI. (Implemented 2026-09: base-HP timeline samples +
      max-tier keys in `MatchStats`, `scripts/ui/coaching_hints.gd`,
      rendered in the game-over panel; `tests/test_coaching_hints.gd`.)
- [x] **Production/completion notifications** — subtle toasts for
      trained units, finished research, finished structure upgrades.
      (Implemented 2026-09: `unit_spawned` + lantern `upgraded` signal
      toasts in `hud.gd`; `tests/test_production_toasts.gd`.)

## Accessibility

- [x] **Colorblind mode** — snow/lava/ore/fog are color-coded; add
      icon or pattern redundancy. In 3D this becomes a material-accent
      problem too — decide palette rules in the Phase 2 style guide.
      (Implemented 2026-09 (2D pass): palette swap in `ui_theme_tokens.gd`,
      enemy-HP bar frame cue, minimap shape coding; 3D palette rules
      remain a Phase 2 decision.)
- [x] **UI scaling** — adjustable HUD scale in settings. (Implemented
      2026-09: 75–150% slider, HUD root scale in `hud.gd`; auto-capped so
      bars always fit; `tests/test_accessibility_settings.gd`.)
- [x] **Reduced-flash / reduced-shake toggle** — matters once Phase 2
      adds screen shake and hit-stop. (Implemented 2026-09: shake gated in
      `player_camera.gd`, banner pulse gated in `hud.gd` — ahead of Phase 2
      since 2D already had shake.)
- [ ] **Volume mixers beyond master/music/SFX** — split weather,
      combat, and UI channels once the dynamic-music work lands.
