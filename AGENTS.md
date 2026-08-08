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
- **Target platforms:** Web, macOS, and Windows (all three presets defined in `export_presets.cfg`; macOS and Web are runnable presets).
- **Version control:** Git with LF-normalized text files (`.gitattributes`)

Key configuration files: `project.godot` (project settings, autoloads, input map, display, rendering, physics) and `export_presets.cfg` (Web export preset).

---

## Project structure

```
mine-attack/
├── project.godot / export_presets.cfg / icon.svg / README.md
├── scenes/                    # Godot scene files (.tscn)
│   ├── main.tscn              # Root gameplay scene (loaded from the main menu)
│   ├── building.tscn / mine_entry.tscn / projectile.tscn / unit.tscn
│   ├── lantern.tscn / tower.tscn / wall_segment.tscn   # placeable structures
│   ├── ui/                    # main_menu (project entry point), hud, debug_overlay
│   └── effects/               # coin_popup, damage_popup (floating text popups)
└── scripts/                   # GDScript source (details in §Code organization)
    ├── autoload/      # constants, game_manager, economy_manager, research_manager, debug_log, audio_manager
    ├── controllers/   # ai_controller, player_controller
    ├── resources/     # unit_data.gd + units/*.tres (miner, swordsman, archer, wizard)
    ├── ui/            # hud, debug_overlay, layer_indicator, training_queue_panel, research_panel, unit_button
    ├── effects/       # coin_popup, damage_popup
    ├── units/         # unit.gd (state machine), projectile.gd
    └── world/         # grid_world, building, mine_entry, lantern
```

A multi-phase revamp guide lives at `improvements/revamp.md` (with new sprites staged in `improvements/mine_attack_sprites/`). **Revamp Phases 1 (Fog of War & lanterns), 2 (factions), and 3 (placeable structures: sentry towers & walls) are implemented**; later phases (dynamic terrain, weather, tech-tree overhaul, AI belief system) are not.

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
- `Structures` — runtime container for built lanterns (Revamp Phase 1).
- `PlayerController` — handles player input, selection, commands, and camera.
- `AIController` — handles enemy economy, mining, attacks, and defense.
- `UI/SelectionBox` — visual drag-selection rectangle.
- `UI/HUD` — resource labels, per-unit-type counts, and selection readout (top bar; a single selected unit shows name + live HP, miners also carried/capacity), training, stance, and disband (Kill) buttons (bottom bar), vertical training queue panel (right edge), game-over panel.

Autoload singletons (configured in `project.godot`, loaded in this order):

- `Constants` — centralized balance numbers and input action names. `DEBUG` (currently **false**) gates the debug overlay and `DebugLog`; `DEBUG_SEED` makes map generation deterministic when `DEBUG` is on. With `DEBUG` off, maps are random each match — test scripts that boot `main.tscn` call `seed(12345)` in `before_all` to get a deterministic layout.
- `GameManager` — global game state, `Team` enum, shared color palette, match timer, win/loss signals.
- `FactionManager` — Revamp Phase 2 faction system: each team's `FactionData` pick (player chosen in the main menu, enemy a hidden random pick per match; both persist across `reset()` like the difficulty), the hidden-faction identification state (a player unit within 8 cells of the enemy building reveals it — `identify_faction`, signal `faction_identified`, cleared per match by `reset()`), and the single source of truth for faction-modified unit costs (`get_unit_cost`, used by `building.queue_unit`, the AI budget checks, and the training buttons) plus starting coin/miner bonuses. A team with no faction (tests booting `main.tscn` directly) is fully neutral — base costs, base stats, 500 coin. Faction definitions are `FactionData` resources in `scripts/resources/factions/{arcane,brute,industrial}.tres`; the resource class carries the stat multipliers, cost overrides, starting bonuses, and per-ability flags.
- `EconomyManager` — coin balances, population counts, miner upgrade levels, units trained, coin mined. Emits `coin_changed`, `population_changed`, `miner_level_changed`, `stats_changed`. `reset()` seeds each team's wallet from `FactionManager.get_starting_coin()` (Industrial +200g).
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
  - Fog of War (Revamp Phase 1): per-type `VISION_*` radii in cells (miner 4 surface / 3 underground, swordsman 8, archer 12, wizard 10, dragon 14, building 10), `FOG_MEMORY_DURATION` (10s), `FOG_COLOR` (`#05070a`), `FOG_MEMORY_ALPHA` (0.7), and the lantern tables (`LANTERN_T1/T2/T3_COST` 200/600/1000, vision 8/14/22, `LANTERN_HP` 500, max 3 surface, min 3 cells apart; `UNDERGROUND_LANTERN_*` 100g, vision 6, 200 HP, max 5, min 2 cells apart; `LANTERN_SALVAGE_RATIO` 0.5).
  - `UNIT_REGEN_DELAY` (5s) / `UNIT_REGEN_PER_SEC` (2 HP/s): out-of-combat regeneration — units that avoid damage for the delay slowly recover HP.
  - Fighter stats are stored in `UnitData` resources under `scripts/resources/units/*.tres`; `FIGHTER_STATS` was removed in Phase 2 to keep a single source of truth.

