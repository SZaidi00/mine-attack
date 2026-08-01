# Agent Guide: MineAttack

This file is written for AI coding agents that need to understand and modify the **MineAttack** project. MineAttack is a standalone 2D RTS (real-time strategy) game built in Godot 4.7. Read this guide before making changes.

---

## Project overview

MineAttack is a single-player 2D RTS with a post-apocalyptic, Frostpunk-inspired aesthetic. The player mines underground ore, trains an army, and destroys the enemy base. The design blends the mining/unit-training loop of *Stick War: Legacy*, the layered, upgrade-gated digging of *SteamWorld Dig*, and the cold industrial visuals of *Frostpunk*.

The game is fully local (no networking or server). The player controls the blue **PLAYER** team on the left; a simple scripted AI controls the red **ENEMY** team on the right. The win condition is destroying the enemy building.

---

## Technology stack

- **Engine:** Godot 4.7
- **Renderer:** `gl_compatibility` (OpenGL / GL Compatibility backend)
- **Physics:** Jolt Physics
- **Language:** GDScript (static typing is used where practical)
- **Target platforms:** Web (primary configured export). `export_presets.cfg` lists runnable presets for both **macOS** and **Web**, but only the Web preset is actually defined.
- **Version control:** Git with LF-normalized text files (`.gitattributes`)

Key configuration files: `project.godot` (project settings, autoloads, input map, display, rendering, physics) and `export_presets.cfg` (Web export preset).

---

## Project structure

```
mine-attack/
├── project.godot / export_presets.cfg / icon.svg / README.md
├── Frost_Mines_Complete_Implementation_Guide.md  # Design reference
├── scenes/                    # Godot scene files (.tscn)
│   ├── main.tscn              # Root gameplay scene (loaded from the main menu)
│   ├── building.tscn / mine_entry.tscn / projectile.tscn / unit.tscn
│   ├── ui/                    # main_menu (project entry point), hud, debug_overlay
│   └── effects/               # coin_popup, damage_popup (floating text popups)
└── scripts/                   # GDScript source (details in §Code organization)
    ├── autoload/      # constants, game_manager, economy_manager, research_manager, debug_log, audio_manager
    ├── controllers/   # ai_controller, player_controller
    ├── resources/     # unit_data.gd + units/*.tres (miner, swordsman, archer, wizard)
    ├── ui/            # hud, debug_overlay, layer_indicator, training_queue_panel, research_panel, unit_button
    ├── effects/       # coin_popup, damage_popup
    ├── units/         # unit.gd (state machine), projectile.gd
    └── world/         # grid_world, building, mine_entry
```

---

## Runtime architecture

`scenes/ui/main_menu.tscn` is the main scene configured in `project.godot`; its Play button sets `GameManager.difficulty` and loads `scenes/main.tscn`, which contains:

- `World/GridWorld` — procedural 2D grid map with A* pathfinding.
- `World/PlayerBuilding` and `World/EnemyBuilding` — bases for each team.
- `World/PlayerMineEntry` and `World/EnemyMineEntry` — mine shafts.
- `Camera2D` — player camera, panned/zoomed by `PlayerController`.
- `PlayerController.ViewMode` — tracks which camera bookmark is active (surface vs. underground). Both layers are always rendered simultaneously; toggling the view only saves/restores the camera position and emits `view_mode_changed(mode)` (used by the HUD view buttons).
- `Units` — runtime container for all spawned units.
- `Projectiles` — runtime container for arrows and fireballs.
- `PlayerController` — handles player input, selection, commands, and camera.
- `AIController` — handles enemy economy, mining, attacks, and defense.
- `UI/SelectionBox` — visual drag-selection rectangle.
- `UI/HUD` — resource labels, per-unit-type counts, and selection readout (top bar; a single selected unit shows name + live HP, miners also carried/capacity), training and stance buttons (bottom bar), vertical training queue panel (right edge), game-over panel.

Autoload singletons (configured in `project.godot`, loaded in this order):

- `Constants` — centralized balance numbers and input action names. `DEBUG` (currently **false**) gates the debug overlay and `DebugLog`; `DEBUG_SEED` makes map generation deterministic when `DEBUG` is on. With `DEBUG` off, maps are random each match — test scripts that boot `main.tscn` call `seed(12345)` in `before_all` to get a deterministic layout.
- `GameManager` — global game state, `Team` enum, shared color palette, match timer, win/loss signals.
- `EconomyManager` — coin balances, population counts, miner upgrade levels, units trained, coin mined. Emits `coin_changed`, `population_changed`, `miner_level_changed`, `stats_changed`.
- `ResearchManager` — timed research tree: one active research per team (coin paid up front, 100% refund on cancel), per-team tech levels, and the Ore Sonar scan ability + cooldown. Tech definitions live in `Constants.RESEARCH_TECHS`; effects are applied by the owning systems (`unit.gd`, `building.gd`) via `research_completed` / `get_stat_bonus(team, key)`. Research and cooldowns freeze when `GameManager.game_active` is false. `hud.gd` calls `reset()` on Play Again / Restart / Quit to Menu (autoloads survive scene reload).
- `DebugLog` — Phase 0 ring-buffer logger used by the debug overlay and command/state logging.

---

## Code organization

### `scripts/autoload/`

Global singletons accessible from any script via their class name.

