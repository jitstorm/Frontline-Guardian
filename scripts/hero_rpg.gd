extends RefCounted
## 保存一局中的英雄成长与装备；金币由战场节点统一持有，避免商店产生第二套余额。

const CAPACITY := 12
const SLOTS: Array[String] = ["weapon", "head", "chest", "hands", "legs", "relic"]
const ITEM_IDS: Array[String] = ["rust_axe", "oak_staff", "iron_helm", "leather_vest", "runner_boots", "fighter_gloves", "vital_charm", "steel_blade", "guardian_mail", "berserker_mark", "frost_focus", "storm_grasp"]
## 装备价格单位为金币；skill_power 为额外技能伤害比例，零点三表示增加百分之三十。
const ITEMS := {
	"rust_axe": {"name": "旧战斧", "slot": "weapon", "rarity": "common", "price": 35, "attack": 5.0},
	"oak_staff": {"name": "橡木法杖", "slot": "weapon", "rarity": "common", "price": 35, "attack": 4.0, "skill_power": 0.30},
	"iron_helm": {"name": "铁盔", "slot": "head", "rarity": "common", "price": 28, "health": 18.0},
	"leather_vest": {"name": "皮甲", "slot": "chest", "rarity": "common", "price": 30, "defense": 2.0},
	"runner_boots": {"name": "疾行靴", "slot": "legs", "rarity": "common", "price": 30, "speed": 25.0},
	"fighter_gloves": {"name": "斗士手套", "slot": "hands", "rarity": "common", "price": 30, "rate": 0.15},
	"vital_charm": {"name": "生命护符", "slot": "relic", "rarity": "rare", "price": 65, "health": 35.0},
	"steel_blade": {"name": "精钢剑", "slot": "weapon", "rarity": "rare", "price": 70, "attack": 12.0},
	"guardian_mail": {"name": "守卫铠甲", "slot": "chest", "rarity": "rare", "price": 70, "defense": 5.0, "health": 20.0},
	"berserker_mark": {"name": "狂战印记", "slot": "relic", "rarity": "epic", "price": 110, "attack": 7.0, "effect": "rage_chain"},
	"frost_focus": {"name": "寒霜法器", "slot": "relic", "rarity": "epic", "price": 110, "attack": 6.0, "effect": "frost_burst"},
	"storm_grasp": {"name": "风暴之握", "slot": "hands", "rarity": "epic", "price": 100, "rate": 0.25, "effect": "wide_sweep"}
}
## 每件装备最多携带一个随机词缀，数值词缀按装备件数叠加，触发词缀按是否穿戴判断。
const AFFIXES := {
	"ember": {"name": "余烬", "detail": "每四次普攻命中引爆周围敌人"},
	"frost": {"name": "寒意", "detail": "普攻命中使目标附近敌人减速一秒"},
	"leech": {"name": "汲取", "detail": "普攻命中回血一点，冷却零点六秒"},
	"swift": {"name": "迅捷", "detail": "攻速增加百分之八"},
	"arcane": {"name": "秘法", "detail": "技能与幻影伤害增加百分之十二"},
	"vigor": {"name": "坚韧", "detail": "生命上限增加十二点"}
}
## 背包词缀与 inventory 严格同索引；装备词缀以槽位为键，交换和出售必须同步移动。
var inventory_affixes: Array[String] = []
var equipment_affixes: Dictionary = {}
## 本局选定的技能形态；第二夜后通过战场选择，一局只能选择一次。
var evolution := ""
## 余烬累计的真实命中次数及汲取剩余冷却秒数，切地图保留以防刷新触发频率。
var affix_hits := 0
var leech_timer := 0.0

## 英雄基础属性；skill_power 为技能增幅，basic_interval 为普攻间隔秒数，basic_range 为射程像素数。
## 两名英雄默认以主动技能为核心；流派随后调整普攻或召唤预算。
const HEROES := {
	"berserker": {"name": "狂战士", "health": 145.0, "attack": 19.0, "defense": 3.0, "rate": 1.0, "speed": 235.0, "skill_power": 0.0, "basic_interval": 0.48, "basic_range": 190.0},
	"frost_mage": {"name": "寒霜法师", "health": 95.0, "attack": 16.0, "defense": 1.0, "rate": 1.15, "speed": 255.0, "skill_power": 0.0, "basic_interval": 0.58, "basic_range": 380.0}
}
const SKILL_NAMES := {
	"berserker": ["横扫", "战吼", "血怒突进", "裂地击"],
	"frost_mage": ["冰枪", "冰霜新星", "寒冰护盾", "暴风雪"]
}
## 三种战斗流派在第一夜前选择并锁定，分别改变技能、普攻或召唤物的核心收益。
const BUILDS := {
	"skill": {"name": "技能爆发", "detail": "攻击技能破甲，抓住窗口集中输出", "tradeoff": "依赖主动技能，普攻用于补刀"},
	"passive": {"name": "连击被动", "detail": "普攻三连触发范围追击、破甲与回血", "tradeoff": "没有四个主动技能，依赖持续命中"},
	"summon": {"name": "幻影召唤", "detail": "召唤幻影自动攻击，用指令集中火力", "tradeoff": "本体攻击降低，需维护幻影与站位"}
}
## 被动与召唤流的四项成长名称；索引仍对应技能升级键五至八。
const BUILD_SKILL_NAMES := {
	"passive": ["三连追击", "连击汲取", "护甲训练", "战斗热忱"],
	"summon": ["幻影召唤", "灵体守护", "幻影迁跃", "集火指令"]
}

