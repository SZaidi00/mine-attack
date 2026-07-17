# Frost Mines / MineAttack — Remaining Functionality Build Plan

**Created:** 2026-07-16
**Engine:** Godot 4.7 (GDScript, Jolt Physics, gl_compatibility)
**Scope:** Take the current MineAttack codebase from "units spawn but core loops don't visibly work" to a fully playable, verifiable match: mine → earn → train → fight → destroy enemy building.
**Primary symptoms to fix:**
1. Swordsman (and fighters generally): issuing **Attack** does nothing — no movement toward the enemy, no damage dealt.
2. Miner: enters the mine but is **never seen mining**, and never visibly **returns to the building to drop off gold**.

---

## 0. How to Use This Plan

- Phases are ordered so that **each phase produces a testable, visible result**. Do not skip ahead — later phases depend on the command pipeline and debug tooling from Phases 0–1.
- Every phase ends with **Acceptance Criteria**: a manual test script you run in the editor (F5). A phase is not "done" until its script passes.
- Where the design doc and the current code disagree (they do in several places — called out below), this plan makes an explicit decision. Decisions are marked **[DECISION]**.
- File references follow the structure in `AGENTS.md` (`scripts/units/unit.gd`, `scripts/world/grid_world.gd`, etc.). Read files in the order listed in AGENTS.md §"Useful files to read first" before editing.

### 0.1 Known design-vs-code conflicts to resolve up front

| # | Topic | Design doc says | AGENTS.md says code does | Decision needed |
|---|-------|-----------------|--------------------------|-----------------|
| C1 | Damage model | Cooldown-based discrete hits (Swordsman 0.5s interval) | "Damage = DPS × delta_time", and table contradicts itself (15 DPS vs 30 dmg/0.5s = 60 DPS) | Phase 2 |
| C2 | Deposit location | Miner walks to **Player Building** to deposit | `mine_entry.deposit(unit)` converts cargo at the mine shaft | Phase 3 — **[DECISION]** deposit happens at the **building** (visible surface leg), per design doc §5.1 and the user's reported expectation |
| C3 | Fighter stats | `Constants.FIGHTER_STATS` | Unused; `.tres` files are authoritative | Phase 2 — keep `.tres` as source of truth, delete/deprecate `FIGHTER_STATS` |
| C4 | Tile visuals | Better Terrain autotiling on destroy | Per-layer sprite swap via `_draw()` | Phase 5 — keep simple sprite swap, skip Better Terrain for now |

---

## Phase 0 — Recon, Instrumentation & Debug Tooling

**Goal:** Make the invisible visible. You cannot fix "nothing happens" bugs without seeing unit state, command dispatch, and pathfinding in real time. This phase adds no gameplay — only observability — and removes guesswork from every later phase.

### 0.1 Code reconnaissance checklist

Read and annotate these before touching anything:

1. `project.godot` — confirm autoload order (`Constants` → `GameManager` → `EconomyManager`), input map actions exist, physics layer names.
2. `scenes/main.tscn` — verify node names match the hard-coded paths (`/root/Main/World/GridWorld`, etc. — see Gotchas in AGENTS.md). Record the actual hierarchy.
3. `scripts/units/unit.gd` — map the real state machine: list every state, every transition condition, every command API entry point (`move_to`, `attack_unit`, `attack_building`, `mine_cell`, `deposit_coin`, `enter_mine`, `exit_mine`, `stop`). Note where `_state` is written.
4. `scripts/controllers/player_controller.gd` — trace the full path from `InputEvent` → selection → right-click context resolution → unit command call.
5. `scripts/world/grid_world.gd` — confirm `AStarGrid2D` setup: which cells are solid, how `damage_cell()` works, how the building footprint is written into `_cells`/`_astar`, and whether paths are ever recomputed after cells change.
6. `scripts/world/building.gd` — queue processing, spawn logic, how spawned miners are told to enter the mine.
7. `scripts/controllers/ai_controller.gd` — which `Unit` internals it touches (`unit._state`, `unit.data`).

### 0.2 Build a debug overlay (new file: `scripts/ui/debug_overlay.gd` + scene)

Toggle with **F3**. Renders, per unit (via `_draw()` on a CanvasLayer or on the unit itself):

- Current state as text above the unit's head: `Unit.State.keys()[unit._state]` — e.g. `IDLE`, `MOVE`, `ATTACK`, `MINE`, `DEPOSIT`.
- Current target (unit/building/cell coordinates) as a line from unit → target.
- The unit's active A* path as a polyline.
- Miner cargo: `cargo / capacity`.

Global panel (top-left, behind a `PanelContainer`):

- FPS, unit counts per team, player coin, AI coin, queue contents, `_aggression_level`, game active flag.
- Buttons: **+500 coin**, **Spawn Swordsman (player)**, **Spawn Miner (player)**, **Teleport selected to cursor**, **Reveal all underground** (draws all cells, bypasses view toggle).

### 0.3 Command dispatch logging

- Add a tiny ring-buffer logger (e.g. `scripts/autoload/debug_log.gd`, or guarded `print_rich` behind `Constants.DEBUG`).
- Log at these exact points:
  - `player_controller.gd`: every resolved command (`"RMB on building(1234) -> attack_building for 3 selected units"`).
  - `unit.gd`: every state transition (`"Unit 45: IDLE -> MOVE (target=(12,3))"`), and every *rejected* command with reason (`"ATTACK rejected: no path to target"`).
  - `building.gd`: queue add/cancel/complete; `mine_entry.gd`: enter/exit/deposit.
