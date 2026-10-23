extends SceneTree

## 以默认 100 金币和实际击杀收益比较速射塔、重炮塔两种固定建造策略。
func _initialize() -> void:
	var script: GDScript = load("res://scripts/game.gd")
	for config in [{"kind": 1, "plan": "attack"}, {"kind": 1, "plan": "defense"}, {"kind": 2, "plan": "attack"}, {"kind": 2, "plan": "defense"}]:
		seed(20261023)
		var kind: int = config.kind
		var plan: String = config.plan
		var game: Node2D = script.new()
		root.add_child(game)
		await process_frame
		assert(game.select_hero("berserker"))
		var sites: Array[Vector2] = [Vector2(185, 255), Vector2(330, 430), Vector2(445, 610), Vector2(660, 350), Vector2(790, 155), Vector2(970, 430), Vector2(1090, 245), Vector2(450, 430), Vector2(660, 155), Vector2(980, 245), Vector2(300, 250), Vector2(750, 345)]
		var next_site := 0
		var ticks := 0
		game.selected_tower = kind
		while game.state != "won" and game.state != "lost" and ticks < 18000:
			var cost := 40 if kind == 1 else 55
			while game.gold >= cost and next_site < sites.size():
				var before: int = game.towers.size()
				game.build_tower(sites[next_site])
				next_site += 1
				if game.towers.size() == before:
					continue
			# 固定建造点用完后把实际赚到的金币投入现有炮塔升级。
			if next_site >= sites.size():
				for index in game.towers.size():
					game.selected_tower_index = index
					game.upgrade_selected_tower()
			if game.state == "ready":
				game.start_wave()
			elif game.state == "upgrade":
				var choice: String = game.upgrade_choices[0]
				var priorities := ["炮塔增幅", "机械润滑", "射程扩展", "军需补给", "核心修复"] if plan == "attack" else ["核心修复", "核心加固", "核心装甲", "防弹衣", "军需补给"]
				for preferred in priorities:
					if game.upgrade_choices.has(preferred):
						choice = preferred
						break
				game.apply_upgrade(choice)
			game._process(0.05)
			ticks += 1
		print("strategy=%s/%s result=%s night=%d kills=%d towers=%d gold=%d core_hp=%.1f ticks=%d" % ["rapid" if kind == 1 else "cannon", plan, game.state, game.wave, game.kills, game.towers.size(), game.gold, game.core_hp, ticks])
		assert(game.state == "won" or game.state == "lost", "默认经济策略未能结算")
		game.queue_free()
	quit(0)