## 当前战斗流派；默认沿用主动技能玩法，第一夜开始后由战场禁止改选。
var build_id := "skill"
## 被动流已命中的普攻次数，默认第三次触发追击后归零，收割形态改为第五次，不统计空枪。
var combo_hits := 0
## 被动流命中叠加的热忱层数及剩余秒数；停止攻击三秒后清空。
var fervor_stacks := 0
var fervor_time := 0.0

## 当前选择的职业标识；空字符串表示尚未选英雄。
var hero_id := ""
## 本局等级和经验，经验只来自实际击杀。
var level := 1
var xp := 0
## 升级获得的未分配技能点。
var skill_points := 0
## Q/W/E/R 技能等级与剩余冷却，数组索引和按键一一对应。
var skill_levels := [1, 1, 1, 1]
var cooldowns := [0.0, 0.0, 0.0, 0.0]
## 未穿戴装备的目录标识；穿戴时移入对应槽位。
var inventory: Array[String] = []
var equipment: Dictionary = {}
## 战吼和冰盾剩余秒数，仅在实战或副本内递减。
var buff_time := 0.0
var ward_time := 0.0

## 选择本局英雄并清空上一局的等级、技能和物品状态。
## @param choice 英雄目录中的标识。
## @return 选择有效时返回 true，否则保持原状并返回 false。
func choose(choice: String) -> bool:
	if not HEROES.has(choice): return false
	hero_id = choice
	build_id = "skill"
	combo_hits = 0
	fervor_stacks = 0
	fervor_time = 0.0
	level = 1
	xp = 0
	skill_points = 0
	skill_levels = [1, 1, 1, 1]
	cooldowns = [0.0, 0.0, 0.0, 0.0]
	inventory.clear()
	inventory_affixes.clear()
	equipment_affixes.clear()
	evolution = ""
	affix_hits = 0
	leech_timer = 0.0
	equipment.clear()
	buff_time = 0.0
	ward_time = 0.0
	return true

## 计算当前英雄、等级、装备和临时增益合成后的实战属性。
## @return 含生命上限、攻击、防御、攻速、像素每秒移速、普攻间隔秒数和射程像素数的字典；未选英雄时为空。
func stats() -> Dictionary:
	if hero_id == "": return {}
	var result: Dictionary = HEROES[hero_id].duplicate()
	result.health += (level - 1) * (12.0 if hero_id == "berserker" else 8.0)
	result.attack += (level - 1) * (2.5 if hero_id == "berserker" else 3.0)
	for item_id in equipment.values():
		var item: Dictionary = ITEMS[item_id]
		for key in ["health", "attack", "defense", "rate", "speed", "skill_power"]:
			result[key] += item.get(key, 0.0)
	for affix in equipment_affixes.values():
		match affix:
			"swift": result.rate += 0.08
			"arcane": result.skill_power += 0.12
			"vigor": result.health += 12.0
	if buff_time > 0.0: result.rate += 0.3
	# 被动流把输出预算转给持续普攻；召唤流让出本体攻击给独立幻影。
	if build_id == "passive":
		result.basic_interval *= 0.68
		result.defense += 2.0 * skill_levels[2]
		result.rate += fervor_stacks * 0.025 * skill_levels[3]
	elif build_id == "summon": result.attack *= 0.8
	return result

## 获取当前流派的四项技能或被动名称，包含已选形态的名称，供升级栏及释放提示共同使用。
## @return 主动技能流返回职业技能名称，其他流派返回对应的四项成长名称。
func skill_names() -> Array:
	var names: Array = (SKILL_NAMES[hero_id] if build_id == "skill" else BUILD_SKILL_NAMES[build_id]).duplicate()
	var forms := {"echo": "回响" + names[0], "nova": "环形" + names[0], "chain": "连锁雷击", "reaper": "收割震波", "hunter": "游猎幻影", "sacrifice": "献祭幻影"}
	if forms.has(evolution): names[0] = forms[evolution]
	return names

## 增加击杀经验并按递增门槛升级，未选英雄时忽略经验。
## @param amount 本次真实击杀给予的经验点数。
## @return 本次提升的等级数。
func gain_xp(amount: int) -> int:
	if hero_id == "" or amount <= 0: return 0
	xp += amount
	var gained := 0
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		skill_points += 1
		gained += 1
	return gained

