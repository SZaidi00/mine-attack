# MineAttack — UI & Art Revamp Context Brief

> Use this document as the single source of truth when iterating on new sprites, UI look-and-feel, menus, icons, and visual effects for **MineAttack**. It covers the game's theme, exact color values, current asset inventory, screen layouts, faction identities, weather/dynamic-event language, and technical constraints.
>
> **Project path:** `/Users/shumail/Documents/Projects/mine-attack`  
> **Engine:** Godot 4.7 (standard build, not .NET)  
> **Renderer:** `gl_compatibility`  
> **Language:** GDScript  
> **Target resolutions:** Logical UI designed at 1920×1080, project viewport is 2560×1440 with stretch scale 1.333.

---

## 1. Project Overview

**MineAttack** is a single-player 2D RTS. The player controls the blue **PLAYER** team on the left; a scripted AI controls the red **ENEMY** team on the right. The win condition is simple: destroy the enemy building before it destroys yours.

### Core gameplay loop
- Train miners, send them underground to dig ore.
- Ore funds an army of swordsmen, archers, wizards, dragons, and pigeon scouts.
- Right-click issues context orders (move, attack, mine, breach walls, climb ladders).
- Place lanterns, towers, walls, and traps from a radial/grid build menu.
- Research mutually-exclusive tech branches to specialize your strategy.
- Survive dynamic events: lava rising, cave-ins, snowstorms, and volcano eruptions.

### Inspirations
- **Stick War: Legacy** — unit training / army push loop.
- **SteamWorld Dig** — layered, upgrade-gated underground mining.
- **Frostpunk** — cold, post-apocalyptic, industrial-survival mood.

---

## 2. Core Theme & Mood

**Primary mood:** A frozen, desperate siege at the edge of a volcanic mine.

- **Surface:** Bleak tundra, pale ice, steel-grey fortifications, harsh winds, falling snow.
- **Underground:** Dark dirt tunnels, glowing ore veins, magma seams, lava floods, flickering lanterns.
- **UI feel:** Military-industrial, cold, functional, slightly worn. Think frost-covered steel consoles, stamped metal panels, glowing indicator lights, and emergency red warning strobes.
- **Contrast:** Cool blues/whites/steel greys dominate; warm gold/yellow/amber are used for economy, upgrades, and lantern light; red/orange signal danger (enemy, lava, volcano).

The UI should feel **diegetic** — like a command panel pulled from the same world as the units and buildings. Avoid clean glassy corporate UI; prefer **stamped metal, frost edges, rivets, worn paint, emergency tape, and glowing vacuum-tube-style readouts**.

---

## 3. Exact Color Palette

Colors are defined in code; preserve these hex values so existing gameplay feedback remains readable.

### Team colors (`scripts/autoload/game_manager.gd`)
| Role | Hex | Notes |
|------|-----|-------|
| Player / ally | `#3B82F6` | Bright blue — selection rings, friendly HP, top-bar accents. |
| Enemy | `#B91C1C` | Deep red — enemy units, enemy HP, danger. |

### Environment colors (`scripts/autoload/game_manager.gd`)
| Name | Hex | Usage |
|------|-----|-------|
| Ice | `#DCECF5` | Surface snow/ice highlights. |
| Steel | `#5A6570` | Steel structures, neutral metal. |
| Rust | `#C45C26` | Rusted enemy metal, worn industrial. |
| Deep Ice | `#3E5A6E` | Cold shadow tones, deep snow. |
| Shadow | `#1E252B` | Fog, deep shadow, silhouette color. |
| Dirt 1 | `#8B6F47` | Topsoil / upper dirt. |
| Dirt 2 | `#6B5637` | Mid dirt. |
| Dirt 3 | `#4A3B26` | Deep dirt. |

### Default clear color (`project.godot`)
- `#0F141E` (Color(0.06, 0.08, 0.12, 1)) — used when nothing else is drawn.