- `constants.gd`
  - Centralized balance numbers: `STARTING_COIN` (500), `STARTING_MINERS` (2 free miners per base at match start), `MAX_UNITS` (100). The training queue is uncapped (limited only by coin); training pauses while the team is at the population cap and resumes when a unit dies.
  - `COSTS`: miner 50, swordsman 100, archer 150, wizard 250.
  - `TRAIN_TIMES`: miner 3.0s, swordsman 5.0s, archer 6.0s, wizard 10.0s.
  - `MINER_STATS`: per-level HP, speed, mining DPS, carry capacity, and max layer.
  - `MINER_UPGRADE_COSTS`: level 2 → 500, level 3 → 1500.
  - `FIGHTER_UPGRADE_COSTS` / `FIGHTER_UPGRADES`: team-wide per-type fighter levels (swordsman/archer/wizard, L1→L3). Costs: swordsman 400/1200, archer 500/1500, wizard 600/1800. Stats are authoritative per-level HP/damage overrides (~+30% HP, +25% damage per level); level 1 rows mirror the `.tres` base stats.
  - `RESEARCH_TECHS`: timed research tree (coexists with the instant upgrades). Six branches of two tiers; each tech declares `tree_pos` (tier column, branch row) and tier-2 techs declare `requires` (prerequisite tech → level): Economy — Reinforced Pack (miner +15 carry) → Swift Boots (+15 miner speed); Recon — Ore Sonar L1/L2 (unlocks the ore scan) → Deep Scan; Defense — Fortify L1/L2 (+2000/+3000 building max HP, heals the delta) → Self-Repair (5 HP/s building regen); Swords — Bulwark L1/L2 (swordsman −2/−2 flat damage taken) → Berserk (20% faster attacks); Bows — Longbow (+30 archer range) → Rapid Fire (25% faster attacks); Arcane — Inferno (+50% fireball AoE) → Arcane Might (+25% wizard damage). Level values are per-level increments summed by `ResearchManager.get_stat_bonus()`. `SONAR_RADIUS` (8/12/16 cells) and `SONAR_COOLDOWN` (60s/40s/25s) are keyed by effective sonar level (ore_sonar + deep_scan). Per-level `desc` strings feed the research overlay's hover tooltips.
  - Building HP, wall HP, layer data, grid bounds, and input action `StringName` constants.
  - `UNIT_REGEN_DELAY` (5s) / `UNIT_REGEN_PER_SEC` (2 HP/s): out-of-combat regeneration — units that avoid damage for the delay slowly recover HP.
  - Fighter stats are stored in `UnitData` resources under `scripts/resources/units/*.tres`; `FIGHTER_STATS` was removed in Phase 2 to keep a single source of truth.

- `game_manager.gd`
  - `enum Team { PLAYER, ENEMY }`, `enum Difficulty { EASY, NORMAL, HARD, NIGHTMARE }`
  - Constants: team colors (`COLOR_PLAYER`, `COLOR_ENEMY`), terrain colors.
  - `DIFFICULTY_MODIFIERS`: per-difficulty AI multipliers — `coin` (deposit income), `train_time` (training duration), `upgrade_speed` (economy decision rate), `push_ratio`/`defend_ratio` (aggression thresholds), `retaliation` (per-hit chance a damaged AI sieger fights back). Fair-play rule: rates only, never rules (same unit stats, pop cap).
  - `difficulty` persists across `reset()` so Play Again keeps the choice; set via the debug overlay dropdown (Phase 6) or main menu (Phase 7).
  - `game_speed` (1.0 / 2.0 / 3.0 / 5.0 / 10.0) is the player-chosen `Engine.time_scale`, set from the HUD speed buttons; it also persists across `reset()`. The win cinematic overrides it temporarily (0.3 slow-mo), then `_process` restores `game_speed` on the wall clock.
  - Accessors: `get_ai_coin_multiplier()`, `get_ai_train_time_multiplier()`, `get_ai_upgrade_speed()`, `get_aggression_thresholds()`, `get_ai_retaliation_chance()`.
  - `signal game_over(winner: Team)`
  - `game_active: bool`, `match_time: float`
  - `declare_winner(winner: Team)`, `reset()`
  - `declare_winner` also runs the win cinematic: `Engine.time_scale = 0.3` slow-mo for 1 real second (wall-clock restore in `_process` back to `game_speed`), then the HUD game-over panel fades in. `reset()` restores `time_scale = game_speed`.

- `economy_manager.gd`
  - Reads balance values from `Constants`.
  - Tracks coin, population, miner level, per-type fighter levels, units trained, and coin mined per team.
  - `add_coin`, `spend_coin`, `can_afford`, population helpers, `upgrade_miner`, `get_miner_upgrade_cost`, `upgrade_fighter`, `get_fighter_level`, `get_fighter_upgrade_cost`.

- `audio_manager.gd`
  - Procedural audio (Phase 8): the project ships no audio assets, so every sound is synthesized at startup into `AudioStreamWAV` (22.05 kHz 16-bit).
  - SFX: `pickaxe`, `sword`, `bow`, `blast`, `coin`, `click`, `alarm`, `sonar` (Ore Sonar scan ping). Looping ambience: `wind`, `drips` on a quiet `Ambient` bus; one-shots use the `SFX` bus.
  - `play(sound, world_pos, volume_db)`: flat players for UI (no position), a rotating pool of 12 `AudioStreamPlayer2D` for world sounds.
  - Runs with `process_mode = ALWAYS` so ambience keeps playing while paused.

- `settings_manager.gd`
  - User-selectable window resolution (desktop only — `is_supported()` is false on web, where the canvas is full-bleed, so the menus hide the dropdown). 16:9 options 1280×720 → 3840×2160, filtered to the screen's usable rect.
  - `set_resolution()` applies + centers the window and persists to `user://settings.cfg`; `_ready()` re-applies the saved size at boot, shrinking the project default if it doesn't fit the current screen.
  - Because of the stretch setup, UI/menus keep the same logical 1920×1080 layout at any 16:9 size, while the in-game camera adapts its base zoom so higher resolutions show more of the world (see Common gotchas).

