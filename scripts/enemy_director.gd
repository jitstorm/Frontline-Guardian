extends RefCounted
## 根据上一夜实际输出结构规划下一夜职责，仅替换至多五分之一普通敌人的职责，不增加怪数或生命。
## 每波开始后计划冻结，玩家能从提示预知，禁止战斗中随装备变化临时生成克制。

## 上次开波时的累计实伤快照，用差值获得完整上一夜数据。
var previous: Dictionary = {}
## 已冻结的本夜计划：night 为一开始的夜次，dominant 为上夜主要来源，ratio 为零至一占比，role 为增援职责。
## limit 为本夜最多调整的只数，assigned 为已经调整的只数，focus_summons 表示震荡是否优先锁定召唤物；history 保存冻结时的计划。
var plan_data: Dictionary = {}
var history: Array[Dictionary] = []

## 读取上一夜实伤并冻结本夜计划，第一至三夜保持原有阵容职责。
## @param game 提供各来源累计真实伤害的战场。
## @param night 即将开始的夜次，从一开始。
## @return 含职责、主输出占比与调整上限的计划。
func plan(game: Node2D, night: int) -> Dictionary:
	var totals := {"basic": game.hero_basic_damage + game.hero_passive_damage + game.hero_affix_damage, "skill": game.hero_skill_damage, "summon": game.summon_damage_dealt, "tower": game.tower_damage_dealt}
	var dominant := "balanced"
	var largest := 0.0
	var total := 0.0
	for source in totals:
		var value: float = maxf(0.0, totals[source] - previous.get(source, 0.0))
		total += value
		if value > largest:
			largest = value
			dominant = source
	previous = totals.duplicate()
	var ratio: float = largest / total if total > 0.0 else 0.0
	var role := "shield" if dominant in ["basic", "tower"] else "shock"
	var enabled: bool = night >= 4 and ratio >= 0.6
	plan_data = {"night": night, "dominant": dominant, "ratio": ratio, "role": role if enabled else "balanced", "limit": int(game.wave_enemy_count(night) / 5) if enabled else 0, "assigned": 0, "focus_summons": enabled and dominant == "summon"}
	history.append(plan_data.duplicate())
	return plan_data.duplicate()

## 给已确定种类的敌人分配本夜职责，精英与首领不参加自适应替换。
## @param enemy 刚由原有生成器创建的敌人。
## @param index 本夜零起始生成索引。
func assign(enemy: Dictionary, index: int) -> void:
	if enemy.kind == "armored" and plan_data.get("night", 0) >= 3: enemy.role = "shield"
	elif enemy.kind == "ranged" and plan_data.get("night", 0) >= 5: enemy.role = "shock"
	if plan_data.get("limit", 0) <= plan_data.get("assigned", 0) or index % 5 != 4 or enemy.kind in ["boss", "elite"]: return
	enemy.role = plan_data.role
	enemy.focus_summons = plan_data.focus_summons
	plan_data.assigned += 1

## 返回本夜的中文应对提示，明确调整的是职责而非临时强化生命。
## @return 无适应计划时返回常规阵容，否则说明可预判的主要威胁。
func label() -> String:
	if plan_data.get("role", "balanced") == "balanced": return "本夜常规阵容"
	return "敌军适应：护卫增援，破甲应对" if plan_data.role == "shield" else "敌军适应：震荡增援，保护召唤物" if plan_data.focus_summons else "敌军适应：震荡增援，注意躲圈"
