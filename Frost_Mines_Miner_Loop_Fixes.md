# Frost Mines — Miner Loop Fix Pack

**Date:** 2026-07-16
**Scope:** Fix the reported miner issues: (1) miners climb partway and get stuck on the ladder, (2) miners hit a tile but it never depletes / is never destroyed, (3) bags never fill and gold from ore tiles isn't visibly collected, (4) miners yo-yo up and down the mine without doing sustained work.
**Based on:** `grid_world.gd`, `mine_entry.gd`, `ladder.gd`, `unit.gd`, `player_controller.gd` (as uploaded).

---

## 0. Root-Cause Summary (Symptom → Cause)

| # | Symptom you see | Root cause in code | Fix |
|---|-----------------|--------------------|-----|
| R1 | "Hit a spot but it doesn't do anything" — tile HP barely moves | `_process_mine()` deals `max(1, roundi(data.damage_per_hit))` damage per swing. `damage_per_hit` is the miner's **combat** stat — miners have 0 combat damage, so every swing deals **1 damage** against 50–100 HP tiles. One tile takes 50+ swings. | Fix 1 |
| R2 | Bags never fill / gold never collected | Two compounding issues: (a) R1 means tiles almost never get destroyed, and coin is only granted **on destruction**; (b) `_find_and_mine()` scores `distance − coin_value * 0.1`, so a worthless DIRT tile next to the miner beats an ORE tile 10 cells away — miners spend their lives digging 0-coin dirt. | Fix 1 + Fix 2 |
| R3 | Stuck on the ladder | `_carve_shaft(-15)` / `_carve_shaft(15)` are hardcoded, but the ladder bottom is computed as `entry.global_position + (0, 160)`. If the MineEntry node's X doesn't sit exactly inside the carved column, the ladder bottom is **inside solid tiles** — A* redirects to "nearest walkable", the miner arrives at the wrong spot, then Phase 2 of the climb **snaps `global_position.x` to the ladder column instantly**, potentially into solid ground. | Fix 3 + Fix 4 |
| R4 | Miners yo-yo up/down, "a little stuck" | When a seek finds nothing (often because of R1/R2 side effects + over-aggressive blacklisting, Fix 5), `_mine_exhausted` sends the miner UP the ladder, waits 5s, goes DOWN, re-fails, repeats. From the outside this looks like miners wandering and stalling. | Fix 7 |
| R5 | Miners glide through solid dirt | Straight-line fallbacks (`_path.append(adj)` when A* returns empty) in `mine_cell()` / `_process_mine()` make miners walk through undug tiles. Looks like clipping/stuck-inside-wall. | Fix 5 |
| R6 | Possible stall at the building during deposit | `_process_deposit()` requires distance ≤ 32px to `get_deposit_point()`, repathing every frame. If that point is on/near a solid footprint cell, A* redirects the path end to a walkable cell up to 6 cells away — the miner walks there, is still > 32px away, repaths forever. **Needs `building.gd` to confirm.** | Fix 6 |

---

## 1. Files I still need to confirm a few things

The fixes below are complete as written, but these would let me verify R6 and exact stat values:

