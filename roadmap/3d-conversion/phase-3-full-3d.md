# Phase 3 — Full 3D (optional, sequel-scale)

**Goal:** turn the layered mine into true vertical 3D space. This is
NOT part of the conversion; it is a major expansion we only attempt if
Phase 2's release validates the 3D direction.

## What would change

| System | Today (2.5D) | Phase 3 target |
|---|---|---|
| Mine geometry | 7 flat layers, Tab-switched | One continuous volume; layers become depth bands |
| Pathfinding | 2D A* per layer, sealed surface row (`find_path_underground`) | 3D A* / `NavigationServer3D` volumes |
| Lava | Rises through layer planes | Rises as a true fluid level; flooded cells become new ore as it recedes |
| Dragons / pigeons | Surface-only | Verticality matters — dragons dive, pigeons fly over the shaft |
| Camera | Fixed-pitch RTS rig | Same rig, but with limited pitch-down into the shaft mouth; Tab becomes "focus depth" instead of "switch plane" |
| Fog of war | Per-layer fog maps | Volumetric fog + per-cell visibility |
| Cave-ins | 3×3 blocks | True collapsing volumes; supports get realistic |

## Why this is hard (be honest with ourselves)

- Every pathfinding and targeting assumption in `unit.gd`,
  `unit_vision_targeting.gd`, and the entire `ai_*` stack is 2D.
  This is a redesign of unit movement, not a rendering change.
- The AI's underground raid logic (`ai_crawlers.gd`) assumes layered
  planes; a true 3D mine changes what "through the breached wall"
  means.
- Readability: seeing your mine at a glance is a core UX strength of
  the current design. A 3D shaft risks losing it.
- The GUT suite's world tests would need a parallel 3D suite.

## If we do it — sequencing

1. **3.1 — Vertical slice:** one continuous shaft column with true 3D
   miner movement; everything else still 2.5D planes. Prove readability.
2. **3.2 — Navigation:** 3D pathfinding behind the same movement API so
   AI modules don't care.
3. **3.3 — Systems migration:** lava level, cave-ins, crawler raids, fog.
4. **3.4 — Camera & UI:** depth-focused camera, layer indicator becomes
   a depth meter.
5. **3.5 — Rebalance & test:** new test suite for 3D world rules.

## Fallback

If 3.1 shows the shaft is unreadable or unfun, stop. The 2.5D layered
mine with a cutaway look is a legitimate final design — arguably the
more distinctive one.
