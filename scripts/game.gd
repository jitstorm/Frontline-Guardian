extends Node2D
## 管理八夜守卫战的角色、道路敌人、炮塔和波间强化；核心被毁或角色阵亡时结束本局。

const PATH: Array[Vector2] = [Vector2(-30, 350), Vector2(230, 350), Vector2(230, 520), Vector2(550, 520), Vector2(550, 250), Vector2(880, 250), Vector2(880, 350), Vector2(1190, 350)]
const CORE_POS := Vector2(1190, 350)
const PLAYER_SPEED := 255.0
const BULLET_SPEED := 650.0
const MAX_WAVES := 8
## 精英与首领战甲未被技能、三连追击或幻影击破时，仅承受百分之五的物理伤害，保留非零伤害。
const GUARD_DAMAGE_MULTIPLIER := 0.05
## 各流派破甲来源命中后的持续时间，单位为秒；基地与营地共用。
const ARMOR_BREAK_SECONDS := 5.0
## 八夜总量配合分组出怪递增；增加战场密度时同步压低单怪金币，避免收入翻倍。
const WAVE_COUNTS := [10, 16, 24, 32, 40, 48, 56, 64]
const BG := Color("101a29")
const ROAD := Color("34475a")
const CELL_SIZE := 40.0
const GRID_SIZE := Vector2i(32, 18)
const START_CELL := Vector2i(0, 8)
const GOAL_CELL := Vector2i(29, 8)
const HeroRPG = preload("res://scripts/hero_rpg.gd")
const EquipmentSystem = preload("res://scripts/equipment_system.gd")
const SkillEvolution = preload("res://scripts/skill_evolution.gd")
const EnemyDirector = preload("res://scripts/enemy_director.gd")
const SummonHealth = preload("res://scripts/summon_health.gd")
const EquipmentUI = preload("res://scripts/equipment_ui.gd")
const BuildEvolution = preload("res://scripts/build_evolution.gd")
const CombatBuilds = preload("res://scripts/combat_builds.gd")
const GoblinCamp = preload("res://dungeon.tscn")
const UI_FONT = preload("res://assets/fonts/NotoSansSC-VF.ttf")
const HERO_WARRIOR = preload("res://assets/kenney/tile_0085.png")
const HERO_MAGE = preload("res://assets/kenney/tile_0084.png")
const ENEMY_GRUNT = preload("res://assets/kenney/tile_0108.png")
const ENEMY_RUNNER = preload("res://assets/kenney/tile_0110.png")
const ENEMY_ARMORED = preload("res://assets/kenney/tile_0096.png")
const ENEMY_RANGED = preload("res://assets/kenney/tile_0121.png")
const ENEMY_ELITE = preload("res://assets/kenney/tile_0122.png")
const ENEMY_BOSS = preload("res://assets/kenney/tile_0110.png")
const TOWER_FAST = preload("res://assets/kenney/tile_0090.png")
const TOWER_HEAVY = preload("res://assets/kenney/tile_0092.png")
const CORE_ART = preload("res://assets/kenney/tile_0082.png")
const FLOOR_ART = preload("res://assets/kenney/tile_0049.png")
const ROAD_ART = preload("res://assets/kenney/tile_0036.png")

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
var state := "select_hero"
## 本局英雄成长与装备容器；金币仍由上方 gold 统一记账。
var hero = HeroRPG.new()
## 连击与召唤的共用运行容器，地图切换时清理临时幻影。
var combat_builds = CombatBuilds.new()
## 第一夜前的流派选择面板，不另设战斗状态或第二套经济余额。
var build_open := false
## 形态选择面板只在第二夜后准备阶段打开；每局路线互斥，后续按夜次和等级领取至三阶。
var evolution_open := false
var evolution_system = BuildEvolution.new()
## 独立模块实例：战场只负责调用顺序，数值与规则分别维护。
var enemy_director = EnemyDirector.new()
var summon_health = SummonHealth.new()
var equipment_ui = EquipmentUI.new()
## 已购买词缀宝匣的夜次，每个准备阶段最多购买一次，防止反复刷取。
var chest_wave := -1
## 基地词缀造成的真实损血，独立于普攻、被动和技能。
var hero_affix_damage := 0.0
## 操作失败或奖励提示，仅用于界面显示，不控制经济状态。
var notice := ""
var notice_time := 0.0
var inventory_open := false
var shop_open := false
## Boss 掉落已经领取，用于阻止同一副本奖励重复发放。
var dungeon_reward_claimed := false
## 本局已经进入营地；撤退后不允许重刷普通怪收益。
var dungeon_attempted := false
## 活跃副本场景；离开后释放，基地节点始终保留。
var dungeon_scene: Node2D
var enemies: Array[Dictionary] = []
var towers: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var hostile_bullets: Array[Dictionary] = []
var hit_texts: Array[Dictionary] = []
var impacts: Array[Dictionary] = []
## 敌人死亡后的短暂残影，不参与碰撞与奖励结算。
var death_frames: Array[Dictionary] = []
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
## 每层赏金每次额外发放的金币，只对每夜前十次击杀生效。
var gold_bonus := 0
## 本夜已结算的击杀数，赏金只覆盖前十只，限制永久经济强化滚雪球。
var bounty_kills := 0
## 本局英雄普攻、技能、被动与词缀实际扣除的敌人生命，不计溢出伤害及营地独立战斗。
var hero_damage_dealt := 0.0
## 基地英雄普攻实际扣除的生命，用于与主动技能分开核验输出预算。
var hero_basic_damage := 0.0
## 基地主动技能实际扣除的生命，不计溢出伤害。
var hero_skill_damage := 0.0
## 基地连击被动实际扣除的生命，计入英雄总伤害。
var hero_passive_damage := 0.0
## 基地幻影实际扣除的生命，独立于英雄本体与炮塔统计。
var summon_damage_dealt := 0.0
## 本局基地炮塔实际扣除的敌人生命，不计溢出伤害。
var tower_damage_dealt := 0.0
var player_armor := 0.0
## 波间强化永久增加的属性，装备重算时必须保留这些增量。
var hero_health_bonus := 0.0
var hero_attack_bonus := 0.0
var hero_armor_bonus := 0.0
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
	if state == "select_hero":
		queue_redraw()
		return
	if state != "dungeon": move_player(delta)
	dodge_timer = maxf(0.0, dodge_timer - delta)
	dodge_cooldown = maxf(0.0, dodge_cooldown - delta)
	update_feedback(delta)
	notice_time = maxf(0.0, notice_time - delta)
	if state == "fighting":
		hero.tick(delta)
		update_spawning(delta)
		evolution_system.tick(self, delta)
		combat_builds.tick(self, delta)
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

## 选择英雄并同步初始实战属性；重新开局由场景重载完成，避免遗留装备和冷却。
## @param choice 狂战士或冰霜法师的目录标识。
## @return 成功选定并进入准备阶段时返回 true。
func select_hero(choice: String) -> bool:
	if state != "select_hero" or not hero.choose(choice): return false
	max_player_hp = hero.stats().health
	player_hp = max_player_hp
	player_damage = hero.stats().attack
	player_armor = hero.stats().defense
	state = "ready"
	show_notice("第一夜前按 C 选择技能、被动或召唤流派")
	return true

## 在第一夜开始前选择战斗流派并同步属性，开波后锁定，避免战斗中换流派重置连击。
## @param choice 流派目录中的标识。
## @return 准备阶段且尚未开始第一夜、标识有效时返回 true；不会赠送金币或装备。
func select_build(choice: String) -> bool:
	if state != "ready" or wave != 0 or not HeroRPG.BUILDS.has(choice): return false
	hero.build_id = choice
	hero.combo_hits = 0
	hero.fervor_stacks = 0
	hero.fervor_time = 0.0
	combat_builds.clear()
	sync_hero_stats()
	build_open = false
	return true

## 花费实际技能点升级当前流派的技能或被动，并同步护甲等即时属性。
## @param index 按五至八升级键排列的成长索引。
## @return 存在技能点且未达五级时返回 true，失败时保持属性不变。
func upgrade_hero_skill(index: int) -> bool:
	if not hero.upgrade_skill(index): return false
	sync_hero_stats()
	return true

## 第 2 夜结束后开放营地入口，领取 Boss 奖励后本局不再开放。
## @return 波间可进入且尚未领奖时返回 true。
func dungeon_available() -> bool:
	return wave == 2 and state == "upgrade" and not dungeon_attempted and not dungeon_reward_claimed

