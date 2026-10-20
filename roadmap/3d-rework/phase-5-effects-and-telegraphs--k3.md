# Phase 5 — Effects & Threat Telegraphs

**Parent plan:** `roadmap/3d-rework/README.md` (read it first for rules).
**Depends on phase 3** (bloom/tonemap), ideally also phase 1 (projectile
proxy pattern to copy).

## Current state (verified)

- Existing 3D ambient effects (`scripts/three_d/effects_3d.gd`): dust motes,
  storm snow drift, volcano embers, cave-in dust bursts. Terrain emissives:
  lava pulse + ember spikes (`scripts/three_d/terrain_3d.gd:237-241`,
  `terrain_detail_3d.gd:117-127`).
- **2D-only event VFX, invisible in 3D mode** (they live on hidden canvas
  layers): meteors (`scripts/effects/meteor.gd`), burning ground
  (`scripts/effects/burning_ground.gd`), volcano background sprite, reject
  popups, coin popups/pickups.
- No attack telegraphs: no target lines, no AoE preview, no wave-warning
  ping in the 3D world (the HUD threat arrows exist and stay 2D —
  `scripts/ui/threat_alert_layer.gd`).

## Reference

TAB is the masterclass in telegraphing: infection attacks, giant telegraphs,
and wave directions are readable at full zoom through color + shape + motion,
not detail. SC2: every spell has a pre-impact decal; projectiles are bright
tracers.

## Goals

1. **3D meteors & burning ground.** Mirror the sim's meteor/burning-ground
   spawns (same reconcile pattern as `entity_proxies_3d.gd` / phase-1
   projectile proxies): a falling emissive streak + impact flash + a
   persistent glowing crack/scorch decal mesh on the terrain for burning
   patches. Snowstorm extinguishing must clear the decal (read the sim's
   burn state, never track it separately).
2. **Volcano event presence in 3D.** Eruption warning: red-orange light
   sweep from the sky direction (the volcano mood already exists in
   `lighting_3d.gd:22-47` — add a pre-eruption pulse), ember density ramp,
   and a low rumble camera shake hooked to the same warnings the HUD shows.
3. **Attack telegraphs.** When the player's units are explicitly ordered to
   attack a target, draw a short-lived red line/arc from attacker group to
   target on the terrain (pooled unshaded quads). Optional stretch: tower
   target lines while a tower is selected.
4. **Event-zone telegraphs.** Lava-rise warning: emissive orange shimmer on
   the cells that will flood (the sim knows the schedule —
   `scripts/world/grid_events.gd`); cave-in warning: dust trickle + shadow
   darkening on the 3×3 target area before the drop.
5. **Emissive polish under bloom.** With phase-3 glow on, retune emission
   energies so the hierarchy reads: UI-critical telegraphs > combat tracers
   > ambient lava/lanterns > decorative embers. Nothing decorative should
   outshine a telegraph.

## Non-goals

- No changes to event timing/damage/schedule (sim untouched).
- No new audio (AudioManager already handles weather/combat layers).

## Steps

1. Add `event_proxies_3d.gd` (meteors, burning ground) following the
   reconcile pattern; register the 2D effect groups.
2. Add eruption-warning lighting pulse + shake hooks in `main_3d.gd` /
   `lighting_3d.gd`, driven by `WeatherManager` signals (same ones the HUD
   banners use).
3. Add telegraph decals/lines; pool them; respect particle/detail budget in
   `ArtStyle3D.apply_quality()` (Potato: no embers/decal shimmer, keep
   telegraph lines — telegraphs are gameplay, not decoration).
4. Retune emission hierarchy across `art_style_3d.gd`, `terrain_3d.gd`,
   `terrain_detail_3d.gd`, `effects_3d.gd`.
5. Update `AGENTS.md` (effects_3d + three_d description).

## Acceptance criteria

- A volcano eruption in 3D mode shows: warning pulse → visible meteors →
  glowing burn patches → snowstorm extinguishes them. None of this is
  visible today.
- Lava-rise and cave-in warnings are readable in 3D before they hit.
- Explicit attack orders show a telegraph line in 3D mode.
- Telegraphs are the brightest emissive class on screen; decorative embers
  never compete.
- Full test suite green
  (`godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests
  -gexit`); extend `tests/test_3d_effects.gd` for the new proxies.
- 60 fps with 200+ units during a simultaneous volcano + snowstorm on Fancy.
