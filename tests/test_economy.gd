extends GutTest

# EconomyManager: spend/refund/upgrade math and cap guards.

const PLAYER: int = 0  # GameManager.Team.PLAYER
const ENEMY: int = 1   # GameManager.Team.ENEMY


func before_each() -> void:
	EconomyManager.reset()


func test_spend_coin_deducts_and_emits() -> void:
	watch_signals(EconomyManager)
	assert_true(EconomyManager.spend_coin(PLAYER, 200))
	assert_eq(EconomyManager.get_coin(PLAYER), 300)
	assert_signal_emitted(EconomyManager, "coin_changed")


func test_spend_coin_fails_without_funds() -> void:
	assert_false(EconomyManager.spend_coin(PLAYER, 501))
	assert_eq(EconomyManager.get_coin(PLAYER), 500, "coin unchanged on failed spend")


func test_coin_never_goes_negative() -> void:
	EconomyManager.spend_coin(PLAYER, 500)
	assert_eq(EconomyManager.get_coin(PLAYER), 0)
	assert_false(EconomyManager.spend_coin(PLAYER, 1))
	assert_eq(EconomyManager.get_coin(PLAYER), 0)


func test_add_coin_and_can_afford() -> void:
	EconomyManager.add_coin(PLAYER, 100)
	assert_eq(EconomyManager.get_coin(PLAYER), 600)
	assert_true(EconomyManager.can_afford(PLAYER, 600))
	assert_false(EconomyManager.can_afford(PLAYER, 601))


func test_teams_have_separate_wallets() -> void:
	EconomyManager.spend_coin(ENEMY, 500)
	assert_eq(EconomyManager.get_coin(PLAYER), 500, "enemy spend must not touch player coin")
	assert_eq(EconomyManager.get_coin(ENEMY), 0)


func test_population_cap_guard() -> void:
	EconomyManager.add_population(PLAYER, 99)
	assert_true(EconomyManager.can_add_population(PLAYER, 1))
	assert_false(EconomyManager.can_add_population(PLAYER, 2))
	EconomyManager.remove_population(PLAYER, 50)
	assert_true(EconomyManager.can_add_population(PLAYER, 51))


func test_remove_population_clamps_at_zero() -> void:
	EconomyManager.add_population(PLAYER, 5)
	EconomyManager.remove_population(PLAYER, 10)
	assert_eq(EconomyManager.get_population(PLAYER), 0)


func test_upgrade_miner_spends_and_levels() -> void:
	watch_signals(EconomyManager)
	assert_true(EconomyManager.upgrade_miner(PLAYER))
	assert_eq(EconomyManager.get_miner_level(PLAYER), 2)
	assert_eq(EconomyManager.get_coin(PLAYER), 0, "L2 costs 500")
	assert_signal_emitted(EconomyManager, "miner_level_changed")


func test_upgrade_miner_fails_without_funds() -> void:
	EconomyManager.spend_coin(PLAYER, 100)
	assert_false(EconomyManager.upgrade_miner(PLAYER))
	assert_eq(EconomyManager.get_miner_level(PLAYER), 1)
	assert_eq(EconomyManager.get_coin(PLAYER), 400, "failed upgrade must not spend")


func test_upgrade_miner_max_level() -> void:
	EconomyManager.add_coin(PLAYER, 2000)
	assert_true(EconomyManager.upgrade_miner(PLAYER))
	assert_true(EconomyManager.upgrade_miner(PLAYER))
	assert_eq(EconomyManager.get_miner_level(PLAYER), 3)
	assert_false(EconomyManager.upgrade_miner(PLAYER), "no level 4")
	assert_eq(EconomyManager.get_miner_upgrade_cost(PLAYER), -1)


func test_stats_tracking() -> void:
	EconomyManager.train_unit(PLAYER)
	EconomyManager.train_unit(PLAYER)
	EconomyManager.mine_coin(PLAYER, 75)
	assert_eq(EconomyManager.get_units_trained(PLAYER), 2)
	assert_eq(EconomyManager.get_coin_mined(PLAYER), 75)
