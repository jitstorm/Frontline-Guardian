extends Node2D
## 管理八夜守卫战的角色、道路敌人、炮塔和波间强化；核心被毁或角色阵亡时结束本局。

const PATH: Array[Vector2] = [Vector2(-30, 350), Vector2(230, 350), Vector2(230, 520), Vector2(550, 520), Vector2(550, 250), Vector2(880, 250), Vector2(880, 350), Vector2(1190, 350)]
const CORE_POS := Vector2(1190, 350)
const PLAYER_SPEED := 255.0
const BULLET_SPEED := 650.0
const MAX_WAVES := 8
const BG := Color("101a29")
const ROAD := Color("34475a")
const CELL_SIZE := 40.0
const GRID_SIZE := Vector2i(32, 18)
const START_CELL := Vector2i(0, 8)
const GOAL_CELL := Vector2i(29, 8)

var upgrade_pool: Array[String] = ["生命补给", "急救包", "枪械增幅", "快速扳机", "高速弹头", "冲击弹", "双重射击", "炮塔增幅", "射程扩展", "机械润滑", "核心修复", "核心加固", "移动训练", "赏金猎人", "军需补给", "防弹衣", "核心装甲", "塔体加固", "穿甲弹", "巨兽克星"]
var rng := RandomNumberGenerator.new()
var player_pos := Vector2(1080, 530)
var player_hp := 100.0
var max_player_hp := 100.0
var core_hp := 120.0
var max_core_hp := 120.0
var gold := 100
var kills := 0
var wave := 0
var state := "ready"
var enemies: Array[Dictionary] = []
var towers: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var hostile_bullets: Array[Dictionary] = []
var hit_texts: Array[Dictionary] = []
var impacts: Array[Dictionary] = []
var spawn_left := 0
var spawned_this_wave := 0
var spawn_timer := 0.0
var fire_timer := 0.0
var dodge_timer := 0.0
var dodge_cooldown := 0.0
var selected_tower := 0
var selected_tower_index := -1
var player_damage := 16.0
var tower_multiplier := 1.0
var move_multiplier := 1.0
var gun_rate_multiplier := 1.0
var bullet_speed_multiplier := 1.0
var bullet_knockback := 14.0
var multishot := false
var tower_range_bonus := 0.0
var tower_rate_multiplier := 1.0
var tower_hp_multiplier := 1.0
var gold_bonus := 0
var player_armor := 0.0
var core_armor := 0.0
var armor_penetration := 0.55
var boss_bonus := 1.0
var upgrade_choices: Array[String] = []
var navigation := AStarGrid2D.new()
var navigation_revision := 0

## 初始化随机源和首局提示；逻辑状态由本节点统一维护。
func _ready() -> void:
	rng.randomize()
	rebuild_navigation()
	queue_redraw()

## 把世界坐标映射到导航格；仅敌人的道路通行区域参与寻路。
## @param pos 世界坐标，单位为画面像素。
## @return 限制在地图内的导航格坐标。
func nav_cell(pos: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor(pos.x / CELL_SIZE)), 0, GRID_SIZE.x - 1), clampi(int(floor(pos.y / CELL_SIZE)), 0, GRID_SIZE.y - 1))

## 根据固定道路走廊和现存炮塔重建可通行网格，供敌人动态绕行。
func rebuild_navigation() -> void:
	navigation.region = Rect2i(Vector2i.ZERO, GRID_SIZE)
	navigation.cell_size = Vector2(CELL_SIZE, CELL_SIZE)
	navigation.offset = Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	navigation.update()
	for x in GRID_SIZE.x:
		for y in GRID_SIZE.y:
			var cell := Vector2i(x, y)
			var point := Vector2(x * CELL_SIZE + CELL_SIZE / 2.0, y * CELL_SIZE + CELL_SIZE / 2.0)
			var on_road := false
			for i in range(PATH.size() - 1):
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point, PATH[i], PATH[i + 1])) <= 78.0:
					on_road = true
					break
			# 重建时必须同时清除已拆除炮塔留下的阻塞标记。
			navigation.set_point_solid(cell, not on_road or y < 2 or y > 16)
	for tower in towers:
		navigation.set_point_solid(nav_cell(tower.pos))
	navigation_revision += 1
	for i in enemies.size():
		var enemy := enemies[i]
		enemy.route = route_from(enemy.pos)
		enemy.route_index = 0
		enemies[i] = enemy

