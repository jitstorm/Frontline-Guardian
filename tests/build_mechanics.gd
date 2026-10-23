extends SceneTree
## 用固定命中夹具定位构筑机制错误；此处配置等级和目标，不作为正常经济通关证据。

## 检查真实弹丸命中、被动升级、召唤生命周期以及两张地图隔离。
func _initialize() -> void:
	var game: Node2D = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.select_hero("berserker")
	var gold_before: int = game.gold
	assert(game.select_build("passive") and game.gold == gold_before)
	var armor: float = game.player_armor
	game.hero.skill_points = 1
	assert(game.upgrade_hero_skill(2) and game.player_armor == armor + 2.0)
	game.start_wave()
	assert(not game.select_build("summon") and not game.cast_skill(0, Vector2.RIGHT))
	game.enemies.append(target(game.player_pos + Vector2(80, 0)))
	game.player_hp = game.max_player_hp / 2.0
	var hp: float = game.player_hp
	# 普攻通过正式发射与碰撞累计，前两次不破甲，第三次才触发被动。
	for hit in 3:
		game.fire_timer = 0.0
		assert(game.fire_at(game.enemies[0].pos))
		game.bullets[0].pos = game.enemies[0].pos
		game.update_bullets(0.0)
		if hit < 2: assert(game.enemies[0].get("exposed_time", 0.0) == 0.0)
	assert(game.hero.combo_hits == 0 and game.enemies[0].exposed_time == 5.0)
	assert(game.hero_passive_damage > 0.0 and game.player_hp > hp)
	assert(is_equal_approx(game.hero_damage_dealt, game.hero_basic_damage + game.hero_skill_damage + game.hero_passive_damage))
	game.enemies.clear()
	game.fire_timer = 0.0
	game.fire_at(game.player_pos + Vector2(80, 0))
	game.update_bullets(1.0)
	assert(game.hero.combo_hits == 0, "空枪不能积累被动")
	game.hero.tick(3.1)
	assert(game.hero.fervor_stacks == 0)
	game.free()
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	game.set_process(false)
	game.select_hero("frost_mage")
	game.select_build("summon")
	game.start_wave()
	var aim: Vector2 = game.player_pos + Vector2(80, 0)
	game.enemies.append(target(aim))
	assert(game.cast_skill(0, aim) and game.combat_builds.familiars.size() == 2)
	assert(not game.cast_skill(0, aim), "冷却中不能重复召唤")
	game.combat_builds.tick(game, 0.05)
	assert(game.bullets.size() == 2)
	var normal: float = game.bullets[0].damage
	game.bullets.clear()
	assert(game.cast_skill(3, aim))
	for familiar in game.combat_builds.familiars: familiar.fire_timer = 0.0
	game.combat_builds.tick(game, 0.05)
	assert(game.bullets[0].damage > normal, "集火指令必须提高幻影输出")
	for tick in 8: game.update_bullets(0.05)
	assert(game.summon_damage_dealt > 0.0 and game.enemies[0].exposed_time == 5.0)
	game.combat_builds.tick(game, 14.1)
	assert(game.combat_builds.familiars.is_empty(), "幻影必须到期消失")
	game.hero.cooldowns[0] = 0.0
	game.hero.skill_levels[0] = 3
	assert(game.cast_skill(0, aim) and game.combat_builds.familiars.size() == 3)
	var before: Vector2 = game.player_pos
	assert(game.cast_skill(2, aim) and game.player_pos.distance_to(before) > 100.0)
	game.wave = 2
	game.state = "upgrade"
	assert(game.enter_dungeon() and game.combat_builds.familiars.is_empty())
	var camp: Node2D = game.dungeon_scene
	camp.set_process(false)
	game.hero.cooldowns[0] = 0.0
	assert(camp.cast_skill(0, camp.hero_pos + Vector2(80, 0)))
	camp.enemies.clear()
	camp.enemies.append(camp.make_goblin(camp.hero_pos + Vector2(80, 0), "boss", 1000.0, 1.0))
	game.combat_builds.tick(game, 0.05, camp)
	for tick in 8: camp.update_bullets(0.05)
	assert(camp.enemies[0].hp < 1000.0 and camp.enemies[0].exposed_time == 5.0)
	var cooldown: float = game.hero.cooldowns[0]
	game.leave_dungeon()
	assert(game.combat_builds.familiars.is_empty() and game.hero.cooldowns[0] == cooldown)
	# 新增中文字符逐字检查字体字形；界面布局另由实际渲染截图检查。
	for path in ["res://scripts/game.gd", "res://scripts/hero_rpg.gd", "res://scripts/combat_builds.gd", "res://scripts/dungeon.gd"]:
		for character in FileAccess.get_file_as_string(path):
			var code := character.unicode_at(0)
			if code >= 0x4e00 and code <= 0x9fff: assert(game.UI_FONT.has_char(code), "字体缺字：" + character)
	game.free()
	print("build_mechanics=PASS 三连真实命中 破甲回血 升级同步 空枪失效 幻影碰撞 集火 寿命 地图隔离 中文字形")
	quit(0)

## 创建只参与弹丸命中的高生命首领夹具，避免移动和击杀干扰单项机制断言。
## @param pos 目标世界像素坐标。
## @return 具有碰撞、战甲与奖励字段的敌人字典。
func target(pos: Vector2) -> Dictionary:
	return {"pos": pos, "hp": 10000.0, "max_hp": 10000.0, "kind": "boss", "radius": 17.0, "reward": 3, "windup": 0.0}
