# Step 2 — Animation Retargeting (the shared-rig workflow)

The single biggest efficiency lever from the K3.1 example: **one rig,
many animations, many units.** KayKit characters share a skeleton and
ship with a base animation set; the Quaternius Universal Animation
Library adds more. We retarget, we do not animate from scratch.

## Plan

- [ ] **Rig import**: bring in the KayKit base character; strip to the
      skeleton + reference mesh; verify skeleton scale/orientation
      against the style-guide standard.
- [ ] **Unit variants**: miner / swordsman / archer / wizard / engineer
      as mesh variants on the same skeleton (armor pieces, hats,
      weapons as separate attachment nodes — matches how `UnitData`
      already parameterizes units).
- [ ] **Animation set mapping**: define the canonical state list the
      unit state machine needs (idle, walk, mine, attack, channel/raise,
      death, fly for dragon/pigeon) and map each to a source animation
      (KayKit or Quaternius retarget).
- [ ] **`UnitData` extension**: add `animation_set: StringName` (or
      resource ref) so unit behavior stays data-driven; no per-unit
      animation code.
- [ ] **Faction accents**: material override slots (Arcane violet /
      Brute red / Industrial brass) applied at spawn from
      `faction_manager` data.
- [ ] **Undead**: same skeleton, desaturated/sickly material preset —
      no new animations.
- [ ] **Web LOD**: simplified pose update rate or reduced bone count at
      distance; document the Potato preset behavior.

## Acceptance

- All humanoid units animate with the shared rig; no unit has bespoke
  animation code.
- Animation state transitions match the 2D timing within one animation
  frame (gameplay feel unchanged).
- GUT suite green; web build plays all animations.

Status: `[ ]`