## 将独立营地场景叠加到战场上，并暂停基地战斗循环。
## @return 入口有效且副本已加载时返回 true。
func enter_dungeon() -> bool:
	if not dungeon_available(): return false
	combat_builds.clear()
	evolution_system.arcs.clear()
	dungeon_scene = GoblinCamp.instantiate()
	dungeon_scene.game = self
	dungeon_scene.reward_collected.connect(complete_dungeon)
	dungeon_scene.retreat_requested.connect(leave_dungeon)
	add_child(dungeon_scene)
	dungeon_attempted = true
	state = "dungeon"
	return true

## 仅在实际拾取 Boss 掉落时发奖一次；背包满时兑换金币。
## @param item_id 副本战利品的装备目录标识。
func complete_dungeon(item_id: String) -> void:
	if state != "dungeon" or dungeon_reward_claimed or dungeon_scene == null or not dungeon_scene.reward_spawned or not dungeon_scene.reward_taken: return
	dungeon_reward_claimed = true
	if hero.pickup(item_id): show_notice("营地已清除：获得史诗战利品")
	else:
		gold += 60
		show_notice("营地已清除：背包已满，获得 60 金币")
	leave_dungeon()

## 返回基地第 2 夜波间状态；炮塔、强化选项和本局经济保持原状。
func leave_dungeon() -> void:
	if state != "dungeon": return
	if dungeon_scene != null:
		dungeon_scene.queue_free()
		dungeon_scene = null
	state = "upgrade"
	combat_builds.clear()
	evolution_system.arcs.clear()

## 装备或等级变化后保留当前生命比例，并同步攻击和防御到原有战斗结算。
func sync_hero_stats() -> void:
	var current: Dictionary = hero.stats()
	if current.is_empty(): return
	var ratio := player_hp / maxf(1.0, max_player_hp)
	max_player_hp = current.health + hero_health_bonus
	player_hp = minf(max_player_hp, max_player_hp * ratio)
	player_damage = current.attack + hero_attack_bonus
	player_armor = current.defense + hero_armor_bonus

## 按职业执行四种技能的伤害、击退、减速或临时防护，只有实战命中才发放击杀收益。
## @param index Q/W/E/R 对应的技能索引。
## @param aim 鼠标所指世界位置，用于方向性技能。
## @return 冷却结束且成功释放时返回 true。
func cast_skill(index: int, aim: Vector2) -> bool:
	if state != "fighting" or index < 0 or index >= 4 or hero.skill_levels[index] <= 0 or hero.cooldowns[index] > 0.0: return false
	if hero.build_id == "passive": return false
	if hero.build_id == "summon": return combat_builds.cast(self, index, aim)
	var direction := (aim - player_pos).normalized()
	if direction == Vector2.ZERO: direction = Vector2.RIGHT
	var damage := hero.skill_damage(index)
	var radius: float = [95.0, 135.0, 115.0, 210.0][index]
	var center := player_pos
	var base_cooldowns := [3.0, 9.0, 8.0, 22.0] if hero.hero_id == "berserker" else [2.8, 10.0, 9.0, 23.0]
	# 1. 技能释放先计算职业特有的方向、范围和临时增益。
	if hero.hero_id == "berserker":
		if index == 1: hero.buff_time = 5.0
		if index == 2:
			player_pos = (player_pos + direction * 110.0).clamp(Vector2(22, 92), Vector2(1258, 695))
			center = player_pos
		if index == 3: center = player_pos + direction * 95.0
	else:
		if index == 0: center = player_pos + direction * 145.0; radius = 52.0
		if index == 2: hero.ward_time = 5.0
		if index == 3: center = player_pos + direction * 150.0
	if hero.has_effect("wide_sweep") and hero.hero_id == "berserker" and index == 0: radius *= 1.55
	if hero.has_effect("frost_burst") and hero.hero_id == "frost_mage" and index == 1: radius *= 1.4
	if index == 0 and hero.evolution == "nova":
		center = player_pos
		radius = SkillEvolution.rules(hero).radius
		damage *= 0.8
	if index == 0 and hero.evolution == "echo": radius += SkillEvolution.rules(hero).radius_bonus
	# 2. 命中时对现存敌人真实扣血，并复用击杀奖励和经验路径。
	var hits := 0
	for i in range(enemies.size() - 1, -1, -1):
		var enemy := enemies[i]
		if enemy.pos.distance_to(center) > radius + enemy.radius: continue
		if hero.hero_id == "berserker" and hero.evolution != "nova" and index == 0 and (enemy.pos - player_pos).normalized().dot(direction) < 0.0: continue
		var dealt: float = damage * (0.65 if enemy.kind == "armored" else 1.0)
		if hero.has_effect("rage_chain") and hero.hero_id == "berserker" and index == 2: dealt *= 1.45
		var actual := minf(dealt, maxf(0.0, enemy.hp))
		hero_damage_dealt += actual
		hero_skill_damage += actual
		# 攻击技能命中后打开五秒物理输出窗口，战吼与护盾不能代替攻击技能破甲。
		if index != (1 if hero.hero_id == "berserker" else 2):
			enemy.exposed_time = ARMOR_BREAK_SECONDS
			evolution_system.interrupt(enemy)
		enemy.hp -= dealt
		if index == 0 and hero.evolution == "nova" and hero.evolution_tier >= 2:
			enemy.slow_time = 1.0
			enemy.slow_factor = 0.5
		enemy.hit_time = 0.16
		enemy.pos += (enemy.pos - center).normalized() * (38.0 if hero.hero_id == "berserker" else 8.0)
		if hero.hero_id == "frost_mage":
			enemy.slow_time = 2.5 if index != 3 else 4.0
			enemy.slow_factor = 0.45
		add_damage_text(enemy.pos, dealt, Color("80deff") if hero.hero_id == "frost_mage" else Color("ffbd7a"))
		if enemy.hp <= 0.0:
			death_frames.append({"pos": enemy.pos, "kind": enemy.kind, "time": 0.35})
			enemies.remove_at(i)
			reward_enemy(enemy)
		else: enemies[i] = enemy
		hits += 1
	if hero.hero_id == "berserker" and index == 1: player_hp = minf(max_player_hp, player_hp + 12.0)
	if hero.hero_id == "frost_mage" and index == 2: player_hp = minf(max_player_hp, player_hp + 6.0)
	# 3. 技能真正释放后才进入冷却；未命中也消耗本次施法机会。
	if index == 0 and hero.evolution == "echo":
		for echo in SkillEvolution.rules(hero).echoes:
			evolution_system.burst(self, null, center + direction * echo[0], radius, damage * echo[1], "skill")
	if index == 0 and hero.evolution == "nova" and hero.evolution_tier >= 3: hero.ward_time = maxf(2.0, hero.ward_time)
	hero.cooldowns[index] = hero.cooldown_seconds(base_cooldowns[index] + (1.0 if index == 0 and hero.evolution == "echo" else 0.0))
	impacts.append({"pos": center, "time": 0.2, "color": Color("80deff") if hero.hero_id == "frost_mage" else Color("ffbd7a")})
	show_notice("%s：命中 %d 次" % [HeroRPG.SKILL_NAMES[hero.hero_id][index], hits])
	return true

## 对真实击杀统一发放原有金币和英雄经验；炮塔与英雄技能走同一条奖励路径。
## @param enemy 已被实际扣血至零的敌人数据。
func reward_enemy(enemy: Dictionary) -> void:
	kills += 1
	if hero.has_affix("renewal"): player_hp = minf(max_player_hp, player_hp + 1.0)
	# 赏金按夜重置十次领取机会，避免每层强化的收入继续随怪物总量线性放大。
	gold += enemy.reward + (gold_bonus if bounty_kills < 10 else 0)
	bounty_kills += 1
	var previous_max := max_player_hp
	# 每只经验随新数量同步压低，保留升级节奏，避免增加怪数同时把等级收益也放大。
	if hero.gain_xp(2 + int(enemy.reward / 2)) > 0:
		sync_hero_stats()
		player_hp = minf(max_player_hp, player_hp + max_player_hp - previous_max)

