extends RefCounted
## 实现连击被动与幻影召唤，基地和营地共用同一套成长、命中及冷却语义。

## 幻影记录：pos 为世界像素坐标，life 与 fire_timer 为寿命和射击冷却秒数；hp/max_hp 为生命点数，由 SummonHealth 管理。
## hurt_time 为受击反馈剩余秒数，shots 为该单位已经发射的次数，用于终阶分裂。
var familiars: Array[Dictionary] = []
## 集火指令的剩余秒数与目标世界像素坐标，地图切换时清空。
var command_time := 0.0
var command_pos := Vector2.ZERO

## 清除地图内幻影与集火状态，不返还英雄技能冷却，避免跨地图带入过期单位。
func clear() -> void:
	familiars.clear()
	command_time = 0.0

## 对真实命中的普攻累计连击，默认第三击触发追击、破甲与续航；收割形态改为第五击，空枪不能累计。
## @param game 本局战场，保存英雄与唯一生命状态。
## @param center 实际命中位置，单位为世界像素。
## @param camp 当前营地；为空表示基地。
func on_basic_hit(game: Node2D, center: Vector2, camp: Node2D = null) -> void:
	if game.hero.build_id != "passive": return
	game.hero.fervor_stacks = mini(8, game.hero.fervor_stacks + 1)
	game.hero.fervor_time = 3.0
	game.hero.combo_hits += 1
	if game.hero.combo_hits < game.SkillEvolution.combo_required(game.hero): return
	game.hero.combo_hits = 0
	# 追击是独立的被动伤害来源，不能再次触发连击，否则范围命中会无限递归。
	var power: float = game.hero.stats().attack * (0.80 + 0.18 * (game.hero.skill_levels[0] - 1))
	var radius: float = 65.0 + 5.0 * game.hero.skill_levels[0]
	if game.hero.has_effect("wide_sweep"): radius *= 1.4
	if game.hero.has_effect("rage_chain"): power *= 1.25
	if game.hero.evolution == "reaper":
		power *= 2.0
		radius = game.SkillEvolution.rules(game.hero).radius
		if game.hero.evolution_tier >= 3: game.hero.ward_time = maxf(1.5, game.hero.ward_time)
	var targets: Array = game.enemies if camp == null else camp.enemies
	var chained: Array = targets.duplicate()
	chained.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.pos.distance_to(center) < b.pos.distance_to(center))
	if game.hero.evolution == "chain":
		# 连锁按最近距离最多跳向三名敌人；保存对象后重新查索引，击杀不能错伤后移的敌人。
		var previous: Vector2 = center
		for target in chained.slice(0, game.SkillEvolution.rules(game.hero).targets):
			if target.pos.distance_to(center) > game.SkillEvolution.rules(game.hero).range: continue
			var index := targets.find(target)
			if index < 0: continue
			game.evolution_system.arcs.append({"start": previous, "end": target.pos, "time": 0.2})
			previous = target.pos
			if game.hero.evolution_tier >= 3:
				target.slow_time = 1.0
				target.slow_factor = 0.5
			if camp == null: game.apply_bullet_damage(index, {"damage": power * 0.7, "velocity": Vector2.ZERO, "knockback": 0.0, "source": "passive", "magic": true, "break_seconds": game.ARMOR_BREAK_SECONDS}, 1.0)
			else: camp.damage_enemy(index, power * 0.7, true)
		game.player_hp = minf(game.max_player_hp, game.player_hp + 2.0 * game.hero.skill_levels[1])
		return
	for index in range(targets.size() - 1, -1, -1):
		if targets[index].pos.distance_to(center) > radius: continue
		if camp == null:
			game.apply_bullet_damage(index, {"damage": power, "velocity": Vector2.ZERO, "knockback": 0.0, "source": "passive", "magic": true, "break_seconds": game.ARMOR_BREAK_SECONDS}, 1.0)
		else: camp.damage_enemy(index, power, true)
	game.player_hp = minf(game.max_player_hp, game.player_hp + 2.0 * game.hero.skill_levels[1])
	if camp == null: game.impacts.append({"pos": center, "time": 0.2, "color": Color("b4ff91"), "radius": radius})