## 给经验条提供下一级所需经验；当前等级越高门槛越高。
## @return 升到下一级所需经验点数。
func xp_to_next() -> int:
	return 35 + (level - 1) * 20

## 花费一个技能点升级对应技能；每技能最高五级。
## @param index 按 Q、W、E、R 排列的技能索引。
## @return 扣点并升级成功时返回 true。
func upgrade_skill(index: int) -> bool:
	if index < 0 or index >= 4 or skill_points <= 0 or skill_levels[index] >= 5: return false
	skill_points -= 1
	skill_levels[index] += 1
	return true

## 计算技能基础伤害；实际目标护甲和范围由战场结算。
## @param index 技能索引。
## @return 当前等级和装备支持下的伤害；未解锁技能返回零。
func skill_damage(index: int) -> float:
	if index < 0 or index >= 4 or skill_levels[index] == 0: return 0.0
	var power: float = stats().get("attack", 0.0)
	var scales := [3.2, 0.6, 2.0, 4.5] if hero_id == "berserker" else [3.0, 1.35, 0.5, 3.6]
	# 法杖提供独立技能增幅，使武器选择在普攻和技能构筑之间产生取舍。
	return power * scales[index] * (1.0 + 0.3 * (skill_levels[index] - 1)) * (1.0 + stats().get("skill_power", 0.0))

## 在有可用背包位置时收下战利品或商店商品。
## @param item_id 装备目录中的标识。
## @param affix 可选词缀标识；空字符串表示原有普通商品。
## @return 商品存在、词缀合法且背包有空位时返回 true。
func pickup(item_id: String, affix: String = "") -> bool:
	if not ITEMS.has(item_id) or inventory.size() >= CAPACITY or (affix != "" and not AFFIXES.has(affix)): return false
	inventory.append(item_id)
	inventory_affixes.append(affix)
	return true

## 把背包装备放入对应槽位，并把原装备交换回背包。
## @param index 背包中待穿戴物品的索引。
## @return 交换成功时返回 true；无效索引不修改装备。
func equip(index: int) -> bool:
	if index < 0 or index >= inventory.size(): return false
	var item_id := inventory[index]
	var slot: String = ITEMS[item_id].slot
	if equipment.has(slot):
		inventory[index] = equipment[slot]
		var old_affix: String = equipment_affixes.get(slot, "")
		equipment_affixes[slot] = inventory_affixes[index]
		inventory_affixes[index] = old_affix
	else:
		equipment_affixes[slot] = inventory_affixes[index]
		inventory.remove_at(index)
		inventory_affixes.remove_at(index)
	equipment[slot] = item_id
	return true

## 将指定槽位物品取回背包，容量不足时保留原装备。
## @param slot 六种装备槽位之一。
## @return 成功卸下时返回 true。
func unequip(slot: String) -> bool:
	if not equipment.has(slot) or inventory.size() >= CAPACITY: return false
	inventory.append(equipment[slot])
	inventory_affixes.append(equipment_affixes.get(slot, ""))
	equipment_affixes.erase(slot)
	equipment.erase(slot)
	return true

## 查询已穿戴装备对技能机制的特殊修饰。
## @param effect 装备目录中的效果标识。
## @return 至少一件装备具有该效果时返回 true。
func has_effect(effect: String) -> bool:
	for item_id in equipment.values():
		if ITEMS[item_id].get("effect", "") == effect: return true
	return false

## 随战斗时间推进技能冷却和临时增益，准备阶段不调用。
## @param delta 已推进的真实战斗秒数。
func tick(delta: float) -> void:
	for i in cooldowns.size(): cooldowns[i] = maxf(0.0, cooldowns[i] - delta)
	buff_time = maxf(0.0, buff_time - delta)
	leech_timer = maxf(0.0, leech_timer - delta)
	ward_time = maxf(0.0, ward_time - delta)
	fervor_time = maxf(0.0, fervor_time - delta)
	if fervor_time <= 0.0: fervor_stacks = 0

## 判断是否穿戴指定触发词缀，多件同类词缀不会重复启动同一次命中效果。
## @param affix 装备词缀目录标识。
## @return 任意已穿戴槽位携带该词缀时返回 true。
func has_affix(affix: String) -> bool:
	return equipment_affixes.values().has(affix)

## 获取物品实例的中文名称和词缀效果，供背包与槽位显示。
## @param item_id 基础装备目录标识。
## @param affix 该物品实例的词缀，空值表示普通装备。
## @return 含基础名称及可读词缀效果的字符串。
func item_label(item_id: String, affix: String = "") -> String:
	return ITEMS[item_id].name if affix == "" else "%s·%s｜%s" % [AFFIXES[affix].name, ITEMS[item_id].name, AFFIXES[affix].detail]