### UI palette (`scripts/ui/hud_styling.gd`)
| Role | Hex / Value | Notes |
|------|-------------|-------|
| Panel background | `rgba(12, 17, 27, 0.94)` | Dark blue-grey, almost opaque. |
| Panel border | `rgba(255, 255, 255, 0.08)` | Very subtle light edge. |
| Button normal | `#1a2434` | Standard command button. |
| Button hover | `#253650` | Mouse-over highlight. |
| Button pressed | `#111927` | Active/selected state. |
| Button disabled | `#151c29` | Greyed-out, low readability. |
| Button border | `rgba(255,255,255,0.07)` | Subtle edge. |
| Button hover border | `#4a86c8` | Bright blue hover outline. |
| Tab active | `#1f3a5c` | Surface/underground tabs, speed buttons. |
| Tab active border | `#4a86c8` | Same bright blue. |
| Upgrade background | `#272210` | Brown/gold “tech” button base. |
| Upgrade border | `#8a6d1f` | Dull gold border for upgrades. |
| Primary gold text | `#fbbf24` | Title highlights, upgrade text, key buttons. |
| Primary off-white text | `#e2e8f0` | Body text, labels. |
| Dim text | `#94a3b8` | Tooltips, secondary info. |

### Research panel colors (`scripts/ui/research_panel.gd`)
| Role | Hex | Notes |
|------|-----|-------|
| Maxed tech bg | `#14251a` | Dark green-ish. |
| Maxed tech border | `#3d7a4a` | Muted green. |
| Locked tech bg | `rgba(23, 26, 33, 0.65)` | Nearly transparent grey. |
| Locked tech border | `rgba(255,255,255,0.04)` | Barely visible. |
| Open edge | `#8a6d1f` | Gold connector lines. |
| Locked edge | `rgba(255,255,255,0.15)` | Grey connector lines. |
| Progress fill | `#8a6d1f` | Gold progress bar. |
| Progress bg | `#121a28` | Very dark blue. |

### Warning/event UI colors
| Event | Color | Notes |
|-------|-------|-------|
| Snowstorm warning text | `#ff4d3f` | Flashing red countdown. |
| Snowstorm vignette | `rgba(20, 40, 107, 0.55)` | Dark blue edge vignette. |
| Lava warning text | `#ff7f26` | Flashing orange countdown. |
| Volcano warning text | `#ff5926` | Red-orange countdown. |
| Volcano vignette | `rgba(166, 38, 13, 0.5)` | Red-orange edge vignette. |
| Fog color | `#05070a` | Pitch black fog tiles. |
| Fog memory overlay | `rgba(5, 7, 10, 0.7)` | Remembered tiles are 30 % brightness + 70 % fog. |

---

## 4. Visual Style & Art Direction

### Current style
- **Surface terrain:** Code-drawn (`grid_drawing.gd`) — flat colors, simple rectangles, ore sparkles.
- **Underground terrain:** Tile-based sprites (`frost_mines_assets/tiles/layer_1_tile.png` … `layer_7_tile.png`, `magma_rock.png`, `fresh_ore.png`).
- **Units:** Pixel-art character sprites (~48×72), side-facing, team-tinted player=blue, enemy=red.
- **Structures:** Placeable pixel-art props (lanterns, towers, walls) in `frost_mines_assets/props/`.
- **UI:** Mostly **flat StyleBoxFlat panels** generated in code; only the main menu currently uses textured buttons and panel background.

### Desired evolution
1. **Keep readability first** — the game is an RTS; the player must read unit counts, HP, coin, timers, and warnings at a glance.
2. **Unify the HUD with the main menu** — currently the HUD is flat code-drawn panels while the menu uses textured pixel-art buttons. The new UI kit should let both share a consistent “frosted steel console” language.
3. **Add tactile texture** — without hurting readability. Subtle brushed metal, frost rim-light, rivets, warning stripes, and recessed screw heads are welcome.
4. **Make faction identity stronger** — faction icons and menu colors are currently simple colored shapes; they should feel like distinct heraldry.
5. **Improve event legibility** — snowstorm/lava/volcano warnings should feel cinematic but not block the player’s view of the battlefield.
6. **Icon clarity** — many icons reuse unit sprites or are abstract shapes; a unified iconography set (coin, HP, attack, weather, abilities) would help.