### `scripts/controllers/`

- `player_controller.gd`
  - Handles selection box, single/box selection (with Shift add-to-selection), camera pan/zoom, hotkeys (Ctrl+A/M/F/D for all/miners/fighters/dragons; click and box pick use combat position so flying dragons are selectable).
  - Issues context-sensitive commands on right-click: attack, mine, breach wall, enter/exit mine, move. Right-clicking the enemy mine entry is rejected with a log line and red-X popup — units can never enter the enemy mine.
  - Supports camera view bookmarks (Tab / Surface / Underground buttons) and pause (Space / Esc toggles `get_tree().paused`). Both layers are always rendered, so `set_view(underground)` only saves the current camera position and slides the camera to the other view's last position (surface base ↔ own mine underground; manual pan cancels the slide), emitting `view_mode_changed(mode)`.
  - Screen shake (Phase 8): connected to both buildings' `hp_changed` (small rumble) and `destroyed` (big shake), applied as a decaying `camera.offset`.
  - Provides UI callbacks: `train_unit(unit_id)`, `upgrade_miner()`, `upgrade_fighter(unit_id)`, `set_stance(stance)`, `set_view(underground)`.
  - Stances: `"attack"` (rush enemy building), `"defend"` (stop/hold in place), `"garrison"` (fall back and defend the base — underground fighters climb out, everyone gathers at the home building's deposit point and holds there via `garrison_home()`), `"rally"` (arms rally mode — the next **left-click** places an army-wide rally point, right-click cancels; fighters hunt every enemy on the surface, miners included, and fall back to the point; any explicit command cancels a unit's rally). Attack/Defend/Garrison are persistent **modes** (`_current_stance`, default `"defend"`): setting one works with zero fighters, and every fighter trained afterwards automatically gets the mode's order on spawn (building `unit_spawned` → `_on_fighter_spawned`; miners are exempt and always enter the mine). The HUD stance buttons are toggles highlighting the active mode. Rally is momentary and does not change the mode.

