# Agent Guide: MineAttack

This file is written for AI coding agents that need to understand and modify the **MineAttack** project. MineAttack is a standalone 2D RTS (real-time strategy) game built in Godot 4.7. Read this guide before making changes.

---

## Project overview

MineAttack is a single-player 2D RTS with a post-apocalyptic, Frostpunk-inspired aesthetic. The player mines underground ore, trains an army, and destroys the enemy base. The design blends:

- Mining and unit-training loop inspired by *Stick War: Legacy*.
- Layered, upgrade-gated digging inspired by *SteamWorld Dig*.
- Cold, industrial visuals inspired by *Frostpunk*.

The game is fully local (no networking or server). The player controls the blue **PLAYER** team on the left; a simple scripted AI controls the red **ENEMY** team on the right. The win condition is destroying the enemy building.

---

## Technology stack

- **Engine:** Godot 4.7
- **Renderer:** `gl_compatibility` (OpenGL / GL Compatibility backend)
- **Physics:** Jolt Physics
- **Language:** GDScript (static typing is used where practical)
- **Target platforms:** Web (primary configured export). `export_presets.cfg` lists runnable presets for both **macOS** and **Web**, but only the Web preset is actually defined.
- **Version control:** Git with LF-normalized text files (`.gitattributes`)

Key configuration files:

| File | Purpose |
|------|---------|
| `project.godot` | Godot project settings, autoloads, input map, display, rendering, physics |
| `export_presets.cfg` | Godot export presets (Web only, despite runnable preset references) |
| `.editorconfig` | UTF-8 charset directive |
| `.gitignore` | Ignores `.godot/` and `android/` |
| `.gitattributes` | Normalizes line endings to LF for text files |

---

## Project structure

```
mine-attack/
├── project.godot              # Godot project entry point
├── export_presets.cfg         # Export configuration
├── icon.svg                   # Project icon
├── README.md                  # Human-facing README
├── Frost_Mines_Complete_Implementation_Guide.md  # Design reference
├── scenes/                    # Godot scene files (.tscn)
│   ├── main.tscn              # Root gameplay scene
│   ├── building.tscn          # Base building scene
│   ├── mine_entry.tscn        # Mine entrance / exit scene
│   ├── projectile.tscn        # Arrow / fireball projectile scene
│   ├── unit.tscn              # Unit scene (miner/fighter)
│   ├── ui/hud.tscn            # In-game UI
│   ├── ui/debug_overlay.tscn  # Phase 0 debug overlay scene
│   └── effects/               # Floating text popups
│       ├── coin_popup.tscn
│       └── damage_popup.tscn
└── scripts/                   # GDScript source files
    ├── autoload/              # Global singletons
    │   ├── constants.gd       # Centralized balance and input constants
    │   ├── game_manager.gd    # Game state, teams, colors, win/loss
    │   ├── economy_manager.gd # Coin, population, miner upgrades, stats
    │   └── debug_log.gd       # Phase 0 ring-buffer logger
    ├── controllers/           # High-level gameplay controllers
    │   ├── ai_controller.gd   # Enemy AI logic
    │   └── player_controller.gd # Input, selection, camera, commands
    ├── resources/             # Custom Resource definitions and data
    │   ├── unit_data.gd       # UnitData resource script
    │   └── units/             # Unit stat resources
    │       ├── miner.tres
    │       ├── swordsman.tres
    │       ├── archer.tres
    │       └── wizard.tres
    ├── ui/                    # UI logic
    │   ├── hud.gd             # HUD updates and button callbacks
    │   ├── debug_overlay.gd   # Phase 0 F3 debug overlay
    │   ├── layer_indicator.gd # Accessible underground layer indicator
    │   ├── training_queue_panel.gd # Training queue display and cancel
    │   └── unit_button.gd     # Train button with cost/disable/shake
    ├── effects/               # Floating text effects
    │   ├── coin_popup.gd      # Coin deposit popup
    │   └── damage_popup.gd    # Damage number popup
    ├── units/                 # Unit behavior
    │   ├── unit.gd            # Main unit state machine
    │   └── projectile.gd      # Projectile movement and damage
    └── world/                 # World and level logic
        ├── grid_world.gd      # Tile grid, pathfinding, map generation
        ├── building.gd        # Base building: training queue, spawning, damage
        └── mine_entry.gd      # Mine shaft enter/exit/deposit logic
```