---

## 5. UI Screens & Components Inventory

### 5.1 Main Menu (`scenes/ui/main_menu.tscn` → `scripts/ui/main_menu.gd`)
**Flow:** Title card → Difficulty select → Faction select → Play.

**Current layout:**
- Full-screen background: `surface_sky.png` (night sky) + `surface_ground.png` (snowy ground strip).
- Decorative sprites anchored to bottom: player building, enemy building, miner, swordsmen.
- Falling snow particle overlay (soft white dots).
- Centered card (`panel_background.png`, 300×200 source texture stretched).
- Card contains:
  - Title: **MINEATTACK** (64 px, off-white, heavy outline).
  - Subtitle: **FROST MINES** (18 px, gold `#fbbf24`).
  - Difficulty dropdown (`Easy / Normal / Hard / Nightmare / Godly`).
  - Resolution dropdown (desktop only).
  - **Next** primary button (textured `button_upgrade.png`).
  - **Quit** secondary button (textured `button_normal.png`).
  - Hint line at bottom.

**Faction select screen:**
- Title: **CHOOSE YOUR FACTION**.
- Three vertical cards side by side (260×320 each).
- Each card: faction icon (64×64), faction name, one-line description, 3 bullet highlights, **Select** button.
- Selected card gets a **gold border + glow**.
- Background particles tinted by selected faction:
  - Arcane: purple sparks `rgba(196, 133, 253, 0.55)`
  - Brute: red embers `rgba(247, 112, 112, 0.55)`
  - Industrial: yellow steam `rgba(250, 202, 54, 0.45)`

### 5.2 In-Game HUD (`scenes/ui/hud.tscn` → `scripts/ui/hud.gd` + helpers)
**Layout:** fixed top bar + fixed bottom bar + floating panels.

#### Top Bar
- Anchored top, full width.
- Left group:
  - Coin icon + coin amount.
  - Miner icon + miner upgrade level (`L1`, `L2`, `L3`).
  - Player faction icon.
- Center group:
  - Total unit count `current/max`.
  - Breakdown: Miner / Swordsman / Archer / Wizard / Dragon / Pigeon counts with small icons.
- Right group:
  - Player HP icon + player building HP.
  - Enemy HP icon + enemy building HP.
  - Enemy faction icon (hidden until scouted) + “Enemy: ???” label.
- Tabs row below:
  - **Surface** / **Underground** toggle buttons.
  - **Pause** toggle.
  - Speed buttons: **1× 2× 3× 5× 10×**.
- Selection readout label (e.g., “Selected: 0”, “Swordsman — HP 150/150”).

#### Bottom Bar
- Anchored bottom, full width.
- Left: **Upgrade Miner** button.
- Center-left: unit training buttons (Miner, Swordsman, Archer, Wizard, Dragon) — each shows icon, cost, train time.
- Center: stance buttons — **Attack**, **Defend**, **Garrison**, **Rally**.
- Right: **Kill** (disband selection), **Research** (R), **Build**.
- Upgrade buttons for swordsmen, archers, wizards, dragons sit between miner upgrade and unit buttons.

#### Floating panels / overlays
- **Research Panel** (`scripts/ui/research_panel.gd`): full-screen dim, centered card ~1040×900, scrollable research tree, active research progress bar, queue list, cancel/respec/scan buttons.
- **Training Queue Panel** (`scripts/ui/training_queue_panel.gd`): right-side vertical panel showing current training progress and queued/cancellable units.
- **Build Menu** (`scripts/ui/hud_menus.gd`): centered modal card 720×420, 3-column grid of build options (Lantern, Mine Lantern, Tower, Wall, Trap, Pigeon) with icon, cost, count/max.
- **Pause Menu** (`scripts/ui/hud_menus.gd`): full-screen dim with centered card, Resume / Restart / Quit to Menu + difficulty & resolution selectors.
- **Game Over Panel**: centered panel with VICTORY/DEFEAT, match time, units trained, coin mined.

