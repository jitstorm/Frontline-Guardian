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
	print("hero_rpg=PASS skills=2 damage_and_slow xp_level=%d gold=%d" % [berserker.hero.level, berserker.gold])
	quit(0)

## 构造与正式战场相同字段的测试敌人，伤害仍由技能逻辑实际扣除。
## @param pos 敌人的战场坐标。
## @return 可被现有技能和导航逻辑处理的敌人数据。
func make_enemy(pos: Vector2) -> Dictionary:
	return {"pos": pos, "segment": 0, "route": PackedVector2Array(), "route_index": 0, "hp": 150.0, "max_hp": 150.0, "speed": 0.0, "attack_timer": 2.0, "windup": 0.0, "target_kind": "", "aim": Vector2.ZERO, "kind": "grunt", "radius": 17.0, "reward": 8}
