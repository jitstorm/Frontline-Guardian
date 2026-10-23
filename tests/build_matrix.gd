extends "res://tests/balance_matrix.gd"
## 在默认金币、真实装备交易与敌人更新下，对三种构筑进行独立八夜及营地回归。

## 分别验证核心输出来源和胜负，技能流禁用技能的失败对照由原矩阵负责。
func _initialize() -> void:
	await process_frame
	var records: Array[Dictionary] = []
	for build_id in ["skill", "passive", "summon"]:
		for class_id in ["berserker", "frost_mage"]:
			for run_seed in [7, 23, 91]:
				records.append(run_case(class_id, "mixed", run_seed, true, false, build_id != "passive", build_id))
			if build_id == "summon": records.append(run_case(class_id, "mixed", 7, true, false, false, build_id))
			if build_id != "skill": records.append(run_case(class_id, "mixed", 7, true, true, build_id != "passive", build_id))
	var file := FileAccess.open("res://test_logs/build_matrix.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	var failures := 0
	for result in records:
		var core_output: float = result.skill_damage if result.build == "skill" else result.passive_damage if result.build == "passive" else result.summon_damage
		var disabled: bool = result.build == "summon" and not result.skills
		if (disabled and (result.result != "lost" or core_output != 0.0)) or (not disabled and (result.result != "won" or core_output <= 0.0)) or (result.camp and not result.camp_success):
			failures += 1
			push_error("构筑未达到验收：%s" % JSON.stringify(result))
	print("build_matrix=COMPLETE cases=%d failures=%d" % [records.size(), failures])
	quit(0 if failures == 0 else 1)
