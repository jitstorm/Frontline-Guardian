extends RefCounted
## 独立生成、校验和重铸装备随机记录；不直接扣款，交易由战场校验后执行。
## 记录字段：quality 为品质标识；power 为基础倍率（一表示原始数值）；affixes 为不重复词缀标识数组；reforges 为从零开始的重铸次数。
const Rules = preload("res://scripts/config/equipment_rules.gd")

## 构造旧普通商品或指定单词缀的记录，不引入随机倍率。
## @param affix 已有词缀，空值表示无词缀。
## @return 基础倍率为一、无重铸历史的物品记录。
static func legacy(affix: String = "") -> Dictionary:
	return {"quality": "common", "power": 1.0, "affixes": [] if affix == "" else [affix], "reforges": 0}

## 校验随机记录，拒绝无效品质、倍率、重复词缀和超过四条的物品。
## @param record 待接收的物品实例数据。
## @return 所有字段合法时返回 true。
static func valid(record: Dictionary) -> bool:
	if not Rules.QUALITIES.has(record.get("quality", "")) or record.get("power", 0.0) <= 0.0 or record.get("power", 2.0) > 1.4: return false
	var rule: Dictionary = Rules.QUALITIES[record.quality]
	if record.power < rule.low or record.power > rule.high: return false
	var seen: Array = []
	if not record.get("affixes", null) is Array or record.affixes.size() > rule.count: return false
	for id in record.affixes:
		if not Rules.AFFIXES.has(id) or seen.has(id): return false
		seen.append(id)
	return record.get("reforges", -1) >= 0

## 根据品质权重与品质区间生成多词条物品，所有随机调用使用传入的独立随机源。
## @param rng 本局可复现随机源。
## @return 含品质、基础倍率和互不重复词缀的完整记录。
static func generate(rng: RandomNumberGenerator) -> Dictionary:
	# 1. 按配置权重总和抽品质，修改权重时不要求调用方重新归一化。
	var total_weight := 0
	for rule in Rules.QUALITIES.values(): total_weight += int(rule.weight)
	var value := rng.randi_range(1, total_weight)
	var quality := "common"
	for id in Rules.QUALITIES:
		value -= Rules.QUALITIES[id].weight
		if value <= 0:
			quality = id
			break
	var rule: Dictionary = Rules.QUALITIES[quality]
	var record := {"quality": quality, "power": rng.randf_range(rule.low, rule.high), "affixes": [], "reforges": 0}
	# 2. 每次从未出现的词缀池抽取，保证同一物品内部不重复。
	while record.affixes.size() < rule.count:
		var pool: Array = Rules.AFFIXES.keys().filter(func(id: String) -> bool: return not record.affixes.has(id))
		record.affixes.append(pool[rng.randi_range(0, pool.size() - 1)])
	return record

## 计算重铸费用，锁定与已重铸次数会提高成本，避免无成本筛词条。
## @param record 当前完整随机记录。
## @param locks 要保留的词条索引，不允许重复或越界。
## @return 合法且仍有可重铸词条时返回金币费用，否则返回负一。
static func cost(record: Dictionary, locks: Array[int]) -> int:
	if not valid(record): return -1
	var seen: Array[int] = []
	for index in locks:
		if index < 0 or index >= record.affixes.size() or seen.has(index): return -1
		seen.append(index)
	if not record.affixes.is_empty() and locks.size() == record.affixes.size(): return -1
	return Rules.REFORGE_BASE + 5 * maxi(1, record.affixes.size()) + 5 * locks.size() + 5 * int(record.reforges)

## 只重抽未锁定词条，保持品质、倍率与锁定位置，且每次至少改变一个未锁定词条。
## @param record 原物品记录，不会就地修改。
## @param locks 已校验的锁定索引。
## @param rng 本局独立随机源。
## @return 成功时返回新记录；锁定参数错误返回空字典。
static func reforge(record: Dictionary, locks: Array[int], rng: RandomNumberGenerator) -> Dictionary:
	if cost(record, locks) < 0: return {}
	var result := record.duplicate(true)
	if result.affixes.is_empty(): result.affixes.append("")
	for i in result.affixes.size():
		if locks.has(i): continue
		var old: String = result.affixes[i]
		var pool: Array = Rules.AFFIXES.keys().filter(func(id: String) -> bool: return id != old and not result.affixes.has(id))
		result.affixes[i] = pool[rng.randi_range(0, pool.size() - 1)]
	result.reforges += 1
	return result

## 将随机装备的全部数值词缀加到英雄合成属性中，按装备实例逐条结算。
## @param stats 已合成基础装备属性的字典，将在此处修改。
## @param equipment 以槽位为键的随机记录。
static func apply_stats(stats: Dictionary, equipment: Dictionary) -> void:
	var bonuses := {"swift": ["rate", 0.08], "arcane": ["skill_power", 0.12], "vigor": ["health", 12.0], "might": ["attack", 3.0], "armor": ["defense", 1.5], "stride": ["speed", 10.0], "reach": ["basic_range", 20.0]}
	for record in equipment.values():
		for id in record.affixes:
			if bonuses.has(id): stats[bonuses[id][0]] += bonuses[id][1]

## 生成品质、基础倍率与词缀摘要；详细词缀效果由界面逐条显示。
## @param item_id 基础物品目录标识。
## @param record 完整物品记录。
## @return 可直接用于中文界面的摘要。
static func label(item_id: String, record: Dictionary) -> String:
	var names: Array[String] = []
	for id in record.affixes: names.append(Rules.AFFIXES[id].name)
	return "%s %s ×%.2f [%s]" % [Rules.QUALITIES[record.quality].name, Rules.ITEMS[item_id].name, record.power, "／".join(names)]

## 为紧凑背包行生成品质和全部词条名称，效果详情在独立重铸面板显示。
## @param record 完整物品随机记录。
## @return 不包含基础名称的中文摘要。
static func summary(record: Dictionary) -> String:
	var names: Array[String] = []
	for id in record.affixes: names.append(Rules.AFFIXES[id].name)
	return "%s ×%.2f %s" % [Rules.QUALITIES[record.quality].name, record.power, "／".join(names)]
