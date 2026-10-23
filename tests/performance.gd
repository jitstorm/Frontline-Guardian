extends SceneTree
## 压测密集战斗与召唤、职责计时，不把模拟耗时当作图形帧率。

## 在固定数量敌人和炮塔下测量战斗逻辑耗时；结果只代表 headless CPU 模拟，不代表图形帧率。
func _initialize() -> void:
	var script: GDScript = load("res://scripts/game.gd")
	var game: Node2D = script.new()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	assert(game.select_hero("berserker"))
	game.select_build("summon")
	game.wave = 8
	game.state = "fighting"
	game.hero.skill_levels[0] = 3
	game.cast_skill(0, game.player_pos)
	# 按末夜六十四只敌人和混合炮塔压测，覆盖重炮范围命中的新增开销。
	for i in 64:
		var pos := Vector2(80 + i * 2, 340)
		game.enemies.append({"pos": pos, "segment": 0, "route": game.route_from(pos), "route_index": 0, "hp": 5000.0, "max_hp": 5000.0, "speed": 85.0, "attack_timer": 2.0, "windup": 0.0, "target_kind": "", "aim": Vector2.ZERO, "kind": "grunt", "radius": 17.0, "reward": 8})
	for i in game.enemies.size(): game.enemies[i].role = "shock" if i % 5 == 0 else "shield" if i % 5 == 1 else ""
	for i in 10:
		game.towers.append({"pos": Vector2(160 + i * 90, 240), "kind": 1 if i % 2 == 0 else 2, "range": 220.0, "damage": 11.0 if i % 2 == 0 else 34.0, "cooldown": 0.0, "level": 1, "hp": 75.0, "max_hp": 75.0, "priority": "nearest", "spent": 40})
	var start := Time.get_ticks_usec()
	for i in 1000:
		game.hero.tick(0.016)
		game.evolution_system.tick(game, 0.016)
		game.combat_builds.tick(game, 0.016)
		game.cast_skill(0, game.player_pos)
		game.update_enemies(0.016)
		game.update_hostile_bullets(0.016)
		game.update_towers(0.016)
		game.update_bullets(0.016)
		game.update_feedback(0.016)
	var elapsed := Time.get_ticks_usec() - start
	print("headless_combat_1000_ticks_ms=%.2f avg_tick_ms=%.4f" % [elapsed / 1000.0, elapsed / 1000000.0])
	quit(0)