#### Warning banners
- **Snowstorm warning**: top-center, snowstorm icon + red flashing text “SNOWSTORM IN Xs”.
- **Volcano warning**: top-center below snowstorm, lava icon + red-orange flashing text.
- **Lava warning**: bottom-center, lava icon + orange flashing text “LAVA RISING IN Xs”.
- **Faction identified popup**: center-screen panel, faction icon + “ENEMY FACTION IDENTIFIED: ARCANE/BRUTE/INDUSTRIAL”.

### 5.3 Layer Indicator (`scripts/ui/layer_indicator.gd`)
- Drawn in-world or in a small HUD slot.
- Shows 7 boxes labeled L1–L7.
- Accessible layers are filled blue `#3b82f6`; inaccessible layers are grey outline `#475569`.

---

## 6. Current Sprite Asset Inventory

All art lives under `frost_mines_assets/`. Sizes below are from the actual PNG files.

### UI textures (`frost_mines_assets/ui/`)
| File | Size | Current usage |
|------|------|---------------|
| `panel_background.png` | 300×200 | Main menu card background, stretched via StyleBoxTexture. |
| `button_normal.png` | 100×70 | Main menu secondary buttons. |
| `button_hover.png` | 100×70 | Hover state. |
| `button_pressed.png` | 100×70 | Pressed state. |
| `button_upgrade.png` | 200×44 | Primary “Next / Play” buttons. |
| `hp_bar_bg.png` | 120×8 | Building HP bar background. |
| `hp_bar_green.png` | 120×8 | Player building HP fill. |
| `hp_bar_red.png` | 120×8 | Enemy building HP fill. |
| `hp_bar_unit_bg.png` | 32×4 | Unit HP bar background. |
| `hp_bar_unit_green.png` | 32×4 | Friendly unit HP fill. |
| `hp_bar_unit_orange.png` | 32×4 | Enemy unit HP fill (or wounded state). |

### Icons (`frost_mines_assets/icons/`)
| File | Size | Usage |
|------|------|-------|
| `icon_coin.png` | 16×16 | Coin amount in top bar. |
| `icon_miner.png` | 16×16 | Miner level, unit breakdown. |
| `icon_swordsman.png` | 16×16 | Unit breakdown. |
| `icon_archer.png` | 16×16 | Unit breakdown, Longbow/Rapid Fire tech icons. |
| `icon_wizard.png` | 16×16 | Unit breakdown. |
| `icon_dragon.png` | 16×16 | Unit breakdown, Dragon Mastery branch icons. |
| `icon_hp.png` | 16×16 | Building HP. |
| `icon_attack.png` | 16×16 | Attack stance button. |
| `icon_building.png` | 16×16 | Fortification / Citadel / Deep Fortress tech icons. |
| `icon_lava.png` | 48×48 | Lava warning banner, Volcano warning banner. |
| `icon_snowstorm.png` | 48×48 | Snowstorm warning banner, weather tech icons. |
| `icon_weather_alert.png` | 48×48 | Weather Alert tech icon. |
| `faction_arcane.png` | 64×64 | Faction select card + top bar. |
| `faction_brute.png` | 64×64 | Faction select card + top bar. |
| `faction_industrial.png` | 64×64 | Faction select card + top bar. |
| `button_build_lantern.png` | 80×40 | Build menu lantern icon (currently unused — code loads prop sprites instead). |
| `button_build_tower.png` | 80×40 | Build menu tower icon (currently unused). |
| `button_build_wall.png` | 80×40 | Build menu wall icon (currently unused). |

### Placeable structure props (`frost_mines_assets/props/`)
| File | Size | Usage |
|------|------|-------|
| `lantern_t1.png` | 32×48 | Surface lantern tier 1. |
| `lantern_t2.png` | 32×56 | Surface lantern tier 2. |
| `lantern_t3.png` | 40×64 | Surface lantern tier 3. |
| `lantern_underground.png` | 24×32 | Underground lantern. |
| `tower_player.png` | 48×72 | Player sentry tower. |
| `tower_enemy.png` | 48×72 | Enemy sentry tower. |
| `wall_player.png` | 32×32 | Player wall segment. |
| `wall_enemy.png` | 32×32 | Enemy wall segment. |
| `wall_segment.png` | 80×100 | Central map wall. |
| `mine_entry.png` | 60×80 | Mine shaft entrance. |

