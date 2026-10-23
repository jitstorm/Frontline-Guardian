extends SceneTree
## 用两名英雄、三种投入方向与多个随机种子评估八夜平衡，记录每夜压力及输出来源。

const Controller = preload("res://tests/balance_controller.gd")

## 顺序运行独立场景并保存原始结果；运行超时、负金币或动作未结算均视为失败。
func _initialize() -> void:
	await process_frame
	var records: Array[Dictionary] = []
	for class_id in ["berserker", "frost_mage"]:
		for plan in ["hero", "mixed", "towers"]:
			for run_seed in [7, 23, 91]:
				records.append(run_case(class_id, plan, run_seed, true, false))
				records.append(run_case(class_id, plan, run_seed, true, false, false))
		# 被动防线作为对照，不要求通关；它的结果用于衡量英雄介入的价值。
		for run_seed in [7, 23, 91]:
			records.append(run_case(class_id, "mixed", run_seed, false, false))
		# 营地使用完整敌人更新和真实移动，避免原有快速奖励回归被当成平衡证据。
		for run_seed in [7, 23]:
			records.append(run_case(class_id, "mixed", run_seed, true, true))
	var file := FileAccess.open("res://test_logs/balance_matrix.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	var failures := 0
	for result in records:
		if result.is_empty():
			failures += 1
			continue
		if result.result not in ["won", "lost"] or (result.active and result.skills and result.result != "won") or (result.active and not result.skills and result.result != "lost") or (result.camp and not result.camp_success):
			failures += 1
			push_error("参考策略未达到验收条件：%s" % JSON.stringify(result))
	print("balance_matrix=COMPLETE cases=%d" % records.size())
	quit(0 if failures == 0 else 1)

## 从默认一百金币运行一局，不修改英雄生命、等级或敌人属性。
## @param class_id 本局英雄目录标识。
## @param plan 英雄、混合或炮塔投入方向。
## @param run_seed 控制波间随机强化的种子。
## @param active 是否允许控制器移动、射击和施法。
## @param camp 是否在第二夜后以正常战斗尝试营地。
## @param skills 是否允许基地技能，用于对照相同装备和走位下的技能收益。
## @param build_id 第一夜前选定的战斗流派，默认沿用技能爆发。
## @param form 第二夜后选择的技能形态；空值表示原始形态，非空时也尝试正常购买词缀宝匣。
## @return 含胜负、逐夜数据和伤害来源的结果字典。
func run_case(class_id: String, plan: String, run_seed: int, active: bool, camp: bool, skills: bool = true, build_id: String = "skill", form: String = "") -> Dictionary:
	seed(run_seed)
	var game: Node2D = load("res://scripts/game.gd").new()
	root.add_child(game)
	game.set_process(false)
	assert(game.select_hero(class_id))
	assert(game.select_build(build_id))
	game.rng.seed = run_seed
	var controller := Controller.new()
	var nights: Array[Dictionary] = []
	var tick := 0
	var current: Dictionary = {}
	var camp_success := false
	while game.state != "won" and game.state != "lost" and tick < 16000:
		if game.state == "ready":
			controller.prepare(game, plan)
			if form != "":
				if game.wave >= 2 and game.hero.evolution == "": assert(game.select_evolution(form))
				if game.wave >= 2 and game.gold >= 50 and game.hero.inventory.size() < game.HeroRPG.CAPACITY:
					if game.buy_affix_chest(): game.equip_item(game.hero.inventory.size() - 1)
			game.start_wave()
			current = {"night": game.wave, "start_tick": tick, "core_start": game.core_hp, "peak_alive": 0, "hero_start": game.hero_damage_dealt, "basic_start": game.hero_basic_damage, "skill_start": game.hero_skill_damage, "tower_start": game.tower_damage_dealt, "towers": game.towers.size(), "equipment": game.hero.equipment.duplicate(), "skill_levels": game.hero.skill_levels.duplicate()}
		if game.state == "fighting":
			if active: controller.act(game, null, skills)
			game._process(controller.STEP)
			current.peak_alive = maxi(current.peak_alive, game.enemies.size())
			if game.state != "fighting":
				current.seconds = (tick - current.start_tick + 1) * controller.STEP
				current.core_end = game.core_hp
				current.gold_end = game.gold
				current.hero_damage = game.hero_damage_dealt - current.hero_start
				current.basic_damage = game.hero_basic_damage - current.basic_start
				current.skill_damage = game.hero_skill_damage - current.skill_start
				current.tower_damage = game.tower_damage_dealt - current.tower_start
				nights.append(current)
		if game.state == "upgrade":
			if form != "" and game.wave >= 2 and game.hero.evolution == "": assert(game.select_evolution(form))
			if camp and game.wave == 2 and not game.dungeon_attempted:
				camp_success = controller.visit_camp(game)
			controller.choose_upgrade(game, plan)
		assert(game.gold >= 0, "任何投入方向都不能产生负金币")
		tick += 1
	var result := {"form": game.hero.evolution, "affix_damage": game.hero_affix_damage, "affixes": game.hero.equipment_affixes.duplicate(), "build": build_id, "passive_damage": game.hero_passive_damage, "summon_damage": game.summon_damage_dealt, "hero": class_id, "plan": plan, "seed": run_seed, "active": active, "skills": skills, "camp": camp, "camp_success": camp_success, "result": game.state, "night": game.wave, "core": game.core_hp, "hp": game.player_hp, "gold": game.gold, "level": game.hero.level, "kills": game.kills, "hero_damage": game.hero_damage_dealt, "basic_damage": game.hero_basic_damage, "skill_damage": game.hero_skill_damage, "tower_damage": game.tower_damage_dealt, "nights": nights}
	assert(game.state == "won" or game.state == "lost", "八夜模拟未在限定步数内结算")
	print("balance_case form=%s build=%s hero=%s plan=%s seed=%d active=%s skills=%s camp=%s/%s result=%s night=%d core=%.1f hero_damage=%.0f tower_damage=%.0f" % [game.hero.evolution, build_id, class_id, plan, run_seed, active, skills, camp, camp_success, game.state, game.wave, game.core_hp, game.hero_damage_dealt, game.tower_damage_dealt])
	game.free()
	return result
