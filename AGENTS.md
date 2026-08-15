# Agent Guide: MineAttack

MineAttack is a single-player 2D RTS built in Godot 4.7. The player controls the blue **PLAYER** team on the left; a scripted AI controls the red **ENEMY** team on the right. Win condition: destroy the enemy building.

## Technology stack

- **Engine:** Godot 4.7
- **Renderer:** `gl_compatibility`
- **Physics:** Jolt Physics
- **Language:** GDScript (static typing where practical)
- **Targets:** Web, macOS, Windows
- **Key configs:** `project.godot`, `export_presets.cfg`

## Project structure

```
mine-attack/
├── project.godot / export_presets.cfg / icon.svg / README.md
├── scenes/                    # Godot scenes (.tscn)
│   ├── main.tscn              # Root gameplay scene
│   ├── building.tscn / mine_entry.tscn / projectile.tscn / unit.tscn
│   ├── lantern.tscn / tower.tscn / wall_segment.tscn / trap.tscn
│   ├── ui/                    # main_menu, hud, debug_overlay
│   └── effects/               # coin_popup, damage_popup, coin_pickup, reject_popup, burning_ground
├── scripts/
│   ├── autoload/      # constants, game_manager, economy_manager, faction_manager, research_manager, debug_log, audio_manager, settings_manager, weather_manager
│   ├── controllers/   # ai_controller, player_controller + helper modules
│   ├── resources/     # unit_data.gd, faction_data.gd, units/*.tres, factions/*.tres
│   ├── ui/            # hud + helper modules, debug_overlay, layer_indicator, training_queue_panel, research_panel, unit_button, main_menu
│   ├── effects/       # coin_popup, damage_popup, burning_ground
│   ├── units/         # unit.gd + helper modules, projectile.gd
│   └── world/         # grid_world.gd + helper modules, building.gd, mine_entry.gd, lantern.gd, tower.gd, wall_segment.gd, trap.gd
├── tests/             # GUT test suite
└── improvements/      # revamp.md + new sprites
```

**Implemented revamp phases:** Phase 1 (Fog of War & lanterns), Phase 2 (factions), Phase 3 (towers & walls), Phase 4 (dynamic terrain: lava rising, cave-ins, ore depletion), Phase 5 (weather: snowstorms), Phase 6 (tech-tree overhaul: mutually-exclusive research branches, respec, traps, burning ground), Phase 7 (UI & menu updates: faction-select glow + themed particles, enemy-faction "???" top-bar indicator + identified popup, radial build menu, red weather warning), Phase 8 (AI refactor: AIBeliefSystem autoload, faction scouting, AI lantern placement, weather/lava responses, faction-specific strategies).

## Runtime architecture

`scenes/ui/main_menu.tscn` is the main scene. Its Play button sets `GameManager.difficulty` and loads `scenes/main.tscn`, which contains:

- `World/GridWorld` — procedural map, A*, fog of war, rendering.
- `World/PlayerBuilding` / `World/EnemyBuilding` — bases.
- `World/PlayerMineEntry` / `World/EnemyMineEntry` — mine shafts.
- `Camera2D` — player camera (pan/zoom handled by `PlayerController`).
- `Units` / `Projectiles` / `Structures` — runtime containers.
- `PlayerController` / `AIController` — input and AI.
- `UI/HUD` — top/bottom bars, queue panel, pause/build menus, game-over panel.

Autoloads (load order): `Constants`, `GameManager`, `FactionManager`, `EconomyManager`, `ResearchManager`, `DebugLog`, `AudioManager`, `SettingsManager`, `WeatherManager`, `AIBeliefSystem`.

## Code organization

### `scripts/autoload/`

Global singletons.

