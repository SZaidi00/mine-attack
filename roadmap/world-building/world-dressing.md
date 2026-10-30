# Step 3 — World Dressing (terrain, structures, props)

Make the map look like a place: coherent terrain materials, structures
with identity, and props that sell the theme. All of it renders from
`GridWorld._cells` + placement data — nothing here writes back to sim.

## 3.1 Terrain materials

- [ ] Replace flat cell colors with materials per cell state: rock
      (layer-tinted darker with depth), dug/empty, ore tiers (richness
      readable at glance), lava (see lighting doc), surface snow.
- [ ] Snow cover on surface cells: accumulates during storms, melts
      after — visual-only, driven by `weather_manager` signals
      (connect, don't poll).
- [ ] Mine shaft walls: the blue-stone kit (`02-G4-0008`) or pack rock
      modules lining dug shafts so the underground reads as carved,
      not deleted.
- [ ] `MultiMeshInstance3D` for repeated cells (ore/rock/snow) — this
      is the known instancing win from the 3D roadmap; measure before
      and after.

## 3.2 Structures

- [ ] **Building** (the base): faction-identifying silhouette — the
      enemy faction reveal moment should be *visible* on the model,
      not just a UI label. Candidate: Medieval Village kit main
      building, faction-accented.
- [ ] **Towers**: arrow tower / castle tower candidates from the design
      library; damage states as material swap + broken parapet mesh.
- [ ] **Walls**: modular half-timber/brick pieces; central wall gets a
      distinct "seam" look so the breach point is legible from the
      default camera.
- [ ] **Lanterns**: three visual tiers matching the three vision
      upgrades — the upgrade must be obvious at zoom-out.
- [ ] **Mine entry**: dressed with the smithy kit's forge/anvil/cart
      props (Industrial), or pack-specific variants per faction.
- [ ] **Traps**: hidden by default (fog handles it); visible to owner
      as a subtle prop — Kenney props.

## 3.3 Props & dressing

- [ ] Surface scatter: dead trees, rocks, snow drifts (Nature MegaKit),
      placed procedurally from the map seed so seeds keep their
      identity.
- [ ] Underground props: mine carts, support beams, crates near dug
      ore pockets.
- [ ] Dead-unit dressing: corpse markers for necromancy already exist in
      sim; give raisable corpses a visible 20s corpse mesh.

## Acceptance

Every structure identifiable at max zoom-out; breach point, mine entry,
and faction identity readable without selecting anything; 60fps desktop
with the full instancing pass.

Status: `[ ]`
