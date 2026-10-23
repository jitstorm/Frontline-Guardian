extends SceneTree
## 向 Godot 投递真实输入事件，检查双英雄选择、面板、方向键、普攻和技能映射。

## 逐个检查键盘路由和鼠标按住状态，不绕过 _unhandled_input 直接调用技能。
func _initialize() -> void:
	for selection in [KEY_1, KEY_2]:
		var game: Node2D = load("res://scripts/game.gd").new()
		root.add_child(game)
		await process_frame
		game.set_process(false)
		await press_key(selection)
		assert(game.state == "ready" and game.hero.hero_id == ("berserker" if selection == KEY_1 else "frost_mage"))
		await press_key(KEY_B)
		assert(game.shop_open)
		await press_key(KEY_B)
		assert(not game.shop_open)
		await press_key(KEY_I)
		assert(game.inventory_open)
		await press_key(KEY_I)
		assert(not game.inventory_open)
		var before: Vector2 = game.player_pos
		key_event(KEY_RIGHT, true)
		await process_frame
		game.move_player(0.1)
		key_event(KEY_RIGHT, false)
		assert(game.player_pos.x > before.x and is_equal_approx(game.player_pos.y, before.y))
		await press_key(KEY_SPACE)
		assert(game.state == "fighting" and game.spawn_left == game.wave_enemy_count(1))
		# 校准目标放在当前鼠标朝向，检查按键实际造成伤害及进入冷却，不要求自动命中移动目标。
		var direction: Vector2 = (game.get_global_mouse_position() - game.player_pos).normalized()
		var target_pos: Vector2 = game.player_pos + direction * (145.0 if selection == KEY_2 else 60.0)
		game.enemies.append({"pos": target_pos, "hp": 1000.0, "max_hp": 1000.0, "kind": "grunt", "radius": 17.0, "reward": 3, "windup": 0.0})
		await press_key(KEY_Q)
		assert(game.enemies[0].hp < 1000.0 and game.hero.cooldowns[0] > 0.0)
		await press_key(KEY_W)
		assert(game.hero.cooldowns[1] > 0.0)
		await press_key(KEY_E)
		assert(game.hero.cooldowns[2] > 0.0)
		await press_key(KEY_R)
		assert(game.hero.cooldowns[3] > 0.0)
		await press_key(KEY_F)
		assert(game.dodge_timer > 0.0 and game.dodge_cooldown > 0.0)
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = true
		Input.parse_input_event(mouse)
		await process_frame
		game.shoot_player(0.05)
		assert(game.bullets.size() > 0 and game.fire_timer > 0.0)
		mouse = InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = false
		Input.parse_input_event(mouse)
		game.free()
	# 流派卡片使用同一输入路由，选择后恢复数字键建塔，开波后不能再打开。
	for choice in [KEY_1, KEY_2, KEY_3]:
		var game: Node2D = load("res://scripts/game.gd").new()
		root.add_child(game)
		await process_frame
		game.set_process(false)
		await press_key(KEY_1)
		await press_key(KEY_C)
		assert(game.build_open)
		await press_key(choice)
		assert(not game.build_open and game.hero.build_id == ({KEY_1: "skill", KEY_2: "passive", KEY_3: "summon"})[choice])
		await press_key(KEY_SPACE)
		await press_key(KEY_C)
		assert(not game.build_open)
		await press_key(KEY_Q)
		if choice == KEY_2: assert(game.hero.cooldowns[0] == 0.0)
		if choice == KEY_3: assert(game.combat_builds.familiars.size() == 2)
		game.free()
	print("input_controls=PASS 双英雄 面板 方向键 空格 鼠标普攻 QWER 闪避")
	quit(0)

## 投递一次按下和释放并等待引擎分发，避免测试直接调用战斗处理函数。
## @param code 与实际键盘一致的物理和逻辑键码。
func press_key(code: Key) -> void:
	key_event(code, true)
	await process_frame
	key_event(code, false)
	await process_frame

## 把键盘状态交给 Godot 输入系统，使按键路由和移动状态读取一起生效。
## @param code 待投递的键码。
## @param pressed 是否处于按下状态。
func key_event(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
