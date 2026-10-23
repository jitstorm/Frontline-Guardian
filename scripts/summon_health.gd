extends RefCounted
## 管理召唤物独立生命、仇恨选择与弹丸承伤；单位死亡由召唤更新统一移除，不在敌人遍历中删数组。

## 为新召唤物建立生命，旧机制夹具缺少字段时也可安全补齐，不改变已有生命。
## @param game 本局战场，生命成长读取英雄等级与召唤技能等级。
## @param pet 召唤物字典，位置与寿命由召唤模块管理。
func ensure(game: Node2D, pet: Dictionary) -> void:
	if pet.has("hp"): return
	pet.max_hp = 30.0 + game.hero.level * 3.0 + game.hero.skill_levels[0] * 4.0
	pet.hp = pet.max_hp
	pet.hurt_time = 0.0

## 查找指定距离内最近的存活召唤物，已死亡单位不能继续吸收攻击。
## @param pets 当前地图召唤物数组。
## @param pos 敌人或弹丸的位置，单位像素。
## @param radius 最大搜索距离，单位像素。
## @return 最近目标的字典引用；无有效目标返回空字典。
func nearest(pets: Array, pos: Vector2, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var distance := radius
	for pet in pets:
		if pet.get("hp", 1.0) <= 0.0 or pet.life <= 0.0: continue
		var value: float = pos.distance_to(pet.pos)
		if value <= distance:
			distance = value
			best = pet
	return best

## 结算召唤物承伤，灵体护佑期间减伤四分之一；不会给玩家发放任何击杀奖励。
## @param game 本局战场，提供护佑状态。
## @param pet 被击中的对象引用，下一次召唤更新统一处理死亡。
## @param amount 原始伤害，非正数不改变生命。
## @return 实际扣除的生命。
func damage(game: Node2D, pet: Dictionary, amount: float) -> float:
	ensure(game, pet)
	if pet.hp <= 0.0 or amount <= 0.0: return 0.0
	var actual: float = minf(pet.hp, amount * (0.75 if game.hero.ward_time > 0.0 else 1.0))
	pet.hp -= actual
	pet.hurt_time = 0.18
	return actual

## 用召唤物半径截获敌方弹丸，命中后只结算一次，不再继续伤害英雄或炮塔。
## @param game 本局战场。
## @param bullet 已推进到本帧位置的真实敌方弹丸。
## @return 命中存活召唤物并消费弹丸时返回 true。
func intercept(game: Node2D, bullet: Dictionary) -> bool:
	var pet := nearest(game.combat_builds.familiars, bullet.pos, bullet.get("radius", 8.0) + 12.0)
	if pet.is_empty(): return false
	damage(game, pet, bullet.damage)
	return true
