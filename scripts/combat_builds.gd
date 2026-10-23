extends RefCounted
## 实现连击被动与幻影召唤，基地和营地共用同一套成长、命中及冷却语义。

## 幻影记录：pos 为世界像素坐标，life 为剩余秒数，fire_timer 为剩余射击冷却秒数。
var familiars: Array[Dictionary] = []
## 集火指令的剩余秒数与目标世界像素坐标，地图切换时清空。
var command_time := 0.0
var command_pos := Vector2.ZERO

## 清除地图内幻影与集火状态，不返还英雄技能冷却，避免跨地图带入过期单位。
func clear() -> void:
	familiars.clear()
	command_time = 0.0

## 对真实命中的普攻累计连击，第三击触发追击、破甲与续航，空枪不能累计。
## @param game 本局战场，保存英雄与唯一生命状态。
## @param center 实际命中位置，单位为世界像素。
## @param camp 当前营地；为空表示基地。
func on_basic_hit(game: Node2D, center: Vector2, camp: Node2D = null) -> void:
	if game.hero.build_id != "passive": return
	game.hero.fervor_stacks = mini(8, game.hero.fervor_stacks + 1)
	game.hero.fervor_time = 3.0
	game.hero.combo_hits += 1
	if game.hero.combo_hits < 3: return
	game.hero.combo_hits = 0
	# 追击是独立的被动伤害来源，不能再次触发连击，否则范围命中会无限递归。
	var power: float = game.hero.stats().attack * (0.80 + 0.18 * (game.hero.skill_levels[0] - 1))
	var radius: float = 65.0 + 5.0 * game.hero.skill_levels[0]
	if game.hero.has_effect("wide_sweep"): radius *= 1.4
	if game.hero.has_effect("rage_chain"): power *= 1.25
	var targets: Array = game.enemies if camp == null else camp.enemies
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
	# 幻影是有持续时间的灵体，不挡路、不承伤；数量上限防止连续召唤积累无限输出。
	match index:
		0:
			var limit := 3 if game.hero.skill_levels[0] >= 3 else 2
			while familiars.size() < limit:
				familiars.append({"pos": pos, "life": 14.0, "fire_timer": 0.0})
			for familiar in familiars: familiar.life = 14.0
		1:
			game.hero.ward_time = 5.0
			game.player_hp = minf(game.max_player_hp, game.player_hp + 6.0 * game.hero.skill_levels[1])
			for familiar in familiars: familiar.life = minf(17.0, familiar.life + 3.0)
		2:
			var destination: Vector2 = (pos + (aim - pos).normalized() * (95.0 + 10.0 * game.hero.skill_levels[2])).clamp(Vector2(50, 110), Vector2(1230, 650))
			if camp == null: game.player_pos = destination
			else: camp.hero_pos = destination
			for familiar in familiars: familiar.pos = (familiar.pos + destination - pos).clamp(Vector2(50, 110), Vector2(1230, 650))
		3:
			command_time = 5.0
			command_pos = aim
	game.hero.cooldowns[index] = [8.0, 10.0, 8.0, 18.0][index]
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
		familiar.life -= delta
		if familiar.life <= 0.0:
			familiars.remove_at(i)
			continue
		var offset := Vector2(-45 + i * 45, -42)
		familiar.pos = familiar.pos.move_toward((owner_pos + offset).clamp(Vector2(30, 110), Vector2(1250, 650)), 300.0 * delta)
		familiar.fire_timer = maxf(0.0, familiar.fire_timer - delta)
		if familiar.fire_timer > 0.0: continue
		var target := -1
		var best := INF
		for j in targets.size():
			if familiar.pos.distance_to(targets[j].pos) > 360.0: continue
			var score: float = targets[j].pos.distance_to(command_pos if command_time > 0.0 else familiar.pos)
			if score < best:
				best = score
				target = j
		if target < 0: continue
		# 幻影法弹通过正式碰撞结算破甲与伤害，不能直接隔空扣除目标生命。
		var direction: Vector2 = (targets[target].pos - familiar.pos).normalized()
		var power: float = game.hero.stats().attack * (1.0 + game.hero.stats().skill_power) * (0.75 + 0.18 * (game.hero.skill_levels[0] - 1))
		if command_time > 0.0: power *= 1.3 + 0.1 * game.hero.skill_levels[3]
		projectiles.append({"pos": familiar.pos, "velocity": direction * 520.0, "damage": power, "life": 0.8, "radius": 6.0, "color": Color("a1e9ff"), "knockback": 0.0, "source": "summon", "magic": true, "break_seconds": game.ARMOR_BREAK_SECONDS, "splash": 65.0 if game.hero.has_effect("frost_burst") else 45.0})
		familiar.fire_timer = 0.80

## 在当前地图绘制带持续时间条的半透明幻影，与真实敌人及本体区分。
## @param game 提供本局合法贴图的战场。
## @param canvas 正在执行绘制回调的基地或营地节点。
func draw(game: Node2D, canvas: Node2D) -> void:
	for familiar in familiars:
		canvas.draw_arc(familiar.pos, 17, 0, TAU, 20, Color("a1e9ff"), 1.5)
		canvas.draw_texture_rect(game.HERO_MAGE, Rect2(familiar.pos - Vector2(15, 15), Vector2(30, 30)), false, Color(0.55, 0.9, 1.0, 0.8))
		canvas.draw_rect(Rect2(familiar.pos + Vector2(-15, -22), Vector2(30.0 * minf(1.0, familiar.life / 14.0), 3)), Color("a1e9ff"))
