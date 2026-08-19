# Agent Guide: MineAttack

MineAttack is a single-player 2D RTS built in Godot 4.7. The player controls the blue **PLAYER** team on the left; a scripted AI controls the red **ENEMY** team on the right. Win condition: destroy the enemy building before it destroys yours.

## Technology stack

- **Engine:** Godot 4.7 (standard build, not .NET)
- **Renderer:** `gl_compatibility`
- **Physics:** Jolt Physics
- **Language:** GDScript (static typing preferred on function signatures)
- **Targets:** Web, macOS, Windows
- **Key configs:** `project.godot`, `export_presets.cfg`
- **Testing:** GUT (bundled in `addons/gut/`)
- **No external package manager** — no `package.json`, `Cargo.toml`, `pyproject.toml`, etc.

## Project structure

```
mine-attack/
├── project.godot / export_presets.cfg / icon.svg / README.md / AGENTS.md
├── scenes/                    # Godot scenes (.tscn)
│   ├── main.tscn              # Root gameplay scene
│   ├── building.tscn / mine_entry.tscn / projectile.tscn / unit.tscn
│   ├── ladder.tscn
│   ├── lantern.tscn / tower.tscn / wall_segment.tscn / trap.tscn
│   ├── ui/                    # main_menu, hud, debug_overlay
│   └── effects/               # coin_popup, damage_popup, coin_pickup,
│                              # reject_popup, burning_ground, meteor, volcano_background
├── scripts/
│   ├── autoload/      # constants, game_manager, economy_manager, faction_manager,
│                      # research_manager, debug_log, audio_manager, settings_manager,
│                      # weather_manager, ai_belief_system
│   ├── controllers/   # ai_controller, player_controller + helper modules
│   ├── resources/     # unit_data.gd, faction_data.gd, units/*.tres, factions/*.tres
│   ├── ui/            # hud + helper modules, debug_overlay, layer_indicator,
│                      # training_queue_panel, research_panel, unit_button, main_menu
│   ├── effects/       # coin_popup, damage_popup, coin_pickup, reject_popup,
│                      # burning_ground, meteor, volcano_background
│   ├── units/         # unit.gd + helper modules, projectile.gd, unit_pigeon.gd
│   └── world/         # grid_world.gd + helper modules, building.gd, mine_entry.gd,
│                      # ladder.gd, lantern.gd, tower.gd, wall_segment.gd, trap.gd
├── tests/             # GUT test suite (~25 test scripts)
├── tools/             # export_all.sh, serve_web.py
├── .githooks/         # pre-push release hook
└── improvements/      # revamp.md + new sprites
```

**Implemented revamp phases:** Phase 1 (Fog of War & lanterns), Phase 2 (factions), Phase 3 (towers & walls), Phase 4 (dynamic terrain: lava rising, cave-ins, ore depletion), Phase 5 (weather: snowstorms), Phase 6 (tech-tree overhaul: mutually-exclusive research branches, respec, traps, burning ground), Phase 7 (UI & menu updates: faction-select glow + themed particles, enemy-faction "???" top-bar indicator + identified popup, radial build menu, red weather warning), Phase 8 (AI refactor: AIBeliefSystem autoload, faction scouting, AI lantern placement, weather/lava responses, faction-specific strategies), Phase 9 (volcano weather event: background volcano, eruption warnings, meteors, burn patches, snowstorm extinguishing, lava-time acceleration).

## Runtime architecture

`scenes/ui/main_menu.tscn` is the main scene (`project.godot` → `application/run/main_scene`). Its Play flow sets `GameManager.difficulty`, stores the player's faction pick, rolls a random enemy faction, and loads `scenes/main.tscn`, which contains:

- `World/VolcanoBackground` — decorative volcano sprite.
- `World/GridWorld` — procedural map, A*, fog of war, rendering.
- `World/PlayerBuilding` / `World/EnemyBuilding` — bases.
- `World/PlayerMineEntry` / `World/EnemyMineEntry` — mine shafts.
- `World/Ladders` — runtime container for ladder nodes.
- `Camera2D` — player camera (pan/zoom handled by `PlayerController`).
- `Units` / `Projectiles` / `Structures` — runtime containers.
- `PlayerController` / `AIController` — input and AI.
- `UI/HUD` — top/bottom bars, queue panel, pause/build menus, game-over panel.
- `DebugOverlay` — runtime debug overlay.

Autoloads (load order from `project.godot`): `Constants`, `GameManager`, `FactionManager`, `EconomyManager`, `ResearchManager`, `DebugLog`, `AudioManager`, `SettingsManager`, `WeatherManager`, `AIBeliefSystem`.

## Code organization

### `scripts/autoload/`

Global singletons. All hold per-match state that survives scene reloads; `hud.gd` resets them on Play Again / Quit to Menu.

