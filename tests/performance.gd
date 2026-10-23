extends SceneTree

## 在固定数量敌人和炮塔下测量战斗逻辑耗时；结果只代表 headless CPU 模拟，不代表图形帧率。
func _initialize() -> void:
	var script: GDScript = load("res://scripts/game.gd")
	var game: Node2D = script.new()
	root.add_child(game)
	await process_frame
	game.wave = 8
	for i in 20:
		var pos := Vector2(80 + i * 2, 340)
		game.enemies.append({"pos": pos, "segment": 0, "route": game.route_from(pos), "route_index": 0, "hp": 5000.0, "max_hp": 5000.0, "speed": 85.0, "attack_timer": 2.0, "windup": 0.0, "target_kind": "", "aim": Vector2.ZERO, "kind": "grunt", "radius": 17.0, "reward": 8})
	for i in 10:
		game.towers.append({"pos": Vector2(160 + i * 90, 240), "kind": 1, "range": 220.0, "damage": 11.0, "cooldown": 0.0, "level": 1, "hp": 75.0, "max_hp": 75.0, "priority": "nearest", "spent": 40})
	var start := Time.get_ticks_usec()
	for i in 1000:
		game.update_enemies(0.016)
		game.update_hostile_bullets(0.016)
		game.update_towers(0.016)
		game.update_bullets(0.016)
	var elapsed := Time.get_ticks_usec() - start
	print("headless_combat_1000_ticks_ms=%.2f avg_tick_ms=%.4f" % [elapsed / 1000.0, elapsed / 1000000.0])
	quit(0)
