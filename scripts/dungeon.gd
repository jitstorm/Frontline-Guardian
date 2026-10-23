extends Node2D
## 哥布林营地的独立战斗场景；基地状态保存在父节点，副本内只改变本局英雄生命和成长。

signal reward_collected(item_id: String)
signal retreat_requested

const HeroRPG = preload("res://scripts/hero_rpg.gd")
const UI_FONT = preload("res://assets/fonts/NotoSansSC-VF.ttf")
const HERO_WARRIOR = preload("res://assets/kenney/tile_0085.png")
const HERO_MAGE = preload("res://assets/kenney/tile_0084.png")
const GOBLIN = preload("res://assets/kenney/tile_0108.png")
const GOBLIN_ELITE = preload("res://assets/kenney/tile_0110.png")
const GOBLIN_BOSS = preload("res://assets/kenney/tile_0122.png")
const LOOT_ART = preload("res://assets/kenney/tile_0082.png")
const FLOOR_ART = preload("res://assets/kenney/tile_0049.png")
const ARENA := Rect2(35, 95, 1210, 580)
## 掉落按所选职业决定，让首次副本奖励能立即参与对应技能构筑。
var loot_id := ""

## 父节点持有本局唯一的金币、英雄成长和炮塔状态。
var game: Node2D
## 副本内独立的英雄坐标；返回基地后恢复基地场景的位置。
var hero_pos := Vector2(170, 375)
var enemies: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var hostile_bullets: Array[Dictionary] = []
## 怪物真实死亡后保留的短暂淡出帧，不再参与副本战斗。
var death_frames: Array[Dictionary] = []
var fire_timer := 0.0
var reward_pos := Vector2.ZERO
## 只有 Boss 生命真实归零后才置位，防止提前领取。
var reward_spawned := false
## 拾取后置位并发射一次奖励信号，父节点也会独立防重。
var reward_taken := false
var notice := ""

## 初始化固定营地队列；小 Boss 必须被真实伤害击败后才生成战利品。
func _ready() -> void:
	loot_id = "berserker_mark" if game.hero.hero_id == "berserker" else "frost_focus"
	enemies = [
		make_goblin(Vector2(470, 225), "grunt", 75.0, 7.0),
		make_goblin(Vector2(590, 500), "grunt", 75.0, 7.0),
		make_goblin(Vector2(715, 270), "grunt", 75.0, 7.0),
		make_goblin(Vector2(850, 510), "elite", 170.0, 12.0),
		make_goblin(Vector2(1050, 365), "boss", 340.0, 16.0)
	]
	queue_redraw()

## 创建副本敌人的生命、攻击和冷却字段，供逐帧战斗结算使用。
## @param pos 敌人的初始位置，单位为画面像素。
## @param kind 普通、精英或小 Boss 类型。
## @param hp 初始及生命上限。
## @param damage 命中英雄时的基础伤害。
## @return 可直接由本场景更新的敌人数据。
func make_goblin(pos: Vector2, kind: String, hp: float, damage: float) -> Dictionary:
	return {"pos": pos, "kind": kind, "hp": hp, "max_hp": hp, "damage": damage, "attack_timer": 0.7, "windup": 0.0, "aim": Vector2.ZERO, "slow_time": 0.0}