### Backgrounds (`frost_mines_assets/backgrounds/`)
| File | Usage |
|------|-------|
| `surface_sky.png` | Main menu night sky. |
| `surface_ground.png` | Main menu snowy ground strip. |
| `underground_base.png` | Underground backdrop. |

### Effects (`frost_mines_assets/effects/`)
| File | Usage |
|------|-------|
| `fog_surface.png` / `fog_underground.png` | Fog of war overlay sprites. |
| `selection_ring.png` | Unit selection ring. |
| `coin_sparkle.png` | Coin pickup sparkle. |
| `impact_hit.png` | Melee impact. |
| `projectile_arrow.png` | Arrow projectile. |
| `projectile_blast.png` | Fireball / magic blast. |

### Tech icons (`improvements/mine_attack_sprites/`)
Several research-tree icons currently live here rather than in `frost_mines_assets/icons/`:
- `tech_deep_delve.png`
- `tech_surface_war.png`
- `tech_ore_sonar.png`
- `tech_reinforced_pack.png`
- `tech_crystal_forge.png`
- `tech_siege_master.png`

---

## 7. Faction Visual Identity

Factions are chosen at match start; the enemy faction is hidden until scouted. Each faction has a `menu_color` used for borders, names, and the identified popup.

### Arcane
- **Name:** Arcane
- **Description:** “Magic enhances all units. Fragile but powerful abilities.”
- **Menu color:** `#AF84FB` (Color(0.686, 0.518, 0.984, 1))
- **Personality:** Glass-cannon, mystical, rune-inscribed, violet/white energy.
- **Visual cues:** Subtle glow effects on units, wizards appear earlier, arcane runes on buildings.
- **Ability keywords:** Rune Blade, Arcane Shot, Blink, Miner Reveal, Mana Burn.

### Brute
- **Name:** Brute
- **Description:** “Raw combat power. Tanky units, slow economy.”
- **Menu color:** `#DF6B6B` (Color(0.875, 0.42, 0.42, 1))
- **Personality:** Heavy, savage, blood-red, iron-clad, berserker rage.
- **Visual cues:** Larger/tankier swordsmen, slower movement, spiked/rough metal.
- **Ability keywords:** Berserk, Heavy Bolt, Fortify, Fight Back, Crush.

### Industrial
- **Name:** Industrial
- **Description:** “Superior economy and production. Weak units, strong attrition.”
- **Menu color:** `#FBBF24` (Color(0.984, 0.749, 0.141, 1))
- **Personality:** Steam, brass, gears, smokestacks, mass production.
- **Visual cues:** More miners early, buildings emit steam/smoke, cheaper gear.
- **Ability keywords:** Swarm, Volley, Supply Drop.

### Faction icon requirements
- Need **large** versions for faction-select cards (64×64 minimum, ideally 128×128 for crispness).
- Need **small** versions for the top-bar (24×24 minimum).
- Need **silhouette / “unknown”** version for the enemy before identification (currently shows “???” text; a greyed-out mystery heraldry would be nicer).
- Icons should read clearly at small size and be distinct at a glance.

---

## 8. Weather & Dynamic Event Visual Language

The game has three major environmental hazards. Their UI must communicate urgency without obscuring the battlefield.

### Snowstorm
- **Warning:** 5 s (or 12 s with Weather Alert research) — red flashing countdown, snowstorm icon.
- **Active:** 15 s — heavy angled snowfall, surface vision halved, surface units slowed, exposure damage outside lantern radius.
- **UI needs:**
  - Warning banner: red text, snowflake/blizzard icon.
  - Active vignette: dark blue radial gradient closing in from edges.
  - Frost overlay on exposed units: currently a simple blue tint; could be ice crystals on the unit sprite.
  - Shelter indicator: a subtle ring around lanterns showing “safe zone”.

