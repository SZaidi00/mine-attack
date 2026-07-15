# Frost Mines — Game Design & Implementation Document

**Version:** 1.0  
**Engine:** Godot 4.x (recommended)  
**Genre:** 2D RTS / Mining / Base Defense  
**Theme:** Post-apocalyptic frozen wasteland (Frostpunk-inspired aesthetics)  
**Max Players:** 1 (PvE vs AI) — expandable to PvP  
**Target Resolution:** 1920×1080 (scalable), pixel-art or stylized vector 2D  
**Session Length:** 8–15 minutes per match

---

## 1. Executive Summary

*Frost Mines* combines the **macro-economy and unit-queue training** of *Stick War: Legacy* with the **layered underground exploration and destructible terrain** of *SteamWorld Dig*. Players manage a surface base and an underground mining operation simultaneously. Coin mined underground funds the training of surface fighters who march across an open field to destroy the enemy building. The underground connects both sides via a thick central wall that can be breached, allowing miners to raid the enemy's mine — but fighters cannot enter enemy mines, only exit from their own.

---

## 2. Platform Decision: Godot 4.x

### 2.1 Why Godot over Unity

| Criteria | Godot 4.x | Unity |
|----------|-----------|-------|
| **2D Native** | True 2D coordinate system, pixel-perfect camera, no 3D projection overhead | 2D is a camera projection of 3D space; requires extra care for pixel art |
| **Scene System** | Composable scenes (units, buildings, tiles) are first-class; ideal for spawner games | Prefabs work but are heavier; nested prefab workflows are more complex |
| **State Machines** | Built-in `AnimationTree` + custom state scripts; lightweight for unit AI | Requires Animator Controller or third-party plugins; heavier for simple 2D states |
| **Navigation2D** | `AStarGrid2D` + `NavigationPolygon` built-in, perfect for tile-based digging | NavMesh is 3D-first; 2D pathfinding requires packages or custom solutions |
| **Build Size** | ~30–50 MB for a 2D game; fast export | 100+ MB minimum; IL2CPP adds significant compile time |
| **Licensing** | MIT License, 100% free, no royalties | Free until revenue thresholds; runtime fee uncertainty |
| **Iteration Speed** | Near-instant play button; C# or GDScript | Slower domain reload; heavier editor |
| **Scripting** | GDScript (Python-like, built for Godot) or C# | C# only (or UnityScript, deprecated) |

### 2.2 Recommended Godot Configuration
- **Renderer:** `Forward+` (desktop) or `Mobile` (if targeting mobile/low-end)
- **Physics:** `Jolt Physics` (Godot 4.3+) or built-in `Godot Physics 2D`
- **Scripting Language:** GDScript for rapid iteration; C# if team has strong .NET background
- **Project Settings:**
  - `display/window/size/viewport_width`: 1920
  - `display/window/size/viewport_height`: 1080
  - `display/window/stretch/mode`: `canvas_items`
  - `display/window/stretch/aspect`: `expand`
  - `rendering/2d/snap_2d_transforms_to_pixel`: `true` (if pixel art)

---

## 3. Game Loop & Core Mechanics

### 3.1 High-Level Loop
```
[Mine Underground] → [Collect Coin] → [Queue Units] → [Train Units] → [Deploy Fighters] → [Destroy Enemy Building]
                     ↑___________________________________________________________________________|
```

### 3.2 Dual-Layer Gameplay
The game operates on two simultaneous planes:

1. **Surface Layer:** Base building, unit training, open-field combat
2. **Underground Layer:** Mining, terrain destruction, economy generation, defensive garrison

The player toggles between views (or uses a split-screen minimap) but both layers run in real-time.

---

## 4. Surface Layout

### 4.1 Horizontal Arrangement (Left to Right)

```
[Player Building]  [Player Mine Entry]  [Open Field / Battleground]  [Enemy Mine Entry]  [Enemy Building]
```

| Element | Position (X) | Width | Height | Notes |
|---------|-------------|-------|--------|-------|
| Player Building | 0 | 120px | 160px | Anchor at bottom-left of screen |
| Player Mine Entry | 200px | 60px | 80px | Visual shaft descending underground |
| Open Field | 280px – 1640px | 1360px | Full height | Combat occurs here |
| Enemy Mine Entry | 1720px | 60px | 80px | Mirror of player mine |
| Enemy Building | 1800px | 120px | 160px | Anchor at bottom-right |

### 4.2 Surface Mechanics
- **Fighters spawn** at the Player Building and march right toward the enemy.
- **Miners spawn** at the Player Building, walk to the Player Mine Entry, and descend.
- **Fighters cannot enter the Enemy Mine** — they pass by it and attack the Enemy Building.
- **Fighters can be stationed inside the Player Mine** for underground defense (see Section 7.3).
- **Enemy AI** mirrors all player behaviors.

---

## 5. Underground System

### 5.1 Layer Architecture

The underground is a 2D grid-based destructible terrain system with **7 layers**.

```
Layer 1 (Surface-1)  ← Miner L1 accessible
Layer 2              ← Miner L1 accessible
─────────────────────
Layer 3              ← Miner L2 required
Layer 4              ← Miner L2 required
─────────────────────
Layer 5              ← Miner L3 required
Layer 6              ← Miner L3 required
Layer 7 (Bottom)     ← Miner L3 required
```

