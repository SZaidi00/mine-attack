# Improvement Ideas

Proposed improvements for MineAttack, grouped by area. Status legend: `[ ]` not started, `[~]` in progress, `[x]` done.

## High impact

- [x] **Post-match stats & match logging** — match-end screen with graphs/numbers (coin mined over time, army size, damage dealt) plus a per-match JSON log from the autoloads to feed balance analysis. (Implemented: `MatchStats` autoload, game-over summary table + `MatchGraph` coin/population charts, JSON logs in `user://match_logs/`.)
- [ ] **AI difficulty smoothing** — adaptive difficulty that nudges `game_manager.gd` modifiers mid-match instead of only fixed tiers (Easy → Godly); builds on `AIBeliefSystem` and smarts tiers.
- [ ] **Save/resume mid-match** — `user://savegame` snapshot of grid state + unit/structure state; state already lives mostly in serializable autoloads and `GridWorld._cells`.

## Gameplay depth

- [ ] **Map seed / map archetypes** — expose the RNG seed or 2–3 archetypes (narrow shaft, wide field, rich-center) via `grid_map_generation.gd`.
- [x] **Support unit: engineer** — repairs structures only (walls/towers/lanterns/building), never units (units already regen out of combat via `UNIT_REGEN_*`). Balance via economy, not hard caps: repair costs coin per HP restored, and a structure damaged in the last ~3s can't be repaired (no out-repairing a live siege). Fragile, slow, ~2 pop, trained from the building. Needs a new sprite. (Implemented: `engineer.tres` + `unit_repair.gd` helper, `repair_structure` command (right-click step 2c in `player_commands.gd`), idle auto-seek, `needs_repair`/`can_be_repaired`/`repair` on the four structure scripts, hotkey 7 + HUD train button, generated hard-hat/wrench sprites. AI trains engineers too: a surplus hire (never a save goal) in `ai_economy._try_train_engineer` when an own structure is below 80% HP past the lockout, smarts-tier gated (Easy never, Hard+ keeps two with several structures), `ENEMY_ENGINEER_*` tuning.)
- [ ] **Healer unit (deprioritized)** — units already have out-of-combat regen, so a unit-healer adds little; revisit only if regen is ever removed or a frontline-support playstyle becomes desirable.
- [x] **Necromancy (Deep Delve research capstone)** — tier-3 mutually-exclusive capstone (three-way with Crystal Forge / Earth Shield). Dead surface swordsmen/archers/dragons leave raisable corpses for 20s; a wizard with the Raise toggle (HUD button when wizards are selected: off → troops → dragon) channels 3s on a corpse to summon an undead copy (~50% HP/damage, no faction abilities or fighter upgrades, no kiting, population 0). Cap per wizard: 5 undead soldiers/archers OR 1 undead dragon (dragon requires an actual dragon corpse). Undead die when their raising wizard dies. The AI picks Necromancy when it rolls Arcane (except on the rush opener, which takes Crystal Forge). (Implemented: `necromancy` tech in `Constants.RESEARCH_TECHS` with Array-style `locks`, `scripts/world/corpse.gd`, `scripts/units/unit_necromancy.gd`, undead raising in `unit.gd` (`_spawn_undead_from`, corpse spawn in `_die`), `UnitData.is_undead`, Raise button in `hud.gd`/`hud_updates.gd`, `player_commands.set_raise_mode`, `_arcane_capstone()` in `ai_economy.gd`, `NECRO_*` tuning, `tests/test_necromancy.gd`.)
- [x] **Underground combat: crawler unit** — new underground-only attacker trained from the building by all factions; descends via the mine entry, cannot surface. Hunts enemy miners through the breached central wall, so miners need crawler escorts; trapped chokepoints (Guerrilla research) are the defender's answer. Sidesteps the problems of sending surface units down (1-wide tunnels, no kiting/AOE). Biggest cost is AI: wave logic, miner shelter orders, and base defense all assume a single surface front — the AI must train crawlers, escort its miners, and defend its mine. Needs a new sprite. (Implemented: `crawler.tres` (`UnitData.is_crawler`, 120g/8s/2 pop, melee), spawn auto-descends and can never climb out or dig, underground-only A* (`find_path_underground` seals the surface row so raids can't bypass the central wall over the top), midfield-rule exception in `unit_vision_targeting._find_crawler_target`, hotkey 8 + HUD train button, generated sprites. AI: surplus guard hire in `ai_economy._try_train_crawler` (smarts-tier gated) plus the `ai_crawlers.gd` module — shelters threatened miners, intercepts visible intruders, raids through the breached wall and pulls home when outnumbered, `ENEMY_CRAWLER_*` tuning. Miner Fight Back now also triggers against crawlers.)
- [ ] **Central wall tuning** — the wall is already breachable: 3-thick column spanning all layers, shared 2000 HP pool, 10 dmg/s per miner, diggable by any miner level, explicit right-click breach command (`player_commands.gd` step 3; idle auto-mining never targets it, so miners mine their own side unless ordered). "Thick wall" model confirmed as the design (no miner-level lock). Crawlers now give breaching a purpose (underground raids); tuning left as-is — revisit e.g. faster dig at higher miner levels if breaches come too late/early.
- [ ] **Sprites for new units** — crawler and engineer need new pixel-art sprites (generated pixel art has precedent: the pigeon card icon). Undead units reuse existing unit sprites with a palette swap (desaturated / sickly tint) rather than new art.

## UX polish

- [ ] **Control groups (Ctrl+1–9)** — saved selection groups; natural home is `player_selection.gd`.
- [ ] **Attack-move (A+click)** — per-order attack-move instead of only the global Attack stance.
- [ ] **Minimap** — canvas-drawn minimap fed by `GridWorld` fog maps; ties fog, layers, and lava events together visually.

## Technical

- [ ] **Web performance audit** — profile `gl_compatibility` + per-frame `_draw` in units/grid with a large army before adding visual features.
- [ ] **CI for the GUT suite** — GitHub Actions job running the headless GUT command on PRs (the pre-push hook only fires on pushes to `main`).
