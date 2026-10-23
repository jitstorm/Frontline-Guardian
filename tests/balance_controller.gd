extends RefCounted
## 平衡回归共用的有限能力控制器：正常花钱、按移速走位、按真实冷却射击施法。
## 不增加金币或生命，不传送追怪，不跳过敌人更新；预设选点与自动瞄准仍不代表真人手感。

## 候选建塔点，单位为世界像素；每次仍须经过正式道路与金币校验。
const SITES := [Vector2(185, 255), Vector2(330, 430), Vector2(445, 610), Vector2(660, 350), Vector2(790, 155), Vector2(970, 430), Vector2(1090, 245), Vector2(450, 430)]
## 每次模拟推进零点零五秒，移动距离、冷却及敌人攻击共用此步长。
const STEP := 0.05

## 在准备阶段按预算购买装备、修理并建塔，所有交易经过正式业务入口。
## @param game 正在运行的战场。
## @param plan 英雄投入、混合投入或炮塔投入策略标识。
func prepare(game: Node2D, plan: String) -> void:
	# 首先保留少量基础防线，随后把同一金币余额投入英雄或炮塔。
	var limit := 3 if plan == "hero" else 4 if plan == "mixed" else 8
	var reserved := 1 if plan == "hero" else maxi(2, mini(limit, game.wave + 1)) if plan == "mixed" else limit
	while game.towers.size() < reserved:
		if not build_next(game): break
	if plan != "towers":
		var weapon := "oak_staff" if game.hero.hero_id == "frost_mage" else "rust_axe"
		for item_id in [weapon, "leather_vest", "fighter_gloves", "steel_blade" if game.hero.hero_id == "berserker" else "frost_focus", "guardian_mail", "runner_boots", "iron_helm"]:
			var item: Dictionary = game.HeroRPG.ITEMS[item_id]
			var current: String = game.hero.equipment.get(item.slot, "")
			if current == item_id: continue
			# 已有更高价的同槽装备时不再反向购买低阶物品。
			if current != "" and game.HeroRPG.ITEMS[current].price >= item.price: continue
			if game.buy_item(item_id): game.equip_item(game.hero.inventory.size() - 1)
		if game.player_hp < game.max_player_hp * 0.65: game.buy_item("potion")
	while game.towers.size() < limit:
		if not build_next(game): break
	for i in game.towers.size():
		game.selected_tower_index = i
		if game.towers[i].hp < game.towers[i].max_hp * 0.65: game.repair_selected_tower()
		game.upgrade_selected_tower()
	# 技能点只从实际经验升级获得，每次调用仍走五级上限校验。
	for slot in [0, 3, 1, 2]:
		while game.hero.upgrade_skill(slot): pass
	game.selected_tower = 0

## 在固定合法候选点放置混合炮塔，余额不足或没有空位时停止。
## @param game 当前战场。
## @return 实际建成一座塔时返回 true。
func build_next(game: Node2D) -> bool:
	game.selected_tower = 1 if game.towers.size() % 2 == 0 else 2
	for site in SITES:
		if game.tower_at(site) >= 0: continue
		var before: int = game.towers.size()
		game.build_tower(site)
		if game.towers.size() > before: return true
	return false

## 从本次随机强化中选择与投入方向相关的一项，不修改抽取结果。
## @param game 当前波间战场。
## @param plan 本次金币投入方向。
func choose_upgrade(game: Node2D, plan: String) -> void:
	var priorities := ["双重射击", "枪械增幅", "快速扳机", "核心装甲", "炮塔增幅", "机械润滑", "生命补给"]
	if plan == "towers": priorities = ["炮塔增幅", "机械润滑", "射程扩展", "核心装甲", "军需补给"]
	if game.core_hp < game.max_core_hp * 0.65: priorities.push_front("核心修复")
	var choice: String = game.upgrade_choices[0]
	for preferred in priorities:
		if game.upgrade_choices.has(preferred):
			choice = preferred
			break
	game.apply_upgrade(choice)

## 用相同的移速限制控制基地或营地英雄，并使用正式普攻与技能入口。
## @param game 当前战场，持有唯一英雄属性和冷却。
## @param camp 可选营地场景；为空时控制基地英雄。
## @param skills 是否允许施法；关闭时作为仅走位普攻的对照。
func act(game: Node2D, camp: Node2D = null, skills: bool = true) -> void:
	var targets: Array = game.enemies if camp == null else camp.enemies
	var pos: Vector2 = game.player_pos if camp == null else camp.hero_pos
	if targets.is_empty(): return
	# 优先处理离核心较近的敌人；副本选择最近目标，不能跳到首领身边刷伤害。
	var target: Dictionary = targets[0]
	var score := INF
	for candidate in targets:
		var value: float = pos.distance_to(candidate.pos) if camp != null else candidate.pos.distance_to(game.CORE_POS) + pos.distance_to(candidate.pos) * 0.25
		if value < score:
			score = value
			target = candidate
	var distance := pos.distance_to(target.pos)
	var desired := 105.0 if game.hero.hero_id == "berserker" else 155.0
	var toward: Vector2 = (target.pos - pos).normalized()
	var motion := toward if distance > desired + 30.0 else -toward if distance < desired - 20.0 else toward.orthogonal() * 0.5
	# 靠近任意敌人或弹丸时横向避让；位移仍受每秒移速限制。
	for candidate in targets:
		var offset: Vector2 = pos - candidate.pos
		if offset.length() < 85.0: motion += offset.normalized() * 1.5
	var projectiles: Array = game.hostile_bullets if camp == null else camp.hostile_bullets
	for bullet in projectiles:
		if bullet.pos.distance_to(pos) < 100.0: motion += (pos - bullet.pos).normalized() * 1.5
	pos += motion.limit_length() * game.hero.stats().speed * game.move_multiplier * STEP
	pos = pos.clamp(Vector2(50, 110), Vector2(1230, 620))
	if camp == null: game.player_pos = pos
	else: camp.hero_pos = pos
	# 只作短距离匀速预判，转弯和前摇仍可能使弹丸落空。
	var aim: Vector2 = target.pos
	if camp == null and target.get("windup", 0.0) <= 0.0 and target.route_index < target.route.size():
		aim += (target.route[target.route_index] - target.pos).normalized() * target.speed * minf(distance / 650.0, 0.3)
	if camp == null: game.fire_at(aim)
	elif camp.fire_timer <= 0.0: camp.fire_at(aim)
	if skills and distance < 245.0:
		for slot in [0, 1, 3, 2]:
			# 突进仅用于接近远处目标，避免贴脸后反复冲入怪群。
			if game.hero.hero_id == "berserker" and slot == 2 and distance < 180.0: continue
			if camp == null: game.cast_skill(slot, aim)
			else: camp.cast_skill(slot, aim)

## 以真实移动、敌人攻击和技能冷却完成一次营地挑战，死亡会走原有撤退路径。
## @param game 已到达第二夜波间的战场。
## @return 只有靠近首领掉落并触发正式领取时返回 true。
func visit_camp(game: Node2D) -> bool:
	if not game.enter_dungeon(): return false
	var camp: Node2D = game.dungeon_scene
	camp.set_process(false)
	for tick in 4800:
		if game.state != "dungeon": break
		if camp.reward_spawned:
			camp.hero_pos = camp.hero_pos.move_toward(camp.reward_pos, game.hero.stats().speed * game.move_multiplier * STEP)
		else: act(game, camp)
		game._process(STEP)
		camp._process(STEP)
	if game.state == "dungeon": game.leave_dungeon()
	return game.dungeon_reward_claimed
