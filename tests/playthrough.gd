extends SceneTree

## 用默认金币和正常击杀收益执行英雄与炮塔协同策略，验证八夜胜利仍然可达。
func _initialize() -> void:
	seed(20261023)
	var script: GDScript = load("res://scripts/game.gd")
	var game: Node2D = script.new()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	assert(game.select_hero("berserker"))
	var controller = load("res://tests/balance_controller.gd").new()
	var ticks := 0
	while game.state != "won" and game.state != "lost" and ticks < 18000:
		# 保留默认经济与胜利断言，英雄按实际移速和冷却作战，不再假设单塔型挂机必须通关。
		if game.state == "ready":
			controller.prepare(game, "mixed")
			game.start_wave()
		elif game.state == "upgrade": controller.choose_upgrade(game, "mixed")
		if game.state == "fighting": controller.act(game)
		game._process(0.05)
		ticks += 1
	print("normal_playthrough=%s night=%d kills=%d gold=%d core_hp=%.1f ticks=%d" % [game.state, game.wave, game.kills, game.gold, game.core_hp, ticks])
	assert(game.state == "won", "默认经济条件下的英雄协同策略未完成八夜")
	quit(0)
