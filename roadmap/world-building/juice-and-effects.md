# Step 5 — Juice & Effects (signature moments)

Zero gameplay cost, all feel. Everything here is visual/audio-only;
gameplay numbers stay frozen.

- [ ] **Cave-in impact**: screen shake scaled by distance from the
      block, dust ring, debris bounce. Reduced-shake setting (see
      accessibility list) gates it.
- [ ] **Dragon crush / heavy hits**: 2–3 frame hit-stop; optional,
      off in Potato preset.
- [ ] **Raise dead channel**: ground glow → corpse twitch → rise
      animation on the shared rig (Step 2), sickly light on completion.
- [ ] **Breach moment**: when the central wall breaks, a one-time
      camera-agnostic event — dust wave both sides, sound sting. This
      is the match's turning point; it should feel like one.
- [ ] **Order feedback**: the ground-target ripple (from Phase 1) gets
      faction-colored accents; queued orders (if/when that feature
      lands) show a path of ripples.
- [ ] **Combat readability**: hit flashes on the shared-rig materials
      (emissive pulse), death animations instead of fade-out.
- [ ] **Weather audio**: positional `AudioStreamPlayer3D` — wind on the
      surface, dripping underground, lava rumble that gets louder with
      the flood level. `audio_manager.gd` gains channels, not logic.
- [ ] **Dynamic music** (from `roadmap/ideas/gameplay.md`): score
      layers tied to combat intensity + storm state; thin the texture
      during snowstorms.

## Acceptance

Each item toggleable from settings (shake, hit-stop, flashes); Potato
preset turns all of them off without code changes; GUT green; a 30s
"moments" clip of breach + cave-in + raise dead is the deliverable.

Status: `[ ]`
