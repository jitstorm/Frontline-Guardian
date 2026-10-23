extends SceneTree

## 使用预置防线跑完八夜，检查波次转换、精英与 Boss 结算能真实到达胜利状态。
func _initialize() -> void:
	var script: GDScript = load("res://scripts/game.gd")
	var game: Node2D = script.new()
	root.add_child(game)
	await process_frame
	game.gold = 2500
	game.selected_tower = 2
	for pos in [Vector2(120, 245), Vector2(205, 245), Vector2(315, 345), Vector2(330, 430), Vector2(450, 430), Vector2(445, 610), Vector2(650, 430), Vector2(650, 345), Vector2(665, 155), Vector2(750, 345), Vector2(790, 155), Vector2(960, 245), Vector2(980, 435), Vector2(1050, 435), Vector2(1110, 250)]:
		game.build_tower(pos)
	print("built_towers=%d" % game.towers.size())
	assert(game.towers.size() >= 10)
	var ticks := 0
	while game.state != "won" and game.state != "lost" and ticks < 16000:
		if game.state == "ready":
			game.start_wave()
		elif game.state == "upgrade":
			game.apply_upgrade(game.upgrade_choices[0])
		game._process(0.05)
		ticks += 1
		if ticks % 2000 == 0:
			print("night=%d ticks=%d enemies=%d core_hp=%.1f" % [game.wave, ticks, game.enemies.size(), game.core_hp])
	print("playthrough_state=%s night=%d ticks=%d core_hp=%.1f kills=%d" % [game.state, game.wave, ticks, game.core_hp, game.kills])
	assert(game.state == "won", "预置防线未能完成八夜流程")
	quit(0)