## 使用原有金币余额购买商品；仅准备阶段开放，失败时显示明确原因。
## @param item_id 装备目录中的商品，或恢复药剂 potion。
## @return 购买且实际取得商品时返回 true。
func buy_item(item_id: String) -> bool:
	if state != "ready":
		show_notice("商店仅在准备阶段开放")
		return false
	var price := 22 if item_id == "potion" else int(HeroRPG.ITEMS.get(item_id, {}).get("price", -1))
	if price < 0:
		show_notice("未知商品")
		return false
	if gold < price:
		show_notice("金币不足")
		return false
	if item_id == "potion":
		if player_hp >= max_player_hp:
			show_notice("生命值已满")
			return false
		player_hp = minf(max_player_hp, player_hp + 55.0)
	elif not hero.pickup(item_id):
		show_notice("背包已满")
		return false
	gold -= price
	show_notice("已购买：" + ("生命药剂" if item_id == "potion" else HeroRPG.ITEMS[item_id].name))
	return true

## 使用正常金币购买随机基础装备、品质倍率和一至四个词缀，每个准备阶段限购一次。
## 随机结果仅在余额、容量和夜次检查成功后生成，失败不会扣金币或消耗随机结果。
## @return 已取得词缀装备并扣除五十金币时返回 true。
func buy_affix_chest() -> bool:
	# 1. 先校验阶段、限购、余额与容量，失败交易不能改变随机源或金币。
	if state != "ready" or chest_wave == wave or gold < 50 or hero.inventory.size() >= HeroRPG.CAPACITY:
		show_notice("宝匣需要 50 金币、背包空位，且每个准备阶段限购一次")
		return false
	# 2. 从最高基础售价七十金币的目录抽取物品，半价出售不能赚回宝匣成本。
	var pool := ["rust_axe", "oak_staff", "iron_helm", "leather_vest", "runner_boots", "fighter_gloves", "vital_charm", "steel_blade", "guardian_mail"]
	var item_id: String = pool[rng.randi_range(0, pool.size() - 1)]
	var record: Dictionary = EquipmentSystem.generate(rng)
	if not hero.pickup(item_id, "", record): return false
	# 3. 实际收货成功后才扣款并记录本准备阶段限购，物品词缀随实例保存。
	gold -= 50
	chest_wave = wave
	show_notice("宝匣：" + EquipmentSystem.label(item_id, record).split("[")[0] + "，背包查看效果")
	return true

## 从当前流派的两种形态中选择一种；第二夜之后波间或准备阶段开放，首次锁定路线，随后按规则领取下一阶。
## @param choice 形态目录中的标识，必须匹配本局流派。
## @return 形态已锁定时返回 true；无效选择不改变英雄。
func select_evolution(choice: String) -> bool:
	if state not in ["ready", "upgrade"] or not SkillEvolution.advance(hero, wave, choice): return false
	evolution_open = false
	show_notice("进化完成：" + SkillEvolution.label(hero))
	return true

## 在准备阶段重铸背包装备，失败不扣款、不消耗随机源，锁定规则由装备模块校验。
## @param index 背包实例索引。
## @param locks 需要保留的词条位置。
## @return 新记录已写入且扣款成功时返回 true。
func reforge_item(index: int, locks: Array[int]) -> bool:
	# 1. 先校验阶段、物品、锁定与预算，拒绝失败交易改变随机序列。
	if state != "ready" or index < 0 or index >= hero.inventory.size(): return false
	var record: Dictionary = hero.inventory_rolls[index]
	var price := EquipmentSystem.cost(record, locks)
	if price < 0 or gold < price:
		show_notice("重铸失败：金币不足或词条全部锁定")
		return false
	# 2. 生成副本并原子替换记录，成功后才扣除唯一金币余额。
	var replacement := EquipmentSystem.reforge(record, locks, rng)
	if not hero.replace_roll(index, replacement): return false
	gold -= price
	show_notice("重铸完成，锁定词条与品质已保留")
	return true

## 返回本流派可选的两种形态，键盘与卡片共用同一顺序。
## @return 与当前流派匹配的形态标识数组。
func evolution_options() -> Array[String]:
	if hero.evolution != "":
		var locked: Array[String] = []
		locked.append(hero.evolution)
		return locked
	var options: Array[String] = []
	for id in BuildEvolution.FORMS:
		if BuildEvolution.FORMS[id].build == hero.build_id: options.append(id)
	return options

## 出售背包中的装备并退回目录价格的一半；穿戴中的装备需先卸下。
## @param index 背包里的装备索引。
## @return 商品存在且成功出售时返回 true。
func sell_item(index: int) -> bool:
	if state != "ready" or index < 0 or index >= hero.inventory.size(): return false
	var item_id: String = hero.inventory[index]
	gold += int(HeroRPG.ITEMS[item_id].price / 2)
	hero.inventory.remove_at(index)
	hero.inventory_affixes.remove_at(index)
	hero.inventory_rolls.remove_at(index)
	show_notice("已出售：" + HeroRPG.ITEMS[item_id].name)
	return true

## 穿戴背包物品后立即更新原战斗变量，使装备加成参与下一次伤害和受击。
## @param index 背包物品索引。
## @return 成功穿戴或交换时返回 true。
func equip_item(index: int) -> bool:
	if not hero.equip(index): return false
	sync_hero_stats()
	return true

## 卸下指定装备并立即撤销其属性；满背包时保持原状态。
## @param slot 装备部位标识。
## @return 成功卸下时返回 true。
func unequip_item(slot: String) -> bool:
	if not hero.unequip(slot): return false
	sync_hero_stats()
	return true

## 在状态栏短暂显示购买失败、技能锁定等操作结果。
## @param message 用户可读的操作结果。
func show_notice(message: String) -> void:
	notice = message
	notice_time = 2.5

## 处理移动以外的输入：建造、开波、强化和重新开始。
## @param event 本帧 Godot 输入事件。
func _unhandled_input(event: InputEvent) -> void:
	if equipment_ui.handle(self, event): return
	if event is InputEventKey and event.pressed and not event.echo:
		if state == "select_hero":
			if event.physical_keycode == KEY_1: select_hero("berserker")
			if event.physical_keycode == KEY_2: select_hero("frost_mage")
			return
		if state == "dungeon":
			match event.physical_keycode:
				KEY_ESCAPE: leave_dungeon()
				KEY_F: dodge()
				KEY_Q: dungeon_scene.cast_skill(0, get_global_mouse_position())
				KEY_W: dungeon_scene.cast_skill(1, get_global_mouse_position())
				KEY_E: dungeon_scene.cast_skill(2, get_global_mouse_position())
				KEY_R: dungeon_scene.cast_skill(3, get_global_mouse_position())
			return
		if evolution_open:
			var options := evolution_options()
			if event.physical_keycode == KEY_1: select_evolution(options[0])
			elif event.physical_keycode == KEY_2: select_evolution(options[1]) if options.size() > 1 else select_evolution(options[0])
			elif event.physical_keycode in [KEY_V, KEY_ESCAPE]: evolution_open = false
			return
		if build_open:
			match event.physical_keycode:
				KEY_1: select_build("skill")
				KEY_2: select_build("passive")
				KEY_3: select_build("summon")
				KEY_C, KEY_ESCAPE: build_open = false
			return
		if shop_open or inventory_open:
			if event.physical_keycode == KEY_T and shop_open: buy_affix_chest()
			elif event.physical_keycode == KEY_B: shop_open = false
			elif event.physical_keycode == KEY_I: inventory_open = false
			elif event.physical_keycode == KEY_J:
				shop_open = false
				inventory_open = false
				equipment_ui.toggle(self)
			return
		match event.physical_keycode:
			KEY_J: equipment_ui.toggle(self)
			KEY_V: evolution_open = state in ["ready", "upgrade"] and SkillEvolution.available(hero, wave)
			KEY_C: build_open = state == "ready" and wave == 0
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
				elif state == "fighting": cast_skill(0, get_global_mouse_position())
			KEY_W:
				if state == "fighting": cast_skill(1, get_global_mouse_position())
			KEY_E:
				if state == "upgrade": apply_upgrade(upgrade_choices[1])
				elif state == "fighting": cast_skill(2, get_global_mouse_position())
			KEY_R:
				if state == "won" or state == "lost": get_tree().reload_current_scene()
				elif state == "fighting": cast_skill(3, get_global_mouse_position())
			KEY_B: shop_open = state == "ready" and not shop_open
			KEY_G: enter_dungeon()
			KEY_I: inventory_open = not inventory_open
			KEY_5: upgrade_hero_skill(0)
			KEY_6: upgrade_hero_skill(1)
			KEY_7: upgrade_hero_skill(2)
			KEY_8: upgrade_hero_skill(3)
	if event is InputEventMouseButton and event.pressed:
		if state == "dungeon": return
		if evolution_open:
			if event.button_index == MOUSE_BUTTON_LEFT:
				for i in evolution_options().size():
					if Rect2(200 + i * 450, 270, 420, 190).has_point(get_global_mouse_position()): select_evolution(evolution_options()[i])
			return
		if build_open:
			if event.button_index == MOUSE_BUTTON_LEFT:
				for i in 3:
					if Rect2(100 + i * 360, 230, 330, 260).has_point(get_global_mouse_position()): select_build(["skill", "passive", "summon"][i])
			return
		if state == "select_hero" and event.button_index == MOUSE_BUTTON_LEFT:
			if Rect2(265, 270, 345, 210).has_point(get_global_mouse_position()): select_hero("berserker")
			elif Rect2(670, 270, 345, 210).has_point(get_global_mouse_position()): select_hero("frost_mage")
			return
		if shop_open and event.button_index == MOUSE_BUTTON_LEFT:
			var point := get_global_mouse_position()
			if Rect2(110, 551, 500, 30).has_point(point):
				buy_affix_chest()
				return
			for i in HeroRPG.ITEM_IDS.size():
				if Rect2(110 + (i % 2) * 530, 150 + int(i / 2) * 68, 500, 57).has_point(point): buy_item(HeroRPG.ITEM_IDS[i]); break
			if Rect2(905, 570, 255, 60).has_point(point): buy_item("potion")
			return
		if inventory_open and event.button_index == MOUSE_BUTTON_LEFT:
			var point := get_global_mouse_position()
			for i in hero.inventory.size():
				if Rect2(100 + (i % 2) * 530, 330 + int(i / 2) * 48, 500, 42).has_point(point):
					if Input.is_key_pressed(KEY_SHIFT): sell_item(i)
					else: equip_item(i)
					break
			for i in HeroRPG.SLOTS.size():
				if Rect2(100 + (i % 3) * 350, 140 + int(i / 3) * 70, 320, 60).has_point(point): unequip_item(HeroRPG.SLOTS[i]); break
			return
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
	var direction := movement_vector()
	player_pos += direction * (hero.stats().get("speed", PLAYER_SPEED) if hero.hero_id != "" else PLAYER_SPEED) * move_multiplier * delta
	player_pos = player_pos.clamp(Vector2(22, 92), Vector2(1258, 695))