- **[IMPORTANT]** Rejections must never be silent. Every `if` that can early-return out of a command gets a log line. "Nothing happens" bugs are almost always silent early-returns.

### 0.4 Determinism & test harness basics

- Seed the RNG used by `grid_world.gd` map generation (`seed(Constants.DEBUG_SEED)` when debugging) so ore layout is identical every run.
- Add a `Constants.DEBUG` flag gating all of the above so it compiles out for release.

### Acceptance Criteria — Phase 0

- [ ] F3 shows every unit's live state, target line, and path.
- [ ] Right-clicking anything produces exactly one log line describing the resolved command. (Known Phase 0 exception: the fall-through resolver can also log a wall/diggable probe with 0 matching units before the final command line — acceptable here; Phase 1 makes resolution exclusive.)
- [ ] Every state transition and rejection appears in the log with a reason.
- [ ] Map layout is identical across two runs with debug seed set.

**Estimated effort:** 0.5–1 day. **Unblocks:** everything.

---

## Phase 1 — Command & Control Pipeline ("Attack Does Nothing")

**Goal:** A right-click or stance button on the player side reliably results in a unit state change and movement. This phase fixes the *plumbing*; Phase 2 fixes the *combat math* that runs once plumbing works.

### 1.1 Trace the exact failure (using Phase 0 tooling)

Reproduce the reported bug: spawn a Swordsman → select → right-click enemy building (or press the Attack stance button). Read the debug log and match against these hypotheses, in order of probability:

| # | Hypothesis | How to confirm | Where |
|---|-----------|----------------|-------|
| H0 | Input pipeline dead: `player_controller.gd` fails to compile (or `_unhandled_input` never fires) → no selection, commands, camera pan, or Tab view toggle at all | Click with nothing selected: log shows **zero** lines — not even the "no selected units" reject | Script load errors in the console; `player_controller.gd` |
| H1 | Stance button not wired: `hud.gd` never calls `player_controller.set_stance("attack")`, or the signal isn't connected in the scene | Click Attack; no log line at all | `hud.gd`, `hud.tscn` signal connections |
| H2 | Stance filters the wrong group: e.g. commands sent to `"units"` but miners included / fighters excluded, or it only commands *selected* units while stance is meant to command *all* fighters | Log shows command issued to 0 units or wrong units | `player_controller.set_stance()` |
| H3 | Right-click target detection misses: enemy building not in `"buildings"` group, or the Area2D hitbox has wrong collision layer/mask so the pick query returns nothing | Log shows `RMB -> move` (ground) instead of `attack` when clicking the building | `building.tscn` collision setup, group membership, `player_controller` pick logic |
| H4 | Command accepted but path fails: building footprint cells are marked solid in `_astar` (AGENTS.md confirms `building.gd` writes them solid), and `attack_building` paths to the building's *own cell* instead of a walkable adjacent cell → `get_id_path()` returns empty → silent abort | Log: `"ATTACK rejected: no path to target"` | `unit.attack_building()`, `grid_world.gd` |
| H5 | Path succeeds but range check measures distance to the **building center**, which is > attack range forever → unit arrives at adjacent cell, never enters ATTACK, stands idle | Overlay shows unit parked next to building in `MOVE`/oscillating state | `unit.gd` range check |
| H6 | State entered but damage timer never started / cooldown var never reset on state entry | State shows `ATTACK`, HP never drops | `unit.gd` ATTACK state |
| H7 | `move_and_slide()` blocked: unit collision layers make fighters collide with the building's StaticBody2D and stop short, outside range | Unit visibly stuck against building edge | `unit.tscn` collision layers |

Expect the true cause to be **H3+H4 or H4+H5 combined**: right-click resolves to "move", and even a correct attack command can't path to a solid target cell.

> **Update (2026-07-16): H0 was the confirmed root cause.** `player_controller.gd` called `Camera2D.project_position()`/`unproject_position()` — Camera3D-only APIs — so the script failed to compile and the entire player input pipeline (selection, commands, camera, Tab view toggle) was dead. This alone explains both reported symptoms: attacks could never be issued, and underground mining could never be seen. Fixed by converting through `get_viewport().get_canvas_transform()`; verify H1–H7 anyway once input is confirmed working.

### 1.2 Implementation fixes

**`grid_world.gd` — add public helper APIs** (stops other scripts from poking `_cells`/`_astar` directly, per Gotchas):

```gdscript
func nearest_walkable_cell(to_cell: Vector2i, max_radius: int = 4) -> Vector2i
func cells_adjacent_to_rect(rect: Rect2i) -> Array[Vector2i]   # walkable ring around a footprint
func is_walkable(cell: Vector2i) -> bool
func world_to_cell(pos: Vector2) -> Vector2i
func cell_to_world(cell: Vector2i) -> Vector2
```

**`unit.gd` — canonical attack-target flow** (applies to `attack_unit` and `attack_building`):

1. Resolve target's *interaction cells*: for units → the unit's current cell (refreshed as it moves); for buildings → `cells_adjacent_to_rect(building_footprint)`.
2. Path to the nearest reachable interaction cell via `nearest_walkable_cell`. If none reachable → log rejection + flash a "can't reach" indicator (red X popup at cursor). Never fail silently.
3. In `MOVE` toward a target: each physics frame, re-check `is_in_attack_range()`. For buildings, measure range **to the closest point on the building's collision rect, not its center** (`Rect2.get_closest_point()` equivalent, or clamp unit position into the rect and measure to that point).
4. On entering range → transition to `ATTACK`; on target dying/moving out of range → re-path or drop to auto-attack acquisition.
5. `set_stance("attack")` → command **all player fighters** (not just selected) to attack-move toward the enemy building; `"defend"` → stop; `"garrison"` → toggle mine entry. **[DECISION]** stance = army-wide order; right-click = selection order.