## 释放召唤流四种指令，只有命令真正生效后才进入冷却。
## @param game 当前本局战场。
## @param index 按 Q/W/E/R 排列的指令索引。
## @param aim 鼠标指向的世界像素坐标，用于迁跃与集火。
## @param camp 当前营地；为空表示基地。
## @return 召唤流且冷却结束、等级有效时返回 true，否则不改变状态。
func cast(game: Node2D, index: int, aim: Vector2, camp: Node2D = null) -> bool:
	if game.hero.build_id != "summon" or index < 0 or index >= 4 or game.hero.cooldowns[index] > 0.0 or game.hero.skill_levels[index] <= 0: return false
	var pos: Vector2 = game.player_pos if camp == null else camp.hero_pos
	# 幻影有独立生命但不阻挡道路；重复召唤不回复现存幻影生命，防止刷新形成无敌肉盾。
	match index:
		0:
			var limit := 3 if game.hero.skill_levels[0] >= 3 else 2
			if game.hero.evolution == "sacrifice" and familiars.size() >= limit: return false
			while familiars.size() < limit:
				familiars.append({"pos": pos, "life": 6.0 if game.hero.evolution == "sacrifice" else 10.0 if game.hero.evolution == "hunter" else 14.0, "fire_timer": 0.0})
			for familiar in familiars: game.summon_health.ensure(game, familiar)
			if game.hero.evolution != "sacrifice":
				for familiar in familiars: familiar.life = 10.0 if game.hero.evolution == "hunter" else 14.0
		1:
			game.hero.ward_time = 5.0
			game.player_hp = minf(game.max_player_hp, game.player_hp + 6.0 * game.hero.skill_levels[1])
			for familiar in familiars:
				game.summon_health.ensure(game, familiar)
				familiar.hp = minf(familiar.max_hp, familiar.hp + 8.0 * game.hero.skill_levels[1])
				if game.hero.evolution != "sacrifice": familiar.life = minf(17.0, familiar.life + 3.0)
		2:
			var destination: Vector2 = (pos + (aim - pos).normalized() * (95.0 + 10.0 * game.hero.skill_levels[2])).clamp(Vector2(50, 110), Vector2(1230, 650))
			if camp == null: game.player_pos = destination
			else: camp.hero_pos = destination
			for familiar in familiars: familiar.pos = (familiar.pos + destination - pos).clamp(Vector2(50, 110), Vector2(1230, 650))
		3:
			command_time = 5.0
			command_pos = aim
	game.hero.cooldowns[index] = game.hero.cooldown_seconds([6.0 if game.hero.evolution == "sacrifice" else 8.0, 10.0, 8.0, 18.0][index])
	game.show_notice(game.hero.skill_names()[index])
	return true

