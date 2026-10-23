extends SceneTree
## 验证词缀实例生命周期、六种技能形态和敌人预警反制；固定目标夹具不作为通关证据。

## 顺序检查真实交易、技能入口与碰撞结算，失败由外部限时运行器判定。
func _initialize() -> void:
	await process_frame
	var game := battle("skill")
	game.state = "ready"
	game.rng.seed = 7
	assert(game.buy_affix_chest() and game.gold == 50)
	var item: String = game.hero.inventory[0]
	var affix: String = game.hero.inventory_affixes[0]
	var random_state: int = game.rng.state
	assert(not game.buy_affix_chest() and game.rng.state == random_state and game.gold == 50)
	assert(game.equip_item(0))
	var slot: String = game.HeroRPG.ITEMS[item].slot
	assert(game.hero.equipment_affixes[slot] == affix)
	game.hero.pickup(item)
	game.equip_item(0)
	assert(game.hero.inventory_affixes[0] == affix and game.hero.equipment_affixes[slot] == "")
	game.equip_item(0)
	game.unequip_item(slot)
	assert(game.hero.inventory_affixes[1] == affix)
	game.sell_item(1)
	assert(game.hero.inventory.size() == game.hero.inventory_affixes.size())
	assert(not game.select_evolution("nova"))
	game.hero.gain_xp(35)
	game.wave = 2
	game.state = "upgrade"
	assert(not game.select_evolution("hunter") and game.select_evolution("nova"))
	assert(not game.select_evolution("echo"), "本局形态必须互斥")
	game.free()
	# 数值词缀随穿戴和卸下生效，触发词缀只统计真实普攻命中。
	for affix_id in ["swift", "arcane", "vigor", "ember", "frost", "leech"]:
		game = battle("skill")
		var before: Dictionary = game.hero.stats()
		game.hero.pickup("iron_helm", affix_id)
		game.equip_item(0)
		if affix_id == "swift": assert(game.hero.stats().rate > before.rate)
		if affix_id == "arcane": assert(game.hero.stats().skill_power > before.skill_power)
		if affix_id == "vigor": assert(game.hero.stats().health == before.health + 30.0)
		game.enemies.append(target(game.player_pos + Vector2(60, 0)))
		game.player_hp = game.max_player_hp / 2.0
		var hp: float = game.player_hp
		for hit in 4: game.apply_bullet_damage(0, {"damage": 1.0, "velocity": Vector2.ZERO, "knockback": 0.0}, 1.0)
		assert(game.hero.affix_hits == 4)
		if affix_id == "ember": assert(game.hero_affix_damage > 0.0)
		if affix_id == "frost": assert(game.enemies[0].slow_time == 1.0)
		if affix_id == "leech": assert(game.player_hp == hp + 1.0)
		game.unequip_item("head")
		assert(not game.hero.has_affix(affix_id))
		game.free()
	for form in ["echo", "nova"]:
		game = battle("skill")
		game.hero.evolution = form
		var aim: Vector2 = game.player_pos + Vector2(300, 0)
		game.enemies.append(target(game.player_pos + Vector2(265 if form == "echo" else -60, 0)))
		assert(game.cast_skill(0, aim) and game.enemies[0].hp < 10000.0)
		if form == "echo": assert(game.hero.cooldowns[0] == 3.8)
		game.free()
	for form in ["chain", "reaper"]:
		game = battle("passive")
		game.hero.evolution = form
		var center: Vector2 = game.player_pos + Vector2(60, 0)
		for offset in [0, 100, 130, 170]: game.enemies.append(target(center + Vector2(offset, 0)))
		var count := 5 if form == "reaper" else 3
		for hit in count: game.combat_builds.on_basic_hit(game, center)
		assert(game.hero.combo_hits == 0 and game.hero_passive_damage > 0.0)
		assert(game.enemies[1].hp < 10000.0)
		assert(game.enemies[3].hp == 10000.0, "连锁最多三敌，震波不能超过一百四十像素")
		game.free()
	for form in ["hunter", "sacrifice"]:
		game = battle("summon")
		game.hero.evolution = form
		game.enemies.append(target(game.player_pos))
		assert(game.cast_skill(0, game.player_pos))
		if form == "hunter":
			assert(game.combat_builds.familiars[0].life == 10.0)
			game.combat_builds.tick(game, 0.01)
			assert(game.bullets[0].splash == 0.0 and game.combat_builds.familiars[0].fire_timer == 0.5)
		else:
			game.hero.cooldowns[0] = 0.0
			assert(not game.cast_skill(0, game.player_pos), "献祭形态不能刷新尚存幻影")
			game.combat_builds.tick(game, 6.1)
			assert(game.combat_builds.familiars.is_empty() and game.summon_damage_dealt > 0.0)
		game.free()
	# 震荡命中锁定旧坐标；移走英雄后仍可打中原位置的幻影，破甲则可直接打断。
	game = battle("summon")
	var enemy := target(game.player_pos + Vector2(100, 0))
	enemy.role = "shock"
	game.enemies.append(enemy)
	var origin: Vector2 = game.player_pos
	game.combat_builds.familiars.append({"pos": origin, "life": 10.0, "fire_timer": 0.0})
	game.evolution_system.tick(game, 4.1)
	assert(enemy.shock_windup == 1.0 and enemy.shock_aim == origin)
	game.player_pos += Vector2(150, 0)
	var health: float = game.player_hp
	game.evolution_system.tick(game, 1.1)
	assert(game.player_hp == health and game.combat_builds.familiars[0].hp == game.combat_builds.familiars[0].max_hp - 12.0)
	enemy.shock_windup = 1.0
	game.apply_bullet_damage(0, {"damage": 1.0, "velocity": Vector2.ZERO, "knockback": 0.0, "break_seconds": 5.0}, 1.0)
	assert(enemy.shock_windup == 0.0)
	enemy.role = "shield"
	enemy.shield_timer = 0.0
	game.evolution_system.tick(game, 0.01)
	var shield_hp: float = enemy.hp
	game.apply_bullet_damage(0, {"damage": 10.0, "velocity": Vector2.ZERO, "knockback": 0.0}, 1.0)
	assert(is_equal_approx(shield_hp - enemy.hp, 6.5))
	game.evolution_system.interrupt(enemy)
	assert(enemy.shield_time == 0.0)
	game.free()
	# 普攻词缀不能替技能流打开战甲窗口，避免装备词缀重新抹掉主动技能的用途。
	game = battle("skill")
	game.hero.pickup("fighter_gloves", "ember")
	game.equip_item(0)
	var guarded := target(game.player_pos + Vector2(60, 0))
	guarded.kind = "boss"
	game.enemies.append(guarded)
	for hit in 4: game.apply_bullet_damage(0, {"damage": 1.0, "velocity": Vector2.ZERO, "knockback": 0.0}, 1.0)
	assert(game.hero_affix_damage > 0.0 and guarded.get("exposed_time", 0.0) == 0.0)
	game.free()
	print("evolution_mechanics=PASS 词缀交换出售 六种词缀 六种形态 预警锁定 躲避 破甲打断 架盾")
	quit(0)

## 创建停止自动推进的战场夹具，后续只由目标机制推进。
## @param build 本次验证的流派。
## @return 已正式选择英雄与流派并开波的战场。
func battle(build: String) -> Node2D:
	var game: Node2D = load("res://scripts/game.gd").new()
	root.add_child(game)
	game.set_process(false)
	game.select_hero("frost_mage")
	game.select_build(build)
	game.start_wave()
	return game

## 创建高生命普通敌人，防止溢出击杀干扰单项伤害断言。
## @param pos 目标的世界像素坐标。
## @return 带碰撞和基础奖励字段的目标。
func target(pos: Vector2) -> Dictionary:
	return {"pos": pos, "hp": 10000.0, "max_hp": 10000.0, "kind": "grunt", "radius": 17.0, "reward": 3, "windup": 0.0}