**`player_controller.gd` — deterministic right-click resolution order:**

1. Enemy unit under cursor → `attack_unit`
2. Enemy building under cursor → `attack_building`
3. Central wall + miners selected → breach command
4. Own mine entry → garrison/enter
5. Ground → `move_to`

Use physics point queries (`PhysicsPointQueryParameters2D`) or explicit hitbox `Area2D`s with correct layers — and assert group membership at spawn: every building in `"buildings"`, every unit in `"units"` + its team group. Add a startup validation that prints an error if any expected group is empty.

**Input event hygiene:**

- Confirm clicks aren't swallowed by UI (`mouse_filter` on HUD panels; use `_unhandled_input` for world clicks so UI gets first pass).
- Confirm the SelectionBox drag doesn't also fire a right-click command on release.

### Acceptance Criteria — Phase 1

- [ ] Spawn Swordsman → select → right-click enemy building → log shows `attack_building`, overlay shows a path, unit walks to the building's edge and stops in `ATTACK` state.
- [ ] Attack stance button commands **all** player fighters (overlay shows every fighter getting a target line).
- [ ] Right-clicking an unreachable target prints a rejection reason and shows a red-X indicator — never silence.
- [ ] Startup validation passes: no empty groups, no missing node paths.

**Estimated effort:** 1–2 days.

---

## Phase 2 — Combat System Completion

**Goal:** Once in `ATTACK`, damage flows correctly, units die, buildings take damage and can be destroyed, projectiles work for Archer/Wizard.

### 2.1 Resolve the damage model conflict (C1)

**[DECISION]** Use **cooldown-based discrete hits** (matches design doc §8.2 and is easier to animate/verify): each unit has `attack_cooldown`; in `ATTACK`, a timer fires every `cooldown` seconds applying `damage_per_hit`.