- `constants.gd` — balance numbers, costs, train times, upgrade tables, vision/fog constants, dynamic-terrain event tuning (`LAVA_*`/`CAVEIN_*`/`MAGMA_*`/`ORE_*`), weather tuning (`SNOWSTORM_*`), volcano tuning (`VOLCANO_*`), research branch tree (`RESEARCH_TECHS`) and branch-effect tuning, input action `StringName`s. Source of truth for all numeric balance.
- `game_manager.gd` — `Team`/`Difficulty` enums (Easy, Normal, Hard, Nightmare, Godly), team colors, difficulty modifiers, game speed, match timer, win/loss, soft pause.
- `faction_manager.gd` — faction picks (Arcane, Brute, Industrial), hidden-faction identification, faction-modified costs and starting bonuses.
- `economy_manager.gd` — coin, population, miner/fighter upgrade levels, units trained, coin mined.
- `research_manager.gd` — timed branch research tree: mutually-exclusive tiers, one-time 500g respec, active research slot with queue, Ore Sonar scan.
- `audio_manager.gd` — synthesized SFX and ambience.
- `settings_manager.gd` — window resolution persistence (desktop only).
- `weather_manager.gd` — snowstorms + volcano eruptions: independent game-time state machines, scheduling/damage/duration scaled by difficulty. Random scheduling can be disabled via `WeatherManager.set_weather_events_enabled(false)` and `WeatherManager.set_volcano_events_enabled(false)` (tests force events instead).
- `ai_belief_system.gd` — per-team belief maps (cells/unit sightings/enemy-faction guess) built only from that team's vision; confidence decays on stale intel. Reset per match via `AIBeliefSystem.reset()`.

### `scripts/controllers/`

Controllers are split into thin main classes plus `RefCounted` helper modules.

- `player_controller.gd` — exports, input routing, camera/view state, stance/build mode state; delegates to helpers.
  - `player_selection.gd` — single/box selection and unit/building picking.
  - `player_commands.gd` — right-click command resolution, train/upgrade/kill callbacks, stance/rally application.
  - `player_camera.gd` — zoom, pan, surface/underground view bookmarks, screen shake.
  - `player_build_placement.gd` — lantern/tower/wall/trap placement ghost and validation.
- `ai_controller.gd` — tick fields, aggression state, scout memory; delegates to helpers.
  - `ai_economy.gd` — economy decisions, training (faction-flavored army mix), upgrades, research (faction branch preferences), miner culling.
  - `ai_mining.gd` — miner task assignment and ore selection (skips miners under shelter orders).
  - `ai_combat.gd` — attack waves, base defense, wall breach. Waves peel up to half their fighters onto remembered enemy towers/lanterns before marching on the base.
  - `ai_smart_behaviors.gd` — focus fire, wounded retreat, harassment, bait, combat predictor, aggression.
  - `ai_awareness.gd` — faction scouting (swordsman at 1:00, 30s retry after death), defensive lantern placement/upgrades, snowstorm miner recall and lava evacuation (signal-driven; sheltered miners hold via `unit.shelter_in_place`).

### `scripts/world/`

- `grid_world.gd` — `Cell` inner class, `CellType` enum, signals, grid/A* state, fog maps; delegates to helpers.
  - `grid_map_generation.gd` — map generation and A* initialization.
  - `grid_pathfinding.gd` — `find_path`, walkability helpers, wall cell sealing.
  - `grid_fog_of_war.gd` — vision maps, memory, ghost silhouettes, fog rendering.
  - `grid_drawing.gd` — surface/underground terrain drawing, effects, wall HP bar.
  - `grid_mining.gd` — cell damage, mining, ore reveal, ore depletion trickle.
  - `grid_ambience.gd` — snow/dust particles, plus storm snow burst toggled by WeatherManager signals.
  - `grid_events.gd` — lava rising (warning → flood → recede into magma rock/fresh ore), cave-ins (3×3 SOLID_ROCK, 50 damage + push), ore vein respawn. Random scheduling can be disabled via `GridWorld.set_dynamic_events_enabled(false)`.
- `building.gd` — training queue, deposits, building HP/destruction, faction identification polling.
- `mine_entry.gd` — ladder teleport positions.
- `ladder.gd` — ladder visuals/positioning.
- `lantern.gd` / `tower.gd` / `wall_segment.gd` / `trap.gd` — placeable structures.

### `scripts/units/`

