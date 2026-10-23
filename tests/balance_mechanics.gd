extends SceneTree
## 验证武器取舍、护甲递减、赏金上限和重炮溅射，防止数值调整只改变界面。

## 在实际战场中执行装备、承伤与击杀结算；断言失败时由外部限时运行器报告失败。
func _initialize() -> void:
	var game: Node2D = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.select_hero("frost_mage")
	game.hero.pickup("rust_axe")
	game.equip_item(0)
	var axe_attack: float = game.player_damage
	var axe_skill: float = game.hero.skill_damage(0)
	game.hero.pickup("oak_staff")
	game.equip_item(0)
	assert(game.player_damage < axe_attack and game.hero.skill_damage(0) > axe_skill, "法杖必须用普攻换取技能收益")
	game.unequip_item("weapon")
	assert(game.hero.skill_damage(0) < axe_skill, "卸下武器必须撤销增幅")
	# 护甲不再把九点近战永久压到一点；护盾仍提供可观察的临时收益。
	assert(game.incoming_damage(9, 8) > 6 and game.incoming_damage(9, 8) < 9)
	assert(game.incoming_damage(9, 8, true) < game.incoming_damage(9, 8))
	assert(game.incoming_damage(9, 16) > 1)
	game.gold_bonus = 1
	var gold_before: int = game.gold
	for i in 15: game.reward_enemy({"reward": 4})
	assert(game.gold - gold_before == 15 * 4 + 10, "每夜赏金必须限制为前十次击杀")
	game.start_wave()
	assert(game.bounty_kills == 0, "下一夜必须恢复十次赏金机会")
	# 使用真实建塔和开火路径，检验重炮直接命中与溅射不会重复发奖。
	game.enemies.clear()
	game.gold = 100
	game.selected_tower = 2
	game.build_tower(Vector2(300, 120))
	game.enemies.append(enemy(Vector2(300, 200), "armored"))
	game.enemies.append(enemy(Vector2(340, 200)))
	game.enemies.append(enemy(Vector2(420, 200)))
	game.update_towers(0.0)
	assert(game.bullets.size() == 1)
	game.bullets[0].pos = Vector2(300, 200)
	game.update_bullets(0.0)
	assert(is_equal_approx(game.enemies[0].hp, 100.0 - 34.0 * 0.85))
	assert(is_equal_approx(game.enemies[1].hp, 100.0 - 34.0 * 0.45))
	assert(game.enemies[2].hp == 100.0, "溅射不能命中半径外敌人")
	var kills_before: int = game.kills
	for target in game.enemies: target.hp = 1.0
	game.bullets.append({"pos": game.enemies[0].pos, "velocity": Vector2.RIGHT, "damage": 34.0, "life": 1.0, "radius": 10.0, "color": Color.WHITE, "knockback": 0.0, "splash": 65.0, "source": "tower", "armor_factor": 0.85})
	game.update_bullets(0.0)
	assert(game.kills - kills_before == 2 and game.enemies.size() == 1)
	assert(game.tower_damage_dealt > 0 and game.hero_damage_dealt == 0)
	# 直接走基地近战结算和副本近战结算，验证两张地图都真正使用递减护甲。
	game.player_armor = 8.0
	var hp_before: float = game.player_hp
	game.resolve_enemy_attack({"target_kind": "player", "kind": "grunt", "pos": game.player_pos, "radius": 17.0})
	assert(hp_before - game.player_hp > 6.0 and hp_before - game.player_hp < 9.0)
	game.wave = 2
	game.state = "upgrade"
	assert(game.enter_dungeon())
	var camp: Node2D = game.dungeon_scene
	camp.set_process(false)
	camp.enemies.clear()
	var attacker: Dictionary = camp.make_goblin(camp.hero_pos, "grunt", 100.0, 9.0)
	attacker.windup = 0.01
	camp.enemies.append(attacker)
	hp_before = game.player_hp
	camp.update_enemies(0.05)
	assert(hp_before - game.player_hp > 6.0 and hp_before - game.player_hp < 9.0)
	# 冰枪击杀前一个索引后，未被技能命中的邻居不能因数组移动而错误获得减速。
	camp.enemies.clear()
	camp.enemies.append(camp.make_goblin(camp.hero_pos + Vector2(140, 0), "grunt", 1.0, 9.0))
	camp.enemies.append(camp.make_goblin(camp.hero_pos + Vector2(500, 0), "grunt", 100.0, 9.0))
	assert(camp.cast_skill(0, camp.hero_pos + Vector2(200, 0)))
	assert(camp.enemies.size() == 1 and camp.enemies[0].slow_time == 0.0)
	game.free()
	check_waves()
	print("balance_mechanics=PASS 武器取舍 护甲递减 赏金上限 重炮穿甲与溅射")
	quit(0)

## 通过正式生成器检查八夜数量和分组节奏，并输出实际生命与金币预算。
## 单帧推进五十毫秒；只测试刷怪配置，不把无伤害的此段运行当作通关证据。
func check_waves() -> void:
	var game: Node2D = load("res://scripts/game.gd").new()
	root.add_child(game)
	game.set_process(false)
	game.select_hero("berserker")
	var total := 0
	for night in range(1, 9):
		game.state = "ready"
		game.enemies.clear()
		game.start_wave()
		var ticks := 0
		var previous_spawn := 0
		var has_pause := false
		var has_dense := false
		while game.spawn_left > 0 and ticks < 1000:
			var before: int = game.enemies.size()
			game.update_spawning(0.05)
			if game.enemies.size() > before:
				var interval: float = (ticks - previous_spawn) * 0.05
				if before > 0:
					has_pause = has_pause or interval >= 1.4
					has_dense = has_dense or interval <= 0.5
				previous_spawn = ticks
			ticks += 1
		assert(game.spawn_left == 0 and has_dense and has_pause, "每夜必须同时具有小队内密集出怪和小队间喘息")
		var hp := 0.0
		var reward := 0
		for target in game.enemies:
			hp += target.hp
			reward += target.reward
		total += game.enemies.size()
		print("wave_budget night=%d count=%d hp=%.1f gold=%d spawn_seconds=%.2f" % [night, game.enemies.size(), hp, reward, ticks * 0.05])
	assert(total == 290)
	game.free()

## 创建用于真实弹丸碰撞的静止目标，避免移动干扰边界检查。
## @param pos 目标世界坐标，单位为像素。
## @param kind 用于选择重甲减伤规则的敌人类型。
## @return 具有生命、碰撞半径和奖励字段的目标字典。
func enemy(pos: Vector2, kind: String = "grunt") -> Dictionary:
	return {"pos": pos, "hp": 100.0, "max_hp": 100.0, "kind": kind, "radius": 17.0, "reward": 4}