- Authoritative stats live in `scripts/resources/units/*.tres` (`unit_data.gd`). Add explicit fields if missing: `damage_per_hit`, `attack_cooldown`, `attack_range`, `projectile_speed`, `aoe_radius`.
- Reconcile numbers to the design intent (DPS × cooldown = damage per hit): Swordsman 15 DPS × 0.5s = **7.5 dmg/hit** (the doc's "30 damage per hit" contradicts its own DPS — go with DPS-consistent values); Archer 12 × 1.0 = **12**; Wizard 25 × 1.5 = **37.5**.
- Delete or clearly deprecate `Constants.FIGHTER_STATS` so there's one source of truth (Gotchas §"Fighter stats come from .tres").

### 2.2 Target lifecycle

- Acquire: auto-attack priority per design — enemy fighters → enemy building → enemy miners (own side only). Auto-acquisition radius defined per unit; manual commands override auto-acquire until the target dies.
- Maintain: if target exits range → chase (re-path); if target dies → clear target, re-acquire nearest in radius, else `IDLE` (fighters) / resume prior order.
- Death: on HP ≤ 0 → state `DEAD`, play impact flash (asset exists), remove from `"units"`/team groups, decrement `EconomyManager` population, spawn damage popup, `queue_free()` after a short fade. **Verify population actually decrements** — leaks here silently break the 100-unit cap.
- Enemy miners killed underground drop **50% of carried cargo** as collectible coin (design §6.1).

### 2.3 Building damage & destruction

- `building.take_damage(amount, source)` → `hp_changed` signal → HUD bar + damage popup.
- HP ≤ 0 → `destroyed` signal → `GameManager.declare_winner(team)` → Phase 7 end sequence. Buildings stop being valid targets once destroyed (remove from groups, swap sprite to rubble or hide + explosion effect).

### 2.4 Projectiles (Archer & Wizard)

- `projectile.gd` already homes and draws sprites — verify: spawn at attacker, travel at `projectile_speed` (300), hit → apply damage (`damage_popup` red numbers), despawn.
- Wizard fireball: splash in `aoe_radius` (40px) damaging **units and buildings** — confirm friendly fire is off (filter by team).
- Edge cases: target dies mid-flight (projectile continues to last position, fizzles or hits whatever is there — pick one, document it); attacker dies before cooldown fires (cancel the shot).
- Object-pool projectiles later (Phase 8); correctness first.

### 2.5 Combat feedback

- Impact flash sprite (already drawn on damage — verify timing ~0.1s).
- Damage popups (red) on every hit; heal/green not needed yet.
- HP bars visible when damaged/hovered/selected (exists per AGENTS.md — verify it triggers on building too).

### Acceptance Criteria — Phase 2

- [ ] 1 Swordsman vs enemy building: building HP ticks down by `damage_per_hit` every `attack_cooldown` seconds, with popups; building destroyed → `game_over` fires.
- [ ] 1 Swordsman vs 1 enemy Swordsman: both fight, one dies, corpse cleaned up, population count drops, survivor re-acquires or idles.
- [ ] Archer kills a target at 150px without entering melee; arrows visibly fly.
- [ ] Wizard fireball damages 2 clustered enemies with one shot (splash), no friendly damage.
- [ ] Killing an enemy miner carrying cargo drops 50% of it.

**Estimated effort:** 2–3 days.

---

## Phase 3 — Miner Economy Loop, End-to-End and *Visible*

**Goal:** The full loop — spawn → walk to mine → descend → dig → fill cargo → ascend → **walk across the surface to the building** → deposit (coin popup, balance rises) → walk back → repeat — runs continuously and is watchable in both views.

This is the second reported bug, and it has two distinct causes to address:

- **Cause A (behavioral):** the surface deposit leg doesn't exist — code deposits at the mine shaft (`mine_entry.deposit(unit)`), so the miner never walks to the building.
- **Cause B (presentational):** even if mining works, the underground activity isn't visible — units likely don't render in the underground view, or the view toggle doesn't reveal the underground world.

### 3.1 Resolve deposit location (C2)

**[DECISION]** Implement the design-doc loop: deposit happens at the **Player Building**.

New miner cycle in `unit.gd`:

```
IDLE → ENTER_MINE (walk surface: spawn point → mine entry; teleport down)
     → (underground) seek tile → MINE → cargo full (or nothing left in level range)
     → EXIT_MINE (teleport up to entry)
     → DEPOSIT (walk surface: mine entry → building deposit point)
     → deposit cargo (EconomyManager.add_coin, coin_popup, stats)
     → ENTER_MINE → repeat
```

Implementation steps:

1. Add a **deposit point** to `building.gd` (a marker at the building's front edge, e.g. `Marker2D` named `DepositPoint`).
2. Replace the at-shaft `deposit()` call in the miner flow with a surface walk to the deposit point; on arrival, call `mine_entry.deposit(unit)` logic (or move that logic to `building.deposit(unit)` — cleaner: deposit belongs to the building now).
3. Keep `mine_entry.deposit()` as a fallback for AI convenience only if needed — but player-facing expectation is the visible walk, so make the walk the one true path for both teams (symmetry also makes the AI's economy observable/balanced).
4. Deposit triggers: `EconomyManager.add_coin(team, cargo)`, `coin_popup` at the deposit point, cargo → 0, stats `coin_mined` increment.
5. Cargo-full check happens **after each tile destroyed**; partial cargo is still deposited if no reachable tiles remain (don't trap miners underground forever).

### 3.2 Underground visibility & view toggle

- Define view modes explicitly: `SURFACE` shows surface layer visuals + buildings; `UNDERGROUND` shows the tile grid + any unit whose `is_underground` flag is true. Units should set `visible` (or z-index/canvas layer) based on view mode — one source of truth: a `view_mode_changed` signal from `player_controller.gd` that `unit.gd` and `grid_world.gd` listen to.
- Verify the camera: Tab toggle should re-center the camera on the player's mine entry underground (or restore the last underground camera position), not leave the player staring at empty space.
- Mining feedback (so "actively mining" is visible at a glance): pickaxe swing timer or bob animation (even a 2-frame sprite swap), dust particle puff every damage tick on the target cell, tile HP flash/crack (swap to a damaged sprite variant or modulate darker as HP drops), and a small progress bar over the cell if you want maximum clarity.

### 3.3 Mining targeting & pathfinding underground

- Idle miners seek the **nearest** unmined diggable cell within their level gate (design says "deepest accessible" — nearest-first is better for early-game income and matches `ai_controller`'s distance-based ore selection; **[DECISION]** nearest-first with a slight preference for higher value at equal distance).
- Level gating: L1 → layers 1–2, L2 → 3–4, L3 → 5–7. `grid_world.gd` already stores `miner_level_requirement` per cell — enforce it in the *seek* query, not just at dig time, so miners don't path to cells they can never dig.
- A* correctness:
  - Dug cells must become walkable: when `damage_cell()` destroys a tile, update `_astar` (clear solid) **and** the visual in the same transaction.
  - Miners path through empty (dug) space and shafts; undug tiles are solid.
  - No-path handling: if the target cell is unreachable (surrounded), mark it `unreachable` for this miner, try the next candidate; if *no* candidates → return to surface and idle near the entry (don't thrash).
  - Reservation: add a light `claimed_by` on cells so 5 miners don't dogpile one tile while neighbors sit idle.
- Mining damage: `damage_cell(cell, miner_mining_dps * delta)` (continuous) or per-swing ticks (matches pickaxe anim — pick one; per-swing is more readable). On destroy: coin value → cargo (clamped to capacity), cell → EMPTY, sprite swap, astar update, dust burst.
- Flee behavior: on taking damage, miners path to the nearest friendly fighter or their mine entry (exists per AGENTS.md — verify it triggers from the underground state too, and that `MINE` → flee transition isn't blocked).

### 3.4 Multi-miner surface traffic

With several miners, the entry → building path becomes a single-file parade. Add: soft collision avoidance (units of the same team don't hard-collide; reduce collision priority or use avoidance on `NavigationAgent2D` if you adopt it), and slight per-miner spawn/return offsets so they don't stack into one sprite.

### Acceptance Criteria — Phase 3

- [ ] Train 1 miner: watch it (debug overlay on) walk to the entry, appear underground in the underground view, dig a tile (dust + tile HP dropping), fill cargo, come up, **walk to the building**, deposit (popup + coin total increases by exactly the cargo amount), walk back, repeat — indefinitely with no stalls for 5 minutes.
- [ ] Train 5 miners: all cycle without stacking, deadlocking at the entry, or targeting the same tile forever.
- [ ] L1 miner never targets layer-3 cells; after upgrading to L2 (Phase 4), the same miner begins targeting layer 3.
- [ ] When all L1-accessible tiles are mined out, miners idle at the surface near the entry (logged state, not invisible).
- [ ] Toggling Tab at any point shows the miner doing the correct thing in whichever view it's in.

**Estimated effort:** 3–4 days. This is the heart of the game — budget accordingly.

---

## Phase 4 — Training Queue, Economy & Miner Upgrades

**Goal:** The economic shell around the loop is airtight: queue behaves, money behaves, upgrades behave.

### 4.1 Training queue (`building.gd` + `training_queue_panel.gd` + `unit_button.gd`)

- FIFO, max 5 (`MAX_QUEUE_SIZE`), one training at a time with progress bar; on complete → spawn at building front with slight offset.
- Cancel: click queued icon → remove → **100% refund** via `EconomyManager.add_coin`. Cancel the *in-progress* unit also refunds 100% (design says cancel = 100% refund; **[DECISION]** applies to in-progress too).
- Guards: queue full → button disabled + tooltip/shake (shake exists); insufficient coin → disabled; population at cap (100) → all train buttons disabled with a "POPULATION MAX" hint. Re-check guards on `coin_changed` and `population_changed` signals, not on a timer.
- Hotkeys 1–4 (`train_miner`…`train_wizard`) route through the same `queue_unit()` path as the buttons — no divergent logic.

### 4.2 Miner upgrade system

- L1→L2 (500), L2→L3 (1500) via `EconomyManager.upgrade_miner(team)`; button shows next-level cost, disabled when unaffordable or maxed.
- Apply to **existing miners and future miners**: AGENTS.md notes `building.gd` duplicates `UnitData` per spawned unit and upgrades mutate the copy. So on upgrade, iterate all living friendly miners and call `_apply_miner_upgrade()` (verify it updates HP, speed, mining DPS, carry capacity, max layer, and swaps the sprite to the correct level texture). Add a regression check: a miner trained *before* the upgrade digs layer 3 after it.
- `layer_indicator.gd` highlights newly accessible layers on `miner_level_changed`.

### 4.3 Economy integrity

- Every coin mutation flows through `EconomyManager` (no direct counter pokes). Audit: training costs, refunds, deposits, miner-death drops, starting 150.
- Stats tracked for the end screen: units trained, coin mined, match time.
- AI economy uses the same `EconomyManager` API with its own team key — verify AI can't spend player coin (sounds obvious; check anyway).

### Acceptance Criteria — Phase 4

- [ ] Queue 5 units → 6th click rejected with shake/log; cancel #2 → exact refund; in-progress cancel → full refund.
- [ ] At 100 population, buttons disable; after a unit dies, they re-enable.
- [ ] Hotkeys and buttons produce identical queue entries.
- [ ] Upgrade to L2: existing miners immediately dig layer 3, sprite swaps, stats match `MINER_STATS`; L3 likewise.
- [ ] Coin total is never negative and every change is explainable from the log.

**Estimated effort:** 1–2 days.

---

## Phase 5 — Underground Systems: Tiles, the Central Wall, Garrison

**Goal:** The underground is a real battlefield, not just an ore field.

### 5.1 Tile lifecycle polish

- Dug tile → EMPTY sprite swap (asset exists) + `_astar` cleared atomically (done in Phase 3; here: verify layer color themes render per §10.2 and dug cells stay empty for the whole match — no regen).
- Skip Better Terrain for now (C4 — simple swaps are fine at 32px with 8 tile sprites); revisit only if edges look bad.
- Ambient: dust motes underground, snow on surface (Phase 8, but hook the particle scenes now).

### 5.2 The Central Wall (breach mechanic)

- State: shared 2000 HP pool across `x = -1, 0, 1` spanning all layers (already modeled in `grid_world.gd`). Renders `wall_segment.png` per cell + a wall HP bar when damaged.
- **Never auto-targeted** (design §4.2): auto-attack acquisition must explicitly exclude `WALL` cells; only an explicit right-click on the wall with miners selected issues the breach command (input resolution order from Phase 1 handles this).
- Breach flow: selected miners path to wall-adjacent cells → `MINE` state against wall cells → `damage_cell` scales with miner level → HP bar ticks → at 0: all wall cells → EMPTY, astar updated, both sides connected, one-time rumble + dust explosion.
- After breach: miners of either team may path through; enemy miners on your side become valid auto-attack targets for your fighters (already in priority rules).
- Regression guard: fighters **cannot** mine the wall or any tile (design §8.3) — assert in `mine_cell` command.

### 5.3 Garrison & underground combat

- Garrison: right-click own mine entry with fighters selected → they enter and patrol a radius around the entry underground (exists per AGENTS.md — verify patrol actually moves them; tie into the view-mode visibility from Phase 3).
- Underground fighter speed = 60% surface speed — verify the modifier applies in the underground `MOVE` branch and clears on exit.
- If an enemy unit crosses to the player's side underground, garrisoned fighters path to it (needs the breach to be possible — test by forcing the wall to 1 HP in debug).
- Fighters **cannot enter the enemy mine** (critical rule #9): `enter_mine` must reject a mine entry whose team ≠ unit team, with a logged rejection.

### Acceptance Criteria — Phase 5

- [ ] Wall takes no damage from auto-attacks or fighter commands; only explicit miner breach damages it.
- [ ] Breach at 0 HP opens a corridor: enemy miners can path to your side; your fighters auto-attack invading miners.
- [ ] Garrisoned fighters patrol visibly in the underground view and engage an intruder.
- [ ] Fighter right-clicked on enemy mine entry → rejection logged, no entry.
- [ ] Dug tiles never regenerate; layer color themes match the palette.

**Estimated effort:** 2 days.

---

## Phase 6 — Enemy AI Verification & Completion

**Goal:** The AI plays the same game the player does, using the same (now-fixed) command APIs, at all four difficulties.

> Note: the AI shares `unit.gd`'s command API and reads `unit._state` directly (Gotchas). Phases 1–3 fixed those paths; this phase is mostly *verification plus AI-specific logic*, not a rewrite.

### 6.1 Economic loop verification

- 2s decision tick: miner-first priority (miners < 5 → queue miner), then fighters, upgrade at thresholds (500/1500). Watch AI coin + queue in the debug panel for 3 minutes: it should sustain a growing economy with zero stalls.
- AI miners run the same visible surface deposit loop (Phase 3) — confirm symmetry, since income parity depends on it.

### 6.2 Aggression & waves

- 10s aggression tick: `push` when AI fighters > player fighters × 1.5, `defend` when < 0.5×, else `balanced`; 18s attack-wave timer issues army commands per aggression.
- `push` → attack-move all fighters at the player building (uses Phase 1's attack-move — verify paths resolve).
- `defend` → garrison 30% of fighters, rest hold near building; if player fighters approach the AI building, defenders intercept (already: "defends building when enemy units are nearby" — test it).
- Wall breach AI: when pushing and no accessible tiles remain on its side and coin > 1000 → explicit breach command with 30% of miners (Phase 5 mechanics).

### 6.3 Difficulty scaling

| Difficulty | AI coin × | Train speed × | Upgrade speed × | Aggression bias |
|------------|-----------|----------------|------------------|-----------------|
| Easy | 0.8 | 1.0 | 0.7 | Defensive |
| Normal | 1.0 | 1.0 | 1.0 | Balanced |
| Hard | 1.2 | 0.9 | 1.2 | Aggressive |
| Nightmare | 1.5 | 0.8 | 1.5 | Very aggressive |

- Implement multipliers in `ai_controller.gd`/`economy_manager.gd` (coin multiplier applied to AI deposits — cleanest single point); a difficulty selector at match start (simple menu or debug dropdown; full menu in Phase 7).
- **Fair-play rule:** multipliers modify rates, never rules — AI uses identical unit stats, queue cap, and pop cap.

### Acceptance Criteria — Phase 6

- [ ] Spectate 5 minutes on Normal: AI trains miners first, upgrades on schedule, fields fighters, and launches at least one coherent attack wave that reaches your side.
- [ ] On Easy, the AI is beatable by a passive player who only defends; on Nightmare, an idle player loses within ~8–10 minutes.
- [ ] AI breach: drain its side's tiles via debug → it breaches the wall and sends miners through.
- [ ] AI never exceeds queue cap 5 / pop cap 100.

**Estimated effort:** 2–3 days.

---

## Phase 7 — Match Flow: Win/Lose, Pause, Restart, Menus

**Goal:** A match has a beginning, an end, and a clean reset.

### 7.1 Win/lose sequence (design §15)

1. Building HP → 0: `building.destroyed` → `GameManager.declare_winner(winner)`.
2. Slow-mo: `Engine.time_scale = 0.3` for 1s (remember to restore!).
3. Collapse: explosion particles + building sprite swap/collapse tween (explosion effect asset exists).
4. Fade to the game-over panel: "VICTORY"/"DEFEAT" + stats (units trained, coin mined, match time from `GameManager.match_time`).
5. Buttons: **Play Again** → `GameManager.reset()` + `EconomyManager.reset()` → `reload_current_scene()` (pattern already in `hud.gd` — extend to any new per-match state you added: debug flags, difficulty, wall HP if it lives outside the scene); **Quit/Main Menu**.
6. On `game_over`: freeze unit AI (`game_active = false` gate in `unit.gd` `_physics_process`), disable input commands, stop AI ticks.

### 7.2 Pause

- Space/Esc toggles `get_tree().paused` — audit `process_mode` on every node: world/units/AI = `Pausable`, HUD pause menu = `When Paused` or `Always`, popups/tweens = inherit. The classic bug: pause menu itself pauses and can't be clicked.
- Esc also opens the menu (resume / restart / quit / difficulty placeholder).

### 7.3 Match start

- Minimal main menu: title, difficulty select (4 options), Play. Sets difficulty → loads `main.tscn`. Keep it placeholder-simple; polish in Phase 8.

### Acceptance Criteria — Phase 7

- [ ] Destroy enemy building → slow-mo → collapse → VICTORY panel with correct stats → Play Again starts a fresh match (150 coin, wall at 2000 HP, no leftover units).
- [ ] Lose → DEFEAT panel; same reset cleanliness.
- [ ] Pause freezes everything including popups and AI; resume works; pause menu clickable.
- [ ] Difficulty chosen in the menu actually reaches `ai_controller.gd`.

**Estimated effort:** 1–2 days.

---

## Phase 8 — Polish, Juice & Performance

**Goal:** Feel and stability. Only after Phases 0–7 pass.

- **Audio** (`AudioManager` doesn't exist yet in the code structure — add it as an autoload): pickaxe ticks, sword hits, bow release, wizard blast, coin deposit chime, building alarm at low HP, wind ambient (surface) / dripping (underground), UI clicks. Route through buses (SFX/Music/Ambient).
- **Particles:** falling snow on surface (1–2px, slow, 30% opacity), dust motes + miner lantern glow underground, magma flicker L5–6, crystal pulse L7 (sine opacity), mining dust per swing, breach collapse burst, building destruction explosion.
- **Game feel:** screen shake on building hits/destruction; impact flash timing polish; coin sparkle at deposit; selection ring pulse; view-toggle transition (fade or slide between surface/underground; Phantom Camera optional).
- **Performance (target: 100 units + projectiles at 60fps):** object pools for projectiles, popups, dust; off-screen culling for underground cells not in view; avoid per-frame `get_nodes_in_group` — cache lists and maintain them on spawn/death signals; profile with Godot's profiler before and after.
- **Art pass (optional):** current 57 PNGs are geometric placeholders; swap in final art per sprite without code changes thanks to `UnitData` textures and `_draw()` fallbacks.

### Acceptance Criteria — Phase 8

- [ ] 100 player units + 100 enemy units mid-battle: stable 60fps at 1920×1080.
- [ ] Every player action has an audible + visual confirmation.
- [ ] No memory growth over a 15-minute match (monitor in debugger).

**Estimated effort:** 2–4 days (scope-dependent).

---

## Phase 9 — QA Harness & Regression Safety

**Goal:** Stop "nothing happens" bugs from ever shipping silently again.

### 9.1 Automated tests with GUT

Add [GUT](https://github.com/bitwes/Gut) and cover the pure-logic cores (fast, headless-runnable):

- `economy_manager`: spend/refund/upgrade math, cap guards.
- `building` queue: FIFO order, cancel refund, cap rejection.
- `grid_world`: `damage_cell` destruction → coin returned, astar cleared; wall shared-HP accounting; `nearest_walkable_cell` around the building footprint (the Phase 1 bug, permanently pinned by a test).
- `unit` command guards: fighter `mine_cell` rejected; `enter_mine` wrong team rejected; unreachable target rejected with reason.

Document the run command in AGENTS.md §Testing, as it invites.

### 9.2 The Match Script (manual regression checklist)

A 15-minute scripted playthrough, run before any export:

1. Train 2 miners → confirm full visible mining/deposit cycle (Phase 3 script).
2. Train 1 of each fighter → right-click enemy building → all engage; building HP drops.
3. Queue to 5, cancel one, verify refund.
4. Upgrade miners to L2 → verify layer 3 digging.
5. Tab-toggle during every activity.
6. Garrison fighters; breach the wall; verify cross-side combat.
7. Let the AI attack; defend; counterattack; win → VICTORY → Play Again.
8. Repeat on Hard. Lose on purpose once → DEFEAT flow.

### 9.3 Export verification

- `godot --headless --export-release "Web" build/MineAttack.html` — smoke-test the Web build (debug flag off): one full match, checking for HTML5-specific issues (audio autoplay policies, mouse capture, performance).

**Estimated effort:** 1–2 days.

---

## Phase 10 — Headless Build & Compile Verification (Kimi Code Terminal, Web + macOS)

**Goal:** Kimi Code can do everything from the terminal, without opening the Godot editor: verify all GDScript compiles, boot the game headless, run tests, and produce **Web** and **macOS** builds — on every change. This turns "does it compile?" from a manual editor check into a one-command gate.

> **Placement note:** Although numbered last, set this phase up **immediately after Phase 0** (before the heavy code changes in Phases 1–3). Every subsequent phase then gets compile-verified automatically as Kimi Code works. The export/smoke parts mature alongside the game.

### 10.1 Toolchain setup (one-time, documented)

- **Pin the engine version:** install the Godot 4.7 **headless-capable binary** on the dev Mac (`brew install --cask godot` or the direct download; the standard binary supports `--headless`). Record the exact version string (`godot --version`) in `AGENTS.md` — export templates and CI must match it exactly.
- **Export templates (required for both targets):** download the template bundle (`Godot_v4.7-stable_export_templates.tpz`) matching the exact engine version and unzip to `~/Library/Application Support/Godot/export_templates/4.7.stable/` (or install once via the editor: *Editor → Manage Export Templates*). Without these, both Web and macOS exports fail. Verify presence before first export.
- **Lint tooling:** `pip install gdtoolkit` for `gdlint` + `gdformat` (static GDScript checks without launching the engine).
- **GUT** committed under `addons/gut/` (from Phase 9) so tests are runnable from CLI on any machine.
- Add a `GODOT` environment variable (or a `.env`/config line in the scripts) pointing at the binary so scripts work on any machine (`GODOT="${GODOT:-godot}"`).

### 10.2 Fix the export presets (known gap)

AGENTS.md flags that `export_presets.cfg` defines **only the Web preset** even though `[runnable_presets]` references macOS. Fix this now:

- **Web preset** (exists — verify): output `build/MineAttack.html`, `progressive_web_app` off unless wanted.
- **macOS preset (new):** output `build/MineAttack.app` (zipped as `build/MineAttack-macOS.zip`). For local/dev builds: code signing set to **ad-hoc / disabled**; distribution signing + notarization requires an Apple Developer account and is **out of scope for V1** (document: unsigned apps launch via right-click → Open, or `xattr -dr com.apple.quarantine build/MineAttack.app`).
- Both presets must reference the same template version as the pinned engine.

### 10.3 Repo scripts (the contract Kimi Code executes)

Create `tools/` at the repo root. Every script: `set -euo pipefail`, logs to `build/logs/`, exits nonzero on failure.

| Script | What it runs | Catches |
|--------|--------------|---------|
| `tools/check_compile.sh` | 1. `"$GODOT" --headless --path . --import` (resource import) 2. Loop over every `.gd` file: `"$GODOT" --headless --check-only --script <file>` 3. `gdlint scripts/ scenes/` | GDScript parse/compile errors with file + line; lint violations |
| `tools/test.sh` | `"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` | Logic regressions (Phase 9 suite) |
| `tools/smoke.sh` | `"$GODOT" --headless --path . --quit-after 900` (boots `main.tscn` for ~15s of frames, then quits) | Autoload failures, missing node paths, `_ready()` crashes, runtime errors on boot |
| `tools/build_web.sh` | `"$GODOT" --headless --path . --export-release "Web" build/MineAttack.html` | Full compile gate (export compiles all GDScript — any error fails the build) + Web packaging |
| `tools/build_macos.sh` | `"$GODOT" --headless --path . --export-release "macOS" build/MineAttack-macOS.zip` | Full compile gate + macOS packaging |
| `tools/verify.sh` | Chains, in order: `check_compile` → `test` → `smoke` → `build_web` → `build_macos` | **The single command Kimi Code runs after every change** |

### 10.4 Workflow contract for Kimi Code

1. After completing any phase task (and before marking it done): run `tools/verify.sh`. Nonzero exit = the task is not done; read `build/logs/`, fix, re-run.
2. Compile errors from `--check-only` and export output include file/line — fix the upstream cause, never work around by deleting code paths.
3. **Headless validates logic, not visuals or input.** Rendering, mouse feel, animations, and audio still require the manual Match Script (Phase 9.2) in the editor or a real build. Both are required; neither replaces the other.
4. Update `AGENTS.md`: toolchain versions, the `tools/` commands, export preset fix, and a new gotcha — "headless can't test input/rendering."

### 10.5 Optional later: CI

A GitHub Actions job running `tools/verify.sh` on push (Godot setup via `chickensoft-games/setup-godot`, templates cached). Not required for V1 — the local scripts are the deliverable — but the scripts are written to be CI-ready (headless, exit codes, logs).

### Acceptance Criteria — Phase 10

- [ ] From a fresh terminal on the dev Mac: `tools/verify.sh` runs with zero interaction and ends with `build/MineAttack.html` (Web) and `build/MineAttack-macOS.zip` (macOS) produced.
- [ ] Deliberately introduce a GDScript syntax error → `check_compile.sh` fails fast naming the file and line; `verify.sh` stops before exporting.
- [ ] Deliberately break a node path in `main.tscn` → `smoke.sh` fails.
- [ ] The Web build loads and plays a full match in Chrome/Safari; the macOS app launches (ad-hoc signed) and plays a full match.
- [ ] `AGENTS.md` documents: pinned Godot version, export template install steps, all `tools/` commands, and the runnable-presets fix.

**Estimated effort:** 0.5–1 day setup, then ~zero ongoing cost (it just runs).

---

## Appendix A — Phase Dependency Map

```
Phase 0 (Debug tooling) ──► Phase 10 (Headless build/compile gate) ──┐
   │                                                                  │  (verify.sh gates every task below)
   └─► Phase 1 (Command pipeline) ──► Phase 2 (Combat) ──┐            │
        └─► Phase 3 (Miner loop) ──► Phase 4 (Economy) ──┼─► Phase 5 (Underground) ──► Phase 6 (AI)
                                                          └─────────────────────────────► Phase 7 (Match flow)
                                                                                          └─► Phase 8 (Polish) ──► Phase 9 (QA)
```

Critical path: **0 → 10 → 1 → 3 → 5 → 6 → 7**. Phase 10 is infrastructure: set it up right after Phase 0 so every code change from Phase 1 onward is compile- and export-verified from the terminal. Phases 2 and 4 can run in parallel with 3 if working in separate files, but both depend on Phase 1's pipeline.

## Appendix B — Reported-Bug Traceability

| Reported symptom | Most likely root cause(s) | Fixed in |
|------------------|---------------------------|----------|
| Swordsman "attack" does nothing | H3 (target pick/group), H4 (path to solid footprint cell), H5 (range to center), possibly H1/H2 (stance wiring) | Phase 1 (plumbing), Phase 2 (damage) |
| Miner not seen mining | Cause B: view-mode visibility / camera not switching to underground | Phase 3.2 |
| Miner never drops gold at building | Cause A: deposit happens at the shaft (`mine_entry.deposit`), no surface leg exists | Phase 3.1 |

## Appendix C — Definition of Done (whole project)

- All phase acceptance criteria pass on **Normal** difficulty.
- A full 8–15 minute match is winnable and losable with zero soft-locks (no state where a unit or the AI is stuck with no legal action and no log explaining why).
- Every silent failure path identified in Phase 0/1 now either works or logs a reason.
- Web export runs a full match cleanly.
- `tools/verify.sh` is green from a clean terminal: compile check, GUT tests, headless smoke boot, and **both** Web and macOS exports succeed (Phase 10).
- The macOS build launches and plays a full match on the dev machine; the Web build does the same in a browser.
- `AGENTS.md` updated: Testing section (GUT command), toolchain versions + `tools/` commands (Phase 10), any new autoloads (`DebugLog`, `AudioManager`), and any resolved gotchas removed.