## 推进副本中的移动、射击、怪物攻击和拾取；基地的八夜循环在此期间停止。
## @param delta 本帧经过的秒数。
func _process(delta: float) -> void:
	if game == null: return
	# 1. 仅推进副本内的英雄、怪物和弹丸，基地的波次与炮塔保持暂停。
	game.hero.tick(delta)
	for i in range(death_frames.size() - 1, -1, -1):
		death_frames[i].time -= delta
		if death_frames[i].time <= 0.0: death_frames.remove_at(i)
	var move: Vector2 = game.movement_vector()
	hero_pos = (hero_pos + move * game.hero.stats().speed * delta).clamp(ARENA.position + Vector2(15, 15), ARENA.end - Vector2(15, 15))
	fire_timer = maxf(0.0, fire_timer - delta)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and fire_timer <= 0.0 and not reward_spawned:
		fire_at(get_global_mouse_position())
	update_enemies(delta)
	update_bullets(delta)
	# 2. 战利品必须由玩家走到 Boss 掉落点拾取；死亡时仅撤退，不发奖。
	if reward_spawned and not reward_taken and hero_pos.distance_to(reward_pos) < 35.0:
		reward_taken = true
		reward_collected.emit(loot_id)
	if game.player_hp <= 0.0:
		game.player_hp = 1.0
		retreat_requested.emit()
	queue_redraw()

## 从英雄当前位置发射有飞行和碰撞的普通攻击弹丸。
## @param aim 鼠标瞄准的世界坐标。
func fire_at(aim: Vector2) -> void:
	var direction := (aim - hero_pos).normalized()
	if direction == Vector2.ZERO: return
	bullets.append({"pos": hero_pos, "velocity": direction * 650.0, "life": 1.5, "damage": game.player_damage, "radius": 6.0})
	fire_timer = 0.19 / (game.gun_rate_multiplier * game.hero.stats().rate)

## 施放当前英雄的副本技能；伤害、减速与冷却读取同一英雄成长实例。
## @param index Q/W/E/R 的技能索引。
## @param aim 玩家鼠标指定的释放方向。
## @return 实际释放并进入冷却时返回 true。
func cast_skill(index: int, aim: Vector2) -> bool:
	if index < 0 or index >= 4 or game.hero.cooldowns[index] > 0.0 or game.hero.skill_levels[index] <= 0: return false
	var direction := (aim - hero_pos).normalized()
	if direction == Vector2.ZERO: direction = Vector2.RIGHT
	var center := hero_pos
	var radius: float = [90.0, 130.0, 115.0, 200.0][index]
	if game.hero.hero_id == "frost_mage" and index == 0: center += direction * 140.0; radius = 55.0
	if game.hero.hero_id == "frost_mage" and index == 3: center += direction * 145.0
	if game.hero.hero_id == "berserker" and index == 2:
		hero_pos = (hero_pos + direction * 105.0).clamp(ARENA.position, ARENA.end)
		center = hero_pos
	if game.hero.hero_id == "berserker" and index == 1: game.hero.buff_time = 5.0
	if game.hero.hero_id == "frost_mage" and index == 2: game.hero.ward_time = 5.0
	if game.hero.has_effect("wide_sweep") and game.hero.hero_id == "berserker" and index == 0: radius *= 1.55
	if game.hero.has_effect("frost_burst") and game.hero.hero_id == "frost_mage" and index == 1: radius *= 1.4
	var power: float = game.hero.skill_damage(index)
	if game.hero.has_effect("rage_chain") and game.hero.hero_id == "berserker" and index == 2: power *= 1.45
	for i in range(enemies.size() - 1, -1, -1):
		if enemies[i].pos.distance_to(center) > radius + 18.0: continue
		if game.hero.hero_id == "berserker" and index == 0 and (enemies[i].pos - hero_pos).normalized().dot(direction) < 0.0: continue
		damage_enemy(i, power)
		if i < enemies.size() and game.hero.hero_id == "frost_mage":
			enemies[i].slow_time = 2.5
	if game.hero.hero_id == "berserker" and index == 1: game.player_hp = minf(game.max_player_hp, game.player_hp + 12.0)
	if game.hero.hero_id == "frost_mage" and index == 2: game.player_hp = minf(game.max_player_hp, game.player_hp + 6.0)
	game.hero.cooldowns[index] = [4.0, 9.0, 8.0, 22.0][index] if game.hero.hero_id == "berserker" else [3.5, 10.0, 9.0, 23.0][index]
	return true