## 读取方向键移动，避免 W 键既移动又释放英雄技能导致误触。
## @return 单位长度以内的二维移动方向。
func movement_vector() -> Vector2:
	return Vector2(float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT)), float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP))).normalized()

## 朝移动方向短距离闪避；无移动输入时朝鼠标方向，短暂无敌用于躲避可见弹丸。
func dodge() -> void:
	if (state != "fighting" and state != "dungeon") or dodge_cooldown > 0.0:
		return
	var direction := movement_vector()
	if direction == Vector2.ZERO:
		direction = (get_global_mouse_position() - player_pos).normalized()
	if direction == Vector2.ZERO:
		return
	if state == "dungeon" and dungeon_scene != null:
		dungeon_scene.hero_pos = (dungeon_scene.hero_pos + direction * 105.0).clamp(Vector2(50, 110), Vector2(1230, 660))
	else:
		player_pos = (player_pos + direction * 105.0).clamp(Vector2(22, 92), Vector2(1258, 695))
	dodge_timer = 0.22
	dodge_cooldown = 2.5
	impacts.append({"pos": player_pos, "time": 0.2, "color": Color("80deff")})

## 返回指定波的敌人总数，供开波和测试共同使用。
## @param number 从 1 开始的波次编号。
## @return 此波需要生成的敌人数量。
func wave_enemy_count(number: int) -> int:
	return WAVE_COUNTS[clampi(number - 1, 0, MAX_WAVES - 1)]

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
	enemy_director.plan(self, wave)
	show_notice(enemy_director.label())
	build_open = false
	evolution_open = false
	spawn_left = wave_enemy_count(wave)
	spawned_this_wave = 0
	spawn_timer = 0.0
	bounty_kills = 0
	state = "fighting"

## 按小队生成敌人，小队内部逐夜加快，两队之间保留一点五秒喘息窗口。
## 单帧最多生成一只，避免卡顿后一次补出整队造成不可读的瞬时压力。
## @param delta 本帧经过的秒数。
func update_spawning(delta: float) -> void:
	if spawn_left == 0:
		return
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		# 类型按夜次逐步解锁，精英和 Boss 只在对应事件夜出现。
		var kind := enemy_kind_for(wave, spawned_this_wave)
		var hp := 30.0 + wave * 14.0
		var speed := 65.0 + wave * 8.0
		var radius := 17.0
		var reward := 3
		if kind == "runner":
			hp *= 0.65
			speed *= 1.55
			radius = 14.0
			reward = 4
		elif kind == "armored":
			hp *= 1.7
			speed *= 0.7
			radius = 20.0
			reward = 6
		elif kind == "ranged":
			hp *= 0.8
			reward = 5
		elif kind == "elite":
			hp *= 5.0
			speed *= 0.7
			radius = 25.0
			reward = 25
		elif kind == "boss":
			# 首领预算按各流派破甲后的协同输出计算；技能流只有普通攻击时难以磨穿战甲。
			hp *= 20.0
			speed *= 0.48
			radius = 35.0
			reward = 70
		enemies.append({"pos": Vector2(20, 340), "segment": 0, "route": route_from(Vector2(20, 340)), "route_index": 0, "hp": hp, "max_hp": hp, "speed": speed, "attack_timer": 0.0, "windup": 0.0, "target_kind": "", "aim": Vector2.ZERO, "kind": kind, "radius": radius, "reward": reward})
		enemy_director.assign(enemies.back(), spawned_this_wave)
		spawn_left -= 1
		spawned_this_wave += 1
		var squad_size := 5 + int(wave / 2)
		spawn_timer += 1.5 if spawned_this_wave % squad_size == 0 else maxf(0.18, 0.45 - wave * 0.035)

## 计算护甲后的实际受伤，避免堆到一个阈值后整类攻击永久降到一点。
## @param amount 本次攻击的原始伤害。
## @param armor 英雄或核心的护甲值；负值按零计算。
## @param ward 是否正在使用寒冰护盾，护盾额外减伤百分之三十五。
## @return 非零攻击至少造成一点伤害；护甲越高收益递减。
func incoming_damage(amount: float, armor: float, ward: bool = false) -> float:
	if amount <= 0.0: return 0.0
	return maxf(1.0, amount * 20.0 / (20.0 + maxf(0.0, armor)) * (0.65 if ward else 1.0))

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
			var pet := summon_health.nearest(combat_builds.familiars, pos, range_to_player)
			# 已突破防线抵达核心的敌人优先攻击核心，不能靠贴身引怪无限拖延结算。
			if pos.distance_to(CORE_POS) < 34.0:
				enemy.target_kind = "core"
				enemy.aim = CORE_POS
				enemy.windup = 0.35
				enemy.attack_timer = 1.35
			elif not pet.is_empty() and pos.distance_to(pet.pos) < pos.distance_to(player_pos):
				enemy.target_kind = "summon"
				enemy.target_pet = pet
				enemy.aim = pet.pos
				enemy.windup = 0.65 if ranged else 0.28
				enemy.attack_timer = enemy.windup + 1.35
			elif pos.distance_to(player_pos) < range_to_player:
				enemy.target_kind = "player"
				enemy.aim = player_pos
				enemy.windup = 0.65 if enemy.kind == "boss" else 0.45 if ranged else 0.28
				enemy.attack_timer = enemy.windup + (1.8 if enemy.kind == "boss" else 1.35 if ranged else 0.9)
			elif enemy.kind == "ranged" and tower_at_range(pos, 155.0) >= 0:
				enemy.target_kind = "tower"
				enemy.aim = towers[tower_at_range(pos, 155.0)].pos
				enemy.windup = 0.45
				enemy.attack_timer = 1.8
		if enemy.windup <= 0.0 and enemy.target_kind == "":
			var remaining: float = enemy.speed * (enemy.get("slow_factor", 1.0) if enemy.get("slow_time", 0.0) > 0.0 else 1.0) * delta
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
		enemy.slow_time = maxf(0.0, enemy.get("slow_time", 0.0) - delta)
		enemies[i] = enemy

