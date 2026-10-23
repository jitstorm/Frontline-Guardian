extends SceneTree
## 从默认经济完成两夜、营地与剩余六夜，验证扩展流程仍能到达胜负终态。

## 自动执行固定炮塔策略并以真实弹丸挑战副本 Boss；不模拟人工操作手感。
func _initialize() -> void:
	seed(20261023)
	var script: GDScript = load("res://scripts/game.gd")
	var game: Node2D = script.new()
	root.add_child(game)
	await process_frame
	assert(game.select_hero("berserker"))
	var sites: Array[Vector2] = [Vector2(185, 255), Vector2(330, 430), Vector2(445, 610), Vector2(660, 350), Vector2(790, 155), Vector2(970, 430), Vector2(1090, 245), Vector2(450, 430), Vector2(660, 155), Vector2(980, 245), Vector2(300, 250), Vector2(750, 345)]
	var next_site := 0
	var entered := false
	var ticks := 0
	game.selected_tower = 1
	while game.state != "won" and game.state != "lost" and ticks < 18000:
		while game.gold >= 40 and next_site < sites.size():
			game.build_tower(sites[next_site])
			next_site += 1
		if game.wave == 2 and game.state == "upgrade" and not entered:
			assert(game.enter_dungeon())
			entered = true
			var camp: Node2D = game.dungeon_scene
			var boss_pos: Vector2 = camp.enemies[4].pos
			camp.hero_pos = boss_pos + Vector2(-60, 0)
			for shot in 30:
				if camp.reward_spawned: break
				camp.fire_at(boss_pos)
				camp.update_bullets(0.05)
				camp.update_bullets(0.05)
			assert(camp.reward_spawned)
			camp.hero_pos = camp.reward_pos
			camp._process(0.0)
			assert(game.dungeon_reward_claimed and game.state == "upgrade")
		if game.state == "ready": game.start_wave()
		elif game.state == "upgrade": game.apply_upgrade(game.upgrade_choices[0])
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
