# Mine Attack

A standalone 2D RTS made in Godot 4.7.

## Premise
Mine ore underground, train an army, and destroy the enemy base. The game blends the mining/unit-training loop of **Stick War: Legacy** with the layered, upgrade-gated digging of **SteamWorld Dig**, wrapped in a cold, post-apocalyptic theme inspired by **Frostpunk**.

---

## Download and play

The easiest way to play is from a release:

1. Go to the [**Releases**](https://github.com/SZaidi00/mine-attack/releases) page.
2. Download the latest zip for your platform:
   - **macOS**: `MineAttack-macOS.zip`
   - **Windows**: `MineAttack-Windows.zip`
3. Extract the zip.
   - **macOS**: open `MineAttack.app`. If Gatekeeper warns that the app is from an unidentified developer, right-click the app and choose **Open**.
   - **Windows**: run `MineAttack.exe`.
4. Pick a difficulty and faction, then press **Play**.

> **Web build**: If you want to play in a browser, the `MineAttack.html` and supporting files are also attached to each release. Serve them over HTTP (not `file://`) — see the web instructions below.

---

## Getting it running locally

### Option A — Run in the Godot editor (recommended for development)

1. Install **Godot 4.7 or newer** from [godotengine.org/download](https://godotengine.org/download) (the standard build, not .NET).
2. Clone or download this repository.
3. Open Godot's project manager, click **Import**, and select the `project.godot` file in the project root.
4. Press **F5** (or the Play button). The main menu opens — pick a difficulty and press **Play**.

No other setup is required: there are no external dependencies, no build step, and all assets are included.

### Option B — Play in the browser (web export)

1. Export the web build (replace `godot` with the path to your Godot binary if it is not on your `PATH`):

   ```bash
   godot --headless --path . --export-release "Web" build/MineAttack.html
   ```

   > Requires the Godot 4.7 web export templates installed (Godot → Editor → Manage Export Templates).

2. Serve the `build/` folder over HTTP. **Opening the .html file directly (file://) will not work**, and Godot 4 web builds need cross-origin isolation headers, so use the included helper:

   ```bash
   python3 tools/serve_web.py 8080
   ```

3. Open **http://localhost:8080/MineAttack.html** in your browser.

### Running the tests

The project uses [GUT](https://github.com/bitwes/Gut) (bundled in `addons/gut/`). Run the suite headless:

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

### Exporting desktop and web builds

Run the release exporter (replace `godot` with the path to your Godot binary if it is not on your `PATH`):

```bash
tools/export_all.sh
```

This produces `build/MineAttack.html`, `build/MineAttack.app`, `build/MineAttack.exe`, `MineAttack-macOS.zip`, and `MineAttack-Windows.zip`.

---

## Controls

- **Left-click / drag**: select units (Shift adds to selection).
- **Right-click**: context order — move, attack, mine, breach the wall, enter/exit the mine.
- **1 / 2 / 3 / 4**: train Miner / Swordsman / Archer / Wizard.
- **Ctrl+A / Ctrl+M / Ctrl+F**: select all units / miners / fighters.
- **WASD / Arrow keys**: pan camera. **Mouse wheel**: zoom.
- **Tab**: toggle surface / underground camera view.
- **Space / Esc**: pause menu.
- **F3**: debug overlay (debug builds).

## Playing the game

- Train units from the bottom bar and watch production in the queue panel on the right.
- Miners dig blind: they don't know where ore is until a tile yields gold — then they remember it and come back.
- Upgrade miners (layers, carry, speed) and each fighter type (HP, damage) from the bottom bar.
- Stances: **Attack** (rush the enemy base), **Defend** (hold), **Garrison** (mine), **Rally** (right-click a point — fighters hunt everything on the surface, miners included).
- Archers and wizards keep their standoff range automatically; units slowly heal when out of combat.
- Dead miners drop their cargo where they fell — walk any miner over it to collect.
- Use the **1×/2×/3×** buttons in the top bar to change game speed.

## Layers

- Layers 1–2: Miner Level 1
- Layers 3–4: Miner Level 2
- Layers 5–7: Miner Level 3

The central wall separating the two mines can be broken by miners on either side when ordered to mine it.

## Game concepts

### Factions
Before each match, both sides pick a faction. Each faction grants a passive bonus and a unit ability you can trigger with the ability button:

- **Brute**: tougher units; **Berserk** ability boosts attack speed.
- **Shadow**: faster, stealthier units; **Blink** teleports a unit.
- **Ironclad**: stronger structures and siege; **Heavy Bolt** and **Crush**.
- **Arcane**: wizard-focused; **Mana Burn** and **Arcane Shot**.
- **Swarm**: cheaper, faster-training units; **Swarm** and **Volley**.
- **Explorer**: mining and vision bonuses; **Miner Reveal** and **Supply Drop**.

Hover the faction cards in the main menu to see the full description.

### Fog of war and vision
The map is hidden until your units or structures reveal it. **Lanterns** provide permanent vision, can be upgraded through three tiers, and shelter miners during snowstorms. Place them from the build menu. Towers and walls also block sight and movement until destroyed.

### Weather and dynamic terrain
The battlefield changes over time:

- **Snowstorms** reduce vision and movement; keep miners near lanterns or they take frost damage.
- **Volcano eruptions** rain meteors on the surface, leaving burning ground that damages units.
- **Lava rises** from the bottom of the mine, forcing you upward and eventually turning flooded cells into new ore.
- **Cave-ins** drop 3×3 rock blocks that deal damage and push units.

### Research
Open the research panel with **R** to advance along mutually-exclusive branches. Completing a tech locks its alternative, but you can respec once per match for 500 gold. Research unlocks traps, burning-ground spells, stronger surface combat, guerrilla tactics, and siege master upgrades.

### Structures
Use the radial build menu to place:

- **Lanterns**: vision and snowstorm shelter.
- **Towers**: ranged defense that attacks enemies in range.
- **Walls**: block enemy movement and sight.
- **Traps**: hidden area damage triggered by enemy units.

## Win condition

Destroy the enemy building before it destroys yours. Difficulty (Easy / Normal / Hard / Nightmare) scales the AI's economy, training speed, aggression, and how fiercely its sieges fight back.

---

## Automated releases

This repository includes a pre-push hook in `.githooks/pre-push`. When you push to `main`, it automatically:

1. Runs `tools/export_all.sh` to rebuild the macOS and Windows zips.
2. Creates a new GitHub release with an auto-incremented patch version (e.g., `v0.1.0` → `v0.1.1`).
3. Attaches `MineAttack-macOS.zip` and `MineAttack-Windows.zip` to the release.

To enable the hook after cloning, run:

```bash
git config core.hooksPath .githooks
```

To skip the hook for a single push:

```bash
SKIP_RELEASE=1 git push origin main
```

To set a specific version instead of auto-incrementing:

```bash
VERSION_OVERRIDE=v0.2.0 git push origin main
```