| Layer | Depth Y-Range | Miner Level Required | Coin per Block | Blocks per Row | Total Blocks | Visual Theme |
|-------|--------------|----------------------|---------------|----------------|--------------|--------------|
| 1 | 0 to -100 | 1 | 5–10 | 20 | ~400 | Frost-covered soil, ice crystals |
| 2 | -100 to -200 | 1 | 8–15 | 22 | ~440 | Packed ice, frozen roots |
| 3 | -200 to -300 | 2 | 12–20 | 24 | ~480 | Dark rock, coal seams |
| 4 | -300 to -400 | 2 | 15–25 | 26 | ~520 | Iron ore, rusted metal debris |
| 5 | -400 to -500 | 3 | 20–35 | 28 | ~560 | Deep granite, magma cracks |
| 6 | -500 to -600 | 3 | 25–40 | 30 | ~600 | Obsidian, ancient ruins |
| 7 | -600 to -700 | 3 | 30–50 | 32 | ~640 | Crystalline cavern, glowing minerals |

### 5.2 Tile System
- Each layer is divided into **destructible tiles** (default 32×32 px or 64×64 px).
- Tiles have HP: `50` (Layer 1–2), `75` (Layer 3–4), `100` (Layer 5–7).
- When a tile is mined, it becomes empty space (air). Miners can walk through empty space.
- **Tile regeneration:** None. Once mined, tiles stay empty for the match.

### 5.3 The Central Wall

A thick vertical wall separates the player's mine from the enemy's mine.

| Property | Value |
|----------|-------|
| Position X | Center of underground map |
| Width | 80px (2.5 tiles) |
| Height | Full depth of all 7 layers |
| HP | 2000 |
| Damage per Miner Hit | 10 per second |
| Breakable By | Either side, but only when actively targeted by player/AI command |
| Visual | Reinforced steel plates with frost, warning stripes |

**Wall Behavior:**
- The wall does **not** auto-target. The player must click the wall and select "Attack/Breach" to send miners to break it.
- Once broken, the wall becomes empty space. Miners from either side can cross into the enemy's mine.
- Miners entering the enemy mine can steal coin from enemy tiles (if any remain) or attack enemy miners.
- The wall **respawns** at match start; does not regenerate mid-match.

### 5.4 Underground Layout Visualization

```
← Player Side →                ← Wall →                ← Enemy Side →
┌─────────────────┐            ┌──────┐            ┌─────────────────┐
│ Layer 1         │            │██████│            │ Layer 1         │
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│            │██████│            │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│            │██████│            │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │
├─────────────────┤            │██████│            ├─────────────────┤
│ Layer 2         │            │██████│            │ Layer 2         │
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│            │██████│            │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │
├─────────────────┤            │██████│            ├─────────────────┤
│ Layer 3         │            │██████│            │ Layer 3         │
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│            │██████│            │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │
│ ...             │            │██████│            │ ...             │
│ Layer 7         │            │██████│            │ Layer 7         │
└─────────────────┘            └──────┘            └─────────────────┘
```

---

## 6. Unit System

### 6.1 Unit Types

#### 6.1.1 Miner

| Property | Level 1 | Level 2 | Level 3 |
|----------|---------|---------|---------|
| **Cost** | 50 coin | — (upgrade) | — (upgrade) |
| **Train Time** | 3 seconds | — | — |
| **HP** | 50 | 75 | 100 |
| **Movement Speed** | 60 px/sec | 70 px/sec | 80 px/sec |
| **Mine Damage (to tiles)** | 10/sec | 15/sec | 25/sec |
| **Carry Capacity** | 20 coin | 30 coin | 50 coin |
| **Mining Rate (coin/sec)** | 10 | 15 | 25 |
| **Max Layer** | 2 | 4 | 7 |
| **Visual** | Pickaxe, ragged coat | Drill backpack, goggles | Jackhammer, heavy armor |

**Miner AI State Machine:**
```
IDLE → find deepest accessible unmined tile
  ↓
MOVING → pathfind to target tile (A* on grid, avoiding unmined tiles if possible, or mining through)
  ↓
MINING → deal damage to tile until destroyed
  ↓
COLLECTING → add coin to cargo (up to capacity)
  ↓
RETURNING → pathfind to Player Mine Entry → surface → Player Building
  ↓
DEPOSITING → add cargo to player coin total
  ↓
IDLE
```

**Miner Combat:** Miners have **0 DPS** against units. If attacked, they flee toward the nearest friendly fighter or the Player Building.

#### 6.1.2 Swordsman

| Property | Value |
|----------|-------|
| **Cost** | 100 coin |
| **Train Time** | 5 seconds |
| **HP** | 150 |
| **Damage Per Second (DPS)** | 15 |
| **Attack Range** | 30 px (melee) |
| **Movement Speed** | 80 px/sec |
| **Visual** | Rusted sword, fur cloak, frostbitten skin |
| **Role** | Frontline tank, absorbs damage |

#### 6.1.3 Archer

