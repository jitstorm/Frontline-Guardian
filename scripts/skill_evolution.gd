extends RefCounted
## 独立管理形态路线锁定、三阶解锁与形态专属反馈，不负责装备或敌人生成。
const Rules = preload("res://scripts/config/evolution_rules.gd")
const FORMS = Rules.FORMS

## 判断下一阶是否已满足夜次与等级门槛，最终阶后不再开放。
## @param hero 本局成长对象。
## @param night 已完成的夜数。
## @return 下一阶可领取时返回 true。
static func available(hero: RefCounted, night: int) -> bool:
	return hero.evolution_tier < 3 and night >= Rules.NIGHTS[hero.evolution_tier] and hero.level >= Rules.LEVELS[hero.evolution_tier]

## 选择初始路线或领取原路线下一阶，路线不可切换，失败不会改变阶段。
## @param hero 本局成长对象。
## @param night 已完成的夜数。
## @param choice 待选择路线标识，后续进阶必须与原路线相同。
## @return 本次实际进阶时返回 true。
static func advance(hero: RefCounted, night: int, choice: String) -> bool:
	if not available(hero, night) or not FORMS.has(choice) or FORMS[choice].build != hero.build_id: return false
	if hero.evolution != "" and hero.evolution != choice: return false
	hero.evolution = choice
	hero.evolution_tier += 1
	return true

## 返回形态的中文阶段名称；旧测试直接设置形态时按初阶显示。
## @param hero 本局成长对象。
## @return 当前路线与阶段名，未选时返回未进化。
static func label(hero: RefCounted) -> String:
	if hero.evolution == "": return "未进化"
	return "%s·%d阶" % [Rules.STAGES[hero.evolution][maxi(0, hero.evolution_tier - 1)], maxi(1, hero.evolution_tier)]

## 说明当前路线下一阶改变的机制，用于进化面板中的具体收益提示。
## @param hero 当前成长对象。
## @return 下一阶收益或已达终阶的说明。
static func next_detail(hero: RefCounted) -> String:
	if hero.evolution_tier >= 3: return "已到终阶"
	var text := {
		"echo": ["回响范围扩大十五像素", "Q 再追加一次五成伤害远端回响"],
		"nova": ["冰环扩大到一百四十五像素并减速", "Q 额外获得两秒护盾"],
		"chain": ["最多跳向四敌，范围二百二十像素", "雷击命中额外减速一秒"],
		"reaper": ["收割改为四次命中触发", "震波扩大并获得一点五秒护盾"],
		"hunter": ["选敌射程提高到四百五十像素", "每四发追加一支半伤分裂箭"],
		"sacrifice": ["死亡爆炸范围扩大到一百八十像素", "死亡时额外迸发八方向灵魂弹"]
	}
	return "先选择路线" if hero.evolution == "" else text[hero.evolution][maxi(0, hero.evolution_tier - 1)]

## 返回当前被动形态触发需要的真实命中次数，供战斗和界面共用。
## @param hero 本局成长对象。
## @return 默认三次，初阶收割五次，进阶收割四次。
static func combo_required(hero: RefCounted) -> int:
	return int(rules(hero).get("combo", 3))

## 读取当前路线阶段的机制配置，未选形态时返回空字典；调用方不得修改共享配置。
## @param hero 本局成长对象。
## @return 配置表中的只读机制记录，旧单阶夹具按第一阶读取。
static func rules(hero: RefCounted) -> Dictionary:
	return {} if hero.evolution == "" else Rules.MECHANICS[hero.evolution][clampi(hero.evolution_tier - 1, 0, 2)]
