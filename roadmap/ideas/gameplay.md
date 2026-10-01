# Gameplay Ideas

New mechanics, modes, and content. Nothing here blocks the 3D
conversion; several items pair well with it (noted inline).

## Controls & orders

- [x] **Waypoints / queued orders (Shift)** — queue multiple
      move/mine/attack orders per unit or group. Natural fit with
      existing right-click context orders (`player_commands.gd`).
- [x] **Unit formations** — column / line / spread when moving fighter
      groups; interacts with existing archer/wizard standoff logic.
- [x] **Attack/threat alerts** — audible ping + screen-edge indicator
      when miners or the base take damage; cheap, high value, and the
      AI raid logic already produces the events.

## Modes & content

- [ ] **Scenario / challenge mode** — handcrafted missions on top of
      the skirmish loop ("survive a lava flood with only miners",
      "defend against three timed sieges"). Reuses all existing
      systems; the weather/lava/cave-in managers are already the
      mission toolkit.
- [ ] **Map editor or seed-sharing screen** — map seeds and archetype
      knobs (`MAP_WALL_HP_MULTS`, `MAP_ORE_CURVES`) already exist in
      `grid_map_generation.gd`; even a simple "copy this seed" UI adds
      replayability for near-zero cost. Full archetypes (shaft
      positions, caverns, dimensions) remain open in IDEAS.md.
- [ ] **Meta-progression (out-of-match unlocks)** — cosmetic-only
      first (faction banners, unit tints); anything stat-affecting
      risks invalidating the difficulty ladder. Defer until the core
      game is where we want it.

## Presentation-driven gameplay

- [x] **Dynamic music** — tie `audio_manager.gd` layers to combat
      intensity and weather state; snowstorms already mute visibility,
      let them thin the score too. (Pairs well with Phase 2 lighting.)
- [x] **Juice pass on signature moments** — cave-in screen shake,
      dragon-crush hit-stop, raise-dead channel VFX. Zero gameplay
      cost; do during the 3D art pass where the tooling is freshest.