### Lava Rising
- **Warning:** 5 s (or 12 s with Weather Alert) — orange flashing countdown, lava icon.
- **Active:** Lava creeps up from bottom 1–2 layers over ~8 s, holds, then recedes over ~8 s.
- **Effect:** Instantly kills units in flooded cells, destroys underground lanterns, converts cells to indestructible lava, then to diggable magma rock / fresh ore.
- **UI needs:**
  - Warning banner: orange text, lava/fire icon.
  - Screen shake + pulsing red glow at bottom layers.
  - A “tide height” indicator or bottom-edge heat glow would be useful.

### Volcano Eruption
- **Warning:** 7 s — red-orange countdown, lava/meteor icon.
- **Active:** ~18 s — meteors rain across surface, leaving burning ground patches.
- **Effect:** Meteor impact damage + burn DOT; existing volcano fires extinguished if a snowstorm starts.
- **UI needs:**
  - Warning banner: red-orange text, volcano/meteor icon.
  - Active vignette: red-orange radial gradient from edges.
  - Meteor warning marker/impact flash on ground.

### Cave-ins
- **Effect:** Sudden 3×3 underground collapse, no warning unless Weather Alert research is owned (3 s heads-up).
- **UI needs:** A small shake + debris dust burst; optional mini-warning icon if research is bought.

---

## 9. Sprite / Art Requests & Redesign Checklist

Below is a prioritized list of what would improve the look most. Sizes are **suggested**; Godot will stretch, but powers-of-two and multiples of the tile size (32 px) work best.

### 9.1 High-priority UI kit
Create a consistent texture-based UI kit to replace or supplement the flat StyleBoxFlat panels.

| Asset | Suggested size | Description |
|-------|----------------|-------------|
| `ui/panel_metal.png` | 256×256 (9-slice) | Main panel background — brushed steel with frost rim, rivets, subtle inner shadow. |
| `ui/panel_metal_dark.png` | 256×256 (9-slice) | Darker variant for modals / game-over. |
| `ui/button_primary_normal.png` | 200×60 (9-slice) | Gold-accented primary button (Play, Next). |
| `ui/button_primary_hover.png` | 200×60 | Brighter gold hover. |
| `ui/button_primary_pressed.png` | 200×60 | Inset / darker pressed. |
| `ui/button_secondary_normal.png` | 160×48 (9-slice) | Steel secondary button. |
| `ui/button_secondary_hover.png` | 160×48 | Blue-glow hover. |
| `ui/button_secondary_pressed.png` | 160×48 | Inset pressed. |
| `ui/button_upgrade_normal.png` | 120×70 (9-slice) | Brown/gold upgrade button base. |
| `ui/button_upgrade_hover.png` | 120×70 | Brighter gold. |
| `ui/button_upgrade_pressed.png` | 120×70 | Darker pressed. |
| `ui/button_danger_normal.png` | 100×70 (9-slice) | Red “Kill / disband” button. |
| `ui/tab_inactive.png` | 90×32 (9-slice) | Inactive tab. |
| `ui/tab_active.png` | 90×32 | Active tab with blue underline/accent. |
| `ui/progress_bar_bg.png` | 120×14 (tiled/9-slice) | Progress bar background. |
| `ui/progress_bar_fill_gold.png` | 120×14 | Gold fill (research / upgrades). |
| `ui/progress_bar_fill_blue.png` | 120×14 | Blue fill (training queue). |
| `ui/progress_bar_fill_red.png` | 120×14 | Red fill (enemy HP). |
| `ui/progress_bar_fill_green.png` | 120×14 | Green fill (friendly HP). |
| `ui/scrollbar_track.png` | 8×64 | Scrollbar track for research tree. |
| `ui/scrollbar_grabber.png` | 8×32 | Scrollbar grabber. |

