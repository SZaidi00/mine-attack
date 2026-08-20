# Approved Design Decisions

This document records the exact selections approved from the interactive mockup. Use it with `design_tokens.json` when implementing the production UI.

## Global Direction

- Design language: **Frosted steel console**
- Mood: frozen post-apocalyptic industrial siege at a volcanic mine
- Visual materials: stamped metal, frost edges, rivets, worn paint, warning stripes, emergency lights, glowing readouts
- Priority: RTS readability first, atmosphere second

## Preserved Colors

| Purpose | Color |
|---|---|
| Player / ally | `#3B82F6` |
| Enemy | `#B91C1C` |
| Arcane | `#AF84FB` |
| Brute | `#DF6B6B` |
| Industrial | `#FBBF24` |

## Snowstorm

**Selected:** B · Ground Whiteout

| Control | Approved value |
|---|---:|
| Storm Intensity | 100% |
| Wind Direction | +16 |
| Visibility Loss | 100% |
| Shelter Pocket Size | 23% |
| Fog Edge Softness | 100% |
| Snow Accumulation | Off |

Additional requirements:

- Fog moves horizontally like cloud banks.
- The storm appears only in the above-ground area.
- The storm does not render underground.
- Shelter pockets remain visible and warm without becoming black holes.

## Meteor Shower

**Selected:** B · Volcanic Siege

| Control | Approved value |
|---|---:|
| Meteor Density | 100 |
| Ember Glow | 100 |
| Impact Marker Strength | 0 |
| Crater Plume | 45 |
| Heat Color Grade | 68 |

Additional requirements:

- Crater plume means smoke/glow rising from the volcano mouth.
- The effect appears only above ground.
- The effect does not render underground.
- Impact-marker rings are disabled.

## Main Menu

**Selected:** A · Command Console

Additional requirement:

- The background should be more atmospheric and less plain while keeping controls readable.

Approved background ingredients:

- Horizontal cloud drift.
- Aurora or ice shimmer.
- Blue player-base glow on the left.
- Red enemy-base glow on the right.
- Warm volcanic horizon glow.
- Soft vignette.

## HUD

**Selected:** A · Frosted Steel

Additional requirement:

- The training queue must be redesigned.

Approved queue structure:

- Header with production count and capacity.
- Large active item with icon, name, ready time, percent, and progress.
- Compact queued rows.
- Locked/ghost row state.
- Pause and clear actions.

## Build Menu

**Selected:** A · Blueprint Tray

Required treatment:

- Compact industrial tray.
- Blueprint-like cards.
- Icon, name, cost, count/max, availability, hover, selected, capped, and disabled states.

## Research Menu

**Selected:** B+C · Doctrine Deck

Required combination:

- Option B’s branch map and visible exclusive choices.
- Option C’s card details, state badges, icons, descriptions, detail rail, and queue controls.

## Surface Mask

Use this normalized viewport band for weather/event rendering:

```text
Top:    0.095
Bottom: 0.382
```

All snowstorm and meteor/volcano visuals must be clipped to that band.
