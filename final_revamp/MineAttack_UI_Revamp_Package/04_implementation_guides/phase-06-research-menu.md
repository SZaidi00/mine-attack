# Phase 06 — Research Menu B+C · Doctrine Deck

## Goal

Implement the approved **B+C · Doctrine Deck** research menu. This combines option B’s branch-map clarity with option C’s card-level detail, state badges, icons, descriptions, and queue controls.

## Source References

- Research mockup: `../../02_approved_mockup/research-menu.html`
- Shared styles: `../../02_approved_mockup/styles.css`
- Variant metadata: `../../02_approved_mockup/variants.js`
- Design tokens: `../../03_design_tokens/design_tokens.json`
- Current research panel: `scripts/ui/research_panel.gd`
- Research state and data: `scripts/autoload/research_manager.gd`
- Research definitions: `scripts/autoload/constants.gd`

## Current Problem

The current research panel communicates the tree, but the presentation is utilitarian. Branch relationships, mutually exclusive choices, research status, selected-node details, and queue controls should be easier to scan.

## Approved Hybrid

The Doctrine Deck must preserve both sides of the approved combination:

### From option B · Doctrine Map

- Spatial branch map.
- Visible connector lines.
- Branch relationship hierarchy.
- Mutually exclusive choices.
- Branch identity through color.

### From option C · Research Deck

- Technology cards.
- State badges.
- Icons.
- Compact descriptions.
- Detail rail.
- Progress display.
- Queue/cancel controls.

## Required Structure

### 1. Header

Include:

- Panel title.
- Current research status.
- Active research progress.
- Overall or branch progress where useful.
- Close hint.

### 2. Branch map

Show the research tree spatially rather than as a plain list.

Required behavior:

- Connector lines show prerequisites and branch divergence.
- Nodes remain positioned consistently.
- Locked branches are visually muted.
- Completed nodes are visibly complete.
- Active research is highlighted.
- Available choices are clear.

### 3. Technology cards

Each node/card should include:

- Technology icon.
- Technology name.
- State badge.
- Short description or effect summary.
- Cost and time where useful.

Suggested states:

- Available
- Active
- Queued
- Complete
- Locked
- Excluded
- Maxed

### 4. Detail rail

Selecting a node should show:

- Full name.
- Branch.
- Description.
- Cost.
- Research time.
- Prerequisites.
- Mutually exclusive alternative.
- Current status.
- Progress if active.
- Action button.

### 5. Queue controls

Preserve the existing research queue behavior:

- Start research.
- Cancel active/queued research where supported.
- Respec if available.
- Ore Sonar scan if applicable.

Do not change research balance, timings, costs, or exclusivity rules.

## Branch Colors

Preserve faction/branch hues:

- Arcane: `#AF84FB`
- Brute: `#DF6B6B`
- Industrial: `#FBBF24`

Use these as borders, connector accents, badges, and highlights. Do not rely on color alone; pair with labels and icons.

## Visual Treatment

Use the shared Phase 02 foundation:

- Full-screen dim behind the panel.
- Large frosted steel outer panel.
- Recessed map area.
- Detail rail with darker inset background.
- Gold progress fill for active research.
- Blue or steel accents for selectable controls.
- Muted grey for locked/excluded states.
- Red or warning styling only for irreversible/exclusion warnings.

## Layout Requirements

The current panel is approximately 1040×900 with a scrollable research tree. Keep the panel large enough for the map and detail rail.

Recommended structure:

```text
Research Panel
├── Header
│   ├── Title
│   ├── Active research summary
│   └── Progress
├── Body
│   ├── Branch map / card grid
│   └── Detail rail
└── Footer
    ├── Queue status
    ├── Cancel
    ├── Respec
    └── Scan
```

The map should remain usable without forcing excessive scrolling at 1920×1080.

## Mutually Exclusive Research

Mutual exclusivity must be unmistakable.

When a tech is selected:

- Show the alternative it will lock.
- Show whether the alternative is already excluded.
- Use warning text or confirmation where irreversible.
- Keep existing one-time 500g respec behavior unchanged.

When a branch is locked:

- Grey the node.
- Mark it `Excluded` or `Locked`.
- Show tooltip/detail explanation.

## Implementation Notes

Start with `scripts/ui/research_panel.gd`.

If the panel becomes too large, split the layout into a helper:

```text
scripts/ui/doctrine_deck_panel.gd
```

Possible structure:

```text
ResearchPanel
├── DimBackground
└── DoctrineDeckPanel
    ├── Header
    ├── HBoxContainer
    │   ├── ResearchMap
    │   └── DetailRail
    └── FooterControls
```

Use the existing `ResearchManager` API as the source of truth. Do not duplicate research state in UI code.

## Connector Lines

Connector lines may be drawn with:

- `Line2D`
- `Control._draw()`
- Precomputed line segments in a dedicated map control

Keep connectors behind cards. Use gold for open/active paths and low-alpha grey for locked paths.

## Icons

Use existing icons first, including copied research icons:

```text
assets/tech/tech_deep_delve.png
assets/tech/tech_surface_war.png
assets/tech/tech_ore_sonar.png
assets/tech/tech_reinforced_pack.png
assets/tech/tech_crystal_forge.png
assets/tech/tech_siege_master.png
```

Existing unit/building/weather icons may continue to represent related techs. Do not add external icon packs.

## Interaction Requirements

- `R` toggles the research panel as it currently does.
- Selecting a node updates the detail rail.
- Starting research preserves existing validation.
- Cancelling research preserves existing refund/queue behavior.
- Respec preserves the existing one-time cost and resets the correct state.
- Scan button preserves Ore Sonar behavior.
- Closing the panel does not cancel active research.

## Testing Steps

1. Open and close the panel with `R`.
2. Select every visible research node.
3. Start an available research.
4. Verify active progress and detail rail.
5. Queue or cancel research according to existing behavior.
6. Complete a mutually exclusive tech and verify the alternative locks.
7. Use respec and verify the one-time rule and cost.
8. Use Ore Sonar scan.
9. Verify branch colors and state badges.
10. Test at 1920×1080 and 2560×1440.
11. Run the GUT test suite.

## Acceptance Criteria

- Research panel visibly matches the Doctrine Deck hybrid.
- Branch relationships are easier to understand than in the current panel.
- Every node has readable state and icon treatment.
- Selected-node details are persistent and clear.
- Queue/cancel/respec/scan behavior remains intact.
- Mutually exclusive choices are clearly communicated.
- No research balance or timing changes are introduced.
- Existing tests pass.