---

## Runtime architecture

`scenes/main.tscn` is the main scene configured in `project.godot`. It contains:

- `World/GridWorld` — procedural 2D grid map with A* pathfinding.
- `World/PlayerBuilding` and `World/EnemyBuilding` — bases for each team.
- `World/PlayerMineEntry` and `World/EnemyMineEntry` — mine shafts.
- `Camera2D` — player camera, panned/zoomed by `PlayerController`.
- `Units` — runtime container for all spawned units.
- `Projectiles` — runtime container for arrows and fireballs.
- `PlayerController` — handles player input, selection, commands, and camera.
- `AIController` — handles enemy economy, mining, attacks, and defense.
- `UI/SelectionBox` — visual drag-selection rectangle.
- `UI/HUD` — resource labels, training buttons, stance buttons, game-over panel.

Autoload singletons (configured in `project.godot`, loaded in this order):

- `Constants` — centralized balance numbers and input action names. Added in Phase 0: `DEBUG` flag and `DEBUG_SEED` for deterministic testing.
- `GameManager` — global game state, `Team` enum, shared color palette, match timer, win/loss signals.
- `EconomyManager` — coin balances, population counts, miner upgrade levels, units trained, coin mined. Emits `coin_changed`, `population_changed`, `miner_level_changed`, `stats_changed`.
- `DebugLog` — Phase 0 ring-buffer logger used by the debug overlay and command/state logging.

---

## Code organization

### `scripts/autoload/`

Global singletons accessible from any script via their class name.

- `constants.gd`
  - Centralized balance numbers: `STARTING_COIN` (150), `MAX_UNITS` (100), `MAX_QUEUE_SIZE` (5).
  - `COSTS`: miner 50, swordsman 100, archer 150, wizard 250.
  - `TRAIN_TIMES`: miner 3.0s, swordsman 5.0s, archer 6.0s, wizard 10.0s.
  - `MINER_STATS`: per-level HP, speed, mining DPS, carry capacity, and max layer.
  - `MINER_UPGRADE_COSTS`: level 2 → 500, level 3 → 1500.
  - Building HP, wall HP, layer data, grid bounds, and input action `StringName` constants.
  - Note: `FIGHTER_STATS` is defined but unused; live fighter stats come from the `.tres` resource files.

- `game_manager.gd`
  - `enum Team { PLAYER, ENEMY }`
  - Constants: team colors (`COLOR_PLAYER`, `COLOR_ENEMY`), terrain colors.
  - `signal game_over(winner: Team)`
  - `game_active: bool`, `match_time: float`
  - `declare_winner(winner: Team)`, `reset()`

- `economy_manager.gd`
  - Reads balance values from `Constants`.
  - Tracks coin, population, miner level, units trained, and coin mined per team.
  - `add_coin`, `spend_coin`, `can_afford`, population helpers, `upgrade_miner`, `get_miner_upgrade_cost`.

### `scripts/controllers/`

- `player_controller.gd`
  - Handles selection box, single/box selection (with Shift add-to-selection), camera pan/zoom, hotkeys.
  - Issues context-sensitive commands on right-click: attack, mine, breach wall, enter/exit mine, move.
  - Supports view toggle (Tab / Surface / Underground buttons) and pause (Space / Esc toggles `get_tree().paused`).
  - Provides UI callbacks: `train_unit(unit_id)`, `upgrade_miner()`, `set_stance(stance)`, `set_view(underground)`.
  - Stances: `"attack"` (rush enemy building), `"defend"` (stop), `"garrison"` (toggle mine).

- `ai_controller.gd`
  - Tick-driven AI with separate timers for economy (`ENEMY_DECISION_INTERVAL` = 2s), mining (1s), attack waves (`ENEMY_ATTACK_WAVE_INTERVAL` = 18s), and aggression updates (`ENEMY_AGGRESSION_INTERVAL` = 10s).
  - Maintains an `_aggression_level` (`"defend"`, `"balanced"`, `"push"`) based on relative fighter counts.
  - Defends building when enemy units are nearby.
  - Selects ore based on distance, value, and side ownership.
  - Attempts central wall breach when pushing and no accessible unmined tiles remain.

### `scripts/world/`