- `game_manager.gd`
  - `enum Team { PLAYER, ENEMY }`, `enum Difficulty { EASY, NORMAL, HARD, NIGHTMARE, GODLY }`
  - Constants: team colors (`COLOR_PLAYER`, `COLOR_ENEMY`), terrain colors.
  - `DIFFICULTY_MODIFIERS`: per-difficulty AI modifiers — `coin` (deposit income), `train_time` (training duration), `upgrade_speed` (economy decision rate), `push_ratio`/`defend_ratio` (aggression thresholds), `retaliation` (per-hit chance a damaged AI sieger fights back), `wave` (attack-tempo multiplier scaling wave size thresholds and the wave tick — lower = earlier, more frequent waves), and `smarts` (0–3 behavior tier gating the AIController's smart behaviors: 1 = focus-fire defense + wounded retreat, 2 = + counter-attack windows + miner harassment, 3 = + counter-composition army mix). Fair-play rule (Easy–Nightmare): rates and behavior only, never rules (same unit stats, pop cap). **GODLY deliberately abandons fair play** — every smart behavior plus openly stacked rates (coin ×2.5, train ×0.45, decisions ×2.5, retaliation 1.0, near-constant push).
  - `difficulty` persists across `reset()` so Play Again keeps the choice; set via the debug overlay dropdown (Phase 6) or main menu (Phase 7).
  - `game_speed` (1.0 / 2.0 / 3.0 / 5.0 / 10.0) is the player-chosen `Engine.time_scale`, set from the HUD speed buttons; it also persists across `reset()`. The win cinematic overrides it temporarily (0.3 slow-mo), then `_process` restores `game_speed` on the wall clock.
  - Accessors: `get_ai_coin_multiplier()`, `get_ai_train_time_multiplier()`, `get_ai_upgrade_speed()`, `get_aggression_thresholds()`, `get_ai_retaliation_chance()`, `get_ai_smarts()`, `get_ai_wave_multiplier()`.
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
  - Provides UI callbacks: `train_unit(unit_id)`, `upgrade_miner()`, `upgrade_fighter(unit_id)`, `set_stance(stance)`, `set_view(underground)`, `kill_selected()`, `start_build_placement(kind)`.
  - Structure placement mode (Revamp Phases 1 & 3): `start_build_placement("lantern" | "underground_lantern" | "tower" | "wall")` spawns a cursor ghost (green/red validity tint + radius ring for lanterns/towers); left-click confirms via `try_place_structure(kind, world_pos)` (lanterns route to `try_place_lantern`; validation lives in `_placement_error`), right-click/Esc cancels. Fog-aware clicks: hidden enemy units and structures can't be clicked; right-clicking a visible enemy structure orders an attack.
  - Stances: `"attack"` (rush enemy building), `"defend"` (stop/hold in place), `"garrison"` (fall back and defend the base — underground fighters climb out, everyone gathers at the home building's deposit point and holds there via `garrison_home()`), `"rally"` (arms rally mode — the next **left-click** places an army-wide rally point, right-click cancels; fighters hunt every enemy on the surface, miners included, and fall back to the point; any explicit command cancels a unit's rally). Attack/Defend/Garrison are persistent **modes** (`_current_stance`, default `"defend"`): setting one works with zero fighters, and every fighter trained afterwards automatically gets the mode's order on spawn (building `unit_spawned` → `_on_fighter_spawned`; miners are exempt and always enter the mine). The HUD stance buttons are toggles highlighting the active mode. Rally is momentary and does not change the mode.

- `ai_controller.gd`
  - Tick-driven AI with separate timers for economy (`ENEMY_DECISION_INTERVAL` = 2s, scaled by the difficulty `upgrade_speed`), mining (1s), attack waves (`ENEMY_ATTACK_WAVE_INTERVAL` = 18s base, scaled by the difficulty `wave` tempo), and aggression updates (`ENEMY_AGGRESSION_INTERVAL` = 10s). The economy also re-runs instantly (deferred) on `coin_changed` / `miner_level_changed`, so upgrades, research, and training never wait out the tick ("pre-queued upgrades"). The economy tick **banks the next miner upgrade as a reserve** — fighter upgrades and research may only spend coin above the full reserve, otherwise the training drain keeps the wallet under 500/1500 forever and miners never advance past level 1. Fighter training budgets against a **60% partial bank** so army production trickles on while saving for level 3 instead of stalling completely. Miner training is fully exempt (miners pay for themselves) and the miner target grows with level (`5 + level * 2`). After the upgrade it buys fighter upgrades once a 250-coin cushion is safe (cheapest first), then research (sonar first, fortify when the base is hurt, then the fighter tech matching its most numerous fighter type); the sonar scan fires whenever its cooldown is up.
  - Trains a mixed army via `_ARMY_MIX` (swordsman 40% / archer 30% / wizard 20% / dragon 10%): `_pick_fighter_to_train(budget)` picks the affordable type furthest below its target share instead of always the most expensive affordable unit.
  - Culls surplus miners (`_cull_miners`) when population reaches `MAX_UNITS - 2`: training pauses at the cap, so the AI disbands miners beyond 3 (emptiest bags first, via `unit.kill()` — no refund) to free slots for fighters.
  - Attacks in **gathered waves** (`_launch_wave_if_ready`): the army holds at home until it reaches `_wave_threshold` (push 4 / balanced 7 / defend 12, each scaled by the difficulty `wave` tempo multiplier — higher difficulties march with smaller armies — and clamped to ≥ 3; all-in at 3 when the enemy base is under 25% HP), then every free surface fighter marches together — engaged fighters keep their duels. While `"push"` the launch check runs every frame instead of waiting for the wave tick.
  - Maintains an `_aggression_level` (`"defend"`, `"balanced"`, `"push"`) based on relative fighter counts; the push/defend ratios come from the difficulty modifiers. On `"defend"` the AI recalls strays idling far from home via `garrison_home()` instead of hiding part of the army underground.
  - Defends building when enemy units come within a 650px net. Defender targeting depends on the `smarts` tier: tier 0 (Easy) has each defender pick its own nearest threat so the defense spreads damage; tier 1+ scores intruders by `hp_fraction * 1000 + distance` so the defense focus-fires wounded enemies first.
  - Smart behaviors, gated by the difficulty `smarts` tier (see `GameManager.DIFFICULTY_MODIFIERS`; tuning constants are the `ENEMY_*` block in `constants.gd`). Several come from the enemy-AI improvement guide (Phases 1–4); deliberate deviations from it: no hidden economic cheats (fair play holds below Godly), "ore denial" means richest-bag raids (raiders can never enter the enemy mine, so underground veins are unreachable), and the guide's ML/search-heavy options are skipped on its own recommendation.
    - **Wounded retreat (tier 1+, 1s tactics tick):** fighters are pulled home (`garrison_home()`) to heal via out-of-combat regen — never while the base itself is under attack, and never units already near home. The check (`_is_wounded`) is both the legacy fixed rule (under 30% HP) and a **predictive** rule: if the unit's recent incoming DPS (a rolling 3s damage window in `unit.gd`, read via `get_incoming_dps()`) would kill it before it could walk home plus a 3s buffer (`ENEMY_RETREAT_PREDICT_BUFFER`), it retreats even at high HP. Healed fighters are swept into the next wave naturally.
    - **Army-wide focus fire (tier 1+, same tactics tick):** `_run_focus_fire()` tallies every AI fighter's current unit target; the most-attacked one (tiebreak: lowest HP fraction) becomes the focus and every other duelling fighter within 1.2× the distance switches to it (the distance rule prevents flip-flop). Sieges on buildings are untouched — retaliation owns those.
    - **Counter-attack window (tier 2+):** `_update_aggression_level` samples the player fighter count every 10s; a drop of ≥3 since the last sample immediately launches a wave with override threshold 4 (`_launch_wave_if_ready(4)`) instead of waiting out the wave timer.
    - **Miner harassment (tier 2+, 20s tick):** while not defending and with ≥ wave-threshold+2 fighters, a small raiding party (`2 + total_fighters / 15` free surface fighters) `attack_unit()`s the enemy's exposed surface miners (combat can't cross layers, so only deposit-trip miners are valid targets), preferring the fattest cargo bags first. Raiders in ATTACK are ignored by wave/defense logic and are re-swept when their target dies.
    - **Counter-composition army mix (tier 3):** `_effective_army_mix()` adjusts `_ARMY_MIX` against the player's army — dragon weight ×3 when player anti-air (archers+wizards) is under 30% of their fighters (dragons are only damageable by archers/wizards), and weight shifted from swordsman to archer/wizard against a melee-majority (>60%) army. It reads an **EMA scout memory** (`_player_comp_memory`, alpha 0.3 per aggression-tick sample via `_sample_player_composition()`) rather than the live count, so production counters the remembered army without mid-fight jitter. `_pick_fighter_to_train` uses it only at tier 3.
    - **Bait and switch (tier 2+, 45s tick):** `_run_bait()` sends the emptiest-bagged surface miner strolling toward the enemy base; the moment an enemy **fighter** comes within 300px, the gathered army launches (`_launch_wave_if_ready(4)`) at the undefended base and the bait is released (its idle handler resumes mining). Never while defending, and only with the army above wave critical mass.
    - **Combat predictor (tier 2+):** `_simulate_combat()` reduces both armies to {hp, dps, hits_air, air} buckets and runs 0.1s focus-fire steps for 2s (dragon immunity respected — only archer/wizard DPS touches dragons), returning the AI/player remaining-HP ratio. It **vetoes organic wave launches** below 0.6 (decisive loss; overrides and the nearly-dead-base all-in always go) and gates the wall breach at ≥ 1.1 ("can I win before they counter?" — otherwise keep mining).
    - **Economic timing attack (tier 2+):** each aggression tick resamples both teams' coin-mined rates from `EconomyManager.get_coin_mined()`. When the enemy out-mines the AI by >1.2× (`ENEMY_ECON_PRESSURE_RATIO`), the AI strikes immediately with whatever is gathered (`ENEMY_TIMING_ATTACK_ARMY` = 4) before the income gap widens; when the AI out-mines, it keeps scaling.
  - Selects ore based on distance, value, and side ownership — but only *discovered* ore (cells that already took mining damage or were revealed by an Ore Sonar scan; miners don't know where buried ore is), skipping cells reserved by other miners or blacklisted as unreachable by that miner.
  - Attempts central wall breach when pushing and no accessible unmined tiles remain.

### `scripts/world/`

- `grid_world.gd`
  - `CellType` enum: `EMPTY`, `SURFACE_GROUND`, `DIRT`, `ORE`, `WALL`.
  - `Cell` inner class holds type, hp, max_hp, layer, miner level requirement, coin value, wall flag, and a `claimed_by` miner reservation.
  - **Fog of War (Revamp Phase 1):** per-team `_vision_maps` (bool per cell) and `_memory_maps` (match_time last seen, -1 = never) recomputed every frame in `_process` from all vision sources (`_get_vision_sources`: living units via `unit.get_vision_radius()`/`get_vision_layer()`, buildings at `VISION_BUILDING`, built lanterns). Sources are layer-masked: lanterns, miners, and dragons only light their own layer (surface row vs. underground); other fighters and buildings light both. A cell that leaves vision stays *remembered* (dimmed) for `FOG_MEMORY_DURATION` (10s of `GameManager.match_time`), then returns to pitch-black fog; cells near live vision get a 2-cell soft edge. Only the PLAYER fog is rendered (`_draw_fog`); full-fog cells get drifting decoration — cloud puffs (`fog_surface.png`) on the surface, sparse mist puffs (`fog_underground.png`) underground — over the guaranteed-opaque fog color. Both teams have maps because combat/mining rules consult them symmetrically. Public API: `is_visible_to(team, world_pos)`, `is_remembered_by(team, world_pos)`, `fog_state_at(team, cell)` (0 fog / 1 remembered / 2 visible). Enemy units that leave the player's vision drop a frozen "?" silhouette (`_unit_ghosts`) that fades with the memory. `set_reveal_all(team, bool)` is a debug/test hook giving a team full vision — used by fog-agnostic test suites, never in gameplay. Coin and damage popups also hide themselves at positions the player cannot see, so enemy deposits/combat don't leak through the fog.
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
  - Fog of War (Revamp Phase 1): the **enemy** building is invisible until the player scouts its cell, then drawn at 30% brightness while only remembered — the enemy base starts every match hidden in fog.
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

- `lantern.gd` (`class_name Lantern`, scene `scenes/lantern.tscn`, parented under `Main/Structures`)
  - Fog of War vision structure (Revamp Phase 1). Surface lanterns are tiered (T1 200g/8 cells → T2 600g/14 → T3 1000g/22, upgraded in place at the same cell, 500 HP, 5s build); underground lanterns are single-tier (100g, 6 cells, 200 HP, 3s build) and permanently reveal buried ore in their radius on completion (`reveal_ore_in_radius` — the same `sonar_revealed` mechanism as Ore Sonar). Both are layer-locked: surface lanterns only light the surface row, underground lanterns only the tunnels.
  - Vision only counts once `is_built()`; lanterns are **invulnerable while under construction**. `take_damage` → at 0 HP the lantern leaves the `"lanterns"` group and drops half its `total_cost` as a `CoinPickup` (salvage).
  - `get_bounds_rect()` returns a zero-height strip at the lantern's ground line so `unit.attack_building()`'s stand point lands on a walkable cell (surface row / the lantern's own dug cell). Fighters auto-attack visible enemy lanterns, and right-clicking one orders an attack.
  - Placement rules are enforced by `PlayerController._lantern_placement_error()`: surface lanterns on the own half's surface row only (player x ≤ −2), ≥3 cells apart, max 3; underground lanterns in dug-out (EMPTY) tunnel cells on the own half, ≥2 cells apart, max 5. Deviation from the revamp guide: underground lanterns go in *dug* tunnel cells, not undug diggable cells (a lantern embedded in solid rock would collide with the mining reservation system).
  - Sprites: `frost_mines_assets/props/lantern_t1..t3.png`, `lantern_underground.png`, plus a code-drawn glow halo, team ring, build-progress and HP bars.

- `tower.gd` (`class_name Tower`, scene `scenes/tower.tscn`, parented under `Main/Structures`)
  - Sentry tower (Revamp Phase 3): static surface defense, group `"towers"`. Auto-attacks the highest-priority visible surface enemy in an 8-cell range every 1.2s (12 dmg) — priority fighters > miners > the remembered enemy building — firing homing projectiles from the sprite top (Arcane variant tints them purple). Built towers are also surface-only vision sources (10 cells, wired into `GridWorld._get_vision_sources`).
  - Faction variants from `FactionData` (neutral = Constants `TOWER_*`): Arcane 350g/600 HP, Brute 1200 HP/1.8s cooldown/18 dmg, Industrial 200g/2× build speed.
  - Same lifecycle rules as lanterns: 8s construction, invulnerable while building, 50% salvage pickup on destruction, zero-height-strip `get_bounds_rect()` for `attack_building`. Fighters auto-attack visible enemy towers (shared `_nearest_visible_enemy_structure()` scan with lanterns); right-click orders work too.
  - Placement (`PlayerController._tower_placement_error`): own half's surface row, not within 2 cells of a building footprint or mine entry, max 2 per team. Draws `frost_mines_assets/props/tower_player|enemy.png`, a rotating scan beam, team ring, and build/HP bars.

- `wall_segment.gd` (`class_name WallSegment`, scene `scenes/wall_segment.tscn`, parented under `Main/Structures`)
  - Placeable wall (Revamp Phase 3): single-cell surface barrier, group `"walls"`. Once the 3s construction finishes the wall seals its **entire column** — the surface cell plus every dug-out cell beneath it, kept sealed as miners dig new cells under it (`_seal_column` + a `cell_destroyed` hook), like the central wall that spans all layers. Otherwise A* routes enemies through tunnels dug below the surface row and the wall never gets attacked. Destruction frees the whole column (undug dirt stays solid on its own) and drops 50% salvage. **Seals are team-aware**: `GridWorld._wall_sealed_cells` maps each sealed cell to its owner, and `find_path(from, to, team)` lifts the caller's own seals for the duration of the query — a wall never blocks its builder (miners keep using tunnels under their own walls), while enemies get no route through. Blocking for enemies is enforced three ways: new A* paths route around the sealed cells, on completion the wall re-paths every *enemy* unit whose in-flight path crosses its column (`_repath_units_crossing_cell`), and per-frame movement can't step into an *enemy* wall's surface cell (`unit._is_wall_at`, also consulted by `_is_walkable_point` so kiting/Blink can't cross). Units already standing in the cell when the wall goes up may always step out. Enemy projectiles within 14px of the surface segment are absorbed by it. 400 HP, invulnerable while building, no attack, no vision. Max 2 segments per team (Industrial 3 at 30g) via `FactionManager.get_wall_cost/get_wall_max_count` (Constants `PLACED_WALL_*` — the plain `WALL_*` names belong to the central wall).
  - Placement (`PlayerController._wall_placement_error`): own half's surface row, unoccupied cell, under the faction cap. (The guide's chain placement and 10/15-segment caps were dropped — a 2D map this size has no room for long walls.) Walls are **not** auto-attacked; fighters break them via explicit right-click orders. Deviation from the guide: miners can't breach placed walls (mining only works underground in this game) — fighters destroy them.
  - The AI does not build towers/walls yet (the guide defers structure placement to the Phase 8 AI refactor).

