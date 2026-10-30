# Step 4 — Lighting & Atmosphere (the Frostpunk payoff)

Overcast-by-default world; weather *is* the lighting direction.
Numeric baselines come from the style guide; all values here are
starting points to tune in-engine.

## 4.1 Baseline rig

- [ ] Directional light (low sun, cold) + hemisphere-style ambient
      (cold sky bounce, faint warm ground bounce in the mine).
- [ ] Fixed time of day: permanent late-afternoon-polar feel. No
      day-night cycle — that is the K3.1 example's identity, not ours.
- [ ] Global color grade: desaturate + cool shadows, decided in the
      style guide; one `WorldEnvironment` rather than per-asset
      recoloring.

## 4.2 Weather-reactive states (visual-only, driven by `weather_manager`)

- [ ] **Snowstorm**: ambient drops, fog density up (matches the vision
      penalty), wind-blown snow particles, directional light dims and
      cools. Underground unaffected except at the shaft mouth.
- [ ] **Volcano eruption**: red-orange key from above, ember particles,
      burning-ground decals cast a glow.
- [ ] **Lava in the mine**: emissive material + point lights on the
      flood front; the rising level should be visible before it's
      dangerous. Animated flow in the shader (this is where the
      K3.1 example's water-shader approach transfers).
- [ ] **Cave-ins**: dust burst + brief light dim as the block lands.

## 4.3 Lanterns as hero lights

- [ ] Real `OmniLight3D` per lantern, three tiers of radius/energy
      matching the vision tiers; warm color — the only warm lights in
      the cold palette besides lava/embers.
- [ ] Cap simultaneous dynamic lights; distance-cull underground lights
      for the web preset.

## 4.4 Shadow & GI strategy

- [ ] Desktop: shadow map on the key light, tight frustum following the
      camera; SSAO on.
- [ ] Web: shadows off or blob-only (already in place from Phase 1),
      SSAO off — document in the Fancy/Standard/Potato presets.
- [ ] No real-time GI. Bake only if the map proves static enough to be
      worth it; otherwise live without.

## Acceptance

Each weather state is recognizable from a screenshot with the HUD
hidden; the 1×/2×/3× speed change doesn't cause light popping;
web preset documented and verified.

Status: `[ ]`
