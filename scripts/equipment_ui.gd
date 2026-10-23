extends RefCounted
## 独立重铸面板，负责选择背包装备和锁词条；金币与物品修改只调用战场交易入口。
const Equipment = preload("res://scripts/equipment_system.gd")
const Rules = preload("res://scripts/config/equipment_rules.gd")
## 面板是否打开、选中的背包索引及锁定词条位置，关闭或切换物品时重新校验。
var opened := false
var selected := 0
var locks: Array[int] = []

## 开关重铸面板，只允许准备阶段；打开时清除上一物品的锁定选择。
## @param game 本局战场。
func toggle(game: Node2D) -> void:
	if game.state != "ready": return
	opened = not opened
	selected = 0
	locks.clear()

## 切换指定词条锁定，空槽位和无效索引不会进入锁定列表。
## @param game 本局战场。
## @param index 当前物品中零起始词条位置。
func toggle_lock(game: Node2D, index: int) -> void:
	if index < 0 or selected >= game.hero.inventory_rolls.size() or index >= game.hero.inventory_rolls[selected].affixes.size(): return
	if locks.has(index): locks.erase(index)
	else: locks.append(index)

## 处理重铸面板输入，面板打开时消费输入，防止数字键同时触发建塔。
## @param game 本局战场。
## @param event 实际键盘或鼠标事件。
## @return 面板打开且已接管输入时返回 true。
func handle(game: Node2D, event: InputEvent) -> bool:
	if not opened: return false
	if game.state != "ready":
		opened = false
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_J, KEY_ESCAPE: opened = false
			KEY_K: game.reforge_item(selected, locks)
			KEY_1: toggle_lock(game, 0)
			KEY_2: toggle_lock(game, 1)
			KEY_3: toggle_lock(game, 2)
			KEY_4: toggle_lock(game, 3)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = game.get_global_mouse_position()
		for i in game.hero.inventory.size():
			if Rect2(105, 155 + i * 35, 430, 32).has_point(pos):
				selected = i
				locks.clear()
		for i in 4:
			if Rect2(585, 240 + i * 65, 590, 56).has_point(pos): toggle_lock(game, i)
		if Rect2(585, 540, 590, 50).has_point(pos): game.reforge_item(selected, locks)
	return true

## 绘制背包实例、品质区间、全部词缀与重铸费用，玩家能先看规则再交易。
## @param game 本局战场。
## @param canvas 当前绘制回调中的战场节点。
## @param font 打包的中文字体。
func draw(game: Node2D, canvas: Node2D, font: Font) -> void:
	if not opened: return
	canvas.draw_rect(Rect2(65, 100, 1150, 570), Color("182b41"))
	canvas.draw_string(font, Vector2(100, 138), "装备重铸｜J 关闭｜K 重铸｜1–4 锁定词条｜金币 %d" % game.gold, HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("ffe074"))
	for i in game.hero.inventory.size():
		var record: Dictionary = game.hero.inventory_rolls[i]
		canvas.draw_rect(Rect2(105, 155 + i * 35, 430, 32), Color("42634a") if i == selected else Color("365a74"))
		canvas.draw_string(font, Vector2(115, 178 + i * 35), "%s %s（%d词条）" % [Rules.QUALITIES[record.quality].name, Rules.ITEMS[game.hero.inventory[i]].name, record.affixes.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	if selected >= game.hero.inventory.size():
		canvas.draw_string(font, Vector2(585, 200), "背包没有装备，请先卸下或购买。", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		return
	var record: Dictionary = game.hero.inventory_rolls[selected]
	var rule: Dictionary = Rules.QUALITIES[record.quality]
	canvas.draw_string(font, Vector2(585, 195), "%s｜倍率 %.2f（区间 %.2f–%.2f）" % [Rules.QUALITIES[record.quality].name, record.power, rule.low, rule.high], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	for i in record.affixes.size():
		var affix: Dictionary = Rules.AFFIXES[record.affixes[i]]
		canvas.draw_rect(Rect2(585, 240 + i * 65, 590, 56), Color("42634a") if locks.has(i) else Color("365a74"))
		canvas.draw_string(font, Vector2(600, 261 + i * 65), "%d %s %s" % [i + 1, "已锁定" if locks.has(i) else "可重铸", affix.name], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
		canvas.draw_string(font, Vector2(600, 283 + i * 65), affix.detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("b4ff91"))
	var price := Equipment.cost(record, locks)
	canvas.draw_rect(Rect2(585, 540, 590, 50), Color("365a74"))
	canvas.draw_string(font, Vector2(600, 572), "至少留一条未锁定词条" if price < 0 else "K：重铸未锁定词条｜%d 金币" % price, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("ffe074"))
	canvas.draw_string(font, Vector2(105, 635), "保留品质和基础倍率；锁定与重铸次数增加费用。穿戴中的装备需先卸下。", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("80deff"))
