extends RefCounted
## 集中管理词缀触发、技能形态与敌人反制；基地和副本复用相同命中和预警规则。

## 形态只能从本流派二选一，各形态具有不同攻击范围、频率或寿命代价。
const FORMS := {
	"echo": {"build": "skill", "name": "回响法阵", "detail": "Q 追加远处七成伤害回响；冷却增加一秒"},
	"nova": {"build": "skill", "name": "环形施法", "detail": "Q 改为自身圆周攻击；伤害降低两成"},
	"chain": {"build": "passive", "name": "连锁雷击", "detail": "三连追击跳向最多三敌；每跳七成伤害"},
	"reaper": {"build": "passive", "name": "收割震波", "detail": "五次命中触发大范围双倍追击"},
	"hunter": {"build": "summon", "name": "游猎幻影", "detail": "单体速射，伤害八成；寿命十秒"},
	"sacrifice": {"build": "summon", "name": "献祭幻影", "detail": "寿命六秒，到期爆炸；不能刷新存活幻影"}
}

## 连锁雷击的起止像素坐标与剩余秒数，只作视觉反馈，不另行结算伤害。
var arcs: Array[Dictionary] = []

## 对当前地图范围内敌人施加独立伤害，倒序结算且不再次触发普攻词缀。
## @param game 本局战场。
## @param camp 当前副本，为空表示基地。
## @param center 范围中心，单位像素。
## @param radius 命中半径，单位像素。
## @param power 本次原始伤害。
## @param source 伤害账本来源，区分词缀、被动、技能与召唤。
func burst(game: Node2D, camp: Node2D, center: Vector2, radius: float, power: float, source: String) -> void:
	var targets: Array = game.enemies if camp == null else camp.enemies
	for i in range(targets.size() - 1, -1, -1):
		if targets[i].pos.distance_to(center) > radius: continue
		if source != "affix": interrupt(targets[i])
		if camp == null:
			game.apply_bullet_damage(i, {"damage": power, "velocity": Vector2.ZERO, "knockback": 0.0, "magic": source != "affix", "break_seconds": 0.0 if source == "affix" else game.ARMOR_BREAK_SECONDS, "source": source}, 1.0)
		else: camp.damage_enemy(i, power, source != "affix")
	if camp == null: game.impacts.append({"pos": center, "time": 0.2, "radius": radius, "color": Color("b9a1ff")})

## 真实普攻命中后启动词缀；额外爆炸、追击和词缀伤害不会递归累计触发次数。
## @param game 本局战场。
## @param center 普攻命中点，单位像素。
## @param camp 当前副本，为空表示基地。
func on_hit(game: Node2D, center: Vector2, camp: Node2D = null) -> void:
	game.hero.affix_hits += 1
	if game.hero.has_affix("ember") and game.hero.affix_hits % 4 == 0:
		burst(game, camp, center, 65.0, game.hero.stats().attack * 0.45, "affix")
	if game.hero.has_affix("leech") and game.hero.leech_timer <= 0.0:
		game.player_hp = minf(game.max_player_hp, game.player_hp + 1.0)
		game.hero.leech_timer = 0.6
	if game.hero.has_affix("frost"):
		var targets: Array = game.enemies if camp == null else camp.enemies
		for enemy in targets:
			if enemy.pos.distance_to(center) <= 35.0:
				enemy.slow_time = maxf(1.0, enemy.get("slow_time", 0.0))
				enemy.slow_factor = 0.7

## 实际破甲命中可打断震荡蓄力与护卫架盾；震荡打断后重等八秒，架盾沿用原有周期。
## @param enemy 仍存活的敌人字典。
func interrupt(enemy: Dictionary) -> void:
	if enemy.get("shock_windup", 0.0) > 0.0: enemy.shock_timer = 8.0
	enemy.shock_windup = 0.0
	enemy.shield_time = 0.0

## 推进固定敌人职责的反制周期；不读取流派生成克制怪，危险区域始终有一秒预警。
## @param game 本局战场。
## @param delta 推进秒数。
## @param camp 当前副本，为空表示基地。
func tick(game: Node2D, delta: float, camp: Node2D = null) -> void:
	for i in range(arcs.size() - 1, -1, -1):
		arcs[i].time -= delta
		if arcs[i].time <= 0.0: arcs.remove_at(i)
	var targets: Array = game.enemies if camp == null else camp.enemies
	var owner: Vector2 = game.player_pos if camp == null else camp.hero_pos
	for enemy in targets:
		if enemy.get("role", "") == "shield":
			enemy.shield_time = maxf(0.0, enemy.get("shield_time", 0.0) - delta)
			enemy.shield_timer = enemy.get("shield_timer", 4.0) - delta
			if enemy.shield_timer <= 0.0:
				enemy.shield_timer = 8.0
				enemy.shield_time = 3.0
		elif enemy.get("role", "") == "shock":
			if enemy.get("shock_windup", 0.0) > 0.0:
				enemy.shock_windup -= delta
				if enemy.shock_windup <= 0.0:
					# 只打击预警时锁定的位置，离开圆圈或闪避可以保护英雄，迁跃可以带走幻影。
					if owner.distance_to(enemy.shock_aim) <= 90.0 and game.dodge_timer <= 0.0:
						game.player_hp -= game.incoming_damage(8.0, game.player_armor, game.hero.ward_time > 0.0)
						game.hero.fervor_stacks = 0
					for familiar in game.combat_builds.familiars:
						if familiar.pos.distance_to(enemy.shock_aim) <= 90.0: familiar.life -= 5.0
					enemy.shock_timer = 8.0
			else:
				enemy.shock_timer = enemy.get("shock_timer", 4.0) - delta
				if enemy.shock_timer <= 0.0 and enemy.pos.distance_to(owner) < 400.0:
					enemy.shock_windup = 1.0
					enemy.shock_aim = owner

## 绘制敌人职责与锁定区域，玩家可根据圆圈选择打断或离开。
## @param canvas 正在绘制的基地或副本。
## @param targets 当前地图的敌人数组。
## @param font 打包的中文字体。
func draw(canvas: Node2D, targets: Array, font: Font) -> void:
	for arc in arcs: canvas.draw_line(arc.start, arc.end, Color("b9a1ff"), 3.0)
	for enemy in targets:
		if enemy.get("role", "") == "shield":
			canvas.draw_string(font, enemy.pos + Vector2(-28, 35), "架盾" if enemy.get("shield_time", 0.0) > 0.0 else "护卫", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("80deff"))
		if enemy.get("role", "") == "shock":
			canvas.draw_string(font, enemy.pos + Vector2(-28, 35), "震荡术士", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e7a6ff"))
		if enemy.get("shock_windup", 0.0) > 0.0:
			canvas.draw_arc(enemy.shock_aim, 90.0, 0, TAU, 48, Color("ff88d0"), 3.0)
			canvas.draw_string(font, enemy.shock_aim + Vector2(-75, -100), "震荡：离开或破甲打断", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("ff88d0"))
