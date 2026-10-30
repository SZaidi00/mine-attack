# Step 0 — Style Guide (write this first)

One page, binding. Everything in Steps 1–5 references it. Do not import
a single asset before this exists.

## Contents to decide and record

- [ ] **Palette**: base surface tones (cold desaturated blues/greys),
      ore accents (warm orange), lava (emissive, hue fixed here),
      necromancy (sickly green), faction accents — Arcane violet,
      Brute red, Industrial brass. Record hex values.
- [ ] **Silhouette rules**: one line per unit type describing the shape
      that must survive at max zoom-out (miner's pickaxe, archer's bow,
      wizard's hat, dragon's wingspan...). New assets are judged
      against these lines.
- [ ] **Scale standard**: 1 unit = 1 metre; humanoids 1.8m tall;
      record the camera height/foil used to check zoom-out readability.
- [ ] **Texel density target**: fixed world-units-per-texture value;
      assets that don't match get normalized on import, not re-authored.
- [ ] **Poly budget**: per-unit tri cap (e.g., humanoids ≤ 2k tris,
      dragon ≤ 6k, structures ≤ 4k) and total on-screen budget.
- [ ] **Lighting baseline**: overcast ambient values, storm variant,
      volcano variant — the numeric starting point for
      `lighting-atmosphere.md`.
- [ ] **Material rules**: flat-shaded stylized; where vertex color vs
      texture is allowed; emissive usage policy (lava, lanterns,
      necromancy only).
- [ ] **What "done" looks like**: 3–5 reference screenshots/sketches.

## Anti-patterns to write down

- No warm/saturated village look as the base (that is the Quaternius
  Medieval default — our cold grade comes from lighting, not asset
  recoloring).
- No per-asset ad-hoc rescaling at placement time; normalize at import.
- No new silhouette-affecting variants without a style-guide line.
