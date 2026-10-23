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
		# 被动防线作为对照，不要求通关；它的结果用于衡量英雄介入的价值。
		for run_seed in [7, 23, 91]:
			records.append(run_case(class_id, "mixed", run_seed, false, false))
		for run_seed in [7, 23, 91]:
			records.append(run_case(class_id, "mixed", run_seed, true, false, false))
		# 营地使用完整敌人更新和真实移动，避免原有快速奖励回归被当成平衡证据。
		for run_seed in [7, 23]:
			records.append(run_case(class_id, "mixed", run_seed, true, true))
	var file := FileAccess.open("res://test_logs/balance_matrix.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	print("balance_matrix=COMPLETE cases=%d" % records.size())
	quit(0)

## 从默认一百金币运行一局，不修改英雄生命、等级或敌人属性。
## @param class_id 本局英雄目录标识。
## @param plan 英雄、混合或炮塔投入方向。
## @param run_seed 控制波间随机强化的种子。
## @param active 是否允许控制器移动、射击和施法。
## @param camp 是否在第二夜后以正常战斗尝试营地。
## @param skills 是否允许基地技能，用于对照相同装备和走位下的技能收益。
## @return 含胜负、逐夜数据和伤害来源的结果字典。
func run_case(class_id: String, plan: String, run_seed: int, active: bool, camp: bool, skills: bool = true) -> Dictionary:
	seed(run_seed)
	var game: Node2D = load("res://scripts/game.gd").new()
	root.add_child(game)
	game.set_process(false)
	assert(game.select_hero(class_id))
	var controller := Controller.new()
	var nights: Array[Dictionary] = []
	var tick := 0
	var current: Dictionary = {}
	var camp_success := false
	while game.state != "won" and game.state != "lost" and tick < 16000:
		if game.state == "ready":
			controller.prepare(game, plan)
			game.start_wave()
			current = {"night": game.wave, "start_tick": tick, "core_start": game.core_hp, "peak_alive": 0, "hero_start": game.hero_damage_dealt, "tower_start": game.tower_damage_dealt, "towers": game.towers.size(), "equipment": game.hero.equipment.duplicate(), "skill_levels": game.hero.skill_levels.duplicate()}
		if game.state == "fighting":
			if active: controller.act(game, null, skills)
			game._process(controller.STEP)
			current.peak_alive = maxi(current.peak_alive, game.enemies.size())
			if game.state != "fighting":
				current.seconds = (tick - current.start_tick + 1) * controller.STEP
				current.core_end = game.core_hp
				current.gold_end = game.gold
				current.hero_damage = game.hero_damage_dealt - current.hero_start
				current.tower_damage = game.tower_damage_dealt - current.tower_start
				nights.append(current)
		if game.state == "upgrade":
			if camp and game.wave == 2 and not game.dungeon_attempted:
				camp_success = controller.visit_camp(game)
			controller.choose_upgrade(game, plan)
		assert(game.gold >= 0, "任何投入方向都不能产生负金币")
		tick += 1
	var result := {"hero": class_id, "plan": plan, "seed": run_seed, "active": active, "skills": skills, "camp": camp, "camp_success": camp_success, "result": game.state, "night": game.wave, "core": game.core_hp, "hp": game.player_hp, "gold": game.gold, "level": game.hero.level, "kills": game.kills, "hero_damage": game.hero_damage_dealt, "tower_damage": game.tower_damage_dealt, "nights": nights}
	assert(game.state == "won" or game.state == "lost", "八夜模拟未在限定步数内结算")
	if active:
		assert(game.state == "won", "普通难度的主动参考策略必须具备通关能力")
	if camp:
		assert(camp_success, "正常移速和冷却下必须能够战胜营地并实际拾取奖励")
	print("balance_case hero=%s plan=%s seed=%d active=%s skills=%s camp=%s/%s result=%s night=%d core=%.1f hero_damage=%.0f tower_damage=%.0f" % [class_id, plan, run_seed, active, skills, camp, camp_success, game.state, game.wave, game.core_hp, game.hero_damage_dealt, game.tower_damage_dealt])
	game.free()
	return result
