extends RefCounted
## 执行架盾与震荡职责，负责预警、打断和结算；敌人职责的自适应分配由 EnemyDirector 决定。

## 破甲命中打断震荡或护盾，已锁定的震荡不再结算。
## @param enemy 当前敌人字典。
static func interrupt(enemy: Dictionary) -> void:
	if enemy.get("shock_windup", 0.0) > 0.0: enemy.shock_timer = 8.0
	enemy.shock_windup = 0.0
	enemy.shield_time = 0.0

## 推进当前地图的职责计时，震荡必须完成一秒预警才结算锁定区域。
## @param game 本局战场。
## @param delta 推进秒数。
## @param camp 当前副本；为空表示基地。
func tick(game: Node2D, delta: float, camp: Node2D = null) -> void:
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
						if familiar.pos.distance_to(enemy.shock_aim) <= 90.0: game.summon_health.damage(game, familiar, 12.0)
					enemy.shock_timer = 8.0
			else:
				enemy.shock_timer = enemy.get("shock_timer", 4.0) - delta
				if enemy.shock_timer <= 0.0 and enemy.pos.distance_to(owner) < 400.0:
					enemy.shock_windup = 1.0
					enemy.shock_aim = owner
					if enemy.get("focus_summons", false):
						var pet: Dictionary = game.summon_health.nearest(game.combat_builds.familiars, enemy.pos, 400.0)
						if not pet.is_empty(): enemy.shock_aim = pet.pos

## 绘制职责名称与震荡锁定圆圈，提供走位和打断的可读提示。
## @param canvas 正在绘制的战场或副本。
## @param targets 当前地图的敌人。
## @param font 打包的中文字体。
func draw(canvas: Node2D, targets: Array, font: Font) -> void:
	for enemy in targets:
		if enemy.get("role", "") == "shield":
			canvas.draw_string(font, enemy.pos + Vector2(-28, 35), "架盾" if enemy.get("shield_time", 0.0) > 0.0 else "护卫", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("80deff"))
		if enemy.get("role", "") == "shock":
			canvas.draw_string(font, enemy.pos + Vector2(-28, 35), "震荡术士", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e7a6ff"))
		if enemy.get("shock_windup", 0.0) > 0.0:
			canvas.draw_arc(enemy.shock_aim, 90.0, 0, TAU, 48, Color("ff88d0"), 3.0)
			canvas.draw_string(font, enemy.shock_aim + Vector2(-75, -100), "震荡：离开或破甲打断", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("ff88d0"))
