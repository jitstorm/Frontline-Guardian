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
## 英雄基础属性；skill_power 从零起步，由装备提供，生命和攻击仍按等级成长。
const HEROES := {
	"berserker": {"name": "狂战士", "health": 145.0, "attack": 19.0, "defense": 3.0, "rate": 1.0, "speed": 235.0, "skill_power": 0.0},
	"frost_mage": {"name": "寒霜法师", "health": 95.0, "attack": 16.0, "defense": 1.0, "rate": 1.15, "speed": 255.0, "skill_power": 0.0}
}
const SKILL_NAMES := {
	"berserker": ["横扫", "战吼", "血怒突进", "裂地击"],
	"frost_mage": ["冰枪", "冰霜新星", "寒冰护盾", "暴风雪"]
}

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
	level = 1
	xp = 0
	skill_points = 0
	skill_levels = [1, 1, 1, 1]
	cooldowns = [0.0, 0.0, 0.0, 0.0]
	inventory.clear()
	equipment.clear()
	buff_time = 0.0
	ward_time = 0.0
	return true

## 计算当前英雄、等级、装备和临时增益合成后的实战属性。
## @return 含生命上限、攻击、防御、攻速和像素每秒移速的字典；未选英雄时为空。
func stats() -> Dictionary:
	if hero_id == "": return {}
	var result: Dictionary = HEROES[hero_id].duplicate()
	result.health += (level - 1) * (12.0 if hero_id == "berserker" else 8.0)
	result.attack += (level - 1) * (2.5 if hero_id == "berserker" else 3.0)
	for item_id in equipment.values():
		var item: Dictionary = ITEMS[item_id]
		for key in ["health", "attack", "defense", "rate", "speed", "skill_power"]:
			result[key] += item.get(key, 0.0)
	if buff_time > 0.0: result.rate += 0.3
	return result

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
	var scales := [1.4, 0.6, 1.1, 2.6] if hero_id == "berserker" else [1.5, 0.85, 0.5, 2.0]
	# 法杖提供独立技能增幅，使武器选择在普攻和技能构筑之间产生取舍。
	return power * scales[index] * (1.0 + 0.3 * (skill_levels[index] - 1)) * (1.0 + stats().get("skill_power", 0.0))

## 在有可用背包位置时收下战利品或商店商品。
## @param item_id 装备目录中的标识。
## @return 商品存在且背包有空位时返回 true。
func pickup(item_id: String) -> bool:
	if not ITEMS.has(item_id) or inventory.size() >= CAPACITY: return false
	inventory.append(item_id)
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
	else:
		inventory.remove_at(index)
	equipment[slot] = item_id
	return true

## 将指定槽位物品取回背包，容量不足时保留原装备。
## @param slot 六种装备槽位之一。
## @return 成功卸下时返回 true。
func unequip(slot: String) -> bool:
	if not equipment.has(slot) or inventory.size() >= CAPACITY: return false
	inventory.append(equipment[slot])
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
	ward_time = maxf(0.0, ward_time - delta)
