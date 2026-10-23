extends Node2D
## 管理八夜守卫战的角色、道路敌人、炮塔和波间强化；核心被毁或角色阵亡时结束本局。

const PATH: Array[Vector2] = [Vector2(-30, 350), Vector2(230, 350), Vector2(230, 520), Vector2(550, 520), Vector2(550, 250), Vector2(880, 250), Vector2(880, 350), Vector2(1190, 350)]
const CORE_POS := Vector2(1190, 350)
const PLAYER_SPEED := 255.0
const BULLET_SPEED := 650.0
const MAX_WAVES := 8
const BG := Color("101a29")
const ROAD := Color("34475a")

var upgrade_pool: Array[String] = ["生命补给", "枪械增幅", "炮塔增幅", "核心修复", "移动训练"]
var rng := RandomNumberGenerator.new()
var player_pos := Vector2(1080, 530)
var player_hp := 100.0
var max_player_hp := 100.0
var core_hp := 120.0
var max_core_hp := 120.0
var gold := 100
var wave := 0
var state := "ready"
var enemies: Array[Dictionary] = []
var towers: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var spawn_left := 0
var spawned_this_wave := 0
var spawn_timer := 0.0
var fire_timer := 0.0
var selected_tower := 0
var player_damage := 16.0
var tower_multiplier := 1.0
var move_multiplier := 1.0
var upgrade_choices: Array[String] = []

## 初始化随机源和首局提示；逻辑状态由本节点统一维护。
func _ready() -> void:
	rng.randomize()
	queue_redraw()

## 推进角色、敌人、炮塔与弹丸；结算后停止所有战斗更新。
## @param delta 距上一帧的秒数，所有移动与冷却均按此时间推进。
func _process(delta: float) -> void:
	if state == "won" or state == "lost":
		queue_redraw()
		return
	move_player(delta)
	if state == "fighting":
		update_spawning(delta)
		update_enemies(delta)
		update_towers(delta)
		update_bullets(delta)
		shoot_player(delta)
		if core_hp <= 0.0 or player_hp <= 0.0:
			state = "lost"
		elif spawn_left == 0 and enemies.is_empty():
			if wave == MAX_WAVES:
				state = "won"
			else:
				state = "upgrade"
				roll_upgrades()
	queue_redraw()

## 处理移动以外的输入：建造、开波、强化和重新开始。
## @param event 本帧 Godot 输入事件。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: selected_tower = 1
			KEY_2: selected_tower = 2
			KEY_SPACE:
				if state == "ready": start_wave()
			KEY_Q:
				if state == "upgrade": apply_upgrade(upgrade_choices[0])
			KEY_E:
				if state == "upgrade": apply_upgrade(upgrade_choices[1])
			KEY_R:
				if state == "won" or state == "lost": get_tree().reload_current_scene()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			selected_tower = 0
		elif event.button_index == MOUSE_BUTTON_LEFT and selected_tower > 0:
			build_tower(get_global_mouse_position())
	queue_redraw()