### 9.2 Icons (unified set, crisp at 24×24)
| Asset | Size | Description |
|-------|------|-------------|
| `icons/icon_coin.png` | 32×32 | Gold coin, readable at 18×18. |
| `icons/icon_miner.png` | 32×32 | Pickaxe + helmet. |
| `icons/icon_swordsman.png` | 32×32 | Sword. |
| `icons/icon_archer.png` | 32×32 | Bow. |
| `icons/icon_wizard.png` | 32×32 | Staff / magic orb. |
| `icons/icon_dragon.png` | 32×32 | Wing / dragon head. |
| `icons/icon_pigeon.png` | 32×32 | Bird / message scroll. |
| `icons/icon_hp.png` | 32×32 | Heart / building shield. |
| `icons/icon_attack.png` | 32×32 | Crossed swords or charge arrow. |
| `icons/icon_defend.png` | 32×32 | Shield. |
| `icons/icon_garrison.png` | 32×32 | Mine shaft / pickaxe. |
| `icons/icon_rally.png` | 32×32 | Flag / waypoint. |
| `icons/icon_kill.png` | 32×32 | Skull / red X. |
| `icons/icon_research.png` | 32×32 | Book / gear / beaker. |
| `icons/icon_build.png` | 32×32 | Hammer / construction. |
| `icons/icon_lava.png` | 32×32 | Lava warning. |
| `icons/icon_snowstorm.png` | 32×32 | Snow warning. |
| `icons/icon_volcano.png` | 32×32 | Volcano/meteor warning. |
| `icons/icon_weather_alert.png` | 32×32 | Weather Alert tech. |
| `icons/icon_speed_1x.png` … `icon_speed_10x.png` | 24×24 | Speed button icons (optional). |

### 9.3 Faction heraldry
| Asset | Size | Description |
|-------|------|-------------|
| `icons/faction_arcane.png` | 128×128 + 64×64 + 32×32 | Rune/glowing eye/crystal motif, purple. |
| `icons/faction_brute.png` | 128×128 + 64×64 + 32×32 | Spiked helm/blood drop/axe motif, red. |
| `icons/faction_industrial.png` | 128×128 + 64×64 + 32×32 | Gear/smokestack/brass motif, gold. |
| `icons/faction_unknown.png` | 64×64 | Greyed-out mystery heraldry for un-scouted enemy. |

### 9.4 Warning banners & overlays
| Asset | Size | Description |
|-------|------|-------------|
| `ui/banner_warning_top.png` | 512×64 (9-slice) | Top-center warning banner backing (red/orange emergency light strip). |
| `ui/banner_warning_bottom.png` | 512×64 (9-slice) | Bottom-center warning banner backing. |
| `ui/vignette_snowstorm.png` | 512×512 | Radial dark-blue vignette texture. |
| `ui/vignette_volcano.png` | 512×512 | Radial red-orange vignette texture. |
| `ui/overlay_frost.png` | 256×256 tileable | Frost edge overlay for exposed units / screen corners during storms. |

### 9.5 Placeable structures (props)
Current props are functional but could be more atmospheric. Keep sizes close to existing to avoid re-layout.

| Asset | Size | Description |
|-------|------|-------------|
| `props/lantern_t1.png` | 32×48 | Small campfire / brazier on post. |
| `props/lantern_t2.png` | 32×56 | Enclosed iron lantern, wider glow. |
| `props/lantern_t3.png` | 40×64 | Industrial floodlight tower, beam effect. |
| `props/lantern_underground.png` | 24×32 | Small mounted torch / glow-crystal for tunnels. |
| `props/tower_player.png` | 48×72 | Blue-grey stone/wood sentry tower with archer silhouette. |
| `props/tower_enemy.png` | 48×72 | Red-brown / spiked variant. |
| `props/wall_player.png` | 32×32 | Grey stone block segment. |
| `props/wall_enemy.png` | 32×32 | Brown wooden stake / spiked barricade. |
| `props/trap.png` | 32×32 | Hidden spike trap (mostly invisible; a subtle blur or pressure plate). |

