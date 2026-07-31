# Mine Attack

A standalone 2D RTS made in Godot 4.7.

## Premise
Mine ore underground, train an army, and destroy the enemy base. The game blends the mining/unit-training loop of **Stick War: Legacy** with the layered, upgrade-gated digging of **SteamWorld Dig**, wrapped in a cold, post-apocalyptic theme inspired by **Frostpunk**.

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

## Win condition

Destroy the enemy building before it destroys yours. Difficulty (Easy / Normal / Hard / Nightmare) scales the AI's economy, training speed, aggression, and how fiercely its sieges fight back.
