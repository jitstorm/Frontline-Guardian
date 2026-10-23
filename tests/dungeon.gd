extends SceneTree
## 通过真实副本弹丸击败小 Boss，验证状态暂停、战利品只领一次及炮塔回归。

## 从第 2 夜波间进入营地并完成实际伤害与奖励测试。
func _initialize() -> void:
	var script: GDScript = load("res://scripts/game.gd")
	var game: Node2D = script.new()
	root.add_child(game)
	await process_frame
	assert(game.select_hero("berserker"))
	game.selected_tower = 1
	game.build_tower(Vector2(300, 120))
	assert(game.towers.size() == 1)
	game.wave = 2
	game.state = "upgrade"
	game.roll_upgrades()
	var gold_before: int = game.gold
	var xp_before: int = game.hero.xp
	var hp_before: float = game.core_hp
	var tower_before: Dictionary = game.towers[0].duplicate()
	assert(game.dungeon_available() and game.enter_dungeon())
	assert(game.state == "dungeon" and game.dungeon_scene.enemies.size() == 5)
	game._process(2.0)
	assert(game.core_hp == hp_before and game.towers[0].hp == tower_before.hp)
	var camp: Node2D = game.dungeon_scene
	var boss_pos: Vector2 = camp.enemies[4].pos
	camp.hero_pos = boss_pos + Vector2(-60, 0)
	var boss_hp: float = camp.enemies[4].hp
	camp.fire_at(boss_pos)
	camp.update_bullets(0.05)
	camp.update_bullets(0.05)
	assert(camp.enemies[4].hp < boss_hp, "副本弹丸必须真实命中 Boss")
	for i in 30:
		if camp.reward_spawned: break
		camp.fire_at(boss_pos)
		camp.update_bullets(0.05)
		camp.update_bullets(0.05)
	assert(camp.reward_spawned and not camp.reward_taken)
	camp.hero_pos = camp.reward_pos
	camp._process(0.0)
	assert(game.dungeon_reward_claimed and game.state == "upgrade")
	assert(game.hero.inventory.has("berserker_mark") and game.gold > gold_before)
	assert(game.hero.xp > xp_before or game.hero.level > 1)
	var claimed_gold: int = game.gold
	game.complete_dungeon("berserker_mark")
	assert(game.gold == claimed_gold and game.hero.inventory.count("berserker_mark") == 1)
	assert(not game.enter_dungeon())
	assert(game.towers.size() == 1 and game.towers[0].pos == tower_before.pos)
	game.apply_upgrade(game.upgrade_choices[0])
	assert(game.state == "ready")
	game.start_wave()
	assert(game.state == "fighting" and game.wave == 3)
	game.enemies.append({"pos": Vector2(300, 240), "segment": 0, "route": game.route_from(Vector2(300, 240)), "route_index": 0, "hp": 100.0, "max_hp": 100.0, "speed": 0.0, "attack_timer": 2.0, "windup": 0.0, "target_kind": "", "aim": Vector2.ZERO, "kind": "grunt", "radius": 17.0, "reward": 8})
	game.update_towers(0.1)
	assert(game.bullets.size() > 0, "返回基地后炮塔仍须开火")
	print("dungeon=PASS boss_damage=real gold=%d tower_resumed=1" % game.gold)
	quit(0)