- `unit.gd` — state enum, exported data, `_ready`/`_process`/`_draw`, public command/combat API; delegates to helpers.
  - `unit_commands.gd` — move, attack, mine, deposit, climb, stop, kill, garrison, rally commands. Siege paths blocked by enemy walls redirect to breaching the nearest wall.
  - `unit_combat.gd` — damage, retaliation, projectiles, DPS window. Sieging units retaliate against towers shooting them.
  - `unit_mining.gd` — idle miner handling, ore seeking, exhausted/blacklist logic.
  - `unit_navigation.gd` — path following, repathing, separation, kiting, flee, walkability.
  - `unit_abilities.gd` — faction abilities (blink, volley, swarm, rune blade, berserk, arcane shot, heavy bolt, crush, mana burn, miner reveal, supply drop, fight back).
  - `unit_vision_targeting.gd` — vision radii, auto-attack target selection, splash targeting. Static structures are targetable on remembered intel, not just live vision.
  - `unit_rendering.gd` — sprites, pickaxe animation, HP bar, cargo, selection ring.
  - `unit_idle.gd` — idle fighter/miner behavior, rally hunt, patrol, return-to-post.
- `unit_pigeon.gd` — flying scout behavior (trained from towers, anti-air vulnerable).
- `projectile.gd` — arrows/fireballs.

### `scripts/ui/`

- `ui_theme_tokens.gd` — shared revamp color/size tokens and `StyleBoxFlat` factories for panels, buttons, tabs, progress bars, and warning banners.
- `hud.gd` — node references, signal wiring, game-over flow, lava/weather/volcano warning banners, faction-identified popup; delegates to helpers.
  - `hud_styling.gd` — HUD-specific styling helpers, now backed by `ui_theme_tokens.gd`.
  - `hud_menus.gd` — pause menu and radial build menu (options fan out above the Build button; icons, costs, grayed out when unaffordable/at max count).
  - `hud_updates.gd` — label/button synchronization, faction icons + "Enemy: ???" indicator, selection readout.
- `main_menu.gd` — title/difficulty/faction select (selected card gets a gold glow; faction-colored particles drift behind the select screen); uses the shared token system.
- `research_panel.gd` — research branch-tree overlay (diverging layout, locked branches grayed with tooltips, respec button).
- `training_queue_panel.gd` — vertical training queue.
- `unit_button.gd` — training buttons.
- `layer_indicator.gd` — underground layer accessibility indicator.
- `debug_overlay.gd` — runtime debug display.

## Game concepts

### Factions

Before each match the player picks one of three factions; the enemy faction is a hidden random pick. Each faction grants passive stat modifiers and activates a set of unit abilities. Faction data is stored in `scripts/resources/factions/*.tres`:

- **Arcane** — magic-focused; wizards +25% damage, Rune Blade first-strike bonus, Blink reduction, Arcane Shot, Mana Burn, Miner Reveal.
- **Brute** — raw combat power; tankier swordsmen, Berserk rage, Heavy Bolt, Fortify, Miner Fight Back, Dragon Crush.
- **Industrial** — economy and production; cheaper fighters, +200g and +1 miner at start, faster tower building, cheaper walls, Swarm, Volley, Supply Drop.

The enemy faction is revealed only when a unit gets within `FactionManager.IDENTIFY_RANGE_CELLS` of the enemy building.

### Units

Trainable units (costs and times in `Constants.COSTS` / `Constants.TRAIN_TIMES`):

- **Miner** — digs underground, deposits gold, can place traps with Guerrilla research.
- **Swordsman** — melee fighter.
- **Archer** — ranged, kites, anti-air.
- **Wizard** — ranged spell damage, AOE.
- **Dragon** — flying, anti-air and ground, high cost.
- **Pigeon** — flying scout trained from towers; provides vision, vulnerable to anti-air.

Miner upgrades unlock deeper layers (Level 1: layers 1–2, Level 2: layers 3–4, Level 3: layers 5–7). Fighter upgrades are per-type levels 1–3.

### Structures

Placeable from the radial build menu:

- **Lanterns** — surface and underground variants provide vision; surface lanterns shelter miners during snowstorms and upgrade T1→T2→T3.
- **Towers** — static surface defenses; auto-attack and vision.
- **Walls** — single-cell surface barriers that block movement and projectiles.
- **Traps** — hidden area damage triggered by enemy units (miner-placed with Guerrilla research).

### Research

Open with `R`. The tree has multiple discipline roots; tier-2 branches can both be researched, but tier-3 capstones are mutually exclusive, and tier-4 cross-path capstones require techs from two disciplines. Completing a tech locks its alternative; a one-time 500g respec resets all choices. Effects are applied by the systems that own the stat.

### Weather and dynamic terrain

- **Snowstorms** reduce vision and movement; units outside friendly lantern radius take frost damage.
- **Volcano eruptions** rain meteors on the surface, leaving burning ground (extinguished by overlapping snowstorms).
- **Lava rises** from the bottom of the mine, forcing units upward and eventually turning flooded cells into magma rock/fresh ore.
- **Cave-ins** drop 3×3 rock blocks that deal damage and push units.

## Development conventions