| Property | Value |
|----------|-------|
| **Cost** | 150 coin |
| **Train Time** | 6 seconds |
| **HP** | 80 |
| **DPS** | 12 |
| **Attack Range** | 150 px |
| **Movement Speed** | 70 px/sec |
| **Projectile Speed** | 300 px/sec |
| **Visual** | Shortbow, ice-quiver, hooded parka |
| **Role** | Ranged DPS, stays behind swordsmen |

#### 6.1.4 Wizard

| Property | Value |
|----------|-------|
| **Cost** | 250 coin |
| **Train Time** | 10 seconds |
| **HP** | 60 |
| **DPS** | 25 |
| **Attack Range** | 120 px |
| **Movement Speed** | 50 px/sec |
| **AOE Radius** | 40 px (splash damage to all enemies in radius) |
| **Visual** | Frost staff, tattered robes, glowing blue hands |
| **Role** | High-damage AOE, fragile, stays at max range |

### 6.2 Unit Caps

| Limit | Value |
|-------|-------|
| **Max Units per Player** | 100 |
| **Max Training Queue** | 5 units |
| **Queue Processing** | FIFO (First In, First Out) |
| **Queue Visibility** | UI panel showing unit icons + progress bars |

### 6.3 Fighter Behavior Rules

1. **Cannot enter enemy mine.** Fighters walk past the Enemy Mine Entry and continue to the Enemy Building.
2. **Can be stationed in own mine.** Player can select fighters and click "Garrison Mine." They descend the Player Mine Entry and patrol underground.
3. **Underground Combat:** If enemy miners breach the wall and enter the player's side, garrisoned fighters will engage them.
4. **Auto-Attack Priority:**
   - Enemy fighters in range (closest first)
   - Enemy building (if no fighters in range)
   - Enemy miners (only if they are on player's side of the wall)
5. **Retreat:** No retreat command. Fighters fight until death.

---

## 7. Economy System

### 7.1 Coin Sources

| Source | Rate | Notes |
|--------|------|-------|
| **Mining** | Variable by layer | Primary source; see Layer table (Section 5.1) |
| **Killing Enemy Miners** | 50% of their carried cargo | Drops on death in underground |
| **Match Start** | 150 coin | Both player and AI |

### 7.2 Coin Sinks

| Sink | Cost | Effect |
|------|------|--------|
| **Train Miner** | 50 coin | Adds 1 miner to population |
| **Train Swordsman** | 100 coin | Adds 1 swordsman |
| **Train Archer** | 150 coin | Adds 1 archer |
| **Train Wizard** | 250 coin | Adds 1 wizard |
| **Upgrade Miners to L2** | 500 coin | All existing + future miners become Level 2 |
| **Upgrade Miners to L3** | 1500 coin | All existing + future miners become Level 3 |

### 7.3 Economy Balance Notes
- A single Level 1 miner takes ~10 seconds to mine 20 coin and return.
- A swordsman costs 100 coin = ~50 seconds of single-miner income.
- Early game: miners are the highest ROI. Late game: high-layer miners generate massive income.
- The upgrade to Level 2 pays for itself after ~50 trips (≈8 minutes).
- The upgrade to Level 3 pays for itself after ~60 trips (≈10 minutes).

---

## 8. Buildings

### 8.1 Player Building (Command Center)

| Property | Value |
|----------|-------|
| **HP** | 5000 |
| **Size** | 120×160 px |
| **Function** | Spawns all units, receives mined coin, training queue hub |
| **Visual** | Industrial bunker, smokestack, frost-covered steel, warm amber windows |
| **Destruction** | If HP reaches 0, player loses. Explosion + collapse animation. |

### 8.2 Enemy Building

Mirror of Player Building. HP: 5000. Visual: darker steel, red warning lights, more angular architecture.

### 8.3 Mine Entry

| Property | Value |
|----------|-------|
| **Size** | 60×80 px |
| **Function** | Portal between surface and underground for miners and garrisoned fighters |
| **Visual** | Elevator shaft with chain lift, icy rim, glowing lantern |
| **Interaction** | Click to toggle view to underground. Miners auto-enter/exit. |

---

## 9. Combat System

### 9.1 Damage Formula

```
Damage Applied = Attacker.DPS * delta_time
```

No armor, no resistances, no critical hits (for simplicity in V1).

### 9.2 Attack Cooldowns

| Unit | Attack Interval |
|------|-----------------|
| Swordsman | 0.5 sec (30 damage per hit) |
| Archer | 1.0 sec (12 damage per arrow) |
| Wizard | 1.5 sec (37.5 damage per blast) |

### 9.3 Targeting Logic

```gdscript
func find_target(unit):
    if unit.type == "miner":
        return null  # Miners don't attack

    enemies = get_enemies_in_range(unit.attack_range)
    if enemies.size() > 0:
        return closest_enemy(enemies, unit.position)
    else:
        return enemy_building  # March toward building
```

### 9.4 Garrison Combat (Underground)

When fighters are garrisoned underground:
- They patrol a radius around the Player Mine Entry.
- If an enemy unit enters the player's side of the mine, garrisoned fighters path toward it.
- Fighters move at 60% of their surface speed underground (tight tunnels).
- Fighters cannot mine tiles.

---

## 10. Training Queue System

### 10.1 Queue Behavior (Stick War: Legacy Style)

- **Single queue:** Only one unit trains at a time.
- **FIFO:** Units are built in the order the player clicks them.
- **Queue Limit:** Maximum 5 units in queue (including currently training).
- **Cancel:** Player can click an queued unit to cancel it and receive a **100% refund**.
- **Progress Bar:** Visible above the Player Building and in the UI panel.

### 10.2 Queue UI

```
┌─────────────────────────────┐
│  TRAINING                   │
│  [Swordsman ▓▓▓▓░░ 60%]     │  ← Currently training
│  [Archer] [Wizard] [Miner]  │  ← Queue (click to cancel)
└─────────────────────────────┘
```

### 10.3 Technical Implementation

```gdscript
class TrainingQueue:
    var queue: Array[UnitType] = []
    var current_progress: float = 0.0
    var current_unit: UnitType = null

    func enqueue(type: UnitType) -> bool:
        if queue.size() >= 5:
            return false
        queue.append(type)
        if current_unit == null:
            _start_next()
        return true

    func _start_next():
        if queue.is_empty():
            return
        current_unit = queue.pop_front()
        current_progress = 0.0

    func update(delta: float):
        if current_unit == null:
            return
        current_progress += delta
        if current_progress >= current_unit.train_time:
            spawn_unit(current_unit)
            current_unit = null
            _start_next()
```

---

## 11. AI Behavior (Enemy)

### 11.1 Enemy AI Architecture

The enemy AI mirrors the player's capabilities but follows scripted decision trees with weighted randomness.

### 11.2 Economic AI

```
Every 2 seconds:
  miner_count = count enemy miners
  fighter_count = count enemy fighters

  IF miner_count < 5 AND coin >= 50:
      queue miner
  ELIF fighter_count < 3 AND coin >= 100:
      queue swordsman
  ELIF coin >= 250 AND random() < 0.3:
      queue wizard
  ELIF coin >= 150:
      queue archer
  ELIF coin >= 100:
      queue swordsman

  IF enemy_miner_level == 1 AND coin >= 500:
      upgrade to L2
  ELIF enemy_miner_level == 2 AND coin >= 1500:
      upgrade to L3
```

### 11.3 Aggression AI

```
Every 10 seconds:
  player_fighter_count = count player fighters on surface
  enemy_fighter_count = count enemy fighters on surface

  IF enemy_fighter_count > player_fighter_count * 1.5:
      aggression_level = "push"  // Send all fighters to attack
  ELIF enemy_fighter_count < player_fighter_count * 0.5:
      aggression_level = "defend"  // Garrison 30% of fighters in mine
  ELSE:
      aggression_level = "balanced"
```

### 11.4 Wall Breach AI

```
IF enemy has no accessible tiles left on their side AND coin > 1000:
    target wall for breach
    send 30% of miners to attack wall
```

### 11.5 Difficulty Scaling

| Difficulty | AI Coin Multiplier | Train Speed | Upgrade Speed | Aggression |
|------------|-------------------|-------------|---------------|------------|
| Easy | 0.8x | 1.0x | 0.7x | Defensive |
| Normal | 1.0x | 1.0x | 1.0x | Balanced |
| Hard | 1.2x | 0.9x | 1.2x | Aggressive |
| Nightmare | 1.5x | 0.8x | 1.5x | Very Aggressive |

---

## 12. Input & Controls

### 12.1 Mouse Controls

| Action | Input | Result |
|--------|-------|--------|
| **Select Unit** | Left-click | Selects single unit; shows HP bar and stats |
| **Multi-Select** | Left-click + drag box | Selects all units in box |
| **Move/Attack** | Right-click on ground | Selected fighters move to location; attack enemies on arrival |
| **Garrison** | Right-click on Mine Entry | Selected fighters enter mine |
| **Breach Wall** | Right-click on Wall | Selected miners target wall (if wall selected) |
| **Queue Unit** | Click UI button | Adds unit to training queue |
| **Cancel Queue** | Click queued unit icon | Removes unit, refunds coin |
| **Toggle View** | Click "Surface"/"Underground" tab or press Tab | Switches camera view |

### 12.2 Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `1` | Queue Miner |
| `2` | Queue Swordsman |
| `3` | Queue Archer |
| `4` | Queue Wizard |
| `Tab` | Toggle Surface / Underground |
| `Space` | Pause game |
| `Esc` | Open menu |
| `Ctrl + A` | Select all visible fighters |
| `Shift + Click` | Add to selection |

---

## 13. UI / HUD Design

### 13.1 Surface HUD

```
┌─────────────────────────────────────────────────────────────┐
│  💰 1,240          ⛏️ Miner L2          ⚔️ 45/100 Units    │  ← Top Bar
│                                                             │
│  [Surface] [Underground]                                    │  ← View Tabs
│                                                             │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐            │
│  │ Miner   │ │Swordsman│ │ Archer  │ │ Wizard  │            │  ← Unit Queue Buttons
│  │  50     │ │  100    │ │  150    │ │  250    │            │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘            │
│                                                             │
│  TRAINING:                                                  │
│  [Swordsman ▓▓▓▓▓▓▓▓░░ 80%] [Archer] [Miner]               │  ← Queue Panel
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                                                     │    │
│  │                  [GAME WORLD]                       │    │
│  │                                                     │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  [Upgrade Miners to L3]  [1,500 coin]                       │  ← Upgrade Button
└─────────────────────────────────────────────────────────────┘
```

### 13.2 Underground HUD

```
┌─────────────────────────────────────────────────────────────┐
│  💰 1,240          ⛏️ Miner L2          ⚔️ 45/100 Units    │
│                                                             │
│  [Surface] [Underground]                                    │
│                                                             │
│  LAYER 1  LAYER 2  LAYER 3  LAYER 4  LAYER 5  LAYER 6  L7  │  ← Layer Indicators
│   ▓▓▓     ▓▓▓▓     ▓▓▓      ▓▓       ░░░      ░░░     ░░  │     (▓ = tiles remain, ░ = empty)
│                                                             │
│  WALL HP: [▓▓▓▓▓▓▓▓░░░░] 1,200 / 2,000                     │
│                                                             │
│  [BREACH WALL]  [Garrison Fighters]  [Recall Miners]        │
└─────────────────────────────────────────────────────────────┘
```

### 13.3 Building Health Bars

- **Surface:** Large HP bar above each building (green = player, red = enemy).
- **Underground:** Wall HP bar at top of screen.
- **Units:** Small HP bar above each unit (visible on hover or when damaged).

---

## 14. Visual & Audio Direction

### 14.1 Art Style

- **Style:** Stylized 2D with a "frozen industrial" aesthetic. Not pure pixel art unless desired — clean vector-style sprites with heavy texture overlays (frost, rust, grime).
- **Color Palette:**
  - **Surface:** White, ice blue, steel gray, dark brown (wood/ruins), warm amber (building lights).
  - **Underground:** Deep slate, charcoal, cyan ice crystals, orange magma cracks (Layer 5+), purple glow (Layer 7).
  - **UI:** Dark steel panels with frost edges. Warning amber for alerts. Cold blue for ally highlights. Red for enemy.
- **Atmosphere:** Snow particles on surface. Dust motes underground. Breath mist on units in cold areas.

### 14.2 Unit Visuals

| Unit | Key Visual Elements |
|------|-------------------|
| **Miner L1** | Pickaxe, hooded cloak, lantern, frost on shoulders |
| **Miner L2** | Steam drill backpack, goggles, reinforced boots |
| **Miner L3** | Hydraulic jackhammer, heavy plating, headlamp |
| **Swordsman** | Rusted broadsword, fur pelt, scarred face, heavy boots |
| **Archer** | Recurve bow, ice-arrow quiver, white hood, light armor |
| **Wizard** | Frost staff (glowing tip), torn robes, blue magical aura |

### 14.3 Animation States

All units require:
- `idle` (breathing/standing)
- `walk` (4–6 frames)
- `attack` (2–3 frames + impact flash)
- `death` (collapse/desaturate/fade)
- `mine` (Miner only: swing pickaxe/drill)

### 14.4 Audio Design

| Event | Audio Description |
|-------|-----------------|
| **Mining** | Metallic *clink* (L1), pneumatic *whir* (L2), heavy *jackhammer thud* (L3) |
| **Sword Attack** | Sharp *swish* + meaty *thwack* |
| **Arrow Fire** | Bow *twang* + whistle + impact |
| **Wizard Blast** | Icy *crackle* + explosion |
| **Building Hit** | Deep *boom* + crumbling concrete |
| **Building Destroyed** | Massive explosion, alarm siren fade |
| **Coin Deposit** | Satisfying *chime* + coin clink |
| **Unit Trained** | Horn/bugle fanfare |
| **Queue Complete** | Small *ding* |
| **Wall Breach** | Loud *metal tear* + grinding |
| **Ambient Surface** | Howling wind, distant machinery, creaking ice |
| **Ambient Underground** | Dripping water, echoing drills, low rumble |

---

## 15. Technical Architecture (Godot)

### 15.1 Project File Structure

```
res://
├── autoload/
│   ├── GameState.gd          # Global game state (coin, score, pause)
│   ├── AudioManager.gd       # SFX and music
│   └── Constants.gd          # All balance numbers, costs, stats
├── scenes/
│   ├── units/
│   │   ├── miner/
│   │   │   ├── Miner.tscn
│   │   │   ├── Miner.gd
│   │   │   ├── sprites/
│   │   │   └── animations/
│   │   ├── swordsman/
│   │   ├── archer/
│   │   └── wizard/
│   ├── buildings/
│   │   ├── PlayerBuilding.tscn
│   │   ├── EnemyBuilding.tscn
│   │   └── MineEntry.tscn
│   ├── world/
│   │   ├── SurfaceWorld.tscn      # Surface level container
│   │   ├── UndergroundWorld.tscn  # Underground level container
│   │   ├── TileMapUnderground.tscn # Destructible tilemap
│   │   └── Wall.tscn
│   ├── ui/
│   │   ├── HUD.tscn
│   │   ├── TrainingQueuePanel.tscn
│   │   ├── UnitButton.tscn
│   │   └── HealthBar.tscn
│   └── effects/
│       ├── Explosion.tscn
│       ├── DustParticle.tscn
│       └── CoinSparkle.tscn
├── scripts/
│   ├── ai/
│   │   └── EnemyAI.gd
│   ├── state_machines/
│   │   ├── UnitStateMachine.gd
│   │   ├── MinerStates.gd
│   │   └── FighterStates.gd
│   └── utils/
│       ├── Pathfinder.gd
│       └── GridUtils.gd
├── assets/
│   ├── sprites/
│   ├── audio/
│   └── fonts/
└── export_presets.cfg
```

### 15.2 Key Godot Nodes

| Game Object | Primary Node Type | Child Nodes |
|-------------|-------------------|-------------|
| **Unit** | `CharacterBody2D` | `Sprite2D`, `CollisionShape2D`, `AnimationPlayer`, `HealthBar (CanvasLayer)` |
| **Building** | `StaticBody2D` | `Sprite2D`, `CollisionShape2D`, `Area2D` (hitbox), `AnimationPlayer` |
| **Mine Entry** | `Area2D` | `Sprite2D`, `CollisionShape2D` |
| **Underground Tile** | `TileMapLayer` (Godot 4.3+) or custom `StaticBody2D` tiles | `Sprite2D`, `CollisionShape2D`, `AnimationPlayer` (break) |
| **Wall** | `StaticBody2D` | `Sprite2D`, `CollisionShape2D`, `HealthBar` |
| **Projectile** | `RigidBody2D` or `Area2D` | `Sprite2D`, `CollisionShape2D` |

### 15.3 Pathfinding Implementation

```gdscript
# Pathfinder.gd — Autoload or utility class
extends Node

class_name Pathfinder

var astar: AStarGrid2D
var tilemap: TileMapLayer

func setup(tilemap_layer: TileMapLayer):
    tilemap = tilemap_layer
    astar = AStarGrid2D.new()
    astar.region = tilemap.get_used_rect()
    astar.cell_size = Vector2i(32, 32)
    astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
    astar.update()

    for cell in tilemap.get_used_cells():
        if tilemap.get_cell_source_id(cell) == -1:  # Empty
            astar.set_point_solid(cell, false)
        else:
            astar.set_point_solid(cell, true)

func get_path(start: Vector2, end: Vector2) -> PackedVector2Array:
    var start_cell = tilemap.local_to_map(start)
    var end_cell = tilemap.local_to_map(end)
    return astar.get_point_path(start_cell, end_cell)

func mark_cell_mined(cell: Vector2i):
    astar.set_point_solid(cell, false)
```

### 15.4 Unit State Machine (GDScript)

```gdscript
# UnitStateMachine.gd
class_name UnitStateMachine
extends Node

enum State { IDLE, MOVING, MINING, ATTACKING, RETURNING, DEAD }

var current_state: State = State.IDLE
var unit: CharacterBody2D
var target: Node2D = null
var target_position: Vector2 = Vector2.ZERO

func _ready():
    unit = get_parent()

func _physics_process(delta: float):
    match current_state:
        State.IDLE:
            _process_idle(delta)
        State.MOVING:
            _process_moving(delta)
        State.MINING:
            _process_mining(delta)
        State.ATTACKING:
            _process_attacking(delta)
        State.RETURNING:
            _process_returning(delta)

func transition_to(new_state: State, data: Dictionary = {}):
    current_state = new_state
    target = data.get("target", null)
    target_position = data.get("position", Vector2.ZERO)

func _process_moving(delta: float):
    if target_position == Vector2.ZERO:
        transition_to(State.IDLE)
        return

    var direction = (target_position - unit.global_position).normalized()
    var velocity = direction * unit.speed
    unit.velocity = velocity
    unit.move_and_slide()

    if unit.global_position.distance_to(target_position) < 5.0:
        transition_to(State.IDLE)
```

### 15.5 Training Queue Manager

```gdscript
# TrainingQueueManager.gd
class_name TrainingQueueManager
extends Node

signal unit_trained(unit_type: String)
signal queue_updated(queue: Array[String], progress: float)

@export var max_queue_size: int = 5

var queue: Array[String] = []
var current_training: String = ""
var current_progress: float = 0.0

func enqueue(unit_type: String) -> bool:
    var total = queue.size() + (1 if current_training != "" else 0)
    if total >= max_queue_size:
        return false

    if current_training == "":
        current_training = unit_type
        current_progress = 0.0
    else:
        queue.append(unit_type)

    queue_updated.emit(get_full_queue(), get_progress_percent())
    return true

func cancel_at_index(index: int) -> bool:
    if index == 0 and current_training != "":
        # Refund and start next
        var refunded = current_training
        current_training = queue.pop_front() if not queue.is_empty() else ""
        current_progress = 0.0
        queue_updated.emit(get_full_queue(), get_progress_percent())
        return true
    elif index > 0 and index - 1 < queue.size():
        queue.remove_at(index - 1)
        queue_updated.emit(get_full_queue(), get_progress_percent())
        return true
    return false

func update(delta: float):
    if current_training == "":
        return

    current_progress += delta
    var train_time = Constants.TRAIN_TIMES[current_training]

    if current_progress >= train_time:
        unit_trained.emit(current_training)
        current_training = queue.pop_front() if not queue.is_empty() else ""
        current_progress = 0.0

    queue_updated.emit(get_full_queue(), get_progress_percent())

func get_full_queue() -> Array[String]:
    var full = []
    if current_training != "":
        full.append(current_training)
    full.append_array(queue)
    return full

func get_progress_percent() -> float:
    if current_training == "":
        return 0.0
    return current_progress / Constants.TRAIN_TIMES[current_training]
```

### 15.6 Constants File (Balance Numbers)

```gdscript
# Constants.gd
extends Node

class_name Constants

# Economy
const STARTING_COIN = 150
const MAX_UNITS = 100
const MAX_QUEUE_SIZE = 5

# Unit Costs
const COSTS = {
    "miner": 50,
    "swordsman": 100,
    "archer": 150,
    "wizard": 250
}

# Train Times (seconds)
const TRAIN_TIMES = {
    "miner": 3.0,
    "swordsman": 5.0,
    "archer": 6.0,
    "wizard": 10.0
}

# Unit Stats
const UNIT_STATS = {
    "miner_l1": { "hp": 50, "speed": 60, "mine_dps": 10, "carry": 20, "mine_rate": 10, "max_layer": 1 },
    "miner_l2": { "hp": 75, "speed": 70, "mine_dps": 15, "carry": 30, "mine_rate": 15, "max_layer": 3 },
    "miner_l3": { "hp": 100, "speed": 80, "mine_dps": 25, "carry": 50, "mine_rate": 25, "max_layer": 6 },
    "swordsman": { "hp": 150, "dps": 15, "range": 30, "speed": 80 },
    "archer": { "hp": 80, "dps": 12, "range": 150, "speed": 70, "proj_speed": 300 },
    "wizard": { "hp": 60, "dps": 25, "range": 120, "speed": 50, "aoe_radius": 40 }
}

# Miner Upgrades
const MINER_UPGRADE_COSTS = {
    1: 500,   # L1 → L2
    2: 1500   # L2 → L3
}

# Buildings
const PLAYER_BUILDING_HP = 5000
const ENEMY_BUILDING_HP = 5000

# Wall
const WALL_HP = 2000
const WALL_DAMAGE_PER_MINER_HIT = 10

# Underground Layers
const LAYERS = 7
const LAYER_HEIGHT = 100  # pixels
const TILE_SIZE = 32

# Layer Coin Ranges (min, max)
const LAYER_COIN_RANGES = {
    0: [5, 10],
    1: [8, 15],
    2: [12, 20],
    3: [15, 25],
    4: [20, 35],
    5: [25, 40],
    6: [30, 50]
}

# Layer Tile HP
const LAYER_TILE_HP = {
    0: 50, 1: 50,
    2: 75, 3: 75,
    4: 100, 5: 100, 6: 100
}
```

---

## 16. Scene Composition Guide

### 16.1 Unit Scene Template

Every unit (Miner, Swordsman, Archer, Wizard) follows this scene tree:

```
CharacterBody2D (named Unit)
├── Sprite2D (named Sprite)
│   └── Material: CanvasItemMaterial (for flash effects)
├── CollisionShape2D (named Hitbox)
│   └── Shape: RectangleShape2D (match sprite bounds)
├── AnimationPlayer (named Animator)
├── HealthBar (CanvasLayer or Node2D positioned above unit)
│   ├── Background (ColorRect)
│   └── Fill (ColorRect)
├── Area2D (named AttackRange) — for fighters only
│   └── CollisionShape2D (CircleShape2D)
└── StateMachine (Node, script: UnitStateMachine.gd)
```

### 16.2 Building Scene Template

```
StaticBody2D (named Building)
├── Sprite2D (named Sprite)
├── CollisionShape2D (named Body)
├── Area2D (named Hitbox)
│   └── CollisionShape2D (RectangleShape2D)
├── HealthBar (CanvasLayer)
├── SpawnPoint (Marker2D) — where units appear
└── AnimationPlayer (named Animator)
```

### 16.3 Underground World Scene

```
Node2D (named UndergroundWorld)
├── TileMapLayer (named GroundTiles)
│   └── TileSet: Custom tileset with 32×32 tiles
├── StaticBody2D (named Wall)
│   ├── Sprite2D
│   ├── CollisionShape2D
│   └── HealthBar
├── Node2D (named UnitsContainer)
│   └── (Miners and garrisoned fighters spawned here)
├── PlayerMineEntry (Area2D)
├── EnemyMineEntry (Area2D)
└── Pathfinder (Node, script: Pathfinder.gd)
```

---

## 17. Match Flow & Win Conditions

### 17.1 Match Start

1. Both player and AI spawn with **150 coin** and **0 units**.
2. Surface view is active.
3. Underground is fully generated with all tiles intact.
4. Training queue is empty.

### 17.2 Win Condition
- **Player Victory:** Enemy Building HP reaches 0.
- **Player Defeat:** Player Building HP reaches 0.

### 17.3 Match End Sequence

**Victory:**
1. Slow-motion effect on final blow (0.3× speed for 1 second).
2. Enemy building collapse animation + explosion particles.
3. Screen fade to white.
4. "VICTORY" text + stats (units trained, coin mined, time elapsed).
5. "Play Again" / "Main Menu" buttons.

**Defeat:**
1. Slow-motion on final blow.
2. Player building collapse.
3. Screen shake + red vignette.
4. "DEFEAT" text + stats.
5. "Retry" / "Main Menu" buttons.

---

## 18. Performance Considerations

| Concern | Solution |
|---------|----------|
| **100 units × 2 players = 200 units** | Use `VisibleOnScreenNotifier2D` to disable off-screen units. Pool projectiles. |
| **Destructible tilemap** | Use `TileMapLayer` (Godot 4.3) with `set_cells_terrain_connect` for efficient updates. Avoid recalculating A* every frame — only update when a tile is mined. |
| **Pathfinding every frame** | Cache paths. Only recalculate when target moves significantly (> 20px) or path is blocked. |
| **Particle effects** | Use `GPUParticles2D` for explosions/dust. Limit max particles to 500. Free completed particle nodes. |
| **UI updates** | Only update HUD when values change (observer pattern), not every frame. |
| **Audio** | Use `AudioStreamPlayer2D` for positional SFX. Limit concurrent sounds to 32. |

---

## 19. Future Expansion (Post-V1)

| Feature | Description |
|---------|-------------|
| **Multiplayer PvP** | LAN or online matchmaking. Godot's built-in multiplayer enet or WebRTC. |
| **Campaign Mode** | 10 levels with increasing difficulty, unique terrain layouts, and boss enemies. |
| **Additional Fighters** | Cavalry (fast melee), Siege (slow, high damage to buildings), Healer (supports other units). |
| **Fighter Upgrades** | Armor upgrades, damage upgrades, range upgrades (separate from miner upgrades). |
| **Traps** | Underground spike traps, surface ice patches (slow enemies). |
| **Weather Events** | Blizzards (slow all surface units), Earthquakes (damage underground tiles randomly). |
| **Skins/Customization** | Unlockable visual themes (steampunk, cyberpunk, medieval). |
| **Observer Mode** | Spectate AI vs AI matches. |
| **Speed Controls** | 1×, 2×, 3× game speed (for replay/spectating). |

---

## 20. Asset Checklist

### 20.1 Sprites (2D)

| Asset | Dimensions | Frames | Notes |
|-------|-----------|--------|-------|
| Miner L1 | 32×48 | 8 (2 idle, 4 walk, 2 mine) | |
| Miner L2 | 32×48 | 8 | Drill backpack overlay |
| Miner L3 | 32×48 | 8 | Heavy armor, jackhammer |
| Swordsman | 32×48 | 8 | |
| Archer | 32×48 | 8 | Bow draw animation |
| Wizard | 32×48 | 8 | Staff glow pulse |
| Player Building | 120×160 | 4 (idle, damaged, critical, destroyed) | |
| Enemy Building | 120×160 | 4 | Darker variant |
| Mine Entry | 60×80 | 2 (idle, active) | Elevator chain moves |
| Wall Segment | 40×100 | 3 (intact, damaged, breached) | |
| Underground Tile | 32×32 | 4 (per layer) | Layer-specific textures |
| Arrow Projectile | 16×4 | 1 | Rotates to velocity |
| Wizard Blast | 32×32 | 6 | AOE explosion |
| Coin | 16×16 | 4 | Spin animation |
| Health Bar | 32×4 | 1 | Green/red fill |

### 20.2 Audio

| Asset | Format | Duration |
|-------|--------|----------|
| Ambient Surface | OGG loop | 60s |
| Ambient Underground | OGG loop | 60s |
| Music — Tension | OGG loop | 120s |
| Music — Combat | OGG loop | 120s |
| SFX Pack (various) | WAV | < 2s each |

---

## 21. Balance Summary Table

| Metric | Early Game (0–3 min) | Mid Game (3–8 min) | Late Game (8+ min) |
|--------|---------------------|---------------------|---------------------|
| **Income Rate** | ~20 coin/min (1 L1 miner) | ~100 coin/min (5 L2 miners) | ~400 coin/min (8 L3 miners) |
| **Army Size** | 0–5 fighters | 10–30 fighters | 40–80 fighters |
| **Dominant Unit** | Swordsman (cheap) | Archer (range advantage) | Wizard (AOE clears groups) |
| **Key Decision** | Miners vs Fighters ratio | When to upgrade miners | Breach wall or push surface? |
| **Match Duration** | — | — | 10–15 min typical |

---

## 22. Implementation Order (Recommended)

1. **Week 1:** Project setup, surface scene, building placeholders, basic unit spawning
2. **Week 2:** Underground generation, tile destruction, miner AI, pathfinding
3. **Week 3:** Training queue system, all 4 unit types, combat logic
4. **Week 4:** Enemy AI, wall breaching, garrison system
5. **Week 5:** UI/HUD, polish, particles, sound integration
6. **Week 6:** Balance testing, difficulty modes, bug fixes, build & deploy

---

*Document Version 1.0 — Ready for implementation in Godot 4.x*
