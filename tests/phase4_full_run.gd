extends SceneTree
## 从默认经济完成两夜、营地与剩余六夜，验证扩展流程仍能到达胜负终态。

## 以正常经济、移速和冷却执行基地与营地战斗，验证完整八夜流程及失败判定。
func _initialize() -> void:
	seed(20261023)
	var script: GDScript = load("res://scripts/game.gd")
	var game: Node2D = script.new()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	assert(game.select_hero("berserker"))
	var controller = load("res://tests/balance_controller.gd").new()
	var entered := false
	var ticks := 0
	while game.state != "won" and game.state != "lost" and ticks < 18000:
		if game.wave == 2 and game.state == "upgrade" and not entered:
			entered = true
			# 不再传送到首领旁反复射击，营地敌人、英雄受伤和技能冷却始终正常更新。
			assert(controller.visit_camp(game), "正常战斗必须能完成营地并走到掉落处领奖")
			assert(game.dungeon_reward_claimed and game.state == "upgrade")
		if game.state == "ready":
			controller.prepare(game, "mixed")
			game.start_wave()
		elif game.state == "upgrade": controller.choose_upgrade(game, "mixed")
		if game.state == "fighting": controller.act(game)
		game._process(0.05)
		ticks += 1
	assert(entered and game.state == "won" and game.wave == 8, "副本后仍须完成第八夜胜利")
	var defeat: Node2D = script.new()
	root.add_child(defeat)
	await process_frame
	defeat.select_hero("frost_mage")
	defeat.start_wave()
	defeat.core_hp = 0.0
	defeat._process(0.0)
	assert(defeat.state == "lost", "核心生命归零必须进入失败结算")
	print("phase4_full_run=PASS night=%d kills=%d core_hp=%.1f ticks=%d" % [game.wave, game.kills, game.core_hp, ticks])
	quit(0)
