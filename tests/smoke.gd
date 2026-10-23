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
	assert(game.MAX_WAVES == 8)
	assert(game.enemy_kind_for(1, 0) == "grunt")
	assert(game.enemy_kind_for(2, 1) == "runner")
	assert(game.enemy_kind_for(3, 2) == "armored")
	assert(game.enemy_kind_for(5, 3) == "ranged")
	assert(game.enemy_kind_for(4, game.wave_enemy_count(4) - 1) == "elite")
	assert(game.enemy_kind_for(8, game.wave_enemy_count(8) - 1) == "boss")
	assert(not game.can_build_at(Vector2(20, 340)))
	assert(game.can_build_at(Vector2(300, 120)))
	var original_route: PackedVector2Array = game.route_from(Vector2(20, 340))
	game.selected_tower = 1
	game.build_tower(Vector2(120, 340))
	assert(game.towers.size() == 1)
	assert(game.route_from(Vector2(20, 340)) != original_route)
	game.sell_selected_tower()
	assert(not game.navigation.is_point_solid(game.nav_cell(Vector2(120, 340))))
	assert(not game.route_from(Vector2(20, 340)).is_empty())
	game.gold = 100
	var blocked: Node2D = script.new()
	root.add_child(blocked)
	await process_frame
	for y in [11, 12, 14]:
		blocked.navigation.set_point_solid(Vector2i(10, y))
	assert(not blocked.can_build_at(Vector2(420, 540)), "禁止封死道路")
	blocked.queue_free()
	var destructible: Node2D = script.new()
	root.add_child(destructible)
	await process_frame
	destructible.selected_tower = 1
	destructible.build_tower(Vector2(300, 120))
	destructible.towers[0].hp = 1.0
	var revision_before: int = destructible.navigation_revision
	destructible.hostile_bullets.append({"pos": Vector2(300, 120), "velocity": Vector2.ZERO, "damage": 8.0, "life": 1.0, "radius": 7.0})
	destructible.update_hostile_bullets(0.0)
	assert(destructible.towers.is_empty() and destructible.navigation_revision > revision_before)
	destructible.queue_free()
	assert(game.upgrade_pool.size() >= 20)
	game.start_wave()
	assert(game.state == "fighting" and game.wave == 1)
	game.update_spawning(0.1)
	assert(game.enemies.size() == 1 and game.spawn_left == 5)
	var ranged_enemy: Dictionary = game.enemies[0]
	ranged_enemy.kind = "ranged"
	ranged_enemy.pos = game.player_pos + Vector2(-120, 0)
	game.enemies[0] = ranged_enemy
	game.update_enemies(0.1)
	assert(game.enemies[0].windup > 0.0 and game.hostile_bullets.is_empty())
	game.update_enemies(0.5)
	assert(game.hostile_bullets.size() == 1)
	game.hostile_bullets[0].pos = game.player_pos
	var hp_before: float = game.player_hp
	game.dodge_timer = 0.2
	game.update_hostile_bullets(0.0)
	assert(game.player_hp == hp_before and game.hostile_bullets.is_empty())
	game.hostile_bullets.append({"pos": game.player_pos, "velocity": Vector2.ZERO, "damage": 6.0, "life": 1.0, "radius": 7.0})
	game.dodge_timer = 0.0
	game.update_hostile_bullets(0.0)
	assert(game.player_hp < hp_before)
	var boss_enemy: Dictionary = game.enemies[0]
	boss_enemy.kind = "boss"
	boss_enemy.attack_timer = 0.0
	boss_enemy.target_kind = ""
	boss_enemy.windup = 0.0
	game.enemies[0] = boss_enemy
	game.update_enemies(0.1)
	game.update_enemies(0.7)
	assert(game.hostile_bullets.size() == 3, "Boss 应发射三枚可闪避弹丸")
	game.hostile_bullets.clear()
	var enemy_pos: Vector2 = game.enemies[0].pos
	game.bullets.append({"pos": enemy_pos, "velocity": Vector2.RIGHT, "damage": 10.0, "life": 1.0, "radius": 5.0, "color": Color.WHITE, "knockback": 12.0})
	game.update_bullets(0.0)
	assert(game.enemies[0].hp < game.enemies[0].max_hp)
	assert(game.enemies[0].pos != enemy_pos and game.hit_texts.size() >= 1)
	game.enemies[0].pos = Vector2(40, 340)
	game.selected_tower = 1
	game.build_tower(Vector2(300, 120))
	assert(game.towers.size() == 1 and game.gold == 60)
	assert(game.tower_at(Vector2(300, 120)) == 0)
	game.cycle_tower_priority()
	assert(game.towers[0].priority == "front")
	game.upgrade_selected_tower()
	assert(game.towers[0].level == 2 and game.gold == 30)
	game.towers[0].hp = 50.0
	game.repair_selected_tower()
	assert(game.towers[0].hp == 85.0 and game.gold == 15)
	game.sell_selected_tower()
	assert(game.towers.is_empty() and game.gold == 50)
	game.state = "upgrade"
	game.roll_upgrades()
	assert(game.upgrade_choices.size() == 2 and game.upgrade_choices[0] != game.upgrade_choices[1])
	game.apply_upgrade(game.upgrade_choices[0])
	assert(game.state == "ready")
	# 每种强化都必须至少改变一个当前数值或后续战斗所用的属性。
	for choice in game.upgrade_pool:
		var candidate: Node2D = script.new()
		candidate.state = "upgrade"
		candidate.upgrade_choices.append(choice)
		candidate.upgrade_choices.append("占位")
		var before := [candidate.max_player_hp, candidate.player_damage, candidate.gun_rate_multiplier, candidate.bullet_speed_multiplier, candidate.bullet_knockback, candidate.multishot, candidate.tower_multiplier, candidate.tower_range_bonus, candidate.tower_rate_multiplier, candidate.max_core_hp, candidate.move_multiplier, candidate.gold_bonus, candidate.gold, candidate.player_armor, candidate.core_armor, candidate.tower_hp_multiplier, candidate.armor_penetration, candidate.boss_bonus]
		candidate.apply_upgrade(choice)
		var after := [candidate.max_player_hp, candidate.player_damage, candidate.gun_rate_multiplier, candidate.bullet_speed_multiplier, candidate.bullet_knockback, candidate.multishot, candidate.tower_multiplier, candidate.tower_range_bonus, candidate.tower_rate_multiplier, candidate.max_core_hp, candidate.move_multiplier, candidate.gold_bonus, candidate.gold, candidate.player_armor, candidate.core_armor, candidate.tower_hp_multiplier, candidate.armor_penetration, candidate.boss_bonus]
		assert(before != after, "强化未生效: " + choice)
		candidate.free()
	quit(0)