## 从敌人当前位置计算到核心的网格路线；建筑变化后调用以绕开新障碍。
## @param pos 敌人当前世界坐标。
## @return 路线点数组；无路时返回空数组。
func route_from(pos: Vector2) -> PackedVector2Array:
	var start := nav_cell(pos)
	if navigation.is_point_solid(start):
		# 击退可能把敌人短暂推出可通行格，选择最近的开放格恢复寻路。
		var best := INF
		for x in range(maxi(0, start.x - 2), mini(GRID_SIZE.x, start.x + 3)):
			for y in range(maxi(0, start.y - 2), mini(GRID_SIZE.y, start.y + 3)):
				var candidate := Vector2i(x, y)
				if navigation.is_point_solid(candidate): continue
				var distance := pos.distance_to(Vector2(x * CELL_SIZE + 20.0, y * CELL_SIZE + 20.0))
				if distance < best:
					best = distance
					start = candidate
		if best == INF:
			return PackedVector2Array()
	return navigation.get_point_path(start, GOAL_CELL)

## 推进角色、敌人、炮塔与弹丸；结算后停止所有战斗更新。
## @param delta 距上一帧的秒数，所有移动与冷却均按此时间推进。
func _process(delta: float) -> void:
	if state == "won" or state == "lost":
		queue_redraw()
		return
	move_player(delta)
	dodge_timer = maxf(0.0, dodge_timer - delta)
	dodge_cooldown = maxf(0.0, dodge_cooldown - delta)
	update_feedback(delta)
	if state == "fighting":
		update_spawning(delta)
		update_enemies(delta)
		update_hostile_bullets(delta)
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
			KEY_U: upgrade_selected_tower()
			KEY_H: repair_selected_tower()
			KEY_X: sell_selected_tower()
			KEY_P: cycle_tower_priority()
			KEY_F: dodge()
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
			selected_tower_index = -1
		elif event.button_index == MOUSE_BUTTON_LEFT and state == "upgrade":
			var mouse := get_global_mouse_position()
			if Rect2(340, 545, 280, 110).has_point(mouse): apply_upgrade(upgrade_choices[0])
			elif Rect2(660, 545, 280, 110).has_point(mouse): apply_upgrade(upgrade_choices[1])
		elif event.button_index == MOUSE_BUTTON_LEFT and selected_tower > 0:
			build_tower(get_global_mouse_position())
		elif event.button_index == MOUSE_BUTTON_LEFT:
			selected_tower_index = tower_at(get_global_mouse_position())
	queue_redraw()

