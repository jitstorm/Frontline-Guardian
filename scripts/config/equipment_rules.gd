extends RefCounted
## 装备基础目录、词缀及品质权重配置；倍率作用于基础属性，词缀数值保持独立。

## price 单位金币，生命／攻击／护甲单位为点，speed 为像素每秒，rate 与 skill_power 为增益比例。
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
const AFFIXES := {
	"ember": {"name": "余烬", "detail": "每四次普攻命中引爆周围敌人"},
	"frost": {"name": "寒意", "detail": "普攻命中使目标附近敌人减速一秒"},
	"leech": {"name": "汲取", "detail": "普攻命中回血一点，冷却零点六秒"},
	"swift": {"name": "迅捷", "detail": "攻速增加百分之八"},
	"arcane": {"name": "秘法", "detail": "技能与幻影伤害增加百分之十二"},
	"vigor": {"name": "坚韧", "detail": "生命上限增加十二点"},
	"might": {"name": "强击", "detail": "攻击增加三点"},
	"armor": {"name": "铁壁", "detail": "护甲增加一点五"},
	"stride": {"name": "轻盈", "detail": "移速增加十像素每秒"},
	"reach": {"name": "远击", "detail": "普攻射程增加二十像素"},
	"renewal": {"name": "复苏", "detail": "每次击杀回复一点生命"},
	"focus": {"name": "专注", "detail": "主动技能和召唤指令冷却缩短百分之六"}
}

## 品质概率权重总和为一百，区间为基础属性倍率，count 为互不重复的词缀数量。
const QUALITIES := {
	"common": {"name": "普通", "weight": 45, "low": 0.90, "high": 1.00, "count": 1},
	"rare": {"name": "稀有", "weight": 32, "low": 1.03, "high": 1.12, "count": 2},
	"epic": {"name": "史诗", "weight": 18, "low": 1.12, "high": 1.25, "count": 3},
	"legend": {"name": "传说", "weight": 5, "low": 1.25, "high": 1.40, "count": 4}
}
## 宝匣与重铸基础费用，单位金币；重铸另外按词条数、锁定数及历史次数收费。
const CHEST_PRICE := 50
const REFORGE_BASE := 15