- `grid_world.gd`
  - `CellType` enum: `EMPTY`, `SURFACE_GROUND`, `DIRT`, `ORE`, `WALL`.
  - `Cell` inner class holds type, hp, max_hp, layer, miner level requirement, coin value, wall flag.
  - Procedural map generation with 7 underground layers (3 rows per layer, `ROWS_PER_LAYER = 3`), layer-specific tile HP and ore coin values, entry shafts at x = -15 and x = 15, and border walls.
  - Map bounds: `GRID_X_MIN = -40` to `GRID_X_MAX = 40`, `GRID_Y_MIN = 0` to `GRID_Y_MAX = 21`.
  - Central wall is a single shared 2000 HP objective spanning all layers at `x = -1, 0, 1`.
  - Uses `AStarGrid2D` for pathfinding.
  - `damage_cell()` applies mining damage and returns coin when destroyed; wall damage reduces the shared wall HP pool and scales with miner level.

- `building.gd`
  - Training queue with `queue_unit(unit_id)` and `cancel_queue(index)` (100% refund).
  - Default building HP is 5000 (`PLAYER_BUILDING_HP` / `ENEMY_BUILDING_HP`).
  - Spawns units at the building front and automatically sends miners into the mine.
  - Emits `hp_changed`, `queue_changed`, `destroyed`.
  - Draws a team-specific building sprite and a health bar above it.
  - Marks its footprint as solid on the grid by writing directly into `GridWorld._cells` and `_astar`.

- `mine_entry.gd`
  - Teleports units between surface and underground positions.
  - `deposit(unit)` converts carried coin into team coin.
  - Draws the mine entry sprite from `frost_mines_assets/props/mine_entry.png`.

### `scripts/units/`

- `unit.gd`
  - Large state machine: `IDLE`, `MOVE`, `ATTACK`, `MINE`, `DEPOSIT`, `ENTER_MINE`, `EXIT_MINE`, `DEAD`.
  - Command API: `move_to`, `attack_unit`, `attack_building`, `mine_cell`, `deposit_coin`, `enter_mine`, `exit_mine`, `stop`.
  - Miners auto-enter mine on spawn, auto-seek diggable cells when idle, and flee toward friendly fighters or the mine entry when attacked.
  - Fighters auto-attack nearby enemies (fighters → building → enemy miners on own side) and patrol underground when idle.
  - Fighters move at 60% speed while underground.
  - Applies miner upgrade bonuses dynamically (`_apply_miner_upgrade`).
  - Custom `_draw()` renders units as sprite assets from `frost_mines_assets/units/` when available, falling back to colored rectangles with class-specific weapon icons if no sprite is assigned. Miners swap sprite by team and upgrade level. All units show an HP bar when damaged, hovered, or selected, use `frost_mines_assets/effects/selection_ring.png` for selection, and flash `frost_mines_assets/effects/impact_hit.png` briefly on damage.

- `projectile.gd`
  - Homing arrow / fireball projectile.
  - Fireballs deal splash damage to units and buildings in a larger radius.
  - Draws `frost_mines_assets/effects/projectile_arrow.png` for arrows and `frost_mines_assets/effects/projectile_blast.png` for fireballs.

### `scripts/resources/`

- `unit_data.gd` — `Resource` subclass defining all unit stats and per-team sprite textures (`player_textures`, `enemy_textures`).
- `units/*.tres` — concrete stats for Miner, Swordsman, Archer, Wizard. These are the authoritative source of unit stats at runtime; `building.gd` duplicates the resource for each spawned unit.

### `scripts/ui/`

- `hud.gd` — wires non-training buttons to `PlayerController`, listens to economy signals, updates labels, toggles surface/underground view, shows game-over stats panel with Play Again and Quit, and adds icon sprites from `frost_mines_assets/icons/` to stat labels and the attack stance button.
- `unit_button.gd` — train button with cost/train-time labels, affordability/disable state, and failure shake.
- `training_queue_panel.gd` — shows currently training unit progress and queued units that can be cancelled.
- `layer_indicator.gd` — highlights accessible underground layers based on miner upgrade level.

### `scripts/effects/`

- `damage_popup.gd` — floating red/green combat numbers.
- `coin_popup.gd` — floating gold coin deposit numbers with a `frost_mines_assets/effects/coin_sparkle.png` icon.

---

## Build, run, and export

### Run in the editor

1. Open the project root in **Godot 4.7+**.
2. Press **F5** or run the main scene `res://scenes/main.tscn` (configured as `run/main_scene` in `project.godot`).