## 扣除真实敌人生命并处理击杀；Boss 击杀才创建可拾取奖励。
## @param index 当前敌人数组索引。
## @param damage 本次结算伤害。
func damage_enemy(index: int, damage: float) -> void:
	if index < 0 or index >= enemies.size(): return
	var enemy := enemies[index]
	enemy.hp -= damage * (0.75 if enemy.kind == "elite" else 1.0)
	enemy.hit_time = 0.16
	if enemy.hp > 0.0:
		enemies[index] = enemy
		return
	enemies.remove_at(index)
	death_frames.append({"pos": enemy.pos, "kind": enemy.kind, "time": 0.35})
	game.kills += 1
	game.gold += 8 if enemy.kind == "grunt" else 20 if enemy.kind == "elite" else 45
	if game.hero.gain_xp(12 if enemy.kind == "grunt" else 28 if enemy.kind == "elite" else 60) > 0: game.sync_hero_stats()
	if enemy.kind == "boss" and not reward_spawned:
		reward_spawned = true
		reward_pos = enemy.pos
		notice = "首领已击败！靠近发光战利品领取奖励。"

## 怪物追逐英雄，近战有攻击前摇，小 Boss 发射可见弹丸。
## @param delta 本帧经过的秒数。
func update_enemies(delta: float) -> void:
	for i in enemies.size():
		var enemy := enemies[i]
		enemy.hit_time = maxf(0.0, enemy.get("hit_time", 0.0) - delta)
		enemy.attack_timer = maxf(0.0, enemy.attack_timer - delta)
		enemy.slow_time = maxf(0.0, enemy.slow_time - delta)
		if enemy.windup > 0.0:
			enemy.windup -= delta
			if enemy.windup <= 0.0:
				if enemy.kind == "boss":
					var direction: Vector2 = (enemy.aim - enemy.pos).normalized()
					hostile_bullets.append({"pos": enemy.pos, "velocity": direction * 310.0, "life": 2.0, "damage": enemy.damage})
				elif enemy.pos.distance_to(hero_pos) < 47.0:
					game.player_hp -= maxf(1.0, enemy.damage - game.player_armor - (5.0 if game.hero.ward_time > 0.0 else 0.0))
		elif enemy.attack_timer <= 0.0 and enemy.pos.distance_to(hero_pos) < (260.0 if enemy.kind == "boss" else 42.0):
			enemy.windup = 0.65 if enemy.kind == "boss" else 0.32
			enemy.aim = hero_pos
			enemy.attack_timer = 1.8 if enemy.kind == "boss" else 1.1
		else:
			var speed := 68.0 if enemy.kind == "boss" else 95.0 if enemy.kind == "elite" else 115.0
			if enemy.slow_time > 0.0: speed *= 0.45
			enemy.pos = enemy.pos.move_toward(hero_pos, speed * delta)
		enemies[i] = enemy

## 推进双方实体弹丸并以半径碰撞结算伤害和闪避。
## @param delta 本帧经过的秒数。
func update_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var bullet := bullets[i]
		bullet.pos += bullet.velocity * delta
		bullet.life -= delta
		var consumed: bool = bullet.life <= 0.0
		for j in range(enemies.size() - 1, -1, -1):
			if bullet.pos.distance_to(enemies[j].pos) < 25.0:
				damage_enemy(j, bullet.damage)
				consumed = true
				break
		if consumed: bullets.remove_at(i)
		else: bullets[i] = bullet
	for i in range(hostile_bullets.size() - 1, -1, -1):
		var bullet := hostile_bullets[i]
		bullet.pos += bullet.velocity * delta
		bullet.life -= delta
		if bullet.pos.distance_to(hero_pos) < 23.0:
			if game.dodge_timer <= 0.0: game.player_hp -= maxf(1.0, bullet.damage - game.player_armor - (5.0 if game.hero.ward_time > 0.0 else 0.0))
			hostile_bullets.remove_at(i)
		elif bullet.life <= 0.0: hostile_bullets.remove_at(i)
		else: hostile_bullets[i] = bullet

