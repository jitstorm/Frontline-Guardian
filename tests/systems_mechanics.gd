extends SceneTree
## 独立验证多词条品质区间、锁定重铸、三阶形态、上夜输出驱动与召唤物真实承伤。
const Equipment = preload("res://scripts/equipment_system.gd")
const Rules = preload("res://scripts/config/equipment_rules.gd")

## 使用固定随机源与战场夹具检查状态边界，通关与等级证据另由矩阵提供。
func _initialize() -> void:
	await process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var qualities: Dictionary = {}
	var affixes: Dictionary = {}
	var legend: Dictionary = {}
	for sample in 1200:
		var record := Equipment.generate(rng)
		assert(Equipment.valid(record))
		assert(record.affixes.size() == Rules.QUALITIES[record.quality].count)
		qualities[record.quality] = true
		for id in record.affixes: affixes[id] = true
		if record.quality == "legend": legend = record
	assert(qualities.size() == 4 and affixes.size() == 12)
	var game := battle("skill")
	game.state = "ready"
	game.gold = 500
	game.hero.pickup("steel_blade", "", legend)
	var original: Dictionary = game.hero.inventory_rolls[0].duplicate(true)
	var locks: Array[int] = [0, 2]
	var price := Equipment.cost(original, locks)
	assert(game.reforge_item(0, locks) and game.gold == 500 - price)
	var reforged: Dictionary = game.hero.inventory_rolls[0]
	assert(reforged.quality == original.quality and reforged.power == original.power)
	assert(reforged.affixes[0] == original.affixes[0] and reforged.affixes[2] == original.affixes[2])
	assert(reforged.affixes[1] != original.affixes[1] and reforged.affixes[3] != original.affixes[3])
	var random_state: int = game.rng.state
	var all_locks: Array[int] = [0, 1, 2, 3]
	assert(not game.reforge_item(0, all_locks) and game.rng.state == random_state)
	game.hero.pickup("steel_blade")
	game.equip_item(0)
	game.equip_item(0)
	game.unequip_item("weapon")
	assert(game.hero.inventory_rolls[0] == reforged, "同名装备交换不得丢失完整词条")
	game.free()
	for form in load("res://scripts/skill_evolution.gd").FORMS:
		var build: String = load("res://scripts/skill_evolution.gd").FORMS[form].build
		game = battle(build)
		game.state = "upgrade"
		game.wave = 2
		assert(not game.select_evolution(form), "一级英雄不能提前领取初阶")
		game.hero.gain_xp(35)
		assert(game.select_evolution(form) and game.hero.evolution_tier == 1)
		assert(not game.select_evolution(form), "同夜不能连续领进阶")
		game.hero.gain_xp(1000)
		game.wave = 4
		assert(game.select_evolution(form) and game.hero.evolution_tier == 2)
		game.wave = 6
		assert(game.select_evolution(form) and game.hero.evolution_tier == 3)
		assert(not game.select_evolution(form))
		game.state = "fighting"
		game.player_pos = Vector2(500, 350)
		if form == "echo":
			game.enemies.append(target(game.player_pos + Vector2(385, 0)))
			assert(game.cast_skill(0, game.player_pos + Vector2(500, 0)) and game.enemies[0].hp < 10000.0)
		elif form == "nova":
			assert(game.cast_skill(0, game.player_pos + Vector2(100, 0)) and game.hero.ward_time >= 2.0)
		elif form == "chain":
			for offset in [0, 80, 140, 210]: game.enemies.append(target(game.player_pos + Vector2(offset, 0)))
			for hit in 3: game.combat_builds.on_basic_hit(game, game.player_pos)
			assert(game.enemies[3].hp < 10000.0 and game.enemies[3].slow_time == 1.0)
		elif form == "reaper":
			game.enemies.append(target(game.player_pos))
			for hit in 4: game.combat_builds.on_basic_hit(game, game.player_pos)
			assert(game.hero.combo_hits == 0 and game.hero.ward_time >= 1.5)
		elif form == "hunter":
			game.enemies.append(target(game.player_pos + Vector2(390, 0)))
			game.enemies.append(target(game.player_pos + Vector2(420, 0)))
			game.cast_skill(0, game.player_pos)
			for pet in game.combat_builds.familiars: pet.shots = 3
			game.combat_builds.tick(game, 0.01)
			assert(game.bullets.size() >= 4, "终阶游猎必须实际发射分裂箭")
		else:
			game.cast_skill(0, game.player_pos)
			game.combat_builds.tick(game, 6.1)
			assert(game.bullets.size() == 16, "一级召唤保留两只数量上限，各迸发八向真实弹丸")
		game.free()
	# 自适应只看上一夜伤害差值，本夜中途切构筑或改变账本不会改已冻结计划。
	game = battle("summon")
	game.summon_damage_dealt = 1000.0
	var plan: Dictionary = game.enemy_director.plan(game, 4)
	assert(plan.role == "shock" and plan.focus_summons)
	game.hero_basic_damage = 10000.0
	assert(game.enemy_director.plan_data.role == "shock")
	var assigned := 0
	for index in game.wave_enemy_count(4):
		var enemy := target(Vector2.ZERO)
		game.enemy_director.assign(enemy, index)
		if enemy.get("role", "") == "shock": assigned += 1
	assert(assigned <= plan.limit and assigned > 0)
	assert(game.enemy_director.plan(game, 5).role == "shield")
	# 正式敌人更新选中更近的召唤物，前摇完成才扣血；死亡不产生金币或经验。
	game.player_pos = Vector2(500, 350)
	game.cast_skill(0, game.player_pos)
	var pet: Dictionary = game.combat_builds.familiars[0]
	pet.pos = Vector2(470, 350)
	game.update_spawning(0.01)
	game.enemies[0].pos = Vector2(450, 350)
	game.update_enemies(0.0)
	assert(game.enemies[0].target_kind == "summon")
	var hp: float = pet.hp
	game.update_enemies(0.3)
	assert(pet.hp < hp)
	hp = pet.hp
	game.hostile_bullets.append({"pos": pet.pos, "velocity": Vector2.ZERO, "damage": 7.0, "life": 1.0, "radius": 7.0})
	game.update_hostile_bullets(0.0)
	assert(pet.hp < hp and game.hostile_bullets.is_empty())
	var gold: int = game.gold
	var xp: int = game.hero.xp
	game.summon_health.damage(game, pet, 10000.0)
	game.combat_builds.tick(game, 0.01)
	assert(not game.combat_builds.familiars.has(pet) and game.gold == gold and game.hero.xp == xp)
	game.free()
	print("systems_mechanics=PASS 1200品质样本 十二词条 锁定重铸 六路线三阶 自适应冻结 召唤仇恨承伤死亡")
	quit(0)

## 建立不自动推进的默认战场，供独立机制夹具调用。
## @param build 待测试流派。
## @return 已正式选择英雄流派并开波的节点。
func battle(build: String) -> Node2D:
	var game: Node2D = load("res://scripts/game.gd").new()
	root.add_child(game)
	game.set_process(false)
	game.select_hero("frost_mage")
	game.select_build(build)
	game.start_wave()
	return game

## 创建不会因单次形态伤害死亡的目标。
## @param pos 目标世界像素坐标。
## @return 具有碰撞与奖励字段的字典。
func target(pos: Vector2) -> Dictionary:
	return {"pos": pos, "hp": 10000.0, "max_hp": 10000.0, "kind": "grunt", "radius": 17.0, "reward": 3, "windup": 0.0}
