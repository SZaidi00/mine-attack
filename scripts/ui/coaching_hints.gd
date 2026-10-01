class_name CoachingHints
extends RefCounted

## Post-match coaching hints for the game-over panel. Pure function over the
## MatchStats summary dictionary: no scene access, safe on missing keys. Rules
## are evaluated most-impactful-first and the list is capped at 3; a generic
## fallback keeps at least one hint when nothing specific fires.

const _RATIO_THRESHOLD: float = 1.5
const _BASE_HP_THRESHOLD: float = 0.7
const _LONG_MATCH_SEC: int = 360
const _FAST_LOSS_SEC: int = 300


static func generate(summary: Dictionary) -> Array[String]:
	var hints: Array[String] = []
	var duration: int = int(summary.get("duration_sec", 0))
	var winner: String = summary.get("winner", "")
	var teams: Dictionary = summary.get("teams", {})
	var player: Dictionary = teams.get("player", {})
	var enemy: Dictionary = teams.get("enemy", {})

	# 1. Fast loss: opener problem, not a macro problem.
	if winner == "enemy" and duration > 0 and duration < _FAST_LOSS_SEC:
		hints.append("You fell in under 5 minutes — early towers and a standing army stop rushes.")

	# 2. Base damage: the lowest base-HP fraction reached, and when.
	var base_hint: String = _base_damage_hint(summary, winner)
	if base_hint != "":
		hints.append(base_hint)

	# 3. Economy: whoever out-mined by 1.5x or more owned the long game.
	var p_mined: int = int(player.get("coin_mined", 0))
	var e_mined: int = int(enemy.get("coin_mined", 0))
	if p_mined > 0 and e_mined > 0:
		var hi: float = float(maxi(p_mined, e_mined))
		var lo: float = float(mini(p_mined, e_mined))
		if hi / lo >= _RATIO_THRESHOLD:
			var ratio: String = "%.1f:1" % (hi / lo)
			if e_mined > p_mined:
				hints.append("The enemy out-mined you %s — more miners earlier wins the long game." % ratio)
			else:
				hints.append("You out-mined the enemy %s — your economy carried this match." % ratio)

	# 4. Army trade: notably negative trades mean micro/stance losses.
	var p_lost: int = int(player.get("units_lost", 0))
	var e_lost: int = int(enemy.get("units_lost", 0))
	if e_lost == 0:
		if p_lost >= 3:
			hints.append("You lost %d units for none in return — focus fire and wounded retreat (Defend stance) improve trades." % p_lost)
	elif float(p_lost) / float(e_lost) >= _RATIO_THRESHOLD:
		hints.append("You traded %d units for %d — focus fire and wounded retreat (Defend stance) improve trades." % [p_lost, e_lost])

	# 5. Tech: a long match decided without capstones.
	if int(summary.get("player_max_tier", 0)) <= 1 and duration > _LONG_MATCH_SEC:
		hints.append("You never researched past tier 1 — tier-3 capstones are match-deciding.")

	if hints.is_empty():
		hints.append("Every match leaves a log — compare the charts above to spot where the momentum shifted.")
	while hints.size() > 3:
		hints.pop_back()
	return hints


## Lowest base-HP fraction (and its timestamp) per side from the timeline; the
## hint phrases around the side most relevant to the player given the result.
static func _base_damage_hint(summary: Dictionary, winner: String) -> String:
	var player_min: float = 1.0
	var player_min_t: int = 0
	var enemy_min: float = 1.0
	var enemy_min_t: int = 0
	for sample: Dictionary in summary.get("timeline", []):
		var t: int = int(sample.get("t", 0))
		var p: float = float(sample.get("player_base_hp", 1.0))
		if p < player_min:
			player_min = p
			player_min_t = t
		var e: float = float(sample.get("enemy_base_hp", 1.0))
		if e < enemy_min:
			enemy_min = e
			enemy_min_t = t
	if winner == "player":
		if enemy_min < _BASE_HP_THRESHOLD:
			return "You had the enemy base down to %d%% HP at %s — sustained pressure closes out games." % [roundi(enemy_min * 100.0), _format_time(enemy_min_t)]
		if player_min < _BASE_HP_THRESHOLD:
			return "Your base dropped to %d%% HP at %s — walls and towers blunt sieges." % [roundi(player_min * 100.0), _format_time(player_min_t)]
	else:
		if player_min < _BASE_HP_THRESHOLD:
			return "Your base dropped to %d%% HP at %s — walls and towers blunt sieges." % [roundi(player_min * 100.0), _format_time(player_min_t)]
		if enemy_min < _BASE_HP_THRESHOLD:
			return "You had the enemy base down to %d%% HP at %s — press the advantage before they rebuild." % [roundi(enemy_min * 100.0), _format_time(enemy_min_t)]
	return ""


static func _format_time(seconds: int) -> String:
	return "%d:%02d" % [seconds / 60, seconds % 60]