## 按当前键盘方向移动玩家并限制在战场内。
## @param delta 本帧经过的秒数。
func move_player(delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	player_pos += direction * PLAYER_SPEED * move_multiplier * delta
	player_pos = player_pos.clamp(Vector2(22, 92), Vector2(1258, 695))

## 返回指定波的敌人总数，供开波和测试共同使用。
## @param number 从 1 开始的波次编号。
## @return 此波需要生成的敌人数量。
func wave_enemy_count(number: int) -> int:
	return 4 + number * 2

## 根据夜次和生成顺序安排敌人类型；第 4 夜的精英和第 8 夜的 Boss 固定在最后登场。
## @param night 当前夜次，从 1 开始。
## @param index 当前夜已生成的敌人数量，从 0 开始。
## @return 用于生成属性和攻击行为的敌人类型。
func enemy_kind_for(night: int, index: int) -> String:
	if night == 8 and index == wave_enemy_count(night) - 1:
		return "boss"
	if night == 4 and index == wave_enemy_count(night) - 1:
		return "elite"
	if night >= 5 and index % 5 == 3:
		return "ranged"
	if night >= 3 and index % 4 == 2:
		return "armored"
	if night >= 2 and index % 3 == 1:
		return "runner"
	return "grunt"

## 开始下一波并重置生成计时；只有准备状态能开波。
func start_wave() -> void:
	if state != "ready" or wave >= MAX_WAVES:
		return
	wave += 1
	spawn_left = wave_enemy_count(wave)
	spawned_this_wave = 0
	spawn_timer = 0.0
	state = "fighting"

## 以固定间隔生成敌人，避免整波同时堆叠在入口。
## @param delta 本帧经过的秒数。
func update_spawning(delta: float) -> void:
	if spawn_left == 0:
		return
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		# 类型按夜次逐步解锁，精英和 Boss 只在对应事件夜出现。
		var kind := enemy_kind_for(wave, spawned_this_wave)
		var hp := 34.0 + wave * 14.0
		var speed := 65.0 + wave * 12.0
		var radius := 17.0
		var reward := 12
		if kind == "runner":
			hp *= 0.65
			speed *= 1.55
			radius = 14.0
			reward = 15
		elif kind == "armored":
			hp *= 1.7
			speed *= 0.7
			radius = 20.0
			reward = 22
		elif kind == "ranged":
			hp *= 0.8
			reward = 20
		elif kind == "elite":
			hp *= 5.0
			speed *= 0.7
			radius = 25.0
			reward = 60
		elif kind == "boss":
			hp *= 13.0
			speed *= 0.48
			radius = 35.0
			reward = 200
		enemies.append({"pos": PATH[0], "segment": 1, "hp": hp, "max_hp": hp, "speed": speed, "attack_timer": 0.0, "kind": kind, "radius": radius, "reward": reward})
		spawn_left -= 1
		spawned_this_wave += 1
		spawn_timer = 1.15

## 沿折线推进敌人；靠近玩家时先攻击玩家，抵达核心后持续攻击核心。
## @param delta 本帧经过的秒数。
func update_enemies(delta: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var enemy := enemies[i]
		var pos: Vector2 = enemy.pos
		var timer: float = maxf(0.0, enemy.attack_timer - delta)
		if enemy.kind == "ranged" and pos.distance_to(player_pos) < 180.0:
			if timer <= 0.0:
				player_hp -= 6.0
				timer = 1.35
		elif pos.distance_to(player_pos) < enemy.radius + 15.0:
			if timer <= 0.0:
				player_hp -= 18.0 if enemy.kind == "boss" else 9.0
				timer = 0.9
		elif enemy.segment >= PATH.size():
			if timer <= 0.0:
				core_hp -= 30.0 if enemy.kind == "boss" else 16.0 if enemy.kind == "elite" else 11.0
				timer = 1.0
		else:
			var remaining: float = enemy.speed * delta
			while remaining > 0.0 and enemy.segment < PATH.size():
				var target: Vector2 = PATH[enemy.segment]
				var distance := pos.distance_to(target)
				if distance <= remaining:
					pos = target
					remaining -= distance
					enemy.segment += 1
				else:
					pos = pos.move_toward(target, remaining)
					remaining = 0.0
		enemy.pos = pos
		enemy.attack_timer = timer
		enemies[i] = enemy

## 玩家按住左键时朝鼠标射击；建造模式下左键只放置炮塔。
## @param delta 本帧经过的秒数。
func shoot_player(delta: float) -> void:
	fire_timer = maxf(0.0, fire_timer - delta)
	if selected_tower != 0 or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or fire_timer > 0.0:
		return
	var aim := get_global_mouse_position() - player_pos
	if aim.length() < 4.0:
		return
	bullets.append({"pos": player_pos, "velocity": aim.normalized() * BULLET_SPEED, "damage": player_damage, "life": 1.6, "radius": 5.0, "color": Color("ffe074")})
	fire_timer = 0.19

## 炮塔自动选取范围内最近敌人；速射塔与重炮塔有不同射程、伤害及射速。
## @param delta 本帧经过的秒数。
func update_towers(delta: float) -> void:
	for i in towers.size():
		var tower := towers[i]
		tower.cooldown = maxf(0.0, tower.cooldown - delta)
		if tower.cooldown > 0.0:
			towers[i] = tower
			continue
		var target := -1
		var best: float = tower.range
		for j in enemies.size():
			var distance: float = tower.pos.distance_to(enemies[j].pos)
			if distance < best:
				best = distance
				target = j
		if target >= 0:
			var direction: Vector2 = (enemies[target].pos - tower.pos).normalized()
			bullets.append({"pos": tower.pos, "velocity": direction * 520.0, "damage": tower.damage * tower_multiplier, "life": 1.0, "radius": 6.0 if tower.kind == 1 else 10.0, "color": Color("7fffd4") if tower.kind == 1 else Color("ff9b71")})
			tower.cooldown = 0.42 if tower.kind == 1 else 1.15
		towers[i] = tower

## 更新弹丸并执行命中结算；倒序删除防止跳过元素。
## @param delta 本帧经过的秒数。
func update_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var bullet := bullets[i]
		bullet.pos += bullet.velocity * delta
		bullet.life -= delta
		var hit := -1
		for j in enemies.size():
			if bullet.pos.distance_to(enemies[j].pos) < enemies[j].radius + bullet.radius:
				hit = j
				break
		if hit >= 0:
			var enemy := enemies[hit]
			# 重甲减伤在命中结算时统一应用，避免玩家枪械和炮塔攻击语义不一致。
			enemy.hp -= bullet.damage * (0.55 if enemy.kind == "armored" else 1.0)
			if enemy.hp <= 0.0:
				enemies.remove_at(hit)
				gold += enemy.reward
			else:
				enemies[hit] = enemy
			bullets.remove_at(i)
		elif bullet.life <= 0.0 or not Rect2(-50, -50, 1380, 820).has_point(bullet.pos):
			bullets.remove_at(i)
		else:
			bullets[i] = bullet

## 检查目标是否远离道路、核心、玩家与其他塔，避免堵住通路。
## @param pos 待放置炮塔的世界坐标，单位为画面像素。
## @return 可以安全建造时返回 true。
func can_build_at(pos: Vector2) -> bool:
	if not Rect2(35, 105, 1210, 575).has_point(pos) or pos.distance_to(CORE_POS) < 66.0 or pos.distance_to(player_pos) < 38.0:
		return false
	for i in range(PATH.size() - 1):
		var nearest := Geometry2D.get_closest_point_to_segment(pos, PATH[i], PATH[i + 1])
		if pos.distance_to(nearest) < 56.0:
			return false
	for tower in towers:
		if pos.distance_to(tower.pos) < 52.0:
			return false
	return true

## 扣费并建造所选炮塔；位置和金币不足时不改变战局。
## @param pos 玩家点击的世界坐标。
func build_tower(pos: Vector2) -> void:
	if state == "won" or state == "lost" or not can_build_at(pos):
		return
	var cost := 40 if selected_tower == 1 else 65
	if gold < cost:
		return
	gold -= cost
	towers.append({"pos": pos, "kind": selected_tower, "range": 180.0 if selected_tower == 1 else 225.0, "damage": 11.0 if selected_tower == 1 else 34.0, "cooldown": 0.0})

## 从强化池中抽取两个不同选项，等待玩家在波间作出选择。
func roll_upgrades() -> void:
	var options := upgrade_pool.duplicate()
	options.shuffle()
	upgrade_choices = [options[0], options[1]]

## 应用波间强化，并让下一波进入待启动状态。
## @param choice 玩家选中的强化名称，必须属于本次抽取结果。
func apply_upgrade(choice: String) -> void:
	if state != "upgrade" or not upgrade_choices.has(choice):
		return
	match choice:
		"生命补给":
			max_player_hp += 20.0
			player_hp = minf(max_player_hp, player_hp + 45.0)
		"枪械增幅": player_damage += 8.0
		"炮塔增幅": tower_multiplier += 0.3
		"核心修复": core_hp = minf(max_core_hp, core_hp + 45.0)
		"移动训练": move_multiplier += 0.18
	upgrade_choices.clear()
	state = "ready"

## 绘制战场、单位、状态栏及波间选择，素材缺失时也能完整运行。
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), BG)
	for x in range(0, 1280, 40):
		draw_line(Vector2(x, 85), Vector2(x, 720), Color("192839"), 1.0)
	for y in range(100, 720, 40):
		draw_line(Vector2(0, y), Vector2(1280, y), Color("192839"), 1.0)
	for i in range(PATH.size() - 1):
		draw_line(PATH[i], PATH[i + 1], ROAD, 76.0, true)
		draw_line(PATH[i], PATH[i + 1], Color("698095"), 2.0, true)
	draw_circle(CORE_POS, 37.0, Color("638cff"))
	draw_circle(CORE_POS, 23.0, Color("c6d4ff"))
	for tower in towers:
		draw_circle(tower.pos, 21.0, Color("247e79") if tower.kind == 1 else Color("995642"))
		draw_circle(tower.pos, 12.0, Color("7fffd4") if tower.kind == 1 else Color("ff9b71"))
	for enemy in enemies:
		var color := Color("e46d75")
		if enemy.kind == "runner": color = Color("f5ba69")
		if enemy.kind == "armored": color = Color("779cae")
		if enemy.kind == "ranged": color = Color("c98bbb")
		if enemy.kind == "elite": color = Color("ae79e9")
		if enemy.kind == "boss": color = Color("ec5370")
		draw_circle(enemy.pos, enemy.radius, color)
		draw_rect(Rect2(enemy.pos + Vector2(-enemy.radius, -enemy.radius - 9.0), Vector2(enemy.radius * 2.0 * enemy.hp / enemy.max_hp, 4)), Color("ffdc7d"))
	for bullet in bullets:
		draw_circle(bullet.pos, bullet.radius, bullet.color)
	draw_circle(player_pos, 17.0, Color("ffe074"))
	draw_line(player_pos, player_pos + (get_global_mouse_position() - player_pos).normalized() * 27.0, Color.WHITE, 5.0)
	draw_rect(Rect2(0, 0, 1280, 85), Color("182b41"))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(25, 33), "FRONTLINE GUARDIAN", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color.WHITE)
	draw_string(font, Vector2(25, 65), "WASD Move  |  Mouse Fire  |  1 Rapid $40  |  2 Cannon $65  |  Right Click Cancel", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("b6c8d7"))
	draw_string(font, Vector2(825, 32), "Night %d/%d   Gold %d" % [wave, MAX_WAVES, gold], HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("ffe074"))
	draw_string(font, Vector2(825, 62), "HP %d/%d   Core %d/%d" % [ceili(player_hp), ceili(max_player_hp), ceili(core_hp), ceili(max_core_hp)], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	if selected_tower > 0:
		var mouse := get_global_mouse_position()
		draw_arc(mouse, 21.0, 0.0, TAU, 36, Color("7fffd4") if can_build_at(mouse) else Color("ff7777"), 2.0)
	var message := "SPACE: Start wave" if state == "ready" else ""
	if state == "upgrade": message = "Choose upgrade: Q  %s      E  %s" % upgrade_choices
	if state == "won": message = "VICTORY!  Eight nights survived.  Press R to restart"
	if state == "lost": message = "DEFEAT!  Press R to restart"
	if message != "":
		draw_rect(Rect2(240, 635, 800, 55), Color("253e59"))
		draw_string(font, Vector2(270, 670), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color.WHITE)
