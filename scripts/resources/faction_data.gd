class_name FactionData
extends Resource

## Asymmetric faction definition (Revamp Phase 2). One .tres per faction under
## scripts/resources/factions/. All multipliers are 1.0 = normal; a null
## faction (no pick, e.g. tests) means fully neutral stats and costs.

@export var faction_id: String = ""
@export var faction_name: String = "Faction"
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var menu_color: Color = Color("#e2e8f0")
## Three short bullet lines shown on the faction-select card.
@export var highlights: Array[String] = []

# Unit stat modifiers (multipliers, 1.0 = normal).
@export var swordsman_hp_mult: float = 1.0
@export var swordsman_dmg_mult: float = 1.0
@export var archer_hp_mult: float = 1.0
@export var archer_dmg_mult: float = 1.0
@export var wizard_hp_mult: float = 1.0
@export var wizard_dmg_mult: float = 1.0
@export var dragon_hp_mult: float = 1.0
@export var dragon_dmg_mult: float = 1.0

# Miner modifiers.
@export var miner_hp_bonus: int = 0
@export var miner_mining_mult: float = 1.0
@export var miner_carry_bonus: int = 0
## Scales the coin each mining swing extracts (Industrial efficiency).
@export var miner_ore_yield_mult: float = 1.0

# Economy.
@export var unit_cost_mult: float = 1.0
## Per-unit-id flat cost overrides, applied before unit_cost_mult.
@export var cost_overrides: Dictionary = {}
@export var starting_gold_bonus: int = 0
@export var starting_miner_bonus: int = 0

# Ability flags (see unit.gd — each gates one faction ability).
@export var swordsman_rune_blade: bool = false
@export var swordsman_berserk: bool = false
@export var swordsman_swarm: bool = false
@export var wizard_fortify: bool = false
## Seconds shaved off the wizard's Blink teleport cooldown (base 15s).
@export var wizard_blink_reduction: float = 0.0
@export var archer_arcane_shot: bool = false
@export var archer_heavy_bolt: bool = false
@export var archer_volley: bool = false
@export var miner_fight_back: bool = false
@export var miner_reveal: bool = false
@export var dragon_mana_burn: bool = false
@export var dragon_crush: bool = false
@export var dragon_supply_drop: bool = false


## Effective purchase cost for a unit type: override first, then multiplier.
func get_unit_cost(unit_id: String, base_cost: int) -> int:
	var cost: float = cost_overrides.get(unit_id, base_cost)
	return maxi(1, roundi(cost * unit_cost_mult))