1. **`scripts/resources/units/miner.tres`** — to confirm `damage_per_hit`, `mining_rate`, `carry_capacity` values (R1's smoking gun).
2. **`scripts/resources/unit_data.gd`** — to know which fields already exist before adding new ones.
3. **`scripts/world/building.gd`** — to verify `get_deposit_point()` returns a walkable point outside the solid footprint (R6).
4. **`scripts/autoload/constants.gd`** — `MINER_STATS`, `LAYER_TILE_HP`, grid bounds.
5. **`scenes/main.tscn`** — MineEntry node positions vs the hardcoded shaft columns at x=∓15 (R3).
6. **`scripts/controllers/ai_controller.gd`** — enemy miners use the same commands; want to confirm whether it calls `mine_cell`/`enter_mine` (teleport) or the ladder path, so both teams get the fix.

---

## Fix 1 — Mining damage must use a mining stat, not the combat stat

**File:** `scripts/units/unit.gd`, `scripts/resources/unit_data.gd`, `scripts/resources/units/miner.tres`, `scripts/autoload/constants.gd`

The core loop "tiles have HP → swings deplete it → tile destroyed → ore grants gold" already exists in `grid_world.damage_cell()`. It's starved by 1-damage swings.

### 1a. Add dedicated mining fields to `UnitData`

```gdscript
# unit_data.gd (add to the exported fields)
@export var mining_damage: int = 5          # tile damage per pickaxe swing
@export var mining_swings_per_sec: float = 2.0
```

Keep `mining_rate` if other code reads it, but treat **swings/sec** as the canonical meaning everywhere (the pickaxe animation in `_draw_pickaxe` already uses `1.0 / data.mining_rate` as the swing period — keep that consistent).

### 1b. Use them in `_process_mine()`

```gdscript
# unit.gd, in _process_mine(), replace the damage block:
if _mine_timer <= 0:
    _mine_timer = 1.0 / max(0.1, data.mining_swings_per_sec)
    _mine_hit_flash = 0.08
    var dmg: int = max(1, data.mining_damage)
    var coin: int = _grid.damage_cell(_target_cell, dmg, data.miner_level)
    if coin > 0:
        carried_coin = min(data.carry_capacity, carried_coin + coin)
        queue_redraw()
```

### 1c. Set per-level values as an absolute table (no incremental `+=`)

The current `_apply_miner_upgrade()` does `data.mining_rate += 1.0` / `+= 2.0`, which is ambiguous and compounds. Replace with an authoritative per-level table in `constants.gd`:

```gdscript
# constants.gd — target mining DPS per GDD: L1 10, L2 15, L3 25.
# 50 HP tile (L1–2) breaks in 5s at L1; 75 HP in 5s at L2; 100 HP in 4s at L3.
const MINING_STATS: Dictionary = {
    1: { "damage": 5, "swings": 2.0 },   # 10 dps
    2: { "damage": 5, "swings": 3.0 },   # 15 dps
    3: { "damage": 5, "swings": 5.0 },   # 25 dps
}
```

```gdscript
# unit.gd _apply_miner_upgrade() — set absolutely, not incrementally:
var stats: Dictionary = Constants.MINING_STATS[level]
data.mining_damage = stats.damage
data.mining_swings_per_sec = stats.swings
```

**Verify:** one L1 miner destroys a 50-HP layer-1 tile in ~5 seconds; the tile HP bar (already drawn in `grid_world._draw_cell_hp_bar`) visibly depletes each swing.

---

## Fix 2 — Seek ORE first so bags actually fill

**File:** `scripts/units/unit.gd` (`_find_and_mine()`)

Coin only enters the bag when an **ORE** tile is destroyed (`coin_value` > 0). DIRT yields 0 — it's just tunneling. The current score (`distance − coin_value * 0.1`) barely prefers ore. Rewrite the scan to track two candidates:

```gdscript
func _find_and_mine() -> void:
    # ... existing bounds/scan setup unchanged ...
    var best_ore: Vector2i = Vector2i(-9999, -9999)
    var best_ore_dist: float = INF
    var best_dirt: Vector2i = Vector2i(-9999, -9999)
    var best_dirt_dist: float = INF

    # inside the scan loop, after all existing filters
    # (type, level gate, claim, blacklist, _has_empty_neighbor):
        var d: float = center.distance_to(pos)
        if cell.type == GridWorld.CellType.ORE:
            if d < best_ore_dist:
                best_ore_dist = d
                best_ore = pos
        else:
            if d < best_dirt_dist:
                best_dirt_dist = d
                best_dirt = pos

    # Ore always wins; dirt is dug only to expand the frontier toward new ore.
    if best_ore != Vector2i(-9999, -9999):
        mine_cell(best_ore)
        return
    if best_dirt != Vector2i(-9999, -9999):
        mine_cell(best_dirt)
        return
    # ... existing exhausted branch unchanged ...
```

**Also:** after each destroyed tile, `_process_mine()` already deposits when `carried_coin >= data.carry_capacity`. Add one quality check so a nearly-full bag doesn't waste a big ore tile: when `carried_coin > 0 and (data.carry_capacity - carried_coin) < 5`, prefer depositing before starting a new tile (insert at the top of `_find_and_mine()`):

```gdscript
if carried_coin > 0 and (data.carry_capacity - carried_coin) < 5:
    deposit_coin()
    return
```

**Verify:** bags fill within ~2–4 ore tiles; the rust-colored bag indicator under the miner appears; deposit popups show the expected amounts.

---

## Fix 3 — Align the ladder/shaft with the actual MineEntry position

**Files:** `scripts/world/mine_entry.gd`, `scripts/world/grid_world.gd`

Right now two hardcoded truths can disagree: the grid carves shafts at x=∓15, while the ladder bottom derives from the entry node's scene position. Make the entry authoritative:

```gdscript
# grid_world.gd — make shaft carving public and parameterized:
func carve_shaft(x: int, y_from: int = 1, y_to: int = 6) -> void:
    for y in range(y_from, y_to + 1):
        var pos: Vector2i = Vector2i(x, y)
        _cells.erase(pos)
        if _astar.is_in_boundsv(pos):
            _astar.set_point_solid(pos, false)
    queue_redraw()
```

```gdscript
# mine_entry.gd _ready() — replace the _underground_position computation:
var grid: GridWorld = get_node("/root/Main/World/GridWorld")
var shaft_x: int = grid.world_to_grid(global_position).x
grid.carve_shaft(shaft_x, 1, 6)            # carve where the entry actually is
_underground_position = grid.grid_to_world(Vector2i(shaft_x, 5))  # carved cell center
if underground_spawn:
    var node = get_node_or_null(underground_spawn)
    if node:
        _underground_position = node.global_position
_spawn_ladder()
# Fail loudly if the ladder bottom is buried in solid ground:
if not grid.is_walkable(grid.world_to_grid(_underground_position)):
    push_error("MineEntry %s: ladder bottom %s is not walkable — shaft misaligned" % [name, str(_underground_position)])
```

Keep `_carve_shaft(-15)`/`_carve_shaft(15)` in `_generate_map()` or delete it — with the entry carving its own shaft, the grid-side call becomes redundant. **Note:** node `_ready` order matters; GridWorld must be above the MineEntries in `main.tscn` (it almost certainly is, but confirm) or guard with `call_deferred`.

**Verify:** no push_error at startup; the ladder visually runs from the entry down the center of an empty carved column.

---

## Fix 4 — Climbing must not snap the miner sideways

**File:** `scripts/units/unit.gd` (`_process_climb_up()`, `_process_climb_down()`)

Phase 2 of both climbs does `global_position.x = ladder_top.x` — an instant horizontal teleport (potentially through solid tiles) before moving vertically. Replace with gradual movement, horizontal first, then vertical:

```gdscript
# Phase 2 (both climb states) — replace the movement lines:
_path.clear()
var target: Vector2 = ladder_top if _state == State.CLIMB_DOWN else ladder_bottom
# Wait: CLIMB_DOWN goes top->bottom, CLIMB_UP goes bottom->top. Destinations:
var dest: Vector2 = ladder_bottom if _state == State.CLIMB_DOWN else ladder_top
var to_dest: Vector2 = dest - global_position
if to_dest.length() <= 8.0:
    # ... existing arrival/teleport code unchanged ...

var climb_speed: float = data.speed * 0.9
var step: float = climb_speed * delta
# Slide horizontally onto the ladder column first (gradual, no snap),
# then move vertically once aligned.
var dx: float = dest.x - global_position.x
if absf(dx) > 1.0:
    global_position.x += clampf(dx, -step, step)
else:
    global_position.x = dest.x
    global_position.y += clampf(dest.y - global_position.y, -step, step)
```

Also lower the Phase 1 arrival threshold from a hard `8.0` to `GridWorld.CELL_SIZE * 0.35` (~11px) so a miner standing at the correct cell center always counts as arrived.

**Verify:** miners visibly walk to the ladder base, slide onto the rail, then climb straight up/down — no sideways pop, no passing through tiles.

---

## Fix 5 — Remove walk-through-dirt fallbacks and tighten blacklisting

**File:** `scripts/units/unit.gd` (`mine_cell()`, `_process_mine()`)

Underground, an empty A* result means "can't get there yet" — the correct response is blacklist + re-seek, not a straight-line path through solid rock:

```gdscript
# mine_cell() — replace:
    _repath(adj)
    if _path.is_empty():
        _path.append(adj)          # DELETE: walks through solid tiles
    if not _path_reaches(adj):
        ...
# with:
    _repath(adj)
    if _path.is_empty() or not _path_reaches(adj):
        _mark_cell_unreachable(grid_pos)
        _set_state(State.IDLE, "mine target unreachable")
        return
```

Same in `_process_mine()`'s movement branch. **Keep** the straight-line fallbacks in the surface states (`_process_enter_mine`, `_process_deposit`) — the surface row is fully walkable, so those are harmless safety nets.

While here: `_mark_cell_unreachable()` already forgets after 10s (`_UNREACHABLE_FORGET_MS`), which is correct — newly dug tunnels reopen routes. No change needed, but watch the log: repeated `"mine target unreachable"` for the same cell every 10s means a real connectivity bug, not a transient one.

---

## Fix 6 — Make deposit arrival robust (confirm with `building.gd`)

**File:** `scripts/units/unit.gd` (`_process_deposit()`), possibly `scripts/world/building.gd`

Two changes:

1. Accept "path finished" as arrival, same pattern as the climb states:

```gdscript
# _process_deposit():
var target_pos: Vector2 = building.call("get_deposit_point")
var path_done: bool = not _path.is_empty() and _path_index >= _path.size()
if global_position.distance_to(target_pos) > GridWorld.CELL_SIZE and not path_done:
    _repath(target_pos)
    if _path.is_empty():
        _path.append(target_pos)   # surface-only fallback, fine to keep
    _follow_path(delta)
    return
```

2. **`building.gd` check (send me the file):** `get_deposit_point()` must return a point on the walkable surface row *outside* the solid footprint — e.g. `Vector2(front_edge_x, GridWorld.CELL_SIZE * 0.5)`. If it returns a point inside the footprint (which `building.gd` marks solid in `_astar`), A* will redirect and the miner can oscillate forever within the old distance-only check. The `path_done` change above makes this survivable either way, but the point should still be correct.

---

## Fix 7 — Stop the exhausted yo-yo

**File:** `scripts/units/unit.gd` (`_idle_near_mine_entry()`, `_find_and_mine()`)

Today: exhausted + underground → climb up → wait 5s on the surface → climb down → fail again → repeat. Two changes:

1. **Stay underground when empty-handed.** There is no reason to surface unless carrying gold:

```gdscript
func _idle_near_mine_entry() -> void:
    var entry: Node2D = _nearest_friendly_mine_entry()
    if entry == null:
        return
    if is_underground:
        if carried_coin > 0:
            climb_up_ladder()      # only surface to cash in
        else:
            # Wait near the shaft bottom; the retry timer re-opens the seek.
            var bottom: Vector2 = entry.call("get_ladder_bottom")
            if global_position.distance_to(bottom) > GridWorld.CELL_SIZE * 1.5:
                move_to(bottom)
        return
    # surface branch unchanged
```

2. **Re-open the seek when the world changes, not just on a timer.** Connect once in `_ready()`:

```gdscript
_grid.cell_destroyed.connect(func(_pos): 
    _mine_exhausted = false
    _unreachable_cells.erase(_pos))
```

Every destroyed tile (by anyone, including the wall breach) opens a new frontier — miners should wake up immediately instead of waiting out the 5s timer.

---

## Fix 8 — Small hardening items

- **Division guard:** `_mine_timer = 1.0 / max(0.1, data.mining_swings_per_sec)` (also fixes a potential divide-by-zero if a .tres has 0).
- **Deposit gating:** `deposit_coin()` rejects when `carried_coin <= 0` — correct, keep; just make sure `_handle_idle_miner()`'s first branch can't call it with 0 (it can't today — the `or` chain guards it — but keep it that way after edits).
- **Ladder-base stacking:** multiple miners converge on the exact same ladder base point. Apply `_movement_offset * 0.5` to the Phase 1 path target in the climb states (not to the climb column itself).
- **Enemy parity:** `ai_controller.gd` drives enemy miners through the same `Unit` API, so all fixes apply to both teams — but confirm it isn't calling the legacy teleport `enter_mine()`/`exit_mine()` in a way that fights the ladder states (send the file and I'll check).
- **Dead code cleanup:** once the ladder path is verified solid, decide whether `enter_mine`/`exit_mine` (teleports) remain player-facing commands. Right-clicking the mine entry currently routes to them via `player_controller._issue_command()` branch 5 — that's fine as an explicit-order fast path, but miners' *automatic* loop should only use the ladder.

---

## 9. What to watch in the DebugLog while testing

| Log line pattern | Meaning |
|------------------|---------|
| `MINE -> IDLE "cell mined"` rapidly, no `deposit` | Swings deal damage but tiles die with 0 coin — you're watching DIRT digging. Expect mostly this between ore tiles, but ore should dominate after Fix 2. |
| Repeating `"mine target unreachable"` for the same cell every ~10s | Real connectivity bug — check shaft alignment (Fix 3 push_error) |
| `CLIMB_UP -> IDLE "climbed out"` immediately followed by `climb_down_ladder` | Yo-yo — Fix 7 not applied or exhausted flag stuck |
| `deposit_coin` rejected `"cargo empty"` | A caller is depositing with 0 cargo — find the caller from the preceding command line |
| Miner stuck in `DEPOSIT` with repeated repaths near the building | Fix 6 territory — send `building.gd` |

---

## 10. Acceptance checklist (run after applying all fixes)

- [ ] Startup: no `push_error` about ladder bottom alignment; startup validation OK.
- [ ] One L1 miner breaks a layer-1 tile in ~5s; HP bar depletes per swing; dust puffs show.
- [ ] Destroying an ORE tile adds its coin value to the bag indicator; DIRT gives 0.
- [ ] Miner with a full bag climbs the ladder smoothly (no sideways snap), walks to the building, coin popup + balance increases by exactly the bag amount, climbs back down, resumes mining — for 10 minutes unattended, no stalls.
- [ ] 5 miners: no two miners claim the same tile; nobody idles at the ladder; no one walks through undug dirt.
- [ ] When the accessible area is fully mined, empty miners wait at the shaft bottom (not yo-yoing); miners with cargo still surface to deposit.
- [ ] Wall breach instantly wakes exhausted miners on both teams.
- [ ] Enemy miners show identical behavior on their side.
