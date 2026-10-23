extends "res://tests/balance_matrix.gd"
## 对六种互斥形态、两名英雄和多个随机种子执行正常经济八夜及营地衔接。

## 保存每局装备词缀与伤害，再统一核对结算；宝匣只在预算有余时购买。
func _initialize() -> void:
	await process_frame
	var records: Array[Dictionary] = []
	var forms: Dictionary = load("res://scripts/build_evolution.gd").FORMS
	for form in forms:
		for class_id in ["berserker", "frost_mage"]:
			for run_seed in [7, 23, 91]:
				records.append(run_case(class_id, "mixed", run_seed, true, false, forms[form].build != "passive", forms[form].build, form, true))
			records.append(run_case(class_id, "mixed", 7, true, true, forms[form].build != "passive", forms[form].build, form, true))
	var file := FileAccess.open("res://test_logs/evolution_matrix.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	var failures := 0
	for result in records:
		if result.result != "won" or result.form == "" or result.tier != 3 or (result.camp and not result.camp_success):
			failures += 1
			push_error("形态回归未通过：%s" % JSON.stringify(result))
	print("evolution_matrix=COMPLETE cases=%d failures=%d" % [records.size(), failures])
	quit(0 if failures == 0 else 1)