- `constants.gd` — balance numbers, costs, train times, upgrade tables, vision/fog constants, dynamic-terrain event tuning (`LAVA_*`/`CAVEIN_*`/`MAGMA_*`/`ORE_*`), weather tuning (`SNOWSTORM_*`), research branch tree (`RESEARCH_TECHS`) and branch-effect tuning (`SURFACE_WAR_*`, `BURNING_GROUND_*`, `TRAP_*`, `GUERRILLA_*`, `SIEGE_MASTER_*`), input action `StringName`s. Source of truth for all numeric balance.
- `game_manager.gd` — `Team`/`Difficulty` enums, team colors, difficulty modifiers, game speed, match timer, win/loss.
- `faction_manager.gd` — faction picks, hidden-faction identification, faction-modified costs and starting bonuses.
- `economy_manager.gd` — coin, population, miner/fighter upgrade levels, units trained, coin mined.
- `research_manager.gd` — timed branch research tree (Phase 6): mutually-exclusive tiers where completing a tech permanently locks its alternative, one-time 500g respec, active research slot, Ore Sonar scan.
- `audio_manager.gd` — synthesized SFX and ambience.
- `settings_manager.gd` — window resolution persistence (desktop only).
- `weather_manager.gd` — Phase 5 snowstorms: game-time state machine (warning → storm), vision/speed multipliers, lantern-shelter exposure damage, frost overlay flags, storm wind/ice-crack audio. Random scheduling can be disabled via `WeatherManager.set_weather_events_enabled(false)` (tests force storms instead).
- `ai_belief_system.gd` — Phase 8: per-team belief maps (cells/unit sightings/enemy-faction guess) built only from that team's vision; confidence decays on stale intel. `update_belief_from_vision`, `get_believed_enemy_army`, `infer_enemy_faction`. Reset per match via `AIBeliefSystem.reset()` (HUD reset flows).

### `scripts/controllers/`

The controllers are split into thin main classes plus `RefCounted` helper modules that own related logic.

- `player_controller.gd` — exports, input routing, camera/view state, stance/build mode state; delegates to helpers.
  - `player_selection.gd` — single/box selection and unit/building picking.
  - `player_commands.gd` — right-click command resolution, train/upgrade/kill callbacks, stance/rally application.
  - `player_camera.gd` — zoom, pan, view bookmarks, screen shake.
  - `player_build_placement.gd` — lantern/tower/wall/trap placement ghost and validation.
- `ai_controller.gd` — tick fields, aggression state, scout memory; delegates to helpers.
  - `ai_economy.gd` — economy decisions, training (faction-flavored army mix, Phase 8), upgrades, research (faction branch preferences), miner culling.
  - `ai_mining.gd` — miner task assignment and ore selection (skips miners under shelter orders).
  - `ai_combat.gd` — attack waves, base defense, wall breach.
  - `ai_smart_behaviors.gd` — focus fire, wounded retreat, harassment, bait, combat predictor, aggression (Brute pushes on a slimmer lead).
  - `ai_awareness.gd` — Phase 8: faction scouting (swordsman at 1:00, 30s retry after it dies), defensive lantern placement/upgrades, snowstorm miner recall and lava evacuation (signal-driven, same warnings as the player; sheltered miners hold via `unit.shelter_in_place`).

### `scripts/world/`

- `grid_world.gd` — `Cell` inner class, `CellType` enum, signals, grid/A* state, fog maps; delegates to helpers.
  - `grid_map_generation.gd` — map generation and A* initialization.
  - `grid_pathfinding.gd` — `find_path`, walkability helpers, wall cell sealing.
  - `grid_fog_of_war.gd` — vision maps, memory, ghost silhouettes, fog rendering.
  - `grid_drawing.gd` — surface/underground terrain drawing, effects, wall HP bar.
  - `grid_mining.gd` — cell damage, mining, ore reveal, ore depletion trickle.
  - `grid_ambience.gd` — snow/dust particles, plus the storm snow burst toggled by WeatherManager signals (Phase 5).
  - `grid_events.gd` — Revamp Phase 4 dynamic terrain: lava rising (warning → flood bottom 1–2 layers → recede into magma rock/fresh ore), cave-ins (3×3 SOLID_ROCK for 10s, 50 damage + push — Reinforced Pack miners take the damage but not the push), ore vein respawn. Game-time timers frozen on pause/game-over; random scheduling can be disabled via `GridWorld.set_dynamic_events_enabled(false)` (tests force events instead).