## 绘制副本、敌人血条、Boss 预警、弹丸和拾取物，便于玩家确认真实战斗状态。
func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("17251e"))
	draw_rect(ARENA, Color("294432"))
	# 副本地面复用同系列图块并染成林地色，避免角色与场景风格断裂。
	for x in range(40, 1240, 40):
		for y in range(100, 660, 40):
			draw_texture_rect(FLOOR_ART, Rect2(x, y, 40, 40), false, Color("6d9370"))
	for i in 10:
		draw_circle(Vector2(120 + i * 115, 140 + (i % 3) * 210), 25.0, Color("31543b"))
	var font := UI_FONT
	draw_string(font, Vector2(35, 40), "哥布林营地｜金币 %d｜生命 %d/%d｜Esc 撤退" % [game.gold, ceili(game.player_hp), ceili(game.max_player_hp)], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, Vector2(35, 72), "方向键移动  鼠标射击  Q/W/E/R 技能  F 闪避", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("d7e7c6"))
	for enemy in enemies:
		var color := Color("99cb70") if enemy.kind == "grunt" else Color("d7a75d") if enemy.kind == "elite" else Color("e66565")
		var radius := 19.0 if enemy.kind == "grunt" else 27.0 if enemy.kind == "elite" else 38.0
		# 普通怪、精英与首领共用同一画风；蓄力时用颜色反馈区分攻击阶段。
		var art: Texture2D = GOBLIN if enemy.kind == "grunt" else GOBLIN_ELITE if enemy.kind == "elite" else GOBLIN_BOSS
		var bob := sin(Time.get_ticks_msec() * 0.009 + enemy.pos.x) * 2.0
		draw_texture_rect(art, Rect2(enemy.pos + Vector2(-radius, -radius + bob), Vector2(radius * 2.0, radius * 2.0)), false, Color("ff8e8e") if enemy.get("hit_time", 0.0) > 0.0 else Color.WHITE if enemy.windup <= 0.0 else color)
		draw_rect(Rect2(enemy.pos + Vector2(-radius, -radius - 11), Vector2(radius * 2.0 * enemy.hp / enemy.max_hp, 5)), Color("ffe074"))
		if enemy.windup > 0.0: draw_line(enemy.pos, enemy.aim, Color("ff7777"), 2.0)
	# 死亡帧与真实敌人数组隔离，奖励仍只由实际击杀路径发放一次。
	for frame in death_frames:
		var art: Texture2D = GOBLIN if frame.kind == "grunt" else GOBLIN_ELITE if frame.kind == "elite" else GOBLIN_BOSS
		var size: float = 42.0 * frame.time / 0.35
		draw_texture_rect(art, Rect2(frame.pos - Vector2(size, size) / 2.0, Vector2(size, size)), false, Color(1, 1, 1, frame.time / 0.35))
	for bullet in bullets: draw_circle(bullet.pos, 6.0, Color("ffe074"))
	for bullet in hostile_bullets: draw_circle(bullet.pos, 8.0, Color("ff7777"))
	draw_texture_rect(HERO_MAGE if game.hero.hero_id == "frost_mage" else HERO_WARRIOR, Rect2(hero_pos - Vector2(22, 22), Vector2(44, 44)), false)
	if reward_spawned and not reward_taken:
		draw_texture_rect(LOOT_ART, Rect2(reward_pos - Vector2(22, 22), Vector2(44, 44)), false)
		draw_string(font, reward_pos + Vector2(28, 0), "史诗战利品", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		draw_rect(Rect2(320, 595, 640, 65), Color("182b41"))
		draw_string(font, Vector2(342, 630), "奖励：%s——靠近发光掉落物领取" % HeroRPG.ITEMS[loot_id].name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("e7a6ff"))
	if notice != "": draw_string(font, Vector2(320, 680), notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("ffe074"))
