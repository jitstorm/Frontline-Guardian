extends SceneTree

## 用默认金币与正常击杀奖励执行八夜预设速射塔策略，验证胜利流程可达。
func _initialize() -> void:
	seed(20261023)
	var script: GDScript = load("res://scripts/game.gd")
	var game: Node2D = script.new()
	root.add_child(game)
	await process_frame
	var sites: Array[Vector2] = [Vector2(185, 255), Vector2(330, 430), Vector2(445, 610), Vector2(660, 350), Vector2(790, 155), Vector2(970, 430), Vector2(1090, 245), Vector2(450, 430), Vector2(660, 155), Vector2(980, 245), Vector2(300, 250), Vector2(750, 345)]
	var next_site := 0
	var ticks := 0
	game.selected_tower = 1
	while game.state != "won" and game.state != "lost" and ticks < 18000:
		while game.gold >= 40 and next_site < sites.size():
			game.build_tower(sites[next_site])
			next_site += 1
		if game.state == "ready": game.start_wave()
		elif game.state == "upgrade": game.apply_upgrade(game.upgrade_choices[0])
		game._process(0.05)
		ticks += 1
	print("normal_playthrough=%s night=%d kills=%d gold=%d core_hp=%.1f ticks=%d" % [game.state, game.wave, game.kills, game.gold, game.core_hp, ticks])
	assert(game.state == "won", "默认经济条件下的预设速射塔策略未完成八夜")
	quit(0)