## 在前摇结束时结算近战，或发射沿预警方向飞行的敌方弹丸。
## @param enemy 前摇中的敌人数据，包含目标类型与锁定位置。
func resolve_enemy_attack(enemy: Dictionary) -> void:
	var target_kind: String = enemy.target_kind
	enemy.target_kind = ""
	if target_kind in ["player", "summon"] and (enemy.kind == "ranged" or enemy.kind == "boss"):
		var direction: Vector2 = (enemy.aim - enemy.pos).normalized()
		if direction == Vector2.ZERO: direction = Vector2.LEFT
		var count := 3 if enemy.kind == "boss" else 1
		for index in count:
			var spread := (index - 1) * 0.22 if count == 3 else 0.0
			hostile_bullets.append({"pos": enemy.pos, "velocity": direction.rotated(spread) * (360.0 if enemy.kind == "boss" else 300.0), "damage": 12.0 if enemy.kind == "boss" else 6.0, "life": 1.5, "radius": 9.0 if enemy.kind == "boss" else 7.0})
	elif target_kind == "summon":
		var pet: Dictionary = enemy.get("target_pet", {})
		if combat_builds.familiars.has(pet) and enemy.pos.distance_to(pet.pos) < enemy.radius + 20.0:
			summon_health.damage(self, pet, 9.0)
	elif target_kind == "tower":
		var direction: Vector2 = (enemy.aim - enemy.pos).normalized()
		hostile_bullets.append({"pos": enemy.pos, "velocity": direction * 300.0, "damage": 8.0, "life": 1.0, "radius": 7.0})
	elif target_kind == "player" and enemy.pos.distance_to(player_pos) < enemy.radius + 20.0 and dodge_timer <= 0.0:
		var damage := incoming_damage(9.0, player_armor, hero.ward_time > 0.0)
		player_hp -= damage
		add_damage_text(player_pos, damage, Color("ff7777"))
	elif target_kind == "core" and enemy.pos.distance_to(CORE_POS) < 42.0:
		var damage := incoming_damage(30.0 if enemy.kind == "boss" else 16.0 if enemy.kind == "elite" else 11.0, core_armor)
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
		if summon_health.intercept(self, bullet):
			consumed = true
		elif bullet.pos.distance_to(player_pos) < bullet.radius + 15.0:
			consumed = true
			if dodge_timer <= 0.0:
				var damage := incoming_damage(bullet.damage, player_armor, hero.ward_time > 0.0)
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
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): fire_at(get_global_mouse_position())

## 按真实冷却朝指定位置发射普攻弹丸，鼠标操作和自动回归使用相同入口。
## 射程和基础间隔来自英雄配置；寿命随弹速换算，攻速和弹速强化不会绕过职业射程。
## @param target 鼠标或控制器瞄准的世界坐标，单位为像素。
## @return 战斗中且非建塔模式、冷却结束并有有效方向时返回 true。
func fire_at(target: Vector2) -> bool:
	if state != "fighting" or selected_tower != 0 or fire_timer > 0.0: return false
	var aim := target - player_pos
	if aim.length() < 4.0:
		return false
	var velocity := aim.normalized() * BULLET_SPEED * bullet_speed_multiplier
	var stats: Dictionary = hero.stats()
	var lifetime: float = stats.basic_range / velocity.length()
	bullets.append({"pos": player_pos, "velocity": velocity, "damage": player_damage, "life": lifetime, "radius": 5.0, "color": Color("ffe074"), "knockback": bullet_knockback})
	if multishot:
		bullets.append({"pos": player_pos, "velocity": velocity.rotated(0.17), "damage": player_damage * 0.7, "life": lifetime, "radius": 5.0, "color": Color("ffe074"), "knockback": bullet_knockback})
	impacts.append({"pos": player_pos + aim.normalized() * 24.0, "time": 0.12, "color": Color("ffe074")})
	fire_timer = stats.basic_interval / (gun_rate_multiplier * stats.rate)
	return true

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
			# 重炮对重甲保留八成五伤害，命中后波及附近单位；速射塔维持单目标高频输出。
			bullets.append({"pos": tower.pos, "velocity": direction * 520.0, "damage": tower.damage * tower_multiplier, "life": 1.0, "radius": 6.0 if tower.kind == 1 else 10.0, "color": Color("7fffd4") if tower.kind == 1 else Color("ff9b71"), "knockback": 7.0 if tower.kind == 1 else 26.0, "source": "tower", "armor_factor": 0.55 if tower.kind == 1 else 0.85, "splash": 0.0 if tower.kind == 1 else 65.0})
			tower.cooldown = (0.42 if tower.kind == 1 else 1.15) / tower_rate_multiplier
		towers[i] = tower

## 更新弹丸并执行命中结算；倒序删除防止跳过元素。
## @param delta 本帧经过的秒数。
func update_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var bullet := bullets[i]
		# 按剩余寿命限制本帧行程，低帧率不能让有限射程的普攻继续飞出整帧距离。
		bullet.pos += bullet.velocity * minf(delta, maxf(0.0, bullet.life))
		bullet.life -= delta
		var hit := -1
		for j in enemies.size():
			if bullet.pos.distance_to(enemies[j].pos) < enemies[j].radius + bullet.radius:
				hit = j
				break
		if hit >= 0:
			# 先保存爆心，再倒序结算；击杀删除数组时仍能保证每个目标只受伤一次。
			var center: Vector2 = enemies[hit].pos
			var splash: float = bullet.get("splash", 0.0)
			for target in range(enemies.size() - 1, -1, -1):
				if target == hit:
					apply_bullet_damage(target, bullet, 1.0)
				elif splash > 0.0 and enemies[target].pos.distance_to(center) <= splash:
					apply_bullet_damage(target, bullet, 0.45)
			impacts.append({"pos": bullet.pos, "time": 0.2, "color": bullet.color})
			if splash > 0.0: impacts.append({"pos": center, "time": 0.2, "color": Color("ff9b71"), "radius": splash})
			bullets.remove_at(i)
		elif bullet.life <= 0.0 or not Rect2(-50, -50, 1380, 820).has_point(bullet.pos):
			bullets.remove_at(i)
		else:
			bullets[i] = bullet

## 结算一枚弹丸对一个目标的伤害、击退和击杀，重炮溅射复用同一奖励路径。
## 精英与首领未破甲时同时抵抗物理伤害和击退，各流派破甲后的五秒窗口恢复正常结算。
## @param index 本次倒序结算中的敌人索引。
## @param bullet 含伤害、方向、来源和重甲系数的真实弹丸。
## @param scale 直接命中为一，溅射为零点四五。
func apply_bullet_damage(index: int, bullet: Dictionary, scale: float) -> void:
	var enemy := enemies[index]
	if bullet.get("break_seconds", 0.0) > 0.0:
		enemy.exposed_time = bullet.break_seconds
		evolution_system.interrupt(enemy)
	# 1. 先记录目标真实损血，避免重炮溅射的溢出伤害虚增平衡统计。
	var armor_factor: float = maxf(bullet.get("armor_factor", 0.55), armor_penetration) if enemy.kind == "armored" and not bullet.get("magic", false) else 1.0
	var guarded: bool = enemy.kind in ["elite", "boss"] and enemy.get("exposed_time", 0.0) <= 0.0 and not bullet.get("magic", false)
	var dealt: float = bullet.damage * scale * armor_factor * (boss_bonus if enemy.kind == "boss" else 1.0) * (GUARD_DAMAGE_MULTIPLIER if guarded else 1.0)
	if enemy.get("shield_time", 0.0) > 0.0 and not bullet.get("magic", false): dealt *= 0.65
	var actual := minf(dealt, maxf(0.0, enemy.hp))
	var source: String = bullet.get("source", "hero")
	if source == "tower": tower_damage_dealt += actual
	elif source == "summon": summon_damage_dealt += actual
	else:
		hero_damage_dealt += actual
		if source == "skill": hero_skill_damage += actual
		elif source == "affix": hero_affix_damage += actual
		elif source == "passive": hero_passive_damage += actual
		else: hero_basic_damage += actual
	enemy.hp -= dealt
	enemy.hit_time = 0.16
	# 战甲同时抵抗击退，防止多塔把首领永久顶在路口、靠非零伤害慢慢磨死。
	# 战甲被击破后恢复击退效果，让控制与输出窗口具有实际价值。
	var knockback_factor := 0.10 if guarded else 1.0
	enemy.pos -= bullet.velocity.normalized() * bullet.knockback * scale * knockback_factor
	add_damage_text(enemy.pos, dealt, Color("ffe074"))
	var impact_pos: Vector2 = enemy.pos
	# 2. 真实死亡后立即移出碰撞数组，金币与经验仅经过一次统一击杀路径。
	if enemy.hp <= 0.0:
		death_frames.append({"pos": enemy.pos, "kind": enemy.kind, "time": 0.35})
		enemies.remove_at(index)
		reward_enemy(enemy)
	else: enemies[index] = enemy
	if source == "hero" and actual > 0.0:
		combat_builds.on_basic_hit(self, impact_pos)
		evolution_system.on_hit(self, impact_pos)