### `scripts/units/`

- `unit.gd`
  - Large state machine: `IDLE`, `MOVE`, `ATTACK`, `MINE`, `DEPOSIT`, `ENTER_MINE`, `EXIT_MINE`, `CLIMB_UP`, `CLIMB_DOWN`, `DEAD`.
  - All AI/movement freezes when `GameManager.game_active` is false (match over); only the `DEAD` fade-out keeps running. Projectiles freeze mid-flight too.
  - Command API: `move_to`, `attack_unit`, `attack_building`, `mine_cell`, `deposit_coin`, `enter_mine`, `exit_mine`, `climb_up_ladder`, `climb_down_ladder`, `rally_to`, `garrison_home`, `stop`, `kill`. The ladder climbs are the auto-loop's way in and out of the mine; `enter_mine`/`exit_mine` teleport and remain as explicit-order fallbacks. `kill()` is the owner's disband order: instant death through `_die()` with no coin refund (the point is freeing the population slot; a miner's cargo still drops as a pickup).
  - Miners auto-enter mine on spawn, auto-seek diggable cells when idle, and flee toward friendly fighters or the mine entry when attacked (fleeing to the shaft's underground position when attacked below ground). When cargo is full (or nothing diggable remains), miners surface and walk to their building's deposit point to cash in before heading back down (Phase 3.1).
  - Mining seek (Phase 3.3 + Revamp Phase 1 blind dig): miners don't know where buried ore is — ore only counts as *discovered* once it yielded gold (`hp < max_hp`) or an Ore Sonar scan / underground lantern revealed it (`cell.sonar_revealed`); discovered ore is preferred at any distance. Otherwise the pick is a **blind dig**: a random choice among the nearest few diggable faces. The miner-level gate is enforced at seek time; targeted cells are reserved via `claimed_by`; cells that can't be pathed to go on a per-miner 10s blacklist; when nothing diggable remains, miners with cargo surface to deposit while empty-handed miners wait near the shaft bottom and re-scan every 5s — 2s for AI-team miners (`ENEMY_MINER_RESCAN_INTERVAL`, perfect worker allocation) — or immediately on any `cell_destroyed` signal, instead of yo-yoing up and down.
  - Fog of War (Revamp Phase 1): `get_vision_radius()` feeds GridWorld's vision sources (miners see less underground; dragons only get their flight radius on the surface) and `get_vision_layer()` layer-locks miners/dragons to their current layer. `_team_can_see(pos)` gates all targeting: auto-attack scans (fighters, splash picks, rally hunts, melee kiting threats, underground miner hunts, retaliation picks) skip enemies the team cannot see, an ATTACK lock on a unit **drops when the target enters fog**, and the enemy building is only auto-attacked once the team remembers it (explicit `attack_building` orders always work). Enemy-team units set `visible = false` while outside the player's vision.
  - Fighters auto-attack nearby enemies (fighters → building → enemy miners on own side) and patrol underground when idle. Combat never crosses the surface/underground boundary: `can_damage_unit()` rejects cross-layer targets (so `attack_unit` orders and all auto-attack scans skip them, dragons included), and an ATTACK lock drops if the target changes layer mid-chase (a miner fleeing down the shaft escapes).
  - Rally mode (`rally_to`): a fighter hunts any enemy on the surface — miners included (`_find_rally_target` skips underground enemies) — while travelling to and idling at the rally point. Underground rally points are rejected; underground fighters climb out first and resume the rally on the surface. Rally engagements bypass `attack_unit()` so `_rally_active` survives the kill (the unit then resumes the hunt); every explicit command cancels the rally via `_clear_target()`.
  - Standing points (`_post_point`): a fighter's idle anchor on the surface — set at spawn, updated by explicit `move_to` (new post) and `stop` (hold here). Attack and auto-attack engagements leave it unchanged, so when the fighting ends the fighter paths back to its post (`_return_to_post_if_needed`) and the army regroups at base instead of spreading across the map.
  - Defend leash (`_hold_post` / `_auto_engaged`): hold-style orders (`stop`, `garrison_home`) set `_hold_post`; movement/attack/rally orders clear it. Targets picked by the idle auto-attack scan are marked `_auto_engaged`. While both are set, the unit only notices targets within `_defend_leash_range()` of its post (never the enemy building — defend units never wander into a siege) and drops the chase once it strays past the leash, then walks home. The leash is `UNIT_DEFEND_LEASH_RANGE` (400) normally, but pulls in to `UNIT_DEFEND_LEASH_UNDER_ATTACK` (150) while the team's building is under attack (`building.is_under_attack()` — 4s after the last hit, `BUILDING_UNDER_ATTACK_SEC`), so defenders finish the fight at the base instead of being lured away. Explicit orders are never leashed, so attack-mode and right-clicked units chase freely.
  - Death drops: a miner that dies with cargo drops its full carried coin as a `CoinPickup` on the spot (any team, any layer), so the coin is never lost; any miner that walks over the pickup collects it.
  - Siege retaliation: a fighter locked onto a building re-evaluates when an enemy fighter damages it — it peels off to fight back (`_maybe_retaliate` / `_pick_retaliation_target`: prefer the attacker if reachable, else the closest enemy fighter in sight on the same level). Player units always retaliate; AI units roll per hit against the difficulty's `retaliation` chance (Easy 0.25 → Godly 1.0). Units already duelling a unit never flip-flop.
  - Fighters move at 60% speed while underground.
  - Ranged standoff (kiting): a fighter with `attack_range > 35` takes a direct steering step away (`_kite_away_from`) while staying in ATTACK and firing on cooldown whenever a threat slips inside `UNIT_KITE_RANGE_FRACTION` (0.6) of its range — the current target, or the nearest enemy **melee** unit (`_nearest_melee_threat`) even while shooting something else, so melee never closes for free. `_is_walkable_point` bounds the step (surface row or EMPTY cells underground) — no pathing, so the target lock is never dropped. Melee units and building sieges are unaffected.
  - Splash-aware targeting: fireball users (wizard/dragon, `aoe_radius > 0`) pick auto-attack targets by splash count (`_pick_splash_target` — the enemy fighter whose position catches the most enemies in the AoE) instead of closest-first, so fireballs aren't wasted on lone stragglers.
  - Incoming-DPS window: `take_damage` appends to a rolling 3s `_damage_log` (aged in `_process`); `get_incoming_dps()` reads it — used by the AI's predictive retreat.
  - Out-of-combat regen: `take_damage` starts a 5s no-damage countdown; once it elapses the unit regains 2 HP/s up to `max_hp`, with a green `+N` popup on each heal tick. Applies to all units, both teams (miners heal between trips too).
  - Applies miner upgrade bonuses dynamically (`_apply_miner_upgrade`) and team-wide fighter upgrade stats (`_apply_fighter_upgrade` — swordsman/archer/wizard HP/damage per level from `Constants.FIGHTER_UPGRADES`, healing the max_hp delta on level-up), plus research-tree bonuses (`_apply_research_bonuses` — bulwark armor, longbow range, inferno AoE, reinforced-pack carry, applied as deltas so re-application never compounds).
  - Custom `_draw()` renders units as sprite assets from `frost_mines_assets/units/` when available, falling back to colored rectangles with class-specific weapon icons if no sprite is assigned. Miners swap sprite by team and upgrade level. All units show an HP bar when damaged, hovered, or selected; miners also show a gold `carried/capacity` cargo readout above the HP bar while hauling or when hovered/selected. Units use `frost_mines_assets/effects/selection_ring.png` for selection (with a gentle pulse), a warm lantern glow when mining underground, and flash `frost_mines_assets/effects/impact_hit.png` briefly on damage. Units are always visible in both views (surface and underground render simultaneously). Mining swings, melee hits, and projectile launches play positional SFX via `AudioManager`.
  - Dragon flight: feet stay on the ground for A*/kiting (`global_position`); surface dragons use `flight_altitude` (40px) via `get_combat_position()` for draw offset, shadow, hover, click/box pick, attack/sight range, and projectile spawn/homing/impact. Altitude is 0 underground. Dragons take damage only from archers/wizards (Euclidean range to the air aim point).
  - Phase 3.4 traffic: each unit gets a small `_movement_offset` applied to miner deposit and mine-entry targets, and `_follow_path()` applies soft repulsion from nearby friendly units so surface parades don't stack into a single sprite. Path arrival is step-aware (`max(2px, speed * delta)`) so large deltas (lag spikes, high `Engine.time_scale`) can't orbit a path point forever against the separation nudge; a large step also advances past every point it covers and moves the unit onto the final point before completing, so a huge delta (10x speed at a low frame rate) can't finish the path while the unit is still out of range of its destination (miners used to freeze mid-approach).

- `projectile.gd`
  - Homing arrow / fireball projectile.
  - Fireballs deal splash damage to units and buildings in a larger radius.
  - Homing and unit impact use `get_combat_position()` when present (flying dragons).
  - Draws `frost_mines_assets/effects/projectile_arrow.png` for arrows and `frost_mines_assets/effects/projectile_blast.png` for wizard fireballs. Dragon shots set `is_dragon_flame` (same splash mechanics, `is_fireball` stays true) and are code-drawn as fire breath instead: a layered flickering flame head (red body / orange mid / yellow-white core, licking forward along the flight direction) with a fading ember trail recorded from recent positions — no particle nodes or extra assets.

### `scripts/resources/`

- `unit_data.gd` — `Resource` subclass defining all unit stats and per-team sprite textures (`player_textures`, `enemy_textures`), plus optional `flight_altitude` / `draw_scale` for flyers.
- `units/*.tres` — concrete stats for Miner, Swordsman, Archer, Wizard, Dragon. These are the authoritative source of unit stats at runtime; `building.gd` duplicates the resource for each spawned unit.
- `faction_data.gd` + `factions/*.tres` — Revamp Phase 2 faction definitions (Arcane / Brute / Industrial): per-type stat multipliers, miner mining/carry/HP modifiers, unit-cost multiplier + per-type cost overrides, starting gold/miner bonuses, and ability flags. Faction stat multipliers are **folded into `unit.gd`'s per-tick recompute functions** (`_apply_fighter_upgrade`, `_apply_miner_upgrade`, `_apply_research_bonuses`) rather than set once — those functions re-derive stats from Constants tables every tick/level-up, so one-shot mutation would be erased; spawn-only stats (dragon HP/damage, miner HP bonus) are applied once in `_apply_faction_bonuses()`. Abilities: Rune Blade (first hit of an engagement +50%, re-arms in `_clear_target`), Berserk (+40% attack speed below 30% HP), Swarm (swordsmen +15% speed in groups of 3+ within 6 cells), Fortify (+30% fireball AoE), Blink (all wizards teleport away from point-blank melee threats, 15s cooldown, 10s for Arcane), Arcane Shot (every 8s an archer's arrow gets `pierce` — on impact it also strikes the nearest enemy within 64px behind the first target), Heavy Bolt (archer hits apply a 30% / 2s movement slow via `apply_slow`), Volley (every 12s, friendly archers within 50px all fire at the same target; participants share the cooldown so volleys can't chain), Fight Back (miners deal 5 damage to fighter attackers), Miner Reveal (personal 4-cell ore scan, 30s cooldown), Mana Burn (dragon flame sets `_next_attack_damage_mult = 0.8`, consumed on the victim's next hit), Crush (dragon flame stuns 0.5s via `apply_stun` — stunned units skip all state processing), Supply Drop (dragon kills +10g). Slow/stun are generic debuffs on `Unit` (`_slow_mult`/`_slow_timer`, `_stun_timer`), so future abilities can reuse them.

### `scripts/ui/`

- `hud.gd` — wires non-training buttons to `PlayerController`, listens to economy signals, updates labels (including the live per-unit-type counts in the top bar), toggles surface/underground view, owns the 1×/2×/3×/5×/10× game-speed buttons (via `GameManager.set_game_speed`), shows the game-over stats panel (1.4s after `game_over`, fading in once the slow-mo collapse has played) with Play Again and Quit to Menu, and adds icon sprites from `frost_mines_assets/icons/` to stat labels and the attack stance button. The **Build button** (Revamp Phases 1 & 3) opens a small popup above the bottom bar with the four structure options (surface/underground lantern, sentry tower, wall — cost + live count/max, disabled when unaffordable or capped); picking one hands placement mode to `PlayerController`. Runs with `process_mode = ALWAYS` and owns the pause menu (full-screen dim: Resume / Restart / Quit to Menu / difficulty / resolution), synced to `get_tree().paused` — Space/Esc toggles it via `PlayerController`. In-game Quit buttons return to the main menu (`_quit_to_menu`: unpause, reset autoloads, `change_scene_to_file`) instead of closing the app — quitting is a no-op in the web export; only the main menu's own Quit exits.
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

The project has three configured export presets in `export_presets.cfg` (all exclude `addons/*` and `tests/*` — GUT is dev tooling and must not ship in the release pck):

- **Web** — exports to `build/MineAttack.html`.
- **macOS** — exports a universal (x86_64 + arm64) `build/MineAttack.app`; runnable preset. Unsigned: on other Macs Gatekeeper will block it until the user right-clicks → Open (or runs `xattr -cr MineAttack.app`); sign + notarize with an Apple Developer ID for friction-free distribution.
- **Windows** — exports a single-file `build/MineAttack.exe` (x86_64, pck embedded via `binary_format/embed_pck=true`). Unsigned: SmartScreen may warn on first run.

To export from the command line:

```bash
tools/export_all.sh   # all three presets in one go (set GODOT=/path/to/Godot if it isn't found)
```

The script also zips the desktop builds for distribution into the **project root** (easier to find than `build/`): `MineAttack-macOS.zip` (via `ditto`, preserving the bundle metadata) and `MineAttack-Windows.zip` (the single-file exe). The root zips are gitignored.

or one preset at a time:

```bash
godot --headless --path . --export-release "Web" build/MineAttack.html
godot --headless --path . --export-release "macOS" build/MineAttack.app
godot --headless --path . --export-release "Windows" build/MineAttack.exe
```

> Export templates: the exact `Godot_v4.7.1-stable_export_templates.tpz` templates are installed in `~/Library/Application Support/Godot/export_templates/4.7.1.stable/` (a real directory now — the old `4.7.stable` dir holds the 4.7.0 templates as a fallback). The macOS/Windows exports require `textures/vram_compression/import_etc2_astc=true` in `project.godot` (enabled for the universal macOS binary).

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
  - `"lanterns"` / `"towers"` / `"walls"` — placeable structures (Revamp Phases 1 & 3).
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
| `kill_units` | K / Delete |
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
  - The AI buys them in its economy tick once it keeps a 250-coin reserve (cheapest first).
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
- **AI difficulty** (`GameManager.DIFFICULTY_MODIFIERS`; Easy–Nightmare are fair-play — rates and behavior only, never rules. Godly abandons fair play on purpose):

  | Difficulty | AI coin × | Train time × | Decision rate × | Retaliation | Smarts | Wave tempo | Aggression bias |
  |------------|-----------|--------------|------------------|-------------|--------|------------|-----------------|
  | Easy | 0.9 | 1.0 | 0.8 | 0.35 | 0 | 1.15 | Defensive (push 1.8×, defend 0.8×) |
  | Normal | 1.15 | 0.95 | 1.15 | 0.6 | 2 | 1.0 | Balanced (push 1.4×, defend 0.5×) |
  | Hard | 1.4 | 0.8 | 1.45 | 0.8 | 3 | 0.85 | Aggressive (push 1.2×, defend 0.35×) |
  | Nightmare | 1.75 | 0.65 | 1.8 | 1.0 | 3 | 0.7 | Very aggressive (push 1.1×, defend 0.2×) |
  | Godly | 2.5 | 0.45 | 2.5 | 1.0 | 3 | 0.55 | Relentless (push 1.0×, defend 0.15×) |

  Wave tempo multiplies the wave size thresholds (push 4 / balanced 7 / defend 12) and the 18s wave tick — lower = earlier, more frequent attacks. Smarts tiers: 1 = focus-fire defense + wounded retreat, 2 = + counter-attack windows + miner harassment, 3 = + counter-composition army mix (see `ai_controller.gd`).

---

## Testing

The project uses [GUT](https://github.com/bitwes/Gut) 9.6.1 (committed under `addons/gut/`). The suite lives in `tests/` and boots the real `main.tscn`, so it exercises the actual building/grid/unit wiring:

- `tests/test_economy.gd` — spend/refund/upgrade math, cap guards, team wallet separation.
- `tests/test_building_queue.gd` — FIFO order, queue accepts beyond the population cap, training pauses at the cap and resumes when population frees (no despawn, no refund churn), cancel refunds (queued + in-progress).
- `tests/test_grid_world.gd` — ore trickle totals, A* clearing on destruction, level gates, wall shared-HP pool, `nearest_walkable_cell`/`cells_adjacent_to_rect` around the building footprint, no tile regen.
- `tests/test_unit_guards.gd` — fighter `mine_cell` rejected, enemy mine entry rejected, unreachable mine target blacklisted, empty-cargo deposit rejected, cross-layer attack rejected (auto-attack skip, mid-chase drop), `_follow_path` large-delta arrival, corpse hits don't double-remove population (`take_damage` ignores `DEAD` units — in-flight projectiles can still land during the 1s fade-out, and without the guard each hit re-ran `_die()` and leaked a population slot past `MAX_UNITS`).
- `tests/test_ai_retaliation.gd` — player sieger deterministically retaliates against its attacker, damaged AI sieger eventually retaliates (per-hit difficulty roll), undamaged sieger stays on the building, retaliation chance scales with difficulty.
- `tests/test_ai_strategy.gd` — AI banks and buys miner upgrades despite ongoing training, fighter training dips into the 60% partial bank (but holds below it), army-mix picker diversifies, waves hold below threshold / launch together at it, wave thresholds scale with the difficulty tempo, all-in when the enemy base is nearly dead.
- `tests/test_ai_smarts.gd` — difficulty `smarts` tier gating: focus-fire vs nearest defense targeting, wounded retreat (skipped on Easy / held under base attack), miner harassment raids (surface-only targets, never below wave critical mass, gated off on Easy), counter-attack windows on sharp player losses, counter-composition mix (dragon spike vs missing anti-air, fed through the scout-memory sampler), Godly modifiers.
- `tests/test_ai_micro.gd` — improvement-guide behaviors: incoming-DPS window + decay, predictive retreat (doomed fighter pulled at 60% HP, safe fighter stays), army-wide focus fire (converges, leaves sieges alone), wizard splash targeting (cluster over lone target), bait-and-switch (miner sent, trap springs on defender contact), combat predictor (bigger army wins, dragon immunity), wave veto on a hopeless sim, economic timing attack (fires when out-economied, holds at parity).
- `tests/test_rally.gd` — rally targets surface miners, skips underground enemies, engagement keeps the rally active, explicit commands cancel it, miners can't rally, miner death drops full cargo as a pickup.
- `tests/test_stance_modes.gd` — stance modes persist with zero fighters, attack/garrison/defend modes auto-order newly spawned fighters, miners ignore modes, rally doesn't change the mode.
- `tests/test_defend_leash.gd` — defend leash: auto-engaged holders chase within 400px of the post and drop the target beyond it, held units ignore far targets and never auto-siege the enemy building, explicit attack/move orders are unleashed, garrison sets the hold, and the leash pulls in to 150px while the own building is under attack (close attackers still fought, distant ones ignored).
- `tests/test_kill_units.gd` — `kill()` disbands without refund but frees population, disbanded miners drop cargo pickups, `kill_selected` only kills the selection, AI culls surplus miners at the population cap (never below it).
- `tests/test_research.gd` — research purchase guards (unknown/busy/unaffordable/maxed/prerequisites), timed completion and pause freeze, 100% cancel refund, fortify/longbow/bulwark/reinforced-pack effects, tier-2 effects (swift boots, berserk, rapid fire, arcane might, self-repair regen + overheat cap, deep scan sonar level), research bonuses surviving miner upgrades, sonar scan reveal + cooldown, `reset()` clearing.
- `tests/test_dragon.gd` — dragon immunity (archer/wizard only), auto-attack skip, fireball splash via source, train queue, surface flight combat position / underground grounded, Euclidean air-range gate, projectile homing to combat pos, `_filter_dragons`.
- `tests/test_fog_of_war.gd` — vision maps (base lit at start, enemy side fogged, remember → fade cycle), per-type vision radii, enemy hiding + "?" ghost silhouettes, attack locks dropping in fog, lantern placement rules (own half, surface/tunnel cells, min distance, max counts), build/upgrade/destruction (salvage pickup, vision loss, invulnerable while building), underground lantern ore reveal, auto-attacking enemy lanterns. Fog-agnostic suites (rally, defend leash, retaliation, AI micro) call `GridWorld.set_reveal_all(team, true)` in `before_all` so unit placement — not vision — drives their outcomes. **Gotcha:** in this GUT version `wait_frames()` does not pump node `_process` in the headless harness — use `await wait_seconds(...)` in tests that need frames to advance.
- `tests/test_factions.gd` — Revamp Phase 2: industrial starting coin/miners and cost overrides, arcane cost multiplier, neutral-default contract (base costs/stats/500 coin with no faction), faction stat multipliers (brute swordsman, arcane wizard, brute/industrial miners), all abilities (rune blade, berserk, swarm, arcane shot pierce + cooldown, blink range + both cooldowns, heavy bolt slow, crush stun, volley, fight back, miner reveal, mana burn, supply drop), and hidden-faction scouting. **Gotcha:** the suite sets factions per test and must restore the neutral default in `after_all` (`set_player_faction("")`, `enemy_faction_id = ""`, `FactionManager.reset()`, `EconomyManager.reset()`) — faction picks persist across suites through the autoload and would break every later suite's hard-coded 500-coin/base-cost assertions.
- `tests/test_structures.gd` — Revamp Phase 3: tower placement rules (own half, surface only, 2-cell building/mine-entry clearance, max 2), construction invulnerability, tower vision + firing + fighter-over-miner priority, salvage pickup, fighter auto-attack on enemy towers, wall placement (open ground, occupancy/underground/own-half rejects, max count 2), wall A* block/unblock, full-column tunnel sealing (existing digs, re-seal on fresh digs, freed on destruction), re-pathing of units whose in-flight path crosses a finished wall, wall cells rejected by `_is_walkable_point` (kiting/Blink), and projectile absorption by walls. **Gotcha:** `before_each` frees all towers/walls (tests reuse fixed cells), and units spawned for structure tests must stand on the surface row (y offset 0, not +16) or they land in cell row 1 where surface-layer tower vision can't see them.

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
- **Web, macOS, and Windows export presets are configured** (`build/MineAttack.html`, `build/MineAttack.app`, `build/MineAttack.exe`). `tools/serve_web.py` serves the web build with the COOP/COEP headers Godot 4 web builds require.
- **Viewport is 2560×1440** (`window/size` in `project.godot`, stretch `canvas_items`/`expand` with `window/stretch/scale=1.333333`). The stretch scale keeps UI and menus at a fixed logical 1920×1080 (`get_viewport().get_visible_rect()` always reports it), so layout never changes with window size. The in-game world is different: `PlayerController` sets the camera's base zoom to `visible_rect.width / window.size.x` (recomputed on `Window.size_changed`), so world pixels render 1:1 with physical pixels — a 2560×1440 window shows a 2560×1440 world area (nearly the whole map), a 1280×720 window a 1280×720 area. Wheel zoom is a 0.65–2.0 factor on top of that base (`_zoom_factor`, `_apply_zoom()`). Note `Window.content_scale_factor` does NOT track window size in `canvas_items` mode (it only carries the stretch scale) — don't use it for this math. When the view exceeds the camera-clamp bounds on an axis (whole world fits), the camera pins to the bounds center on that axis instead of panning into empty space, and `GridWorld` pads its backgrounds (`_BG_PAD` = 3200px, with solid edge-color bands above the sky and below the deepest layer) so oversize views never show unpainted void. The Web export injects full-bleed canvas CSS via `html/head_include`.
- **Headless teardown spam:** in `-s` SceneTree harnesses, after `quit()` the script unregistration can race node teardown and spam `Trying to return a value of type 'Node' ... 'PlayerController'` from `hud._get_player_controller` (kept alive by `process_mode = ALWAYS`). Harness-only noise after the check result; normal boots and gameplay are clean.
- **Resources are duplicated at spawn:** `building.gd` calls `data.duplicate(true)` so each unit gets its own mutable `UnitData`. Upgrades mutate that copy in `unit.gd`.
- **Autoloads survive scene reload:** `hud.gd` explicitly calls `GameManager.reset()` and `EconomyManager.reset()` before `get_tree().reload_current_scene()` so a new match starts fresh.
- **Fighter stats come from `.tres` resources:** `Constants.FIGHTER_STATS` was removed in Phase 2; `scripts/resources/units/*.tres` are the sole source of truth. Combat uses cooldown-based discrete hits (`damage_per_hit` / `attack_cooldown`).

---

## Useful files to read first

`project.godot` (input, autoloads, display) → `scenes/main.tscn` (scene hierarchy) → `scripts/autoload/game_manager.gd` + `economy_manager.gd` (global state) → `scripts/world/grid_world.gd` (map, pathfinding) → `scripts/units/unit.gd` (unit state machine, commands) → `scripts/controllers/player_controller.gd` + `ai_controller.gd` (how the game is driven).
