class_name AIMining
extends RefCounted

const _Constants = preload("res://scripts/autoload/constants.gd")

var ai: AIController

func _init(a: AIController) -> void:
	ai = a


func _run_mining() -> void:
	for unit in ai.get_tree().get_nodes_in_group(ai._combat.team_name()):
		if not unit.data.is_miner:
			continue
		# Revamp Phase 8: miners under shelter orders (storm/lava) hold their
		# position until the awareness module releases them.
		if unit.shelter_in_place:
			continue
		if _is_busy(unit):
			continue
		if unit.carried_coin >= unit.data.carry_capacity:
			unit.deposit_coin()
		else:
			var ore: Vector2i = _find_best_ore(unit)
			if ore != Vector2i(-9999, -9999):
				unit.mine_cell(ore)
			elif unit.carried_coin > 0:
				unit.deposit_coin()


func _find_best_ore(unit: Unit) -> Vector2i:
	var center: Vector2i = ai._grid.world_to_grid(unit.global_position)
	var best: Vector2i = Vector2i(-9999, -9999)
	var best_score: float = -999999.0
	var team_dir: int = -1 if ai.team == GameManager.Team.PLAYER else 1
	for x in range(-12, 13):
		for y in range(0, 15):
			var pos: Vector2i = center + Vector2i(x, y)
			var cell: GridWorld.Cell = ai._grid.get_cell(pos)
			if cell == null or (cell.type != GridWorld.CellType.ORE and cell.type != GridWorld.CellType.FRESH_ORE):
				continue
			# Depleted veins (Revamp Phase 4) trickle at a tenth rate — the AI
			# leaves them to the miner's blind auto-seek.
			if GridMining.is_depleted(cell):
				continue
			# Miners don't know where buried ore is: the AI may only route to
			# ore that already proved itself (damaged = yielded gold) or that
			# an Ore Sonar scan revealed. Undiscovered ore is dug blind via
			# the miner's own auto-seek.
			if cell.hp >= cell.max_hp and not cell.sonar_revealed.get(ai.team, false):
				continue
			if unit.data.miner_level < cell.miner_level_required:
				continue
			# If wall is still up, stick to own side.
			if ai._grid.get_wall_hp() > 0 and pos.x * team_dir < -2:
				continue
			# Respect miner reservations and this miner's no-path blacklist so
			# the AI doesn't re-order tiles the miner already failed to reach.
			if not ai._grid.is_cell_claimable(pos, unit.get_instance_id()):
				continue
			if unit.is_cell_blacklisted(pos):
				continue
			var dist: float = center.distance_to(pos)
			var score: float = cell.coin_value - dist * 0.5
			if score > best_score:
				best_score = score
				best = pos
	return best


## True while a unit is in a transition state that the AI tick should not override.
func _is_busy(unit: Unit) -> bool:
	match unit._state:
		Unit.State.IDLE, Unit.State.MOVE:
			return false
		_:
			return true