## 记录一次命中数字，显示实际结算伤害而非武器面板值。
## @param pos 命中位置，单位为画面像素。
## @param amount 扣除的生命值。
## @param color 区分我方和敌方伤害的颜色。
func add_damage_text(pos: Vector2, amount: float, color: Color) -> void:
	hit_texts.append({"pos": pos, "value": ceili(amount), "time": 0.65, "color": color})

## 逐帧消退枪口闪光、命中光圈和飘字，避免特效无限累积。
## @param delta 本帧经过的秒数。
func update_feedback(delta: float) -> void:
	# 残影与真实敌人分开推进，避免视觉死亡帧重复触发奖励。
	for i in range(death_frames.size() - 1, -1, -1):
		death_frames[i].time -= delta
		if death_frames[i].time <= 0.0: death_frames.remove_at(i)
	for enemy in enemies:
		enemy.hit_time = maxf(0.0, enemy.get("hit_time", 0.0) - delta)
		enemy.exposed_time = maxf(0.0, enemy.get("exposed_time", 0.0) - delta)
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
			hero_health_bonus += 20.0
			max_player_hp += 20.0
			player_hp = minf(max_player_hp, player_hp + 45.0)
		"急救包":
			hero_health_bonus += 5.0
			max_player_hp += 5.0
			player_hp = minf(max_player_hp, player_hp + 60.0)
		"枪械增幅":
			hero_attack_bonus += 8.0
			player_damage += 8.0
		"快速扳机": gun_rate_multiplier += 0.2
		"高速弹头": bullet_speed_multiplier += 0.25
		"冲击弹": bullet_knockback += 12.0
		"双重射击":
			if multishot:
				hero_attack_bonus += 4.0
				player_damage += 4.0
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
		"赏金猎人": gold_bonus += 1
		"军需补给": gold += 45
		"防弹衣":
			hero_armor_bonus += 2.0
			player_armor += 2.0
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

## 把炮塔、英雄和敌人的战斗状态映射到同一套 CC0 像素素材；动画由时间和战斗状态驱动。
## @param art 实际绘制的贴图。
## @param pos 单位中心坐标，单位为画面像素。
## @param size 绘制边长，单位为画面像素。
## @param tint 受伤或攻击时的颜色反馈。
func draw_unit(art: Texture2D, pos: Vector2, size: float, tint: Color = Color.WHITE) -> void:
	var bob := sin(Time.get_ticks_msec() * 0.009 + pos.x) * 2.0
	draw_texture_rect(art, Rect2(pos + Vector2(-size / 2.0, -size / 2.0 + bob), Vector2(size, size)), false, tint)

## 将塔的内部目标策略转换为玩家可见的中文名称。
## @param priority 塔的目标策略标识。
## @return 对应的中文名称；未知标识按最近目标显示。
func priority_name(priority: String) -> String:
	return {"nearest": "最近", "front": "最前", "strong": "最强"}.get(priority, "最近")

## 转换商店和背包共用的装备稀有度名称。
## @param rarity 装备目录中的稀有度标识。
## @return 中文稀有度名称；未知标识显示为未知。
func rarity_name(rarity: String) -> String:
	return {"common": "普通", "rare": "稀有", "epic": "史诗"}.get(rarity, "未知")

## 转换背包中的装备槽名称，不修改实际装备关系。
## @param slot 装备目录中的槽位标识。
## @return 对应的中文槽位名称；未知标识显示为未知。
func slot_name(slot: String) -> String:
	return {"weapon": "武器", "head": "头部", "chest": "胸甲", "hands": "手部", "legs": "腿部", "relic": "饰品"}.get(slot, "未知")