## 按真实时间推进灵体寿命、跟随和射击，目标与弹丸均来自当前地图。
## @param game 本局战场，提供英雄属性和共享冷却。
## @param delta 本次推进秒数。
## @param camp 当前营地；为空表示基地。
func tick(game: Node2D, delta: float, camp: Node2D = null) -> void:
	if game.hero.build_id != "summon": return
	command_time = maxf(0.0, command_time - delta)
	var owner_pos: Vector2 = game.player_pos if camp == null else camp.hero_pos
	var targets: Array = game.enemies if camp == null else camp.enemies
	var projectiles: Array = game.bullets if camp == null else camp.bullets
	for i in range(familiars.size() - 1, -1, -1):
		var familiar := familiars[i]
		game.summon_health.ensure(game, familiar)
		familiar.hurt_time = maxf(0.0, familiar.hurt_time - delta)
		familiar.life -= delta
		if familiar.life <= 0.0 or familiar.hp <= 0.0:
			if game.hero.evolution == "sacrifice": game.evolution_system.burst(game, camp, familiar.pos, game.SkillEvolution.rules(game.hero).death_radius, game.hero.stats().attack * (1.0 + game.hero.stats().skill_power) * 1.5, "summon")
			if game.hero.evolution == "sacrifice" and game.hero.evolution_tier >= 3:
				# 终阶死亡迸发实际弹丸，不能在清地图时触发或跨地图保留。
				for direction_index in int(game.SkillEvolution.rules(game.hero).radials):
					projectiles.append({"pos": familiar.pos, "velocity": Vector2.RIGHT.rotated(TAU * direction_index / 8.0) * 350.0, "life": 0.6, "damage": game.hero.stats().attack * 0.35, "radius": 5.0, "color": Color("b9a1ff"), "knockback": 0.0, "source": "summon", "magic": true, "break_seconds": game.ARMOR_BREAK_SECONDS})
			familiars.remove_at(i)
			continue
		var offset := Vector2(-45 + i * 45, -42)
		familiar.pos = familiar.pos.move_toward((owner_pos + offset).clamp(Vector2(30, 110), Vector2(1250, 650)), 300.0 * delta)
		familiar.fire_timer = maxf(0.0, familiar.fire_timer - delta)
		if familiar.fire_timer > 0.0: continue
		var target := -1
		var best := INF
		for j in targets.size():
			if familiar.pos.distance_to(targets[j].pos) > float(game.SkillEvolution.rules(game.hero).get("range", 360.0)): continue
			var score: float = targets[j].pos.distance_to(command_pos if command_time > 0.0 else familiar.pos)
			if score < best:
				best = score
				target = j
		if target < 0: continue
		# 幻影法弹通过正式碰撞结算破甲与伤害，不能直接隔空扣除目标生命。
		var direction: Vector2 = (targets[target].pos - familiar.pos).normalized()
		var power: float = game.hero.stats().attack * (1.0 + game.hero.stats().skill_power) * (0.75 + 0.18 * (game.hero.skill_levels[0] - 1))
		if game.hero.evolution == "hunter": power *= 0.8
		if command_time > 0.0: power *= 1.3 + 0.1 * game.hero.skill_levels[3]
		projectiles.append({"pos": familiar.pos, "velocity": direction * 520.0, "damage": power, "life": game.SkillEvolution.rules(game.hero).get("projectile_life", 0.8), "radius": 6.0, "color": Color("a1e9ff"), "knockback": 0.0, "source": "summon", "magic": true, "break_seconds": game.ARMOR_BREAK_SECONDS, "splash": 0.0 if game.hero.evolution == "hunter" else 65.0 if game.hero.has_effect("frost_burst") else 45.0})
		familiar.shots = familiar.get("shots", 0) + 1
		if game.hero.evolution == "hunter" and game.hero.evolution_tier >= 3 and familiar.shots % 4 == 0:
			for other in targets:
				if other == targets[target] or other.pos.distance_to(targets[target].pos) > 100.0: continue
				var extra: Dictionary = projectiles.back().duplicate()
				extra.velocity = (other.pos - familiar.pos).normalized() * 520.0
				extra.damage *= 0.5
				projectiles.append(extra)
				break
		familiar.fire_timer = 0.5 if game.hero.evolution == "hunter" else 0.80

## 在当前地图绘制带持续时间条的半透明幻影，与真实敌人及本体区分。
## @param game 提供本局合法贴图的战场。
## @param canvas 正在执行绘制回调的基地或营地节点。
func draw(game: Node2D, canvas: Node2D) -> void:
	for familiar in familiars:
		game.summon_health.ensure(game, familiar)
		canvas.draw_rect(Rect2(familiar.pos + Vector2(-15, -28), Vector2(30.0 * familiar.hp / familiar.max_hp, 3)), Color("b4ff91"))
		canvas.draw_arc(familiar.pos, 17, 0, TAU, 20, Color("a1e9ff"), 1.5)
		canvas.draw_texture_rect(game.HERO_MAGE, Rect2(familiar.pos - Vector2(15, 15), Vector2(30, 30)), false, Color(0.55, 0.9, 1.0, 0.8))
		canvas.draw_rect(Rect2(familiar.pos + Vector2(-15, -22), Vector2(30.0 * minf(1.0, familiar.life / (6.0 if game.hero.evolution == "sacrifice" else 10.0 if game.hero.evolution == "hunter" else 14.0)), 3)), Color("a1e9ff"))