- `building.gd` — training queue, deposits, building HP/destruction (Earth Shield `building_hp` bonus recomputed on research changes), faction identification polling (both directions since Phase 8: opposing units within `IDENTIFY_RANGE_CELLS` identify that building's faction).
- `mine_entry.gd` — ladder teleport positions.
- `lantern.gd` / `tower.gd` / `wall_segment.gd` / `trap.gd` — placeable structures.

### `scripts/units/`

- `unit.gd` — state enum, exported data, `_ready`/`_process`/`_draw`, public command/combat API; delegates to helpers.
  - `unit_commands.gd` — move, attack, mine, deposit, climb, stop, kill, garrison, rally commands.
  - `unit_combat.gd` — damage, retaliation, projectiles, DPS window.
  - `unit_mining.gd` — idle miner handling, ore seeking, exhausted/blacklist logic.
  - `unit_navigation.gd` — path following, repathing, separation, kiting, flee, walkability.
  - `unit_abilities.gd` — faction abilities (blink, volley, swarm, rune blade, berserk, arcane shot, heavy bolt, crush, mana burn, miner reveal, supply drop, fight back).
  - `unit_vision_targeting.gd` — vision radii, auto-attack target selection, splash targeting.
  - `unit_rendering.gd` — sprites, pickaxe animation, HP bar, cargo, selection ring.
  - `unit_idle.gd` — idle fighter/miner behavior, rally hunt, patrol, return-to-post.
- `projectile.gd` — arrows/fireballs.

### `scripts/ui/`

- `hud.gd` — node references, signal wiring, game-over flow, lava warning banner (Phase 4), weather warning banner + storm vignette (Phase 5), faction-identified popup (Phase 7); delegates to helpers.
  - `hud_styling.gd` — StyleBoxFlat helpers and panel/button styling.
  - `hud_menus.gd` — pause menu and radial build menu (options fan out above the Build button; icons, costs, grayed out when unaffordable/at max count).
  - `hud_updates.gd` — label/button synchronization, faction icons + "Enemy: ???" indicator, selection readout.
- `main_menu.gd` — title/difficulty/faction select (Phase 7: selected card gets a gold glow; faction-colored particles drift behind the select screen).
- `research_panel.gd` — research branch-tree overlay (diverging layout, locked branches grayed with tooltips, respec button).
- `training_queue_panel.gd` — vertical training queue.
- `unit_button.gd` — training buttons.
- `layer_indicator.gd` — underground layer accessibility indicator.

## Development conventions

- **Language:** English for code, comments, docs.
- **Typing:** Prefer static types on function signatures.
- **Naming:** `snake_case` files/functions/variables; `PascalCase` classes/scene nodes; `_` prefix for private members.
- **Autoloads:** Global systems live in `scripts/autoload/`.
- **Resources:** Unit/faction stats are `.tres` resources.
- **Groups:** `units`, `player`, `enemy`, `buildings`, `mine_entries`, `lanterns`, `towers`, `walls`, `traps`.
- **Drawing:** Surface is code-drawn; underground uses tile sprites.

## Input map (highlights)

- `lmb` / `rmb` — select / command
- `Ctrl+A/M/F/D` — select all/miners/fighters/dragons
- `1`–`5` — train miner/swordsman/archer/wizard/dragon
- `Tab` — toggle surface/underground camera bookmark
- `R` — toggle research panel
- `K` / `Delete` — disband selection
- `Space` / `Esc` — pause

## Build, run, and export

Run in editor: open project root in Godot 4.7+ and press F5.

Run tests headless:

```bash
/Users/shumail/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Export all presets:

```bash
GODOT=/Users/shumail/Downloads/Godot.app/Contents/MacOS/Godot tools/export_all.sh
```

Export presets: `Web` → `build/MineAttack.html`, `macOS` → `build/MineAttack.app`, `Windows` → `build/MineAttack.exe`.

## Common gotchas

- **Hard-coded paths:** Several scripts use `get_node("/root/Main/...")`. Do not rename `Main` or its children without updating these.
- **A* offset:** `GridWorld._astar.offset = CELL_SIZE * 0.5`. Path points are cell centers; movement code relies on this.
- **Ladders are vertical:** `MineEntry` uses the shaft column center; climb states rely on the ladder column check.
- **Building footprint writes `_cells` directly:** `building.gd` mutates `GridWorld._cells` and `_astar` directly.
- **Resources duplicated at spawn:** `building.gd` calls `data.duplicate(true)` so each unit gets mutable `UnitData`.
- **Autoloads survive scene reload:** `hud.gd` resets `GameManager`, `FactionManager`, `EconomyManager`, `ResearchManager`, `WeatherManager`, `AIBeliefSystem` on restart/quit-to-menu (and `WeatherManager` + `AIBeliefSystem` again in `hud._ready`, since `GameManager.match_time` accumulates through the main menu).
- **Test harness teardown:** free `main.tscn` immediately with `_main.free()` in `after_all`, not `queue_free()`, to avoid node-name collisions.
- **Web full-bleed:** web export uses custom head include for canvas sizing.
- **Viewport stretch:** logical UI is 1920×1080; camera base zoom adapts to physical window size.

## Useful files to read first

`project.godot` → `scenes/main.tscn` → `scripts/autoload/game_manager.gd` + `economy_manager.gd` → `scripts/world/grid_world.gd` → `scripts/units/unit.gd` → `scripts/controllers/player_controller.gd` + `ai_controller.gd`.

For implementation details, see `improvements/revamp.md`.