## 绘制战场、单位、状态栏及波间选择；中文均使用随项目打包的字体。
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), BG)
	# 地面与道路保持原有碰撞、导航和建塔判定，仅替换视觉表现。
	for x in range(0, 1280, 40):
		for y in range(80, 720, 40):
			draw_texture_rect(FLOOR_ART, Rect2(x, y, 40, 40), false, Color("737f84"))
	for x in range(0, 1280, 40):
		draw_line(Vector2(x, 85), Vector2(x, 720), Color("192839"), 1.0)
	for y in range(100, 720, 40):
		draw_line(Vector2(0, y), Vector2(1280, y), Color("192839"), 1.0)
	for i in range(PATH.size() - 1):
		draw_line(PATH[i], PATH[i + 1], ROAD, 76.0, true)
		draw_line(PATH[i], PATH[i + 1], Color("698095"), 2.0, true)
		var distance := PATH[i].distance_to(PATH[i + 1])
		for step in range(0, int(distance), 36):
			var point := PATH[i].lerp(PATH[i + 1], float(step) / distance)
			draw_texture_rect(ROAD_ART, Rect2(point - Vector2(20, 20), Vector2(40, 40)), false)
	draw_unit(CORE_ART, CORE_POS, 70.0)
	for i in towers.size():
		var tower := towers[i]
		draw_unit(TOWER_FAST if tower.kind == 1 else TOWER_HEAVY, tower.pos, 48.0)
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
		var art: Texture2D = ENEMY_GRUNT
		match enemy.kind:
			"runner": art = ENEMY_RUNNER
			"armored": art = ENEMY_ARMORED
			"ranged": art = ENEMY_RANGED
			"elite": art = ENEMY_ELITE
			"boss": art = ENEMY_BOSS
		# 受击时短暂发亮，蓄力时用原有预警线表示攻击状态。
		draw_unit(art, enemy.pos, enemy.radius * 2.4, Color("ff8e8e") if enemy.get("hit_time", 0.0) > 0.0 else Color.WHITE if enemy.windup <= 0.0 else color)
		draw_rect(Rect2(enemy.pos + Vector2(-enemy.radius, -enemy.radius - 9.0), Vector2(enemy.radius * 2.0 * enemy.hp / enemy.max_hp, 4)), Color("ffdc7d"))
		if enemy.kind in ["elite", "boss"]:
			var exposed: bool = enemy.get("exposed_time", 0.0) > 0.0
			draw_arc(enemy.pos, enemy.radius + 5.0, 0.0, TAU, 24, Color("ffbd7a") if exposed else Color("80deff"), 2.0)
			draw_string(UI_FONT, Vector2(maxf(20.0, enemy.pos.x - 35.0), enemy.pos.y - enemy.radius - 17), "破甲 %.1f秒" % enemy.exposed_time if exposed else "战甲：技能／三连／幻影破甲", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("ffbd7a") if exposed else Color("80deff"))
		if enemy.windup > 0.0:
			draw_line(enemy.pos, enemy.aim, Color("ff7272", 0.7), 2.0)
			draw_arc(enemy.aim, 18.0, 0.0, TAU, 24, Color("ff7272"), 2.0)
		if enemy.kind == "boss":
			draw_rect(Rect2(825, 155, 400, 20), Color("182b41"))
			draw_rect(Rect2(833, 161, 384.0 * maxf(0.0, enemy.hp) / enemy.max_hp, 8), Color("ec5370"))
			draw_string(UI_FONT, Vector2(825, 148), "首领：躲开预警范围", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ffd2a8"))
	# 敌人移出战斗数组后缩小淡出，表示死亡且不会继续受击。
	for frame in death_frames:
		var art: Texture2D = ENEMY_BOSS if frame.kind == "boss" else ENEMY_ELITE if frame.kind == "elite" else ENEMY_GRUNT
		var size: float = 45.0 * frame.time / 0.35
		draw_texture_rect(art, Rect2(frame.pos - Vector2(size, size) / 2.0, Vector2(size, size)), false, Color(1, 1, 1, frame.time / 0.35))
	for bullet in bullets:
		draw_circle(bullet.pos, bullet.radius, bullet.color)
	for bullet in hostile_bullets:
		draw_circle(bullet.pos, bullet.radius, Color("ff7777"))
		draw_arc(bullet.pos, bullet.radius + 3.0, 0.0, TAU, 16, Color("ffd2a8"), 2.0)
	for impact in impacts:
		var radius: float = impact.get("radius", 17.0) * (1.0 - impact.time / 0.2)
		draw_arc(impact.pos, 9.0 + radius, 0.0, TAU, 24, impact.color, 2.0)
	for item in hit_texts:
		var tint: Color = item.color
		tint.a = clampf(item.time / 0.65, 0.0, 1.0)
		draw_string(UI_FONT, item.pos, str(item.value), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, tint)
	combat_builds.draw(self, self)
	evolution_system.draw(self, enemies, UI_FONT)
	draw_unit(HERO_MAGE if hero.hero_id == "frost_mage" else HERO_WARRIOR, player_pos, 43.0)
	if dodge_timer > 0.0:
		draw_arc(player_pos, 23.0, 0.0, TAU, 24, Color("80deff"), 3.0)
	draw_line(player_pos, player_pos + (get_global_mouse_position() - player_pos).normalized() * 27.0, Color.WHITE, 5.0)
	draw_rect(Rect2(0, 0, 1280, 85), Color("182b41"))
	var font := UI_FONT
	draw_string(font, Vector2(25, 33), "最后防线", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color.WHITE)
	draw_string(font, Vector2(25, 65), "方向键移动  鼠标射击  Q/W/E/R 技能  F 闪避  B 商店  I 背包  1/2 选塔", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("b6c8d7"))
	if selected_tower_index >= 0 and selected_tower_index < towers.size():
		var selected := towers[selected_tower_index]
		var upgrade_cost: int = 30 * selected.level
		var next_stats := "已满级" if selected.level >= 3 else "U 花费 %d 金币：伤害 %.0f→%.0f  射程 %.0f→%.0f" % [upgrade_cost, selected.damage, selected.damage * 1.35, selected.range + tower_range_bonus, selected.range + tower_range_bonus + 20.0]
		draw_rect(Rect2(18, 91, 760, 65), Color("182b41", 0.9))
		draw_string(font, Vector2(25, 117), "炮塔 %d级  生命 %d/%d  目标 %s｜H 修理 15 金币  X 出售  P 切换目标" % [selected.level, ceili(selected.hp), ceili(selected.max_hp), priority_name(selected.priority)], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
		draw_string(font, Vector2(25, 142), next_stats, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("80deff"))
	draw_string(font, Vector2(825, 32), "第 %d/%d 夜  金币 %d  剩余 %d" % [wave, MAX_WAVES, gold, spawn_left + enemies.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("ffe074"))
	draw_string(font, Vector2(825, 62), "生命 %d/%d   核心 %d/%d" % [ceili(player_hp), ceili(max_player_hp), ceili(core_hp), ceili(max_core_hp)], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	draw_string(font, Vector2(575, 65), "F 闪避 %s" % ("就绪" if dodge_cooldown <= 0.0 else "%.1fs" % dodge_cooldown), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("80deff"))
	draw_rect(Rect2(825, 73, 180.0 * maxf(0.0, player_hp) / max_player_hp, 5), Color("ffe074"))
	draw_rect(Rect2(1020, 73, 180.0 * maxf(0.0, core_hp) / max_core_hp, 5), Color("638cff"))
	if selected_tower > 0:
		var mouse := get_global_mouse_position()
		var legal := can_build_at(mouse) and gold >= (40 if selected_tower == 1 else 55)
		var tint := Color("7fffd4") if legal else Color("ff7777")
		draw_arc(mouse, 21.0, 0.0, TAU, 36, tint, 2.0)
		draw_arc(mouse, (180.0 if selected_tower == 1 else 225.0) + tower_range_bonus, 0.0, TAU, 72, Color(tint, 0.45), 1.5)
		draw_string(font, mouse + Vector2(26, -20), "建造：%d 金币" % (40 if selected_tower == 1 else 55) if legal else "不可建造／金币不足", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, tint)
	if state == "fighting" and wave >= 4:
		draw_string(font, Vector2(20, 180), enemy_director.label(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("ffe074"))
	var message := ("空格：开始第一夜｜C：选择流派" if wave == 0 else "空格：开始下一夜｜V：选择形态" if SkillEvolution.available(hero, wave) else "空格：开始下一夜") if state == "ready" else ""
	if state == "upgrade" and SkillEvolution.available(hero, wave):
		draw_string(font, Vector2(420, 425), "V：选择技能形态｜可先选择再挑战营地", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("b4ff91"))
	if state == "upgrade" and upgrade_choices.size() == 2:
		if dungeon_available(): draw_string(font, Vector2(420, 454), "G：进入哥布林营地｜选择强化可跳过", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("e7a6ff"))
		draw_rect(Rect2(300, 470, 680, 200), Color("182b41"))
		draw_string(font, Vector2(475, 515), "本夜已完成：选择一项强化", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("ffe074"))
		for i in 2:
			var card := Rect2(340 + i * 320, 545, 280, 110)
			draw_rect(card, Color("365a74"))
			draw_string(font, card.position + Vector2(18, 42), upgrade_choices[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color.WHITE)
			if upgrade_choices[i] == "赏金猎人":
				draw_string(font, card.position + Vector2(18, 62), "每夜前十次击杀各多得 1 金币", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("b6c8d7"))
			draw_string(font, card.position + Vector2(18, 79), "按 Q 选择" if i == 0 else "按 E 选择", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("b6c8d7"))
	if state == "won": message = "胜利！守住八夜。按 R 重新开始"
	if state == "lost": message = "失败！按 R 重新开始"
	if state == "won" or state == "lost":
		draw_rect(Rect2(240, 550, 800, 140), Color("182b41"))
		draw_string(font, Vector2(275, 600), "坚持夜数：%d    击败敌人：%d" % [wave, kills], HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("ffe074"))
	if state == "ready":
		draw_rect(Rect2(20, 575, 370, 42), Color("253e59"))
		draw_string(font, Vector2(35, 604), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	elif message != "":
		draw_rect(Rect2(240, 635, 800, 55), Color("253e59"))
		draw_string(font, Vector2(270, 670), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color.WHITE)
	# 胜负结算置于底部战斗栏之上，避免技能格和命中提示遮住重开说明。
	if state == "won" or state == "lost": return
	if hero.hero_id != "":
		draw_string(font, Vector2(770, 105), "按 5–8 升级 Q/W/E/R 技能", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("80deff"))
		draw_rect(Rect2(20, 672, 340, 7), Color("253e59"))
		draw_rect(Rect2(20, 672, 340.0 * hero.xp / hero.xp_to_next(), 7), Color("80deff"))
		draw_string(font, Vector2(20, 660), "%s %d级  经验 %d/%d  技能点 %d" % [HeroRPG.HEROES[hero.hero_id].name, hero.level, hero.xp, hero.xp_to_next(), hero.skill_points], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("80deff"))
		draw_string(font, Vector2(20, 633), "流派：%s %s" % [HeroRPG.BUILDS[hero.build_id].name, SkillEvolution.label(hero) if hero.evolution != "" else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("b4ff91"))
		for i in 4:
			var key_name: String = ["Q", "W", "E", "R"][i]
			var skill_rect := Rect2(375 + i * 100, 620, 94, 75)
			draw_rect(skill_rect, Color("365a74") if hero.cooldowns[i] <= 0.0 else Color("253545"))
			draw_string(font, skill_rect.position + Vector2(8, 23), "%s %d" % [key_name, hero.skill_levels[i]], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
			draw_string(font, skill_rect.position + Vector2(8, 44), hero.skill_names()[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
			draw_string(font, skill_rect.position + Vector2(8, 65), "被动" if hero.build_id == "passive" else "就绪" if hero.cooldowns[i] <= 0.0 else "%.1f秒" % hero.cooldowns[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("80deff"))
		if hero.build_id == "passive":
			draw_string(font, Vector2(800, 650), "连击 %d/%d｜热忱 %d/8（%.1f秒）" % [hero.combo_hits, SkillEvolution.combo_required(hero), hero.fervor_stacks, hero.fervor_time], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("b4ff91"))
		elif hero.build_id == "summon":
			draw_string(font, Vector2(800, 650), "幻影 %d｜集火 %.1f秒" % [combat_builds.familiars.size(), combat_builds.command_time], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("a1e9ff"))
	if notice_time > 0.0:
		draw_rect(Rect2(760, 575, 470, 43), Color("253e59"))
		draw_string(font, Vector2(775, 603), notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("ffe074"))
	if state == "select_hero":
		draw_rect(Rect2(190, 160, 900, 390), Color("182b41"))
		draw_string(font, Vector2(490, 220), "选择英雄", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("ffe074"))
		for i in 2:
			var rect := Rect2(265 + i * 405, 270, 345, 210)
			draw_rect(rect, Color("704b3e") if i == 0 else Color("365a74"))
			var title := "1  狂战士" if i == 0 else "2  寒霜法师"
			var detail := "高生命／近战／击退" if i == 0 else "冰霜／远程／减速"
			draw_unit(HERO_WARRIOR if i == 0 else HERO_MAGE, rect.position + Vector2(280, 100), 75.0)
			draw_string(font, rect.position + Vector2(30, 65), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
			draw_string(font, rect.position + Vector2(30, 115), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
	if shop_open:
		draw_rect(Rect2(65, 102, 1150, 560), Color("182b41"))
		draw_string(font, Vector2(100, 136), "商店：点击购买｜B 关闭｜金币 %d" % gold, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("ffe074"))
		for i in HeroRPG.ITEM_IDS.size():
			var id: String = HeroRPG.ITEM_IDS[i]
			var item: Dictionary = HeroRPG.ITEMS[id]
			var effect_label := ""
			if item.has("skill_power"):
				effect_label = "｜被动流不使用技能增幅" if hero.build_id == "passive" else ("｜幻影伤害 +%d%%" if hero.build_id == "summon" else "｜技能伤害 +%d%%") % int(item.skill_power * 100)
			match item.get("effect", ""):
				"rage_chain": effect_label = "｜追击 +25%" if hero.build_id == "passive" else "｜血怒伤害 +45%" if hero.build_id == "skill" and hero.hero_id == "berserker" else "｜职业特效未启用"
				"frost_burst": effect_label = "｜幻影溅射 65 像素" if hero.build_id == "summon" else "｜冰霜新星范围 +40%" if hero.build_id == "skill" and hero.hero_id == "frost_mage" else "｜职业特效未启用"
				"wide_sweep": effect_label = "｜追击范围 +40%" if hero.build_id == "passive" else "｜横扫范围 +55%" if hero.build_id == "skill" and hero.hero_id == "berserker" else "｜职业特效未启用"
			var pos := Vector2(110 + (i % 2) * 530, 150 + int(i / 2) * 68)
			draw_rect(Rect2(pos, Vector2(500, 57)), Color("365a74"))
			draw_string(font, pos + Vector2(12, 22), "%s [%s]  %d 金币%s" % [item.name, rarity_name(item.rarity), item.price, effect_label], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
			draw_string(font, pos + Vector2(12, 44), "攻击 %d  生命 %d  防御 %d  移速 %d  攻速 +%d%%" % [int(item.get("attack", 0)), int(item.get("health", 0)), int(item.get("defense", 0)), int(item.get("speed", 0)), int(item.get("rate", 0.0) * 100)], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("b6c8d7"))
		draw_rect(Rect2(110, 551, 500, 30), Color("42634a"))
		draw_string(font, Vector2(120, 573), "本阶段宝匣已购买" if chest_wave == wave else "T：词缀宝匣 50 金币｜每个准备阶段限购一次", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		draw_rect(Rect2(905, 570, 255, 60), Color("365a74"))
		draw_string(font, Vector2(110, 595), "护甲按比例减伤；速射塔单攻，重炮塔溅射并克制重甲。", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("b6c8d7"))
		draw_string(font, Vector2(110, 622), "战甲减伤 95%；攻击技能、三连追击、幻影法弹可破甲五秒。", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("80deff"))
		draw_string(font, Vector2(920, 605), "药剂：恢复 55 生命｜22 金币", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	if inventory_open:
		draw_rect(Rect2(65, 102, 1150, 560), Color("182b41"))
		draw_string(font, Vector2(100, 132), "装备：点击槽位卸下｜I 关闭", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("ffe074"))
		for i in HeroRPG.SLOTS.size():
			var slot: String = HeroRPG.SLOTS[i]
			var pos := Vector2(100 + (i % 3) * 350, 140 + int(i / 3) * 70)
			draw_rect(Rect2(pos, Vector2(320, 60)), Color("365a74"))
			draw_string(font, pos + Vector2(12, 24), "%s：%s" % [slot_name(slot), hero.item_label(hero.equipment[slot], hero.equipment_affixes.get(slot, "")).split("｜")[0] if hero.equipment.has(slot) else "空"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
			var affix: String = hero.equipment_affixes.get(slot, "")
			if affix != "": draw_string(font, pos + Vector2(12, 48), EquipmentSystem.summary(hero.equipment_rolls[slot]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("b4ff91"))
		draw_string(font, Vector2(100, 315), "背包 %d/%d：点击穿戴，Shift＋点击出售；J 重铸与词条详情" % [hero.inventory.size(), HeroRPG.CAPACITY], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("ffe074"))
		for i in hero.inventory.size():
			var pos := Vector2(100 + (i % 2) * 530, 330 + int(i / 2) * 48)
			draw_rect(Rect2(pos, Vector2(500, 42)), Color("365a74"))
			draw_string(font, pos + Vector2(12, 18), "%s  [%s]" % [hero.item_label(hero.inventory[i], hero.inventory_affixes[i]).split("｜")[0], rarity_name(HeroRPG.ITEMS[hero.inventory[i]].rarity)], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)

			if hero.inventory_affixes[i] != "": draw_string(font, pos + Vector2(12, 36), EquipmentSystem.summary(hero.inventory_rolls[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("b4ff91"))
	if build_open:
		draw_rect(Rect2(65, 150, 1150, 410), Color("182b41"))
		draw_string(font, Vector2(100, 196), "选择本局流派｜第一夜后锁定｜C 关闭", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color("ffe074"))
		for i in 3:
			var id: String = ["skill", "passive", "summon"][i]
			var build: Dictionary = HeroRPG.BUILDS[id]
			var card := Rect2(100 + i * 360, 230, 330, 260)
			draw_rect(card, Color("365a74") if id != hero.build_id else Color("42634a"))
			draw_string(font, card.position + Vector2(18, 45), "%d  %s" % [i + 1, build.name], HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color.WHITE)
			var lines: Array = [["攻击技能命中打开破甲窗口", "抓住窗口释放范围爆发", "装备选择：法杖、职业特效", "依赖主动技能与冷却管理"], ["普攻第三击触发范围追击", "连击回血，命中叠加攻速", "装备选择：武器、攻速、防御", "四个升级项均为被动"], ["Q 召唤，W 护佑，E 迁跃", "R 集火；幻影有寿命与射程", "装备选择：法杖、攻击、保命", "本体攻击降低两成"]][i]
			for j in lines.size():
				draw_string(font, card.position + Vector2(18, 94 + j * 35), lines[j], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("d7e7c6"))
			draw_string(font, Vector2(100, 530), "按 1／2／3 或点击卡片选择；升级键 5–8 随流派改变，商店与炮塔共用金币。", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("80deff"))

	if evolution_open:
		draw_rect(Rect2(160, 180, 960, 350), Color("182b41"))
		draw_string(font, Vector2(200, 230), "技能形态：选择路线或领取下一阶｜V 关闭", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color("ffe074"))
		var options := evolution_options()
		for i in options.size():
			var form: Dictionary = BuildEvolution.FORMS[options[i]]
			var card := Rect2(200 + i * 450, 270, 420, 190)
			draw_rect(card, Color("365a74"))
			draw_string(font, card.position + Vector2(20, 45), "%d  %s" % [i + 1, form.name if hero.evolution == "" else SkillEvolution.Rules.STAGES[hero.evolution][mini(2, hero.evolution_tier)]], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
			if hero.evolution != "":
				var next_index := mini(2, hero.evolution_tier)
				draw_string(font, Vector2(655, 320), "下一阶门槛：完成第 %d 夜／%d 级" % [SkillEvolution.Rules.NIGHTS[next_index], SkillEvolution.Rules.LEVELS[next_index]], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("80deff"))
				draw_string(font, Vector2(655, 365), "当前：已完成 %d 夜／%d 级" % [wave, hero.level], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
				draw_string(font, Vector2(655, 410), "按 1 进化，不消耗金币；V 稍后决定", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("b4ff91"))
			var parts: PackedStringArray = form.detail.split("；") if hero.evolution == "" else PackedStringArray([SkillEvolution.next_detail(hero)])
			for j in parts.size():
				draw_string(font, card.position + Vector2(20, 100 + j * 35), parts[j], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("d7e7c6"))

	equipment_ui.draw(self, self, font)
