extends SceneTree
## 在真实战场脚本中验证两种技能、成长、装备交换和原有金币账户的收支。

## 创建两名英雄并执行实伤害与经济断言；失败时脚本测试立即报错。
func _initialize() -> void:
	var script: GDScript = load("res://scripts/game.gd")
	var berserker: Node2D = script.new()
	root.add_child(berserker)
	await process_frame
	assert(berserker.select_hero("berserker"))
	assert(berserker.hero.hero_id == "berserker" and berserker.player_hp == 145.0)
	var start_gold: int = berserker.gold
	assert(berserker.buy_item("rust_axe"))
	assert(berserker.gold == start_gold - 35 and berserker.hero.inventory.size() == 1)
	var attack_before: float = berserker.player_damage
	assert(berserker.equip_item(0) and berserker.player_damage == attack_before + 5.0)
	assert(berserker.unequip_item("weapon") and berserker.player_damage == attack_before)
	assert(berserker.sell_item(0) and berserker.gold == start_gold - 35 + 17)
	berserker.player_hp -= 60.0
	assert(berserker.buy_item("potion") and berserker.player_hp == berserker.max_player_hp - 5.0)
	assert(berserker.gold == start_gold - 35 + 17 - 22)
	berserker.state = "fighting"
	berserker.enemies.append(make_enemy(berserker.player_pos + Vector2(60, 0)))
	var hp_before: float = berserker.enemies[0].hp
	assert(berserker.cast_skill(0, berserker.player_pos + Vector2(100, 0)))
	assert(berserker.enemies[0].hp < hp_before and berserker.hero.cooldowns[0] > 0.0)
	assert(not berserker.cast_skill(0, berserker.player_pos + Vector2(100, 0)))
	berserker.enemies.clear()
	berserker.enemies.append(make_enemy(berserker.player_pos + Vector2(30, 0)))
	berserker.enemies[0].hp = 1.0
	berserker.cast_skill(1, berserker.player_pos + Vector2(60, 0))
	assert(berserker.kills == 1 and berserker.hero.xp > 0)
	var old_level: int = berserker.hero.level
	berserker.hero.gain_xp(100)
	assert(berserker.hero.level > old_level and berserker.hero.skill_points > 0)
	assert(berserker.hero.upgrade_skill(0) and berserker.hero.skill_levels[0] == 2)
	var mage: Node2D = script.new()
	root.add_child(mage)
	await process_frame
	assert(mage.select_hero("frost_mage"))
	assert(mage.player_hp < berserker.max_player_hp and mage.hero.inventory.is_empty())
	mage.state = "fighting"
	mage.enemies.append(make_enemy(mage.player_pos + Vector2(145, 0)))
	assert(mage.cast_skill(0, mage.player_pos + Vector2(145, 0)))
	assert(mage.enemies[0].hp < 150.0 and mage.enemies[0].slow_time > 0.0)
	assert(mage.hero.cooldowns[0] != berserker.hero.cooldowns[0])
	# 三件史诗装备分别扩大横扫、新星范围及冲锋伤害，断言实际敌人生命变化。
	var sweep: Node2D = script.new()
	root.add_child(sweep)
	await process_frame
	sweep.select_hero("berserker")
	sweep.state = "fighting"
	sweep.enemies.append(make_enemy(sweep.player_pos + Vector2(135, 0)))
	sweep.cast_skill(0, sweep.player_pos + Vector2(200, 0))
	assert(sweep.enemies[0].hp == 150.0)
	sweep.hero.pickup("storm_grasp")
	sweep.equip_item(0)
	sweep.hero.cooldowns[0] = 0.0
	sweep.cast_skill(0, sweep.player_pos + Vector2(200, 0))
	assert(sweep.enemies[0].hp < 150.0)
	var frost: Node2D = script.new()
	root.add_child(frost)
	await process_frame
	frost.select_hero("frost_mage")
	frost.state = "fighting"
	frost.enemies.append(make_enemy(frost.player_pos + Vector2(165, 0)))
	frost.cast_skill(1, frost.player_pos + Vector2(200, 0))
	assert(frost.enemies[0].hp == 150.0)
	frost.hero.pickup("frost_focus")
	frost.equip_item(0)
	frost.hero.cooldowns[1] = 0.0
	frost.cast_skill(1, frost.player_pos + Vector2(200, 0))
	assert(frost.enemies[0].hp < 150.0)
	var rage: Node2D = script.new()
	root.add_child(rage)
	await process_frame
	rage.select_hero("berserker")
	rage.state = "fighting"
	rage.enemies.append(make_enemy(rage.player_pos + Vector2(130, 0)))
	rage.hero.pickup("berserker_mark")
	rage.equip_item(0)
	rage.cast_skill(2, rage.player_pos + Vector2(200, 0))
	assert(rage.enemies[0].hp < 150.0 - rage.hero.skill_damage(2))
	var full: Node2D = script.new()
	root.add_child(full)
	await process_frame
	full.select_hero("berserker")
	for i in 12: assert(full.hero.pickup("iron_helm"))
	var full_gold: int = full.gold
	assert(not full.buy_item("oak_staff") and full.gold == full_gold and full.notice == "背包已满")
	full.hero.choose("frost_mage")
	assert(full.hero.inventory.is_empty() and full.hero.equipment.is_empty() and full.hero.skill_points == 0)
	full.gold = 0
	assert(not full.buy_item("steel_blade") and full.notice == "金币不足" and full.gold == 0)
	# 每个按键都在真实敌人生命上检查伤害和冷却，避免只有界面技能图标而无战斗效果。
	for class_id in ["berserker", "frost_mage"]:
		for skill_index in 4:
			var fighter: Node2D = script.new()
			root.add_child(fighter)
			await process_frame
			fighter.select_hero(class_id)
			fighter.state = "fighting"
			var distance := 145.0 if class_id == "frost_mage" and (skill_index == 0 or skill_index == 3) else 130.0 if class_id == "berserker" and skill_index == 2 else 60.0
			fighter.enemies.append(make_enemy(fighter.player_pos + Vector2(distance, 0)))
			assert(fighter.cast_skill(skill_index, fighter.player_pos + Vector2(200, 0)))
			assert(fighter.enemies[0].hp < 150.0 and fighter.hero.cooldowns[skill_index] > 0.0, "技能必须造成实伤并进入冷却")
			fighter.queue_free()
	print("hero_rpg=PASS skills=2 damage_and_slow xp_level=%d gold=%d" % [berserker.hero.level, berserker.gold])
	quit(0)

## 构造与正式战场相同字段的测试敌人，伤害仍由技能逻辑实际扣除。
## @param pos 敌人的战场坐标。
## @return 可被现有技能和导航逻辑处理的敌人数据。
func make_enemy(pos: Vector2) -> Dictionary:
	return {"pos": pos, "segment": 0, "route": PackedVector2Array(), "route_index": 0, "hp": 150.0, "max_hp": 150.0, "speed": 0.0, "attack_timer": 2.0, "windup": 0.0, "target_kind": "", "aim": Vector2.ZERO, "kind": "grunt", "radius": 17.0, "reward": 8}
