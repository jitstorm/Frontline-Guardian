extends RefCounted
## 独立处理命中类词缀触发；装备生成与数值合成由 EquipmentSystem 负责。

## 真实普攻命中后启动词缀；额外爆炸、追击和词缀伤害不会递归累计触发次数。
## @param game 本局战场。
## @param center 普攻命中点，单位像素。
## @param camp 当前副本，为空表示基地。
func apply(game: Node2D, center: Vector2, camp: Node2D = null) -> void:
	game.hero.affix_hits += 1
	if game.hero.has_affix("ember") and game.hero.affix_hits % 4 == 0:
		game.evolution_system.burst(game, camp, center, 65.0, game.hero.stats().attack * 0.45, "affix")
	if game.hero.has_affix("leech") and game.hero.leech_timer <= 0.0:
		game.player_hp = minf(game.max_player_hp, game.player_hp + 1.0)
		game.hero.leech_timer = 0.6
	if game.hero.has_affix("frost"):
		var targets: Array = game.enemies if camp == null else camp.enemies
		for enemy in targets:
			if enemy.pos.distance_to(center) <= 35.0:
				enemy.slow_time = maxf(1.0, enemy.get("slow_time", 0.0))
				enemy.slow_factor = 0.7

