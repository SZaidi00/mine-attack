# UX Polish Ideas

Controls, UI, feedback, and accessibility. These compound with the 3D
conversion — camera and selection UX especially.

## Controls & camera

- [ ] **Control groups (Ctrl+1–9)** — tracked in `improvements/IDEAS.md`;
      natural home is `player_selection.gd`. Do before the 3D port so
      selection architecture is settled first.
- [ ] **Attack-move (A+click)** — also in IDEAS.md. Same note: land
      before Phase 1 so the 3D ray-picking layer inherits it.
- [ ] **Minimap** — tracked in IDEAS.md; canvas-drawn from `GridWorld`
      fog maps. In 2.5D it stays a 2D Control — cheap. In full 3D it
      needs a depth indicator.
- [ ] **Hotkey remapping** — the scheme is growing (1–8 train keys,
      Ctrl+A/M/F/D, R, K, Tab, F3); rebindable keys belong in
      `settings_manager.gd`.
- [ ] **Ground-target marker on orders** — subtle click ripple at the
      order destination; cheap depth cue, listed as a Phase 1 item too.

## Feedback & onboarding

- [ ] **First-time tutorial / contextual tooltips** — stances, layers,
      factions, research, and weather interact; a lightweight guided
      first match teaches the loop without a wall of text.
- [ ] **Floating damage numbers / hit feedback** — makes combat legible
      at a glance.
- [ ] **Post-game coaching hints** — surface 2–3 concrete observations
      from `MatchStats` logs ("out-mined 2:1 after minute 5", "base
      took 60% damage in the first siege"). The logging exists; this
      is mostly UI.
- [ ] **Production/completion notifications** — subtle toasts for
      trained units, finished research, finished structure upgrades.

## Accessibility

- [ ] **Colorblind mode** — snow/lava/ore/fog are color-coded; add
      icon or pattern redundancy. In 3D this becomes a material-accent
      problem too — decide palette rules in the Phase 2 style guide.
- [ ] **UI scaling** — adjustable HUD scale in settings.
- [ ] **Reduced-flash / reduced-shake toggle** — matters once Phase 2
      adds screen shake and hit-stop.
- [ ] **Volume mixers beyond master/music/SFX** — split weather,
      combat, and UI channels once the dynamic-music work lands.
