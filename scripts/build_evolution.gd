extends RefCounted
## 管理词缀触发与范围伤害，转发独立敌人职责模块；形态规则由 SkillEvolution 管理。

## 形态只能从本流派二选一，各形态具有不同攻击范围、频率或寿命代价。
const FORMS = preload("res://scripts/skill_evolution.gd").FORMS
const Counter = preload("res://scripts/enemy_counter.gd")
var counter = Counter.new()
var affix_effects = preload("res://scripts/affix_effects.gd").new()

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

## 转发一次真实普攻命中到独立词缀效果模块，保持基地与副本的统一调用入口。
## @param game 本局战场。
## @param center 实际命中位置，单位像素。
## @param camp 当前副本；为空表示基地。
func on_hit(game: Node2D, center: Vector2, camp: Node2D = null) -> void:
	affix_effects.apply(game, center, camp)

## 实际破甲命中可打断震荡蓄力与护卫架盾；震荡打断后重等八秒，架盾沿用原有周期。
## @param enemy 仍存活的敌人字典。
func interrupt(enemy: Dictionary) -> void:
	Counter.interrupt(enemy)

## 推进反馈与本夜已确定的敌人职责，职责分配在上一夜输出分析后冻结。
## @param game 本局战场。
## @param delta 推进秒数。
## @param camp 当前副本，为空表示基地。
func tick(game: Node2D, delta: float, camp: Node2D = null) -> void:
	for i in range(arcs.size() - 1, -1, -1):
		arcs[i].time -= delta
		if arcs[i].time <= 0.0: arcs.remove_at(i)
	counter.tick(game, delta, camp)

## 绘制敌人职责与锁定区域，玩家可根据圆圈选择打断或离开。
## @param canvas 正在绘制的基地或副本。
## @param targets 当前地图的敌人数组。
## @param font 打包的中文字体。
func draw(canvas: Node2D, targets: Array, font: Font) -> void:
	for arc in arcs: canvas.draw_line(arc.start, arc.end, Color("b9a1ff"), 3.0)
	counter.draw(canvas, targets, font)
