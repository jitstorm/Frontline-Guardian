extends SceneTree
## 通过图形渲染器截取中文界面、实际后期战斗和结算，检查密集敌人下的显示。

## 逐一切换游戏状态并在绘制完成后保存画面；不模拟玩家操作结果。
func _initialize() -> void:
	var game: Node2D = load("res://scripts/game.gd").new()
	root.add_child(game)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_logs/hero_selection.png")
	game.select_hero("berserker")
	game.shop_open = true
	game.queue_redraw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_logs/shop.png")
	game.shop_open = false
	game.buy_item("rust_axe")
	game.equip_item(0)
	game.buy_item("fighter_gloves")
	game.inventory_open = true
	game.queue_redraw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_logs/inventory.png")
	game.inventory_open = false
	game.wave = 2
	game.state = "upgrade"
	game.roll_upgrades()
	game.enter_dungeon()
	game.queue_redraw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_logs/goblin_camp.png")
	game.free()
	# 用正常经济和控制器推进到后期，截图中的敌人、装备、弹丸均来自真实流程。
	seed(7)
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	game.set_process(false)
	game.select_hero("frost_mage")
	var controller = load("res://tests/balance_controller.gd").new()
	var captured := false
	for tick in 16000:
		if game.state == "won" or game.state == "lost": break
		if game.state == "ready":
			controller.prepare(game, "towers")
			game.start_wave()
		elif game.state == "upgrade": controller.choose_upgrade(game, "towers")
		controller.act(game)
		game._process(0.05)
		if not captured and game.wave >= 7 and game.enemies.size() >= 8:
			game.queue_redraw()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://test_logs/balance_combat.png")
			captured = true
	assert(captured and game.state == "won")
	game.queue_redraw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_logs/victory.png")
	# 失败截图验证同一结算层，不把本段构造状态当作战斗失败概率的证据。
	game.core_hp = 0.0
	game.state = "fighting"
	game._process(0.0)
	assert(game.state == "lost")
	game.queue_redraw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_logs/defeat.png")
	print("visual_capture=PASS hero_selection shop inventory goblin_camp balance_combat victory defeat")
	quit(0)