## 按当前键盘方向移动玩家并限制在战场内。
## @param delta 本帧经过的秒数。
func move_player(delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	player_pos += direction * PLAYER_SPEED * move_multiplier * delta
	player_pos = player_pos.clamp(Vector2(22, 92), Vector2(1258, 695))

## 朝移动方向短距离闪避；无移动输入时朝鼠标方向，短暂无敌用于躲避可见弹丸。
func dodge() -> void:
	if state != "fighting" or dodge_cooldown > 0.0:
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction == Vector2.ZERO:
		direction = (get_global_mouse_position() - player_pos).normalized()
	if direction == Vector2.ZERO:
		return
	player_pos = (player_pos + direction * 105.0).clamp(Vector2(22, 92), Vector2(1258, 695))
	dodge_timer = 0.22
	dodge_cooldown = 2.5
	impacts.append({"pos": player_pos, "time": 0.2, "color": Color("80deff")})

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
		var hp := 34.0 + wave * 18.0
		var speed := 65.0 + wave * 12.0
		var radius := 17.0
		var reward := 8
		if kind == "runner":
			hp *= 0.65
			speed *= 1.55
			radius = 14.0
			reward = 11
		elif kind == "armored":
			hp *= 1.7
			speed *= 0.7
			radius = 20.0
			reward = 16
		elif kind == "ranged":
			hp *= 0.8
			reward = 14
		elif kind == "elite":
			hp *= 5.0
			speed *= 0.7
			radius = 25.0
			reward = 42
		elif kind == "boss":
			hp *= 13.0
			speed *= 0.48
			radius = 35.0
			reward = 100
		enemies.append({"pos": Vector2(20, 340), "segment": 0, "route": route_from(Vector2(20, 340)), "route_index": 0, "hp": hp, "max_hp": hp, "speed": speed, "attack_timer": 0.0, "windup": 0.0, "target_kind": "", "aim": Vector2.ZERO, "kind": kind, "radius": radius, "reward": reward})
		spawn_left -= 1
		spawned_this_wave += 1
		spawn_timer = 1.15

## 沿动态路线推进敌人；攻击前摇锁定目标位置，闪避可使弹丸落空。
## @param delta 本帧经过的秒数。
func update_enemies(delta: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var enemy := enemies[i]
		var pos: Vector2 = enemy.pos
		enemy.attack_timer = maxf(0.0, enemy.attack_timer - delta)
		if enemy.windup > 0.0:
			enemy.windup -= delta
			if enemy.windup <= 0.0:
				resolve_enemy_attack(enemy)
		elif enemy.attack_timer <= 0.0:
			# 优先攻击靠近的玩家；远程敌人可转向炮塔，Boss 具有更远的弹幕预警。
			var ranged: bool = enemy.kind == "ranged" or enemy.kind == "boss"
			var range_to_player: float = 300.0 if enemy.kind == "boss" else 180.0 if ranged else enemy.radius + 15.0
			if pos.distance_to(player_pos) < range_to_player:
				enemy.target_kind = "player"
				enemy.aim = player_pos
				enemy.windup = 0.65 if enemy.kind == "boss" else 0.45 if ranged else 0.28
				enemy.attack_timer = enemy.windup + (1.8 if enemy.kind == "boss" else 1.35 if ranged else 0.9)
			elif enemy.kind == "ranged" and tower_at_range(pos, 155.0) >= 0:
				enemy.target_kind = "tower"
				enemy.aim = towers[tower_at_range(pos, 155.0)].pos
				enemy.windup = 0.45
				enemy.attack_timer = 1.8
			elif pos.distance_to(CORE_POS) < 34.0:
				enemy.target_kind = "core"
				enemy.aim = CORE_POS
				enemy.windup = 0.35
				enemy.attack_timer = 1.35
		if enemy.windup <= 0.0 and enemy.target_kind == "":
			var remaining: float = enemy.speed * delta
			var route: PackedVector2Array = enemy.route
			while remaining > 0.0 and enemy.route_index < route.size():
				var target: Vector2 = route[enemy.route_index]
				var distance := pos.distance_to(target)
				if distance <= remaining:
					pos = target
					remaining -= distance
					enemy.route_index += 1
				else:
					pos = pos.move_toward(target, remaining)
					remaining = 0.0
			enemy.segment = enemy.route_index
		# 轻微分离重叠敌人，避免同一格内完全叠在一起。
		for j in enemies.size():
			if j == i: continue
			var offset: Vector2 = pos - enemies[j].pos
			if offset.length() > 0.1 and offset.length() < enemy.radius * 1.1:
				pos += offset.normalized() * minf(8.0 * delta, enemy.radius * 1.1 - offset.length())
		enemy.pos = pos
		enemies[i] = enemy

## 在前摇结束时结算近战，或发射沿预警方向飞行的敌方弹丸。
## @param enemy 前摇中的敌人数据，包含目标类型与锁定位置。
func resolve_enemy_attack(enemy: Dictionary) -> void:
	var target_kind: String = enemy.target_kind
	enemy.target_kind = ""
	if target_kind == "player" and (enemy.kind == "ranged" or enemy.kind == "boss"):
		var direction: Vector2 = (enemy.aim - enemy.pos).normalized()
		if direction == Vector2.ZERO: direction = Vector2.LEFT
		var count := 3 if enemy.kind == "boss" else 1
		for index in count:
			var spread := (index - 1) * 0.22 if count == 3 else 0.0
			hostile_bullets.append({"pos": enemy.pos, "velocity": direction.rotated(spread) * (360.0 if enemy.kind == "boss" else 300.0), "damage": 12.0 if enemy.kind == "boss" else 6.0, "life": 1.5, "radius": 9.0 if enemy.kind == "boss" else 7.0})
	elif target_kind == "tower":
		var direction: Vector2 = (enemy.aim - enemy.pos).normalized()
		hostile_bullets.append({"pos": enemy.pos, "velocity": direction * 300.0, "damage": 8.0, "life": 1.0, "radius": 7.0})
	elif target_kind == "player" and enemy.pos.distance_to(player_pos) < enemy.radius + 20.0 and dodge_timer <= 0.0:
		var damage: float = maxf(1.0, 9.0 - player_armor)
		player_hp -= damage
		add_damage_text(player_pos, damage, Color("ff7777"))
	elif target_kind == "core" and enemy.pos.distance_to(CORE_POS) < 42.0:
		var damage: float = maxf(1.0, (30.0 if enemy.kind == "boss" else 16.0 if enemy.kind == "elite" else 11.0) - core_armor)
		core_hp -= damage
		add_damage_text(CORE_POS, damage, Color("ff7777"))

## 推进敌方实体弹丸并检查玩家闪避、炮塔受损与弹丸寿命。
## @param delta 本帧经过的秒数。
func update_hostile_bullets(delta: float) -> void:
	var route_dirty := false
	for i in range(hostile_bullets.size() - 1, -1, -1):
		var bullet := hostile_bullets[i]
		bullet.pos += bullet.velocity * delta
		bullet.life -= delta
		var consumed := false
		if bullet.pos.distance_to(player_pos) < bullet.radius + 15.0:
			consumed = true
			if dodge_timer <= 0.0:
				var damage: float = maxf(1.0, bullet.damage - player_armor)
				player_hp -= damage
				add_damage_text(player_pos, damage, Color("ff7777"))
		else:
			var target := tower_at_range(bullet.pos, bullet.radius + 21.0)
			if target >= 0:
				consumed = true
				var tower := towers[target]
				tower.hp -= bullet.damage
				add_damage_text(tower.pos, bullet.damage, Color("ff7777"))
				if tower.hp <= 0.0:
					towers.remove_at(target)
					selected_tower_index = -1
					route_dirty = true
				else: towers[target] = tower
		if consumed or bullet.life <= 0.0 or not Rect2(-50, -50, 1380, 820).has_point(bullet.pos):
			hostile_bullets.remove_at(i)
		else:
			hostile_bullets[i] = bullet
	if route_dirty:
		rebuild_navigation()

## 玩家按住左键时朝鼠标射击；建造模式下左键只放置炮塔。
## @param delta 本帧经过的秒数。
func shoot_player(delta: float) -> void:
	fire_timer = maxf(0.0, fire_timer - delta)
	if selected_tower != 0 or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or fire_timer > 0.0:
		return
	var aim := get_global_mouse_position() - player_pos
	if aim.length() < 4.0:
		return
	var velocity := aim.normalized() * BULLET_SPEED * bullet_speed_multiplier
	bullets.append({"pos": player_pos, "velocity": velocity, "damage": player_damage, "life": 1.6, "radius": 5.0, "color": Color("ffe074"), "knockback": bullet_knockback})
	if multishot:
		bullets.append({"pos": player_pos, "velocity": velocity.rotated(0.17), "damage": player_damage * 0.7, "life": 1.6, "radius": 5.0, "color": Color("ffe074"), "knockback": bullet_knockback})
	impacts.append({"pos": player_pos + aim.normalized() * 24.0, "time": 0.12, "color": Color("ffe074")})
	fire_timer = 0.19 / gun_rate_multiplier

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
		var best := INF
		for j in enemies.size():
			var distance: float = tower.pos.distance_to(enemies[j].pos)
			if distance > tower.range + tower_range_bonus:
				continue
			var score := distance
			if tower.priority == "front": score = -float(enemies[j].segment) * 1000.0 - enemies[j].pos.x
			if tower.priority == "strong": score = -float(enemies[j].hp)
			if score < best:
				best = score
				target = j
		if target >= 0:
			var direction: Vector2 = (enemies[target].pos - tower.pos).normalized()
			bullets.append({"pos": tower.pos, "velocity": direction * 520.0, "damage": tower.damage * tower_multiplier, "life": 1.0, "radius": 6.0 if tower.kind == 1 else 10.0, "color": Color("7fffd4") if tower.kind == 1 else Color("ff9b71"), "knockback": 7.0 if tower.kind == 1 else 26.0})
			tower.cooldown = (0.42 if tower.kind == 1 else 1.15) / tower_rate_multiplier
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
			var dealt: float = bullet.damage * (maxf(0.55, armor_penetration) if enemy.kind == "armored" else 1.0) * (boss_bonus if enemy.kind == "boss" else 1.0)
			enemy.hp -= dealt
			enemy.pos -= bullet.velocity.normalized() * bullet.knockback
			add_damage_text(enemy.pos, dealt, Color("ffe074"))
			impacts.append({"pos": bullet.pos, "time": 0.2, "color": bullet.color})
			if enemy.hp <= 0.0:
				enemies.remove_at(hit)
				kills += 1
				gold += enemy.reward + gold_bonus
			else:
				enemies[hit] = enemy
			bullets.remove_at(i)
		elif bullet.life <= 0.0 or not Rect2(-50, -50, 1380, 820).has_point(bullet.pos):
			bullets.remove_at(i)
		else:
			bullets[i] = bullet

## 记录一次命中数字，显示实际结算伤害而非武器面板值。
## @param pos 命中位置，单位为画面像素。
## @param amount 扣除的生命值。
## @param color 区分我方和敌方伤害的颜色。
func add_damage_text(pos: Vector2, amount: float, color: Color) -> void:
	hit_texts.append({"pos": pos, "value": ceili(amount), "time": 0.65, "color": color})

## 逐帧消退枪口闪光、命中光圈和飘字，避免特效无限累积。
## @param delta 本帧经过的秒数。
func update_feedback(delta: float) -> void:
	for i in range(hit_texts.size() - 1, -1, -1):
		hit_texts[i].time -= delta
		hit_texts[i].pos.y -= 36.0 * delta
		if hit_texts[i].time <= 0.0:
			hit_texts.remove_at(i)
	for i in range(impacts.size() - 1, -1, -1):
		impacts[i].time -= delta
		if impacts[i].time <= 0.0:
			impacts.remove_at(i)

## 检查金币以外的建造条件，并临时封格确认入口及场上敌人仍能到达核心。
## @param pos 待放置炮塔的世界坐标，单位为画面像素。
## @return 可以安全建造时返回 true。
func can_build_at(pos: Vector2) -> bool:
	if not Rect2(35, 105, 1210, 575).has_point(pos) or pos.distance_to(CORE_POS) < 66.0 or pos.distance_to(player_pos) < 38.0:
		return false
	var cell := nav_cell(pos)
	if cell == START_CELL or cell == GOAL_CELL:
		return false
	for enemy in enemies:
		if pos.distance_to(enemy.pos) < 40.0:
			return false
	for tower in towers:
		if pos.distance_to(tower.pos) < 52.0:
			return false
	# 临时阻塞候选格，检查入口和场上所有敌人仍能到达核心。
	var was_solid := navigation.is_point_solid(cell)
	navigation.set_point_solid(cell)
	var reachable := not navigation.get_id_path(START_CELL, GOAL_CELL).is_empty()
	if reachable:
		for enemy in enemies:
			if route_from(enemy.pos).is_empty():
				reachable = false
				break
	navigation.set_point_solid(cell, was_solid)
	if not reachable:
		return false
	return true

## 扣费并建造所选炮塔；位置和金币不足时不改变战局。
## @param pos 玩家点击的世界坐标。
func build_tower(pos: Vector2) -> void:
	if state == "won" or state == "lost" or not can_build_at(pos):
		return
	var cost := 40 if selected_tower == 1 else 55
	if gold < cost:
		return
	gold -= cost
	towers.append({"pos": pos, "kind": selected_tower, "range": 180.0 if selected_tower == 1 else 225.0, "damage": 11.0 if selected_tower == 1 else 34.0, "cooldown": 0.0, "level": 1, "hp": 75.0 * tower_hp_multiplier, "max_hp": 75.0 * tower_hp_multiplier, "priority": "nearest", "spent": cost})
	selected_tower_index = towers.size() - 1
	rebuild_navigation()

## 查找点击位置内的炮塔，用于选中后管理。
## @param pos 世界坐标，单位为画面像素。
## @return 命中的炮塔索引；未命中返回 -1。
func tower_at(pos: Vector2) -> int:
	return tower_at_range(pos, 25.0)

## 查找指定距离内最近的炮塔，供玩家选择及远程敌人攻击使用。
## @param pos 查询中心的世界坐标。
## @param distance 最大查询距离，单位为画面像素。
## @return 最近炮塔索引；范围内没有炮塔时返回 -1。
func tower_at_range(pos: Vector2, distance: float) -> int:
	var result := -1
	var best := distance
	for i in towers.size():
		var current: float = pos.distance_to(towers[i].pos)
		if current < best:
			best = current
			result = i
	return result

## 花费金币提升所选炮塔的伤害、射程及耐久，最高三级。
func upgrade_selected_tower() -> void:
	if selected_tower_index < 0 or selected_tower_index >= towers.size(): return
	var tower := towers[selected_tower_index]
	var cost: int = 30 * tower.level
	if tower.level >= 3 or gold < cost: return
	gold -= cost
	tower.spent += cost
	tower.level += 1
	tower.damage *= 1.35
	tower.range += 20.0
	tower.max_hp += 25.0
	tower.hp += 25.0
	towers[selected_tower_index] = tower

## 花费 15 金币维修受损炮塔，未受损或金币不足时不扣费。
func repair_selected_tower() -> void:
	if selected_tower_index < 0 or selected_tower_index >= towers.size(): return
	var tower := towers[selected_tower_index]
	if tower.hp >= tower.max_hp or gold < 15: return
	gold -= 15
	tower.hp = minf(tower.max_hp, tower.hp + 35.0)
	towers[selected_tower_index] = tower

## 出售所选炮塔并返还累计投入的一半，用于调整防线。
func sell_selected_tower() -> void:
	if selected_tower_index < 0 or selected_tower_index >= towers.size(): return
	gold += int(towers[selected_tower_index].spent / 2)
	towers.remove_at(selected_tower_index)
	selected_tower_index = -1
	rebuild_navigation()

## 在最近、最前和高血量目标间循环炮塔攻击优先级。
func cycle_tower_priority() -> void:
	if selected_tower_index < 0 or selected_tower_index >= towers.size(): return
	var tower := towers[selected_tower_index]
	match tower.priority:
		"nearest": tower.priority = "front"
		"front": tower.priority = "strong"
		_: tower.priority = "nearest"
	towers[selected_tower_index] = tower

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
		"急救包":
			max_player_hp += 5.0
			player_hp = minf(max_player_hp, player_hp + 60.0)
		"枪械增幅": player_damage += 8.0
		"快速扳机": gun_rate_multiplier += 0.2
		"高速弹头": bullet_speed_multiplier += 0.25
		"冲击弹": bullet_knockback += 12.0
		"双重射击":
			if multishot: player_damage += 4.0
			else: multishot = true
		"炮塔增幅": tower_multiplier += 0.3
		"射程扩展": tower_range_bonus += 25.0
		"机械润滑": tower_rate_multiplier += 0.2
		"核心修复":
			max_core_hp += 5.0
			core_hp = minf(max_core_hp, core_hp + 45.0)
		"核心加固":
			max_core_hp += 30.0
			core_hp += 30.0
		"移动训练": move_multiplier += 0.18
		"赏金猎人": gold_bonus += 5
		"军需补给": gold += 45
		"防弹衣": player_armor += 2.0
		"核心装甲": core_armor += 3.0
		"塔体加固":
			tower_hp_multiplier += 0.25
			for tower in towers:
				tower.max_hp += 20.0
				tower.hp += 20.0
		"穿甲弹": armor_penetration = minf(1.0, armor_penetration + 0.2)
		"巨兽克星": boss_bonus += 0.3
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
	for i in towers.size():
		var tower := towers[i]
		draw_circle(tower.pos, 21.0, Color("247e79") if tower.kind == 1 else Color("995642"))
		draw_circle(tower.pos, 12.0, Color("7fffd4") if tower.kind == 1 else Color("ff9b71"))
		draw_rect(Rect2(tower.pos + Vector2(-20, -31), Vector2(40.0 * tower.hp / tower.max_hp, 3)), Color("7fffd4"))
		if i == selected_tower_index:
			draw_arc(tower.pos, 27.0, 0.0, TAU, 32, Color.WHITE, 2.0)
			draw_arc(tower.pos, tower.range + tower_range_bonus, 0.0, TAU, 72, Color("80deff", 0.55), 1.5)
	for enemy in enemies:
		var color := Color("e46d75")
		if enemy.kind == "runner": color = Color("f5ba69")
		if enemy.kind == "armored": color = Color("779cae")
		if enemy.kind == "ranged": color = Color("c98bbb")
		if enemy.kind == "elite": color = Color("ae79e9")
		if enemy.kind == "boss": color = Color("ec5370")
		draw_circle(enemy.pos, enemy.radius, color)
		draw_rect(Rect2(enemy.pos + Vector2(-enemy.radius, -enemy.radius - 9.0), Vector2(enemy.radius * 2.0 * enemy.hp / enemy.max_hp, 4)), Color("ffdc7d"))
		if enemy.windup > 0.0:
			draw_line(enemy.pos, enemy.aim, Color("ff7272", 0.7), 2.0)
			draw_arc(enemy.aim, 18.0, 0.0, TAU, 24, Color("ff7272"), 2.0)
		if enemy.kind == "boss":
			draw_rect(Rect2(400, 676, 480, 26), Color("182b41"))
			draw_rect(Rect2(408, 683, 464.0 * maxf(0.0, enemy.hp) / enemy.max_hp, 11), Color("ec5370"))
			draw_string(ThemeDB.fallback_font, Vector2(400, 667), "BOSS - dodge the warning spread", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("ffd2a8"))
	for bullet in bullets:
		draw_circle(bullet.pos, bullet.radius, bullet.color)
	for bullet in hostile_bullets:
		draw_circle(bullet.pos, bullet.radius, Color("ff7777"))
		draw_arc(bullet.pos, bullet.radius + 3.0, 0.0, TAU, 16, Color("ffd2a8"), 2.0)
	for impact in impacts:
		draw_arc(impact.pos, 9.0 + 40.0 * (0.2 - impact.time), 0.0, TAU, 16, impact.color, 2.0)
	for item in hit_texts:
		var tint: Color = item.color
		tint.a = clampf(item.time / 0.65, 0.0, 1.0)
		draw_string(ThemeDB.fallback_font, item.pos, str(item.value), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, tint)
	draw_circle(player_pos, 17.0, Color("ffe074"))
	if dodge_timer > 0.0:
		draw_arc(player_pos, 23.0, 0.0, TAU, 24, Color("80deff"), 3.0)
	draw_line(player_pos, player_pos + (get_global_mouse_position() - player_pos).normalized() * 27.0, Color.WHITE, 5.0)
	draw_rect(Rect2(0, 0, 1280, 85), Color("182b41"))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(25, 33), "FRONTLINE GUARDIAN", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color.WHITE)
	draw_string(font, Vector2(25, 65), "WASD Move  |  Mouse Fire  |  F Dodge  |  1 Rapid $40  |  2 Cannon $55", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("b6c8d7"))
	if selected_tower_index >= 0 and selected_tower_index < towers.size():
		var selected := towers[selected_tower_index]
		var upgrade_cost: int = 30 * selected.level
		var next_stats := "MAX LEVEL" if selected.level >= 3 else "U $%d: DMG %.0f -> %.0f  RNG %.0f -> %.0f" % [upgrade_cost, selected.damage, selected.damage * 1.35, selected.range + tower_range_bonus, selected.range + tower_range_bonus + 20.0]
		draw_rect(Rect2(18, 91, 760, 65), Color("182b41", 0.9))
		draw_string(font, Vector2(25, 117), "Tower Lv%d  HP %d/%d  Target %s | H Repair $15  X Sell  P Priority" % [selected.level, ceili(selected.hp), ceili(selected.max_hp), selected.priority], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
		draw_string(font, Vector2(25, 142), next_stats, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("80deff"))
	draw_string(font, Vector2(825, 32), "Night %d/%d   Gold %d" % [wave, MAX_WAVES, gold], HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("ffe074"))
	draw_string(font, Vector2(825, 62), "HP %d/%d   Core %d/%d" % [ceili(player_hp), ceili(max_player_hp), ceili(core_hp), ceili(max_core_hp)], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	draw_string(font, Vector2(575, 65), "F Dodge %s" % ("READY" if dodge_cooldown <= 0.0 else "%.1fs" % dodge_cooldown), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("80deff"))
	draw_rect(Rect2(825, 73, 180.0 * maxf(0.0, player_hp) / max_player_hp, 5), Color("ffe074"))
	draw_rect(Rect2(1020, 73, 180.0 * maxf(0.0, core_hp) / max_core_hp, 5), Color("638cff"))
	if selected_tower > 0:
		var mouse := get_global_mouse_position()
		var legal := can_build_at(mouse) and gold >= (40 if selected_tower == 1 else 55)
		var tint := Color("7fffd4") if legal else Color("ff7777")
		draw_arc(mouse, 21.0, 0.0, TAU, 36, tint, 2.0)
		draw_arc(mouse, (180.0 if selected_tower == 1 else 225.0) + tower_range_bonus, 0.0, TAU, 72, Color(tint, 0.45), 1.5)
		draw_string(font, mouse + Vector2(26, -20), "BUILD $%d" % (40 if selected_tower == 1 else 55) if legal else "BLOCKED / NO GOLD", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, tint)
	var message := "SPACE: Start wave" if state == "ready" else ""
	if state == "upgrade" and upgrade_choices.size() == 2:
		draw_rect(Rect2(300, 470, 680, 200), Color("182b41"))
		draw_string(font, Vector2(475, 515), "NIGHT CLEARED - CHOOSE ONE", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("ffe074"))
		for i in 2:
			var card := Rect2(340 + i * 320, 545, 280, 110)
			draw_rect(card, Color("365a74"))
			draw_string(font, card.position + Vector2(18, 42), upgrade_choices[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color.WHITE)
			draw_string(font, card.position + Vector2(18, 79), "Press Q" if i == 0 else "Press E", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("b6c8d7"))
	if state == "won": message = "VICTORY!  Eight nights survived.  Press R to restart"
	if state == "lost": message = "DEFEAT!  Press R to restart"
	if state == "won" or state == "lost":
		draw_rect(Rect2(240, 550, 800, 140), Color("182b41"))
		draw_string(font, Vector2(275, 600), "Nights reached: %d    Enemies defeated: %d" % [wave, kills], HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("ffe074"))
	if message != "":
		draw_rect(Rect2(240, 635, 800, 55), Color("253e59"))
		draw_string(font, Vector2(270, 670), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color.WHITE)
