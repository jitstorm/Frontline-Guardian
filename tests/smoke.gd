extends SceneTree

## 验证三波配置、道路判定和强化池的基本约束，失败时设置非零退出码。
func _initialize() -> void:
	var script: GDScript = load("res://scripts/game.gd")
	var game: Node2D = script.new()
	root.add_child(game)
	await process_frame
	assert(game.wave_enemy_count(1) == 6)
	assert(game.wave_enemy_count(2) > game.wave_enemy_count(1))
	assert(game.wave_enemy_count(3) > game.wave_enemy_count(2))
	assert(not game.can_build_at(Vector2(80, 350)))
	assert(game.can_build_at(Vector2(300, 120)))
	assert(game.upgrade_pool.size() >= 4)
	game.start_wave()
	assert(game.state == "fighting" and game.wave == 1)
	game.update_spawning(0.1)
	assert(game.enemies.size() == 1 and game.spawn_left == 5)
	game.selected_tower = 1
	game.build_tower(Vector2(300, 120))
	assert(game.towers.size() == 1 and game.gold == 60)
	game.state = "upgrade"
	game.roll_upgrades()
	assert(game.upgrade_choices.size() == 2 and game.upgrade_choices[0] != game.upgrade_choices[1])
	game.apply_upgrade(game.upgrade_choices[0])
	assert(game.state == "ready")
	quit(0)