### Debug tooling (Phase 0)

A debug overlay is wired into `scenes/main.tscn` as `DebugOverlay`; it frees itself at startup when `Constants.DEBUG` is `false`, so release builds exclude it.

- **Toggle:** `F3` (`toggle_debug` input action).
- **Per-unit overlay:** current state text above the unit, target line, active A* path polyline, and miner cargo `carried / capacity`.
- **Global panel (top-left):** FPS, match time, unit counts, coin totals, miner levels, game-active flag, AI aggression level, and the most recent debug-log lines.
- **Debug buttons:** +500 coin, spawn swordsman/miner, teleport selected units to cursor, force underground view, clear log.

`scripts/autoload/debug_log.gd` is a ring-buffer logger. Log categories include `command`, `state`, `reject`, `economy`, `combat`, `mine`, `ai`, and `general`. Logging is fully disabled (no buffer, no output) when `Constants.DEBUG` is `false`; when `true`, lines are kept in the buffer and printed to the editor output with a color prefix.

`scripts/autoload/constants.gd` defines:

- `DEBUG` — gates all debug output and tooling. Set to `false` for release builds.
- `DEBUG_SEED` — seeds the global RNG in `GridWorld._generate_map()` so ore layout is identical across runs.

### Export

The project has one configured export preset in `export_presets.cfg`:

- **Web** — exports to `build/MineAttack.html`.

Runnable presets are configured for **macOS** and **Web** in the `[runnable_presets]` section, but only the Web preset is defined. To export from the command line:

```bash
godot --headless --export-release "Web" build/MineAttack.html
```

> Note: There is no automated test suite, CI/CD pipeline, or dependency manager. Godot itself is the only build tool required.

---

## Development conventions and style

- **Language:** English for all code comments, variable names, and documentation.
- **Typing:** Prefer static types. Most function signatures include return types and parameter types.
- **Naming:**
  - `snake_case` for files, functions, variables, and private members.
  - `PascalCase` for class names (`class_name UnitData`) and scene node names.
  - Private helper functions and variables prefixed with `_`.
- **Scene organization:** Each major entity has its own `.tscn` file in `scenes/` with a matching `.gd` script in `scripts/`.
- **Autoload pattern:** Global systems live as autoload singletons in `scripts/autoload/`.
- **Resource data:** Unit stats are stored as `.tres` `Resource` files so designers can tweak values without touching code.
- **Groups:** Runtime node discovery relies heavily on Godot groups:
  - `"units"` — all units.
  - `"player"` / `"enemy"` — team-specific units.
  - `"buildings"` — all buildings.
  - `"mine_entries"` — all mine shafts.
- **Signals:** UI and controllers connect to signals emitted by `EconomyManager`, `Building`, `GameManager`, and `MineEntry` rather than polling.
- **Drawing:** The surface ground row is code-drawn (`_draw()`) using simple rectangles and arcs. Underground dirt/ore tiles use per-layer sprite assets from `frost_mines_assets/tiles/`. Buildings use sprite assets from `frost_mines_assets/buildings/` (player/enemy variants). Wall cells use `frost_mines_assets/props/wall_segment.png`. Mine entrances use `frost_mines_assets/props/mine_entry.png`. Backgrounds use sprite assets from `frost_mines_assets/backgrounds/` (sky, surface ground, underground base). Units use sprite assets from `frost_mines_assets/units/` assigned through `UnitData.player_textures` / `enemy_textures`, with miners swapping by upgrade level, and use `frost_mines_assets/effects/` for selection rings and impact flashes. Projectiles use arrow/blast effect sprites. The in-game HUD/UI uses sprite assets from `frost_mines_assets/ui/` and `frost_mines_assets/icons/` (panel backgrounds, buttons, progress bars, stat/unit icons, and building/unit HP bars).

---

## Input map

Defined in `project.godot` under `[input]`:

| Action | Binding |
|--------|---------|
| `lmb` | Left mouse button |
| `rmb` | Right mouse button |
| `select_all` | Ctrl+A |
| `select_miners` | Ctrl+M |
| `select_fighters` | Ctrl+F |
| `camera_up` | W / Up arrow |
| `camera_down` | S / Down arrow |
| `camera_left` | A / Left arrow |
| `camera_right` | D / Right arrow |
| `camera_zoom_in` | Mouse wheel up |
| `camera_zoom_out` | Mouse wheel down |
| `train_miner` | `1` |
| `train_swordsman` | `2` |
| `train_archer` | `3` |
| `train_wizard` | `4` |
| `toggle_view` | Tab |
| `pause` | Space / Esc |
| `toggle_debug` | F3 |
| Add to selection | Shift + click / drag |

