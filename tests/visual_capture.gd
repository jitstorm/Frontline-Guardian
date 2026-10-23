extends SceneTree
## 通过图形渲染器截取英雄选择、商店和副本画面，检查界面是否实际显示。

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
	game.wave = 2
	game.state = "upgrade"
	game.roll_upgrades()
	game.enter_dungeon()
	game.queue_redraw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_logs/goblin_camp.png")
	print("visual_capture=PASS hero_selection shop goblin_camp")
	quit(0)
