# Agent Guide: MineAttack

This file is written for AI coding agents that need to understand and modify the **MineAttack** project. MineAttack is a standalone 2D RTS (real-time strategy) game built in Godot 4.7. Read this guide before making changes.

---

## Project overview

MineAttack is a single-player 2D RTS with a post-apocalyptic, Frostpunk-inspired aesthetic. The player mines underground ore, trains an army, and destroys the enemy base. The design blends:

- Mining and unit-training loop inspired by *Stick War: Legacy*.
- Layered, upgrade-gated digging inspired by *SteamWorld Dig*.
- Cold, industrial visuals inspired by *Frostpunk*.

The game is fully local (no networking or server). The player controls the blue **PLAYER** team on the left; a simple scripted AI controls the red **ENEMY** team on the right.

---

## Technology stack

- **Engine:** Godot 4.7
- **Renderer:** `gl_compatibility` (OpenGL / GL Compatibility backend)
- **Physics:** Jolt Physics
- **Language:** GDScript (strict/static typing is used where practical)
- **Target platforms:** Web (primary configured export), with runnable presets for macOS and Web. Windows, macOS, and Linux desktop exports are mentioned in the README but not currently configured in `export_presets.cfg`.
- **Version control:** Git with LF-normalized text files (`.gitattributes`)

Key configuration files:

| File | Purpose |
|------|---------|
| `project.godot` | Godot project settings, autoloads, input map, display, rendering, physics |
| `export_presets.cfg` | Godot export presets (currently Web only) |
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
├── scenes/                    # Godot scene files (.tscn)
│   ├── main.tscn              # Root gameplay scene
│   ├── building.tscn          # Base building scene
│   ├── mine_entry.tscn        # Mine entrance / exit scene
│   ├── projectile.tscn        # Arrow / fireball projectile scene
│   ├── unit.tscn              # Unit scene (miner/fighter)
│   └── ui/hud.tscn            # In-game UI
└── scripts/                   # GDScript source files
    ├── autoload/              # Global singletons
    │   ├── game_manager.gd    # Game state, teams, colors, win/loss
    │   └── economy_manager.gd # Coin, population, miner upgrades
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
    │   └── hud.gd             # HUD updates and button callbacks
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

`scenes/main.tscn` is the main scene. It contains:

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

Autoload singletons (configured in `project.godot`):

- `GameManager` — global game state, team enum, shared color palette, population cap, win/loss signals.
- `EconomyManager` — coin balances, population counts, miner upgrade levels, units trained, coin mined. Emits `coin_changed`, `population_changed`, `miner_level_changed`, `stats_changed`.

---

## Code organization

### `scripts/autoload/`

Global singletons accessible from any script via their class name.

- `game_manager.gd`
  - `enum Team { PLAYER, ENEMY }`
  - Constants: `POPULATION_CAP = 100`, team colors, terrain colors.
  - `signal game_over(winner: Team)`
  - `game_active: bool`
  - `declare_winner(winner: Team)`

- `economy_manager.gd`
  - `STARTING_COIN = 150`
  - `UNIT_COSTS`: miner 50, swordsman 100, archer 150, wizard 250.
  - `MINER_UPGRADE_COSTS`: level 2 → 500, level 3 → 1500.
  - Coin, population, miner-level, units-trained, and coin-mined getters/setters with signals.

### `scripts/controllers/`

- `player_controller.gd`
  - Handles selection box, single/box selection (with Shift add-to-selection), camera pan/zoom, hotkeys.
  - Issues context-sensitive commands on right-click: attack, mine, breach wall, enter/exit mine, move.
  - Supports view toggle (Tab / Surface / Underground buttons) and pause (Space / Esc).
  - Provides UI callbacks: `train_unit(unit_id)`, `upgrade_miner()`, `set_stance(stance)`, `set_view(underground)`.

- `ai_controller.gd`
  - Tick-driven AI with separate timers for economy (2s), mining (1s), and attack waves (18s).
  - Defends building when enemy units are nearby.
  - Selects ore based on distance, value, and side ownership.

### `scripts/world/`