---

## Gameplay rules and balance

- **Population cap:** 100 per team (`MAX_UNITS`).
- **Starting coin:** 150 per team (`STARTING_COIN`).
- **Training queue cap:** 5 units (`MAX_QUEUE_SIZE`).
- **Units:** Miner, Swordsman, Archer, Wizard.
- **Unit costs / train times:**
  - Miner: 50 coin, 3.0s
  - Swordsman: 100 coin, 5.0s
  - Archer: 150 coin, 6.0s
  - Wizard: 250 coin, 10.0s
- **Miner upgrades:**
  - Level 2 costs 500, unlocks layers 3–4, +5 carry capacity, +10 HP, +1 mining rate.
  - Level 3 costs 1500, unlocks layers 5–7, +10 carry capacity (cumulative), +15 HP, +2 mining rate.
- **Layers:**
  - 7 underground layers, 3 grid rows each (`ROWS_PER_LAYER = 3`, ~32 px per row).
  - Layers 1–2: miner level 1, tile HP 50, ore coin 5–10 / 8–15.
  - Layers 3–4: miner level 2, tile HP 75, ore coin 12–20 / 15–25.
  - Layers 5–7: miner level 3, tile HP 100, ore coin 20–35 / 25–40 / 30–50.
- **Central wall:** A 3-tile thick wall at `x = -1, 0, 1` spans all layers and shares a single 2000 HP pool. Miners on either team can breach it with an explicit right-click command. Wall damage scales with miner level.
- **Win condition:** Destroy the enemy building.

---

## Testing

There is currently no automated test framework, unit test suite, or integration test in the repository. Testing is done manually by running the project in the Godot editor.

If you add tests, consider using [GUT](https://github.com/bitwes/Gut) (Godot Unit Testing), the most common GDScript testing framework, and document the run command here.

---

## Security considerations

- This is a fully offline, single-player game. There is no network code, authentication, saved game serialization, or external data ingestion beyond Godot's built-in scene/resource loading.
- No sensitive files (passwords, API keys, certificates) are present.
- Be cautious if adding online features later: Godot's `HTTPRequest` or third-party networking would introduce new trust boundaries.

---

## Common gotchas

- **Hard-coded node paths:** Several scripts use `get_node("/root/Main/...")` or `get_node("/root/Main/World/GridWorld")`. Renaming nodes in `main.tscn` will break these references.
- **AI controller relies on `Unit` internals:** `ai_controller.gd` reads `unit._state` and `unit.data` directly, including the underscore-prefixed `_state` variable. Refactoring `Unit`'s state machine requires updating the AI controller too.
- **Building footprint writes into `_cells` directly:** `building.gd` mutates `GridWorld._cells` and `_astar` directly rather than using a public API.
- **No null-safe node access for UI:** `hud.gd` looks up the player controller and building at runtime with `get_node_or_null`; if the scene hierarchy changes, the HUD may silently stop updating.
- **Export presets mismatch:** The README mentions Windows, macOS, and Linux exports, but only the Web preset is configured.
- **Resources are duplicated at spawn:** `building.gd` calls `data.duplicate(true)` so each unit gets its own mutable `UnitData`. Upgrades mutate that copy in `unit.gd`.
- **Autoloads survive scene reload:** `hud.gd` explicitly calls `GameManager.reset()` and `EconomyManager.reset()` before `get_tree().reload_current_scene()` so a new match starts fresh.
- **Fighter stats come from `.tres` resources:** `Constants.FIGHTER_STATS` exists but is not used at runtime; the `.tres` files are the source of truth.

---

## Useful files to read first

When starting work on a feature, read these files in order:

1. `project.godot` — input, autoloads, display.
2. `scenes/main.tscn` — scene hierarchy.
3. `scripts/autoload/game_manager.gd` and `scripts/autoload/economy_manager.gd` — global state.
4. `scripts/world/grid_world.gd` — map and pathfinding.
5. `scripts/units/unit.gd` — unit state machine and commands.
6. `scripts/controllers/player_controller.gd` and `scripts/controllers/ai_controller.gd` — how the game is driven.