- **Language:** English for code, comments, docs.
- **Typing:** Prefer static types on function signatures.
- **Naming:** `snake_case` files/functions/variables; `PascalCase` classes/scene nodes; `_` prefix for private members.
- **Autoloads:** Global systems live in `scripts/autoload/` and are registered in `project.godot`.
- **Resources:** Unit/faction stats are `.tres` resources under `scripts/resources/`.
- **Groups:** `units`, `player`, `enemy`, `buildings`, `mine_entries`, `lanterns`, `towers`, `walls`, `traps`.
- **Drawing:** Surface is code-drawn; underground uses tile sprites.
- **Editor config:** `.editorconfig` enforces UTF-8.

## Input map (highlights)

Defined in `project.godot` under `[input]`:

- `lmb` / `rmb` — select / command
- `Ctrl+A` / `Ctrl+M` / `Ctrl+F` / `Ctrl+D` — select all / miners / fighters / dragons
- `1`–`6` — train miner / swordsman / archer / wizard / dragon / pigeon
- `Tab` (`toggle_view`) — toggle surface/underground camera bookmark
- `R` (`toggle_research`) — toggle research panel
- `K` / `Delete` (`kill_units`) — disband selection
- `Space` / `Esc` (`pause`) — pause
- `F3` (`toggle_debug`) — debug overlay

## Build, run, and export

### Run in the editor

Open the project root in Godot 4.7+ and press `F5` (or click Play).

### Run tests headless

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Replace `godot` with the path to your Godot binary if it is not on `PATH` (e.g. `/Applications/Godot.app/Contents/MacOS/Godot`).

### Export all presets

```bash
tools/export_all.sh
```

The script looks for `godot` on `PATH`, then falls back to `$HOME/Downloads/Godot.app/Contents/MacOS/Godot` or `/Applications/Godot.app/Contents/MacOS/Godot`. Override with:

```bash
GODOT=/path/to/Godot tools/export_all.sh
```

Export presets in `export_presets.cfg`:

- `Web` → `build/MineAttack.html`
- `macOS` → `build/MineAttack.app`
- `Windows` → `build/MineAttack.exe`

The script also packages `MineAttack-macOS.zip` (via `ditto`, preserving bundle metadata) and `MineAttack-Windows.zip`. Both `addons/*` and `tests/*` are excluded from exports.

### Web export and local serve

```bash
godot --headless --path . --export-release "Web" build/MineAttack.html
python3 tools/serve_web.py 8080
```

Open `http://localhost:8080/MineAttack.html`. Web builds require cross-origin isolation headers, so do not open the `.html` directly over `file://`.

### Automated releases

This repository includes a pre-push hook in `.githooks/pre-push`. When enabled, pushes to `main` automatically:

1. Run `tools/export_all.sh` to rebuild macOS and Windows zips.
2. Create a new GitHub release with an auto-incremented patch version (e.g. `v0.1.0` → `v0.1.1`).
3. Attach `MineAttack-macOS.zip` and `MineAttack-Windows.zip` to the release.

Enable the hook after cloning:

```bash
git config core.hooksPath .githooks
```

Skip the hook for a single push:

```bash
SKIP_RELEASE=1 git push origin main
```

Set a specific version instead of auto-incrementing:

```bash
VERSION_OVERRIDE=v0.2.0 git push origin main
```

## Testing strategy

- Framework: GUT (`addons/gut/`).
- Tests live in `tests/` and are discovered by `-gdir=res://tests`.
- Many tests instantiate `scenes/main.tscn`, run assertions against the live scene, and free it immediately in `after_all()` (not `queue_free()`) to avoid node-name collisions on the next test script.
- Deterministic tests seed the RNG (`seed(12345)`) and rely on `Constants.DEBUG` being off so `GridWorld` does not re-seed itself.
- Category coverage: AI awareness/belief/faction strategy/micro/retaliation/smarts/strategy, building queue, defend leash, dragon, dynamic terrain, economy, factions, fog of war, grid world, kill units, pigeon, rally, research, stance modes, structures, tech branches, unit guards, volcano, weather.

## Security and deployment considerations

- No secrets, credentials, or API keys are stored in the repository.
- `.gitignore` excludes `.godot/`, `build/`, `MineAttack-*.zip`, and `.DS_Store`.
- The pre-push hook uses `gh release create` and requires the GitHub CLI to be authenticated.
- Web export uses a custom head include in `export_presets.cfg` for full-bleed canvas sizing and cross-origin isolation.
- macOS export bundle identifier: `com.shumail.mineattack`.

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

`project.godot` → `scenes/main.tscn` → `scripts/autoload/game_manager.gd` + `economy_manager.gd` + `faction_manager.gd` → `scripts/world/grid_world.gd` → `scripts/units/unit.gd` → `scripts/controllers/player_controller.gd` + `ai_controller.gd`.

For implementation details, see `improvements/revamp.md`.