### 9.6 Menu backgrounds
| Asset | Size | Description |
|-------|------|-------------|
| `backgrounds/surface_sky.png` | 1920×1080+ | Night sky with aurora / distant volcano / falling snow. |
| `backgrounds/surface_ground.png` | 1920×256 | Snowy ground strip with footprints / fortifications. |
| `backgrounds/menu_faction_arcane.png` | 1920×1080 | Arcane-themed variant background (optional). |
| `backgrounds/menu_faction_brute.png` | 1920×1080 | Brute-themed variant background (optional). |
| `backgrounds/menu_faction_industrial.png` | 1920×1080 | Industrial-themed variant background (optional). |

---

## 10. Technical Constraints

1. **Godot 4.7, GL Compatibility renderer.** Keep textures reasonably small; the game targets web, macOS, and Windows.
2. **No external package manager.** Do not introduce new tools or dependencies. Deliver PNG files only.
3. **Pixel-art scaling.** Godot’s TextureRect uses `STRETCH_KEEP_ASPECT_CENTERED` + `EXPAND_FIT_HEIGHT` or `EXPAND_IGNORE_SIZE`. Textures should look crisp when scaled by integer multiples.
4. **9-slice friendly.** For panels/buttons that stretch, provide 9-slice guides or keep borders simple enough that StyleBoxTexture can stretch them cleanly.
5. **Color consistency.** The exact team/enemy/faction colors are gameplay-critical. Tinting can be applied in Godot, but base sprites should align with the palette.
6. **Transparency.** UI panels can be semi-transparent but must remain readable over busy backgrounds (surface + underground + units).
7. **Mouse filtering.** UI elements that should not block clicks on the world (top/bottom bars, banners) use `MOUSE_FILTER_IGNORE`; buttons must remain clickable.
8. **No animated textures required.** Most UI is static; animations are done via code (modulate pulses, tweens, particles). Provide frames only if asked.

---

## 11. Layout & Typography Notes

- **Logical UI resolution:** 1920×1080. The top and bottom bars are full-width fixed strips.
- **Main menu card:** ~460 px wide, centered, with 40 px margins.
- **Faction select cards:** 260×320 px each, arranged horizontally with 16 px gaps.
- **Research tree card:** ~1040×900 px centered, with a 520 px tall scrollable canvas.
- **Build menu card:** 720×420 px centered grid.
- **Font:** Godot default theme font. All text size overrides are in code; larger title text uses outline (`font_outline_color` + `outline_size`) for readability over busy backgrounds.
- **Icon-in-label pattern:** Icons are placed as small `TextureRect` children before labels, sized 18×18 to 26×26.

---

## 12. References & Inspirations

- **Frostpunk** — cold industrial UI, radial dials, warning lamps, steel panels.
- **Into the Breach** — clean, readable tactical UI with strong iconography.
- **StarCraft / Warcraft 3** — bottom command card with unit portraits, resource readouts, minimap area.
- **SteamWorld Dig** — layered mining, ore glow, lantern light.
- **Stick War: Legacy** — simple unit training buttons and army rally flow.

---

## 13. Non-Goals / Things to Preserve

- **Do not change team colors** (blue/red) — they are hard-coded and central to readability.
- **Do not change faction menu colors** unless improving them within the same hue.
- **Do not remove flat UI code** entirely — provide textures that can be swapped in via StyleBoxTexture or new theme overrides.
- **Do not redesign units or terrain tiles** unless explicitly requested; focus on UI, icons, menus, and props.
- **Do not add new fonts** unless they are open-licensed and web-safe; the project currently uses the Godot default font.

---

## 14. Quick-Start Prompt for Sprite Iteration

When handing this to a sprite/UI artist, you can lead with:

> “We’re revamping the UI for MineAttack, a 2D RTS set in a frozen post-apocalyptic mine siege. The game uses Godot 4.7 with a GL compatibility renderer. Please produce a cohesive ‘frosted steel console’ UI kit (panels, buttons, progress bars, icons) plus improved faction heraldry and warning overlays. Preserve the exact color palette in Section 3, especially team blue `#3B82F6`, enemy red `#B91C1C`, and the three faction colors. All assets should be PNGs, crisp at small sizes, and 9-slice friendly. See Section 9 for the full checklist.”

---

*Document generated from the live MineAttack codebase. For implementation details, see `improvements/revamp.md` and `AGENTS.md`.*