- `grid_world.gd`
  - `CellType` enum: `EMPTY`, `SURFACE_GROUND`, `DIRT`, `ORE`, `WALL`.
  - `Cell` inner class holds type, hp, layer, miner level requirement, coin value, wall flag.
  - Procedural map generation with 7 underground layers (3 rows per layer), layer-specific tile HP and ore coin values, entry shafts, borders.
  - Central wall is a single shared 2000 HP objective spanning all layers at `x = -1, 0, 1`.
  - Uses `AStarGrid2D` for pathfinding.
  - `damage_cell()` applies mining damage and returns coin when destroyed; wall damage reduces the shared wall HP pool.

- `building.gd`
  - Training queue with `queue_unit(unit_id)` and `cancel_queue(index)` (100% refund).
  - Default building HP is 5000.
  - Spawns units at the building front and automatically sends miners into the mine.
  - Emits `hp_changed`, `queue_changed`, `destroyed`.
  - Draws a health bar above the building.
  - Marks its footprint as solid on the grid.

- `mine_entry.gd`
  - Teleports units between surface and underground positions.
  - `deposit(unit)` converts carried coin into team coin.

### `scripts/units/`

- `unit.gd`
  - Large state machine: `IDLE`, `MOVE`, `ATTACK`, `MINE`, `DEPOSIT`, `ENTER_MINE`, `EXIT_MINE`, `DEAD`.
  - Command API: `move_to`, `attack_unit`, `attack_building`, `mine_cell`, `deposit_coin`, `enter_mine`, `exit_mine`, `stop`.
  - Miners auto-enter mine on spawn, auto-seek diggable cells when idle, and flee toward friendly fighters or the mine entry when attacked.
  - Fighters auto-attack nearby enemies (fighters → building → enemy miners on own side) and patrol underground when idle.
  - Fighters move at 60% speed while underground.
  - Applies miner upgrade bonuses dynamically (`_apply_miner_upgrade`).
  - Custom `_draw()` renders each unit as a colored rectangle with class-specific weapon icons and an HP bar when damaged.

- `projectile.gd`
  - Homing arrow / fireball projectile.
  - Fireballs deal splash damage to units and buildings.

### `scripts/resources/`

- `unit_data.gd` — `Resource` subclass defining all unit stats.
- `units/*.tres` — concrete stats for Miner, Swordsman, Archer, Wizard.

### `scripts/ui/`

- `hud.gd` — wires buttons to `PlayerController`, listens to economy and queue signals, updates labels, shows training progress, displays clickable training queue with cancel, toggles surface/underground view, and shows game-over stats panel with Play Again.

---

## Build, run, and export

### Run in the editor

1. Open the project root in **Godot 4.7+**.
2. Press **F5** or run the main scene `res://scenes/main.tscn` (configured as `run/main_scene` in `project.godot`).

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
- **Drawing:** Visuals are code-drawn (`_draw()`) using simple rectangles and arcs; there are no imported sprite assets except `icon.svg`.

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
| Add to selection | Shift + click / drag |

---

## Gameplay rules and balance

- **Population cap:** 100 per team.
- **Starting coin:** 150 per team.
- **Units:** Miner, Swordsman, Archer, Wizard.
- **Miner upgrades:**
  - Level 2 costs 500, unlocks layers 3–4, +5 carry capacity, +10 HP, +1 mining rate.
  - Level 3 costs 1500, unlocks layers 5–7, +10 carry capacity (cumulative), +15 HP, +2 mining rate.
- **Layers:**
  - 7 underground layers, 3 grid rows each (~96 px per layer).
  - Layers 1–2: miner level 1, tile HP 50, ore coin 5–10 / 8–15.
  - Layers 3–4: miner level 2, tile HP 75, ore coin 12–20 / 15–25.
  - Layers 5–7: miner level 3, tile HP 100, ore coin 20–35 / 25–40 / 30–50.
- **Central wall:** A 3-tile thick wall at `x = -1, 0, 1` spans all layers and shares a single 2000 HP pool. Miners on either team can breach it with an explicit right-click command.
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

---

## Useful files to read first

When starting work on a feature, read these files in order:

1. `project.godot` — input, autoloads, display.
2. `scenes/main.tscn` — scene hierarchy.
3. `scripts/autoload/game_manager.gd` and `scripts/autoload/economy_manager.gd` — global state.
4. `scripts/world/grid_world.gd` — map and pathfinding.
5. `scripts/units/unit.gd` — unit state machine and commands.
6. `scripts/controllers/player_controller.gd` and `scripts/controllers/ai_controller.gd` — how the game is driven.