- `ai_controller.gd`
  - Tick-driven AI with separate timers for economy (`ENEMY_DECISION_INTERVAL` = 2s, scaled by the difficulty `upgrade_speed`), mining (1s), attack waves (`ENEMY_ATTACK_WAVE_INTERVAL` = 18s), and aggression updates (`ENEMY_AGGRESSION_INTERVAL` = 10s). The economy tick buys miner upgrades first, then fighter upgrades once a 400-coin reserve is safe (cheapest first), then research (sonar first, fortify when the base is hurt, then the fighter tech matching its most numerous fighter type) under the same reserve rule; the sonar scan fires whenever its cooldown is up.
  - Maintains an `_aggression_level` (`"defend"`, `"balanced"`, `"push"`) based on relative fighter counts; the push/defend ratios come from the difficulty modifiers.
  - Defends building when enemy units are nearby.
  - Selects ore based on distance, value, and side ownership — but only *discovered* ore (cells that already took mining damage or were revealed by an Ore Sonar scan; miners don't know where buried ore is), skipping cells reserved by other miners or blacklisted as unreachable by that miner.
  - Attempts central wall breach when pushing and no accessible unmined tiles remain.

### `scripts/world/`

- `grid_world.gd`
  - `CellType` enum: `EMPTY`, `SURFACE_GROUND`, `DIRT`, `ORE`, `WALL`.
  - `Cell` inner class holds type, hp, max_hp, layer, miner level requirement, coin value, wall flag, and a `claimed_by` miner reservation.
  - Procedural map generation with 7 underground layers (3 rows per layer, `ROWS_PER_LAYER = 3`), layer-specific tile HP and ore coin values, entry shafts at x = -15 and x = 15, and border walls.
  - Map bounds: `GRID_X_MIN = -40` to `GRID_X_MAX = 40`, `GRID_Y_MIN = 0` to `GRID_Y_MAX = 21`.
  - Central wall is a single shared 2000 HP objective spanning all layers at `x = -1, 0, 1`; an HP bar renders once it has taken damage, and at 0 HP every wall cell bursts dust and clears its A* solid in the same transaction.
  - Ambient particles (Phase 5.1): slow falling snow over the surface and drifting dust motes underground, spawned in `_ready()` with a code-generated soft-dot texture. Deep-layer shimmer (Phase 8): magma flicker overlays on layers 5–6 and a crystal pulse on layer 7, redrawn at ~8 fps.
  - Uses `AStarGrid2D` for pathfinding.
  - `damage_cell()` applies mining damage and returns coin; ore tiles trickle gold on every swing (a share proportional to the damage dealt, with the remainder paid on destruction — each tile yields exactly `coin_value` total). Wall damage reduces the shared wall HP pool and scales with miner level. Partially damaged cells show a brief flash, dust puffs, and a small HP bar so active mining is visible; destroyed tiles burst dust and clear their A* solid in the same transaction.
  - Cell reservations (`claim_cell` / `release_cell` / `is_cell_claimable`) let miners spread across tiles instead of dogpiling one (Phase 3.3).
  - Draws both layers every frame — sky, surface ground, and the surface row, plus the underground background, ceiling, and all subterranean tiles — so surface and underground activity are visible simultaneously.

- `building.gd`
  - Training queue with `queue_unit(unit_id)` and `cancel_queue(index)` (100% refund). At the population cap, training pauses mid-progress and resumes when a unit dies (no despawn, no refund churn). The AI building's training speed and deposit income scale with the difficulty modifiers; the player is always ×1.0.
  - Default building HP is 5000 (`PLAYER_BUILDING_HP` / `ENEMY_BUILDING_HP`); the Fortify research adds on top of the stored base (`_base_max_hp`) and heals the delta via `research_completed`.
  - Spawns units at the building front and automatically sends miners into the mine.
  - Emits `hp_changed`, `queue_changed`, `destroyed`, `coin_deposited`, `unit_spawned`.
  - On destruction: clears the queue, leaves the `"buildings"` group, plays a collapse (one-shot dust burst + squash/darken tween under the slow-mo), and hides its HP bar. Sounds: coin chime on deposit, alarm below 25% HP, blast on destruction.
  - Owns the miner deposit point (Phase 3.1): a `DepositPoint` Marker2D just outside the front edge on the surface row; `deposit(unit)` converts carried coin into team coin and spawns the coin popup there.
  - Draws a team-specific building sprite and a health bar above it.
  - Marks its footprint as solid on the grid by writing directly into `GridWorld._cells` and `_astar`.
  - Always visible; both surface and underground render simultaneously.
  - Phase 3.4: spawns units with a slight randomized offset so training bursts don't perfectly overlap.

- `mine_entry.gd`
  - Teleports units between surface and underground positions; `enter_mine` / `enter_mine_climb` reject units of the wrong team with a logged rejection (units can never enter the enemy mine).
  - `deposit(unit)` converts carried coin into team coin — legacy fallback only; the main loop deposits at the building (see `unit.deposit_coin()`).
  - Draws the mine entry sprite from `frost_mines_assets/props/mine_entry.png`. Always visible; both surface and underground render simultaneously.

### `scripts/units/`

- `unit.gd`
  - Large state machine: `IDLE`, `MOVE`, `ATTACK`, `MINE`, `DEPOSIT`, `ENTER_MINE`, `EXIT_MINE`, `CLIMB_UP`, `CLIMB_DOWN`, `DEAD`.
  - All AI/movement freezes when `GameManager.game_active` is false (match over); only the `DEAD` fade-out keeps running. Projectiles freeze mid-flight too.
  - Command API: `move_to`, `attack_unit`, `attack_building`, `mine_cell`, `deposit_coin`, `enter_mine`, `exit_mine`, `climb_up_ladder`, `climb_down_ladder`, `rally_to`, `garrison_home`, `stop`. The ladder climbs are the auto-loop's way in and out of the mine; `enter_mine`/`exit_mine` teleport and remain as explicit-order fallbacks.
  - Miners auto-enter mine on spawn, auto-seek diggable cells when idle, and flee toward friendly fighters or the mine entry when attacked (fleeing to the shaft's underground position when attacked below ground). When cargo is full (or nothing diggable remains), miners surface and walk to their building's deposit point to cash in before heading back down (Phase 3.1).
  - Mining seek (Phase 3.3): miners don't know where buried ore is — every diggable face is equal until a tile proves itself. Ore that already took mining damage (`hp < max_hp`, i.e. it yielded gold) or was revealed by an Ore Sonar scan (`cell.sonar_revealed`) counts as *discovered* and is preferred at any distance; otherwise the nearest diggable cell wins regardless of type. The miner-level gate is enforced at seek time; targeted cells are reserved via `claimed_by`; cells that can't be pathed to go on a per-miner 10s blacklist; when nothing diggable remains, miners with cargo surface to deposit while empty-handed miners wait near the shaft bottom and re-scan every 5s (or immediately on any `cell_destroyed` signal) instead of yo-yoing up and down.
  - Fighters auto-attack nearby enemies (fighters → building → enemy miners on own side) and patrol underground when idle.
  - Rally mode (`rally_to`): a fighter hunts any enemy on the surface — miners included (`_find_rally_target` skips underground enemies) — while travelling to and idling at the rally point. Underground rally points are rejected; underground fighters climb out first and resume the rally on the surface. Rally engagements bypass `attack_unit()` so `_rally_active` survives the kill (the unit then resumes the hunt); every explicit command cancels the rally via `_clear_target()`.
  - Standing points (`_post_point`): a fighter's idle anchor on the surface — set at spawn, updated by explicit `move_to` (new post) and `stop` (hold here). Attack and auto-attack engagements leave it unchanged, so when the fighting ends the fighter paths back to its post (`_return_to_post_if_needed`) and the army regroups at base instead of spreading across the map.
  - Death drops: a miner that dies with cargo drops its full carried coin as a `CoinPickup` on the spot (any team, any layer), so the coin is never lost; any miner that walks over the pickup collects it.
  - AI retaliation: an **enemy-team** fighter locked onto a building re-evaluates when an enemy fighter damages it — a per-hit roll against the difficulty's `retaliation` chance (Easy 0.25 → Nightmare 0.9) makes some of the wave peel off to fight back (`_maybe_retaliate` / `_pick_retaliation_target`: prefer the attacker if reachable, else the closest enemy fighter in sight on the same level). Units already duelling a unit never flip-flop; player units never auto-retaliate (explicit orders stay sovereign).
  - Fighters move at 60% speed while underground.
  - Ranged standoff (kiting): a fighter with `attack_range > 35` whose unit target slips inside 40% of its range takes a direct steering step away (`_kite_away_from`) while staying in ATTACK and firing on cooldown. `_is_walkable_point` bounds the step (surface row or EMPTY cells underground) — no pathing, so the target lock is never dropped. Melee units and building sieges are unaffected.
  - Out-of-combat regen: `take_damage` starts a 5s no-damage countdown; once it elapses the unit regains 2 HP/s up to `max_hp`, with a green `+N` popup on each heal tick. Applies to all units, both teams (miners heal between trips too).
  - Applies miner upgrade bonuses dynamically (`_apply_miner_upgrade`) and team-wide fighter upgrade stats (`_apply_fighter_upgrade` — swordsman/archer/wizard HP/damage per level from `Constants.FIGHTER_UPGRADES`, healing the max_hp delta on level-up), plus research-tree bonuses (`_apply_research_bonuses` — bulwark armor, longbow range, inferno AoE, reinforced-pack carry, applied as deltas so re-application never compounds).
  - Custom `_draw()` renders units as sprite assets from `frost_mines_assets/units/` when available, falling back to colored rectangles with class-specific weapon icons if no sprite is assigned. Miners swap sprite by team and upgrade level. All units show an HP bar when damaged, hovered, or selected; miners also show a gold `carried/capacity` cargo readout above the HP bar while hauling or when hovered/selected. Units use `frost_mines_assets/effects/selection_ring.png` for selection (with a gentle pulse), a warm lantern glow when mining underground, and flash `frost_mines_assets/effects/impact_hit.png` briefly on damage. Units are always visible in both views (surface and underground render simultaneously). Mining swings, melee hits, and projectile launches play positional SFX via `AudioManager`.
  - Dragon flight: feet stay on the ground for A*/kiting (`global_position`); surface dragons use `flight_altitude` (40px) via `get_combat_position()` for draw offset, shadow, hover, click/box pick, attack/sight range, and projectile spawn/homing/impact. Altitude is 0 underground. Dragons take damage only from archers/wizards (Euclidean range to the air aim point).
  - Phase 3.4 traffic: each unit gets a small `_movement_offset` applied to miner deposit and mine-entry targets, and `_follow_path()` applies soft repulsion from nearby friendly units so surface parades don't stack into a single sprite. Path arrival is step-aware (`max(2px, speed * delta)`) so large deltas (lag spikes, high `Engine.time_scale`) can't orbit a path point forever against the separation nudge.

- `projectile.gd`
  - Homing arrow / fireball projectile.
  - Fireballs deal splash damage to units and buildings in a larger radius.
  - Homing and unit impact use `get_combat_position()` when present (flying dragons).
  - Draws `frost_mines_assets/effects/projectile_arrow.png` for arrows and `frost_mines_assets/effects/projectile_blast.png` for fireballs.

### `scripts/resources/`

- `unit_data.gd` — `Resource` subclass defining all unit stats and per-team sprite textures (`player_textures`, `enemy_textures`), plus optional `flight_altitude` / `draw_scale` for flyers.
- `units/*.tres` — concrete stats for Miner, Swordsman, Archer, Wizard, Dragon. These are the authoritative source of unit stats at runtime; `building.gd` duplicates the resource for each spawned unit.

### `scripts/ui/`

- `hud.gd` — wires non-training buttons to `PlayerController`, listens to economy signals, updates labels (including the live per-unit-type counts in the top bar), toggles surface/underground view, owns the 1×/2×/3×/5×/10× game-speed buttons (via `GameManager.set_game_speed`), shows the game-over stats panel (1.4s after `game_over`, fading in once the slow-mo collapse has played) with Play Again and Quit to Menu, and adds icon sprites from `frost_mines_assets/icons/` to stat labels and the attack stance button. Runs with `process_mode = ALWAYS` and owns the pause menu (full-screen dim: Resume / Restart / Quit to Menu / difficulty / resolution), synced to `get_tree().paused` — Space/Esc toggles it via `PlayerController`. In-game Quit buttons return to the main menu (`_quit_to_menu`: unpause, reset autoloads, `change_scene_to_file`) instead of closing the app — quitting is a no-op in the web export; only the main menu's own Quit exits.
- `main_menu.gd` — main menu: night-sky backdrop with falling snow (CPUParticles2D), both bases and units on the ground strip, and a centered card (title, difficulty and resolution dropdowns, gold Play button, Quit, hotkey hint line); Play sets `GameManager.difficulty` and switches to `main.tscn`.
- `unit_button.gd` — train button with cost/train-time labels, a hotkey hint badge, affordability/disable state, and failure shake.
- `training_queue_panel.gd` — vertical queue panel docked on the right edge of the screen (between the top and bottom bars); shows the currently training unit's progress and a scrollable list of queued units; both the in-progress unit and queued units can be cancelled (100% refund).
- `research_panel.gd` — research tree overlay: full-screen dim with a centered card, toggled by the BottomBar Research button / `R` hotkey (click outside or Close to dismiss). Techs from `Constants.RESEARCH_TECHS` are laid out as a tree — nodes at their `tree_pos` (tier column × branch row), elbow connectors drawn from the `requires` table (gold when unlocked, dim when locked), so progression is visible at a glance. Hovering a node shows a native tooltip with per-level effects, costs, and unmet prerequisites. Footer holds the active-research progress bar with 100%-refund cancel and the Ore Sonar Scan button with cooldown countdown. The overlay never pauses the game by itself; a "Pause game" checkbox in the header opts in (the panel owns that pause via `owns_pause()`, releases it on close, and the HUD keeps the pause menu hidden while the panel owns it).
- `layer_indicator.gd` — highlights accessible underground layers based on miner upgrade level.

### `scripts/effects/`

- `damage_popup.gd` — floating combat numbers: red `-N` for damage, green `+N` for healing.
- `coin_popup.gd` — floating gold coin deposit numbers with a `frost_mines_assets/effects/coin_sparkle.png` icon.

---

## Build, run, and export

### Run in the editor

1. Open the project root in **Godot 4.7+**.
2. Press **F5** — the main menu (`res://scenes/ui/main_menu.tscn`, configured as `run/main_scene` in `project.godot`) opens; pick a difficulty and press Play. To run the match scene directly, run `res://scenes/main.tscn`.

### Debug tooling (Phase 0)

A debug overlay is wired into `scenes/main.tscn` as `DebugOverlay`; it frees itself at startup when `Constants.DEBUG` is `false`, so release builds exclude it.

- **Toggle:** `F3` (`toggle_debug` input action).
- **Per-unit overlay:** current state text above the unit, target line, active A* path polyline, and miner cargo `carried / capacity`.
- **Global panel (top-left):** FPS, match time, unit counts, coin totals, miner levels, game-active flag, AI aggression level, and the most recent debug-log lines.
- **Debug buttons:** +500 coin, spawn swordsman/miner, teleport selected units to cursor, force underground view, clear log, and a difficulty dropdown (Easy/Normal/Hard/Nightmare — sets `GameManager.difficulty`).

`scripts/autoload/debug_log.gd` is a ring-buffer logger. Log categories include `command`, `state`, `reject`, `economy`, `combat`, `mine`, `ai`, and `general`. Logging is fully disabled (no buffer, no output) when `Constants.DEBUG` is `false`; when `true`, lines are kept in the buffer and printed to the editor output with a color prefix.

`scripts/autoload/constants.gd` defines:

- `DEBUG` — gates all debug output and tooling. Set to `false` for release builds.
- `DEBUG_SEED` — seeds the global RNG in `GridWorld._generate_map()` so ore layout is identical across runs.

### Export

The project has one configured export preset in `export_presets.cfg`:

- **Web** — exports to `build/MineAttack.html`. The preset excludes `addons/*` and `tests/*` (GUT is dev tooling and must not ship in the release pck).

Runnable presets are configured for **macOS** and **Web** in the `[runnable_presets]` section, but only the Web preset is defined. To export from the command line:

```bash
godot --headless --path . --export-release "Web" build/MineAttack.html
```

> Export templates: the engine (4.7.1.stable) looks in `~/Library/Application Support/Godot/export_templates/4.7.1.stable/`. This machine has the 4.7.0 templates under `4.7.stable/` with a `4.7.1.stable` symlink pointing at them — works for dev smoke builds, but for a release download the exact `Godot_v4.7.1-stable_export_templates.tpz`.

> Note: There is no CI/CD pipeline or dependency manager. Godot itself is the only build tool required; tests run via GUT (see §Testing).

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
- **Drawing:** The surface ground row is code-drawn (`_draw()`) using simple rectangles and arcs. Underground dirt/ore tiles use per-layer sprite assets from `frost_mines_assets/tiles/`. Buildings use sprite assets from `frost_mines_assets/buildings/` (player/enemy variants). Wall cells use `frost_mines_assets/props/wall_segment.png`. Mine entrances use `frost_mines_assets/props/mine_entry.png`. Backgrounds use sprite assets from `frost_mines_assets/backgrounds/` (sky, surface ground, underground base). Units use sprite assets from `frost_mines_assets/units/` assigned through `UnitData.player_textures` / `enemy_textures`, with miners swapping by upgrade level, and use `frost_mines_assets/effects/` for selection rings and impact flashes. Projectiles use arrow/blast effect sprites. The in-game HUD (top bar, bottom bar, queue panel) is styled in code with flat `StyleBoxFlat` panels and buttons (solid dark fills, 1px borders, rounded corners — no gradient textures); stat/unit icons come from `frost_mines_assets/icons/`. The main menu and the world-space building/unit HP bars still use the `frost_mines_assets/ui/` textures.

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
| `select_dragons` | Ctrl+D |
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
| `train_dragon` | `5` |
| `toggle_view` | Tab |
| `toggle_research` | R |
| `pause` | Space / Esc |
| `toggle_debug` | F3 |
| Add to selection | Shift + click / drag |

---

## Gameplay rules and balance

- **Population cap:** 100 per team (`MAX_UNITS`).
- **Starting coin:** 500 per team (`STARTING_COIN`).
- **Starting units:** each base spawns 2 free miners at match start (`STARTING_MINERS`); they count toward population.
- **Training queue:** uncapped — limited only by coin. Population never blocks *queueing*: at the 100-unit cap the queue pauses mid-training (the queue panel shows "paused (population cap)") and resumes when a unit dies — the finished unit is never despawned and the coin never refunded away.
- **Units:** Miner, Swordsman, Archer, Wizard, Dragon.
- **Unit costs / train times:**
  - Miner: 50 coin, 3.0s
  - Swordsman: 100 coin, 5.0s
  - Archer: 150 coin, 6.0s
  - Wizard: 250 coin, 10.0s
- **Miner upgrades:**
  - Level 2 costs 500, unlocks layers 3–4, +10 carry capacity (30 total), +10 HP, +1 mining rate, speed 60 → 70.
  - Level 3 costs 1500, unlocks layers 5–7, +10 carry capacity (40 total), +15 HP, +2 mining rate, speed 70 → 80.
- **Fighter upgrades (team-wide, per type):**
  - Swordsman L2 400 / L3 1200 → HP 195/245, damage 9.5/12.
  - Archer L2 500 / L3 1500 → HP 105/130, damage 15/19.
  - Wizard L2 600 / L3 1800 → HP 80/100, damage 47/58.
  - The AI buys them in its economy tick once it keeps a 400-coin reserve (cheapest first).
- **Research tree (timed techs, one active research per team, 100% refund on cancel):**
  - Six branches of two tiers; tier-2 techs have prerequisites (e.g. Deep Scan needs Ore Sonar L2, Berserk needs Bulwark L2).
  - Economy: Reinforced Pack 400g → miners +15 carry; Swift Boots 500g → +15 miner speed.
  - Recon: Ore Sonar 300g/800g → Scan ability reveals buried ore in 8/12-cell radius (60s/40s cooldown); Deep Scan 1000g → 16 cells, 25s cooldown.
  - Defense: Fortify 600g/1500g → building max HP +2000/+3000 (heals the delta); Self-Repair 800g → building regenerates 5 HP/s.
  - Swords: Bulwark 500g/1000g → swordsmen take 2/4 less damage per hit (min 1); Berserk 800g → 20% faster attacks.
  - Bows: Longbow 500g → archers +30 range; Rapid Fire 700g → 25% faster attacks.
  - Arcane: Inferno 600g → fireballs +50% AoE; Arcane Might 900g → wizards +25% damage.
  - Coexists with the instant upgrades above; the AI researches the same tree in its economy tick (prerequisite-gated).
- **Layers:**
  - 7 underground layers, 3 grid rows each (`ROWS_PER_LAYER = 3`, ~32 px per row).
  - Layers 1–2: miner level 1, tile HP 50, ore coin 25–40 / 30–50.
  - Layers 3–4: miner level 2, tile HP 75, ore coin 45–70 / 55–90.
  - Layers 5–7: miner level 3, tile HP 100, ore coin 75–120 / 95–160 / 120–200.
  - Ore spawn chance rises with depth (`0.10 + layer * 0.05`), and every pickaxe swing on ore extracts a share of the tile's gold (see `damage_cell()`).
- **Mining requires being inside the mine:** `mine_cell` only executes while the miner is underground. A mine order given to a surface miner (right-click ore/wall, AI ore orders) is deferred: the miner rides the ladder down first, then `_handle_idle_miner` re-issues the pending cell. Ore yields are sized so each side's layers can fund the 500 / 1500 miner upgrades before the next tier unlocks.
- **Central wall:** A 3-tile thick wall at `x = -1, 0, 1` spans all layers and shares a single 2000 HP pool. Miners on either team can breach it with an explicit right-click command. Wall damage scales with miner level.
- **Win condition:** Destroy the enemy building.
- **AI difficulty** (`GameManager.DIFFICULTY_MODIFIERS`; rates only, never rules):

  | Difficulty | AI coin × | Train time × | Decision rate × | Retaliation | Aggression bias |
  |------------|-----------|--------------|------------------|-------------|-----------------|
  | Easy | 0.8 | 1.0 | 0.7 | 0.25 | Defensive (push 2.0×, defend 0.75×) |
  | Normal | 1.0 | 1.0 | 1.0 | 0.5 | Balanced (push 1.5×, defend 0.5×) |
  | Hard | 1.2 | 0.9 | 1.2 | 0.7 | Aggressive (push 1.3×, defend 0.4×) |
  | Nightmare | 1.5 | 0.8 | 1.5 | 0.9 | Very aggressive (push 1.1×, defend 0.25×) |

---

## Testing

The project uses [GUT](https://github.com/bitwes/Gut) 9.6.1 (committed under `addons/gut/`). The suite lives in `tests/` and boots the real `main.tscn`, so it exercises the actual building/grid/unit wiring:

- `tests/test_economy.gd` — spend/refund/upgrade math, cap guards, team wallet separation.
- `tests/test_building_queue.gd` — FIFO order, queue accepts beyond the population cap, training pauses at the cap and resumes when population frees (no despawn, no refund churn), cancel refunds (queued + in-progress).
- `tests/test_grid_world.gd` — ore trickle totals, A* clearing on destruction, level gates, wall shared-HP pool, `nearest_walkable_cell`/`cells_adjacent_to_rect` around the building footprint, no tile regen.
- `tests/test_unit_guards.gd` — fighter `mine_cell` rejected, enemy mine entry rejected, unreachable mine target blacklisted, empty-cargo deposit rejected, corpse hits don't double-remove population (`take_damage` ignores `DEAD` units — in-flight projectiles can still land during the 1s fade-out, and without the guard each hit re-ran `_die()` and leaked a population slot past `MAX_UNITS`).
- `tests/test_ai_retaliation.gd` — damaged AI sieger eventually retaliates against its attacker, undamaged sieger stays on the building, player units never auto-retaliate.
- `tests/test_rally.gd` — rally targets surface miners, skips underground enemies, engagement keeps the rally active, explicit commands cancel it, miners can't rally, miner death drops full cargo as a pickup.
- `tests/test_stance_modes.gd` — stance modes persist with zero fighters, attack/garrison/defend modes auto-order newly spawned fighters, miners ignore modes, rally doesn't change the mode.
- `tests/test_research.gd` — research purchase guards (unknown/busy/unaffordable/maxed/prerequisites), timed completion and pause freeze, 100% cancel refund, fortify/longbow/bulwark/reinforced-pack effects, tier-2 effects (swift boots, berserk, rapid fire, arcane might, self-repair regen + overheat cap, deep scan sonar level), research bonuses surviving miner upgrades, sonar scan reveal + cooldown, `reset()` clearing.
- `tests/test_dragon.gd` — dragon immunity (archer/wizard only), auto-attack skip, fireball splash via source, train queue, surface flight combat position / underground grounded, Euclidean air-range gate, projectile homing to combat pos, `_filter_dragons`.

> Test harness gotcha: every script that boots `main.tscn` must free it **immediately** in `after_all` (`_main.free()`, never `queue_free()`). A deferred free can still be pending when the next script instantiates its own `main.tscn` — the old `Main` name stays taken, the new scene gets renamed, and every hard-coded `/root/Main/...` lookup breaks (flaky, timing-dependent failures).

Run the suite headless (exits nonzero on failure):

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

### The Match Script (manual regression checklist)

GUT covers logic, not feel or input. Run this ~15-minute playthrough in the editor before any export:

1. Train 2 miners → confirm the full visible cycle: descend, dig (gold trickles per swing), surface, walk to the building, deposit popup, repeat.
2. Train 1 of each fighter → right-click the enemy building → all engage; enemy HP drops.
3. Queue 8+ units → all accepted (queue is uncapped; the right-side panel scrolls); cancel a queued and an in-progress unit → exact refunds.
4. Upgrade miners to L2 → they begin digging layer 3; sprite swaps; layer indicator highlights.
5. Tab-toggle (camera slide) during every activity; check snow, dust motes, lantern glow, and deep-layer shimmer.
6. Garrison fighters; force the wall to low HP (debug overlay) → breach → cross-side combat works.
7. Let the AI attack; defend; counterattack; win → slow-mo collapse → VICTORY panel → Play Again resets cleanly.
8. Repeat on Hard. Lose on purpose once → DEFEAT flow. Pause mid-fight → menu works, resume works.

---

## Security considerations

Fully offline, single-player game: no network code, authentication, saved-game serialization, or secrets. Adding online features later (e.g. `HTTPRequest` or third-party networking) would introduce new trust boundaries.

---

## Common gotchas

- **Hard-coded node paths:** Several scripts use `get_node("/root/Main/...")` or `get_node("/root/Main/World/GridWorld")`. Renaming nodes in `main.tscn` will break these references.
- **A* path points are cell centers:** `GridWorld._init_astar()` sets `_astar.offset = cell_size * 0.5`, because raw `AStarGrid2D.get_point_path()` returns cell corners (`point * cell_size`). All movement code (`_follow_path`, arrival thresholds, climb states) assumes centered points — do not remove the offset. `find_path()` also snaps negative world Y to the surface row, since spawn jitter and per-unit target offsets can push units/targets above y = 0 (outside the A* region).
- **Ladders are vertical by design:** `MineEntry` hangs the ladder from the shaft column center (`_underground_position.x`), not the entry node's origin (which sits on a cell corner). The climb states in `unit.gd` rely on the column being straight: their "on the ladder column" check is what lets phase 2 (the vertical climb) run without re-triggering phase 1 (pathing to the ladder).
- **AI controller relies on `Unit` internals:** `ai_controller.gd` reads `unit._state` and `unit.data` directly, including the underscore-prefixed `_state` variable. Refactoring `Unit`'s state machine requires updating the AI controller too.
- **Building footprint writes into `_cells` directly:** `building.gd` mutates `GridWorld._cells` and `_astar` directly rather than using a public API.
- **No null-safe node access for UI:** `hud.gd` looks up the player controller and building at runtime with `get_node_or_null`; if the scene hierarchy changes, the HUD may silently stop updating.
- **Only the Web export preset is configured** (`build/MineAttack.html`); desktop presets were never set up. `tools/serve_web.py` serves the build with the COOP/COEP headers Godot 4 web builds require.
- **Viewport is 2560×1440** (`window/size` in `project.godot`, stretch `canvas_items`/`expand` with `window/stretch/scale=1.333333`). The stretch scale keeps UI and menus at a fixed logical 1920×1080 (`get_viewport().get_visible_rect()` always reports it), so layout never changes with window size. The in-game world is different: `PlayerController` sets the camera's base zoom to `visible_rect.width / window.size.x` (recomputed on `Window.size_changed`), so world pixels render 1:1 with physical pixels — a 2560×1440 window shows a 2560×1440 world area (nearly the whole map), a 1280×720 window a 1280×720 area. Wheel zoom is a 0.65–2.0 factor on top of that base (`_zoom_factor`, `_apply_zoom()`). Note `Window.content_scale_factor` does NOT track window size in `canvas_items` mode (it only carries the stretch scale) — don't use it for this math. When the view exceeds the camera-clamp bounds on an axis (whole world fits), the camera pins to the bounds center on that axis instead of panning into empty space, and `GridWorld` pads its backgrounds (`_BG_PAD` = 3200px, with solid edge-color bands above the sky and below the deepest layer) so oversize views never show unpainted void. The Web export injects full-bleed canvas CSS via `html/head_include`.
- **Headless teardown spam:** in `-s` SceneTree harnesses, after `quit()` the script unregistration can race node teardown and spam `Trying to return a value of type 'Node' ... 'PlayerController'` from `hud._get_player_controller` (kept alive by `process_mode = ALWAYS`). Harness-only noise after the check result; normal boots and gameplay are clean.
- **Resources are duplicated at spawn:** `building.gd` calls `data.duplicate(true)` so each unit gets its own mutable `UnitData`. Upgrades mutate that copy in `unit.gd`.
- **Autoloads survive scene reload:** `hud.gd` explicitly calls `GameManager.reset()` and `EconomyManager.reset()` before `get_tree().reload_current_scene()` so a new match starts fresh.
- **Fighter stats come from `.tres` resources:** `Constants.FIGHTER_STATS` was removed in Phase 2; `scripts/resources/units/*.tres` are the sole source of truth. Combat uses cooldown-based discrete hits (`damage_per_hit` / `attack_cooldown`).

---

## Useful files to read first

`project.godot` (input, autoloads, display) → `scenes/main.tscn` (scene hierarchy) → `scripts/autoload/game_manager.gd` + `economy_manager.gd` (global state) → `scripts/world/grid_world.gd` (map, pathfinding) → `scripts/units/unit.gd` (unit state machine, commands) → `scripts/controllers/player_controller.gd` + `ai_controller.gd` (how the game is driven).
