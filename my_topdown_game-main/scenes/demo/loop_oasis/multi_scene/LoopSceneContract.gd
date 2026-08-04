extends RefCounted

const VALID_ROUTES := ["puzzle_first", "combat_first"]
const SCENE_ALIASES := {
	"observe": "r0_observe",
	"program": "r1_safe_program",
	"puzzle": "puzzle_bridge",
	"combat": "pulse_defense",
	"transfer": "r4_transfer",
	"growth_chamber": "growth",
	"archive_star_map": "archive",
	"workshop_range": "workshop",
	"result": "settlement",
}


static func validate(scene_id: String, evidence: Dictionary) -> Dictionary:
	var id := _normalize_id(scene_id)
	match id:
		"home":
			return _ok(id)
		"theme_map":
			return _validate_theme_map(id, evidence)
		"level_prep":
			return _validate_level_prep(id, evidence)
		"r0_observe":
			return _validate_r0(id, evidence)
		"r1_safe_program":
			return _validate_r1(id, evidence)
		"puzzle_bridge":
			return _validate_puzzle(id, evidence)
		"pulse_defense":
			return _validate_combat(id, evidence)
		"r4_transfer":
			return _validate_transfer(id, evidence)
		"boss_observe":
			return _validate_boss_observe(id, evidence)
		"boss_debug":
			return _validate_boss_debug(id, evidence)
		"boss_combat":
			return _validate_boss_combat(id, evidence)
		"settlement":
			return _validate_settlement(id, evidence)
		"farm":
			return _validate_farm(id, evidence)
		"growth":
			return _validate_growth(id, evidence)
		"archive":
			return _validate_archive(id, evidence)
		"workshop":
			return _validate_workshop(id, evidence)
	return _fail("UNKNOWN_SCENE_ID", "未注册的证据场景：%s" % scene_id)


static func _validate_theme_map(id: String, evidence: Dictionary) -> Dictionary:
	var missing := _missing(evidence, ["route_order", "puzzle_required", "combat_required"])
	if not missing.is_empty():
		return _missing_fail(id, missing)
	if str(evidence.route_order) not in VALID_ROUTES or not bool(evidence.puzzle_required) or not bool(evidence.combat_required):
		return _fail("MAP_ROUTE_CONTRACT_INVALID", "路线必须明确包含解谜和战斗。")
	return _ok(id)


static func _validate_level_prep(id: String, evidence: Dictionary) -> Dictionary:
	var missing := _missing(evidence, ["tool_claimed", "training_target_hit", "shots_fired"])
	if not missing.is_empty():
		return _missing_fail(id, missing)
	if not bool(evidence.tool_claimed) or not bool(evidence.training_target_hit) or int(evidence.shots_fired) < 1:
		return _fail("PREP_WORLD_EVIDENCE_INVALID", "必须实际领取工具并至少射击命中一次训练靶。")
	return _ok(id)


static func _validate_r0(id: String, evidence: Dictionary) -> Dictionary:
	var missing := _missing(evidence, ["movement_distance", "action_runs", "changed_targets", "total_targets"])
	if not missing.is_empty():
		return _missing_fail(id, missing)
	if float(evidence.movement_distance) < 40.0 or int(evidence.action_runs) != 1 or int(evidence.changed_targets) != 1 or int(evidence.total_targets) != 5:
		return _fail("R0_WORLD_EVIDENCE_INVALID", "R0 需要移动并证明一次动作只改变 5 个目标中的 1 个。")
	return _ok(id)


static func _validate_r1(id: String, evidence: Dictionary) -> Dictionary:
	var missing := _missing(evidence, ["repeat_count", "completed_targets", "total_targets", "trace_steps", "used_run_or_step"])
	if not missing.is_empty():
		return _missing_fail(id, missing)
	if int(evidence.repeat_count) != 5 or int(evidence.completed_targets) != 5 or int(evidence.total_targets) != 5 or int(evidence.trace_steps) != 5 or not bool(evidence.used_run_or_step):
		return _fail("R1_TRACE_EVIDENCE_INVALID", "R1 需要 Repeat(5) 的 5/5 世界轨迹。")
	return _ok(id)


static func _validate_puzzle(id: String, evidence: Dictionary) -> Dictionary:
	var fields := ["from_count", "to_count", "bridge_segments_open", "counterfactual_last_dormant", "player_crossed_exit"]
	var missing := _missing(evidence, fields)
	if not missing.is_empty():
		return _missing_fail(id, missing)
	if int(evidence.from_count) != 5 or int(evidence.to_count) != 4 or int(evidence.bridge_segments_open) != 4 or not bool(evidence.counterfactual_last_dormant) or not bool(evidence.player_crossed_exit):
		return _fail("PUZZLE_WORLD_EVIDENCE_INVALID", "谜桥需要完成 5→4 反事实、打开 4 段桥并实际穿越出口。")
	return _ok(id)


static func _validate_combat(id: String, evidence: Dictionary) -> Dictionary:
	var fields := ["enemies_spawned", "enemies_defeated", "shots_fired", "pulse_uses", "player_moved"]
	var missing := _missing(evidence, fields)
	if not missing.is_empty():
		return _missing_fail(id, missing)
	var spawned := int(evidence.enemies_spawned)
	var defeated := int(evidence.enemies_defeated)
	if spawned < 3 or defeated != spawned or int(evidence.shots_fired) < defeated or int(evidence.pulse_uses) < 1 or not bool(evidence.player_moved):
		return _fail("COMBAT_WORLD_EVIDENCE_INVALID", "战斗需要移动、射击、使用脉冲并清除全部实体敌人。")
	return _ok(id)


static func _validate_transfer(id: String, evidence: Dictionary) -> Dictionary:
	var fields := ["repeat_count", "completed_targets", "total_targets", "trace_steps"]
	var missing := _missing(evidence, fields)
	if not missing.is_empty():
		return _missing_fail(id, missing)
	if int(evidence.repeat_count) != 6 or int(evidence.completed_targets) != 6 or int(evidence.total_targets) != 6 or int(evidence.trace_steps) != 6:
		return _fail("TRANSFER_WORLD_EVIDENCE_INVALID", "陌生迁移需要精确完成 6/6 世界轨迹。")
	return _ok(id)


static func _validate_boss_observe(id: String, evidence: Dictionary) -> Dictionary:
	var fields := ["observed_beats", "player_moved", "dodged_hazards"]
	var missing := _missing(evidence, fields)
	if not missing.is_empty():
		return _missing_fail(id, missing)
	if int(evidence.observed_beats) < 4 or not bool(evidence.player_moved) or int(evidence.dodged_hazards) < 1:
		return _fail("BOSS_OBSERVE_EVIDENCE_INVALID", "Boss 观察阶段需要移动躲避并看完至少四拍。")
	return _ok(id)


static func _validate_boss_debug(id: String, evidence: Dictionary) -> Dictionary:
	var fields := ["defect_run", "blocked_hits", "condition_changed", "safe_hits", "debug_success"]
	var missing := _missing(evidence, fields)
	if not missing.is_empty():
		return _missing_fail(id, missing)
	if not bool(evidence.defect_run) or int(evidence.blocked_hits) < 2 or not bool(evidence.condition_changed) or int(evidence.safe_hits) != 2 or not bool(evidence.debug_success):
		return _fail("BOSS_DEBUG_EVIDENCE_INVALID", "Boss Debug 需要先运行缺陷、观察护盾拦截，再修改条件并安全命中两次。")
	return _ok(id)


static func _validate_boss_combat(id: String, evidence: Dictionary) -> Dictionary:
	var fields := ["boss_max_hp", "boss_hp", "hits_landed", "shots_fired", "debug_clear"]
	var missing := _missing(evidence, fields)
	if not missing.is_empty():
		return _missing_fail(id, missing)
	if int(evidence.boss_max_hp) != 6 or int(evidence.boss_hp) != 0 or int(evidence.hits_landed) < 6 or int(evidence.shots_fired) < 6 or not bool(evidence.debug_clear):
		return _fail("BOSS_COMBAT_EVIDENCE_INVALID", "Boss 战斗需要 Debug 已完成并把 6 HP 实体 Boss 击至 0。")
	return _ok(id)


static func _validate_settlement(id: String, evidence: Dictionary) -> Dictionary:
	var missing := _missing(evidence, ["all_gates", "missing_flags"])
	if not missing.is_empty():
		return _missing_fail(id, missing)
	if not bool(evidence.all_gates) or not (evidence.missing_flags is Array) or not evidence.missing_flags.is_empty():
		return _fail("SETTLEMENT_GATE_EVIDENCE_INVALID", "结算仍有未完成门禁。")
	return _ok(id)


static func _validate_farm(id: String, evidence: Dictionary) -> Dictionary:
	var fields := ["plots_planted", "plots_watered", "plots_harvested", "repeat_count", "seed_available"]
	var missing := _missing(evidence, fields)
	if not missing.is_empty():
		return _missing_fail(id, missing)
	if int(evidence.plots_planted) != 4 or int(evidence.plots_watered) != 4 or int(evidence.plots_harvested) != 4 or int(evidence.repeat_count) != 4 or not bool(evidence.seed_available):
		return _fail("FARM_WORLD_EVIDENCE_INVALID", "农场需要播种、浇灌、收获四格，并运行 Repeat(4)。")
	return _ok(id)


static func _validate_growth(id: String, evidence: Dictionary) -> Dictionary:
	var fields := ["evidence_nodes", "farm_complete", "crop_available", "calibration_complete"]
	var missing := _missing(evidence, fields)
	if not missing.is_empty():
		return _missing_fail(id, missing)
	if int(evidence.evidence_nodes) != 5 or not bool(evidence.farm_complete) or not bool(evidence.crop_available) or not bool(evidence.calibration_complete):
		return _fail("GROWTH_WORLD_EVIDENCE_INVALID", "成长舱需要五类证据、农场成果和完整校准。")
	return _ok(id)


static func _validate_archive(id: String, evidence: Dictionary) -> Dictionary:
	var fields := ["trace_nodes", "ordered", "program_clear", "combat_clear", "farm_clear"]
	var missing := _missing(evidence, fields)
	if not missing.is_empty():
		return _missing_fail(id, missing)
	if int(evidence.trace_nodes) != 3 or not bool(evidence.ordered) or not bool(evidence.program_clear) or not bool(evidence.combat_clear) or not bool(evidence.farm_clear):
		return _fail("ARCHIVE_WORLD_EVIDENCE_INVALID", "档案馆需要按序回放编程、战斗和农场三段轨迹。")
	return _ok(id)


static func _validate_workshop(id: String, evidence: Dictionary) -> Dictionary:
	var fields := ["targets_spawned", "targets_destroyed", "shots_landed"]
	var missing := _missing(evidence, fields)
	if not missing.is_empty():
		return _missing_fail(id, missing)
	if int(evidence.targets_spawned) != 3 or int(evidence.targets_destroyed) != 3 or int(evidence.shots_landed) < 3:
		return _fail("WORKSHOP_WORLD_EVIDENCE_INVALID", "工坊需要实际击毁 3/3 个训练靶。")
	return _ok(id)


static func _normalize_id(scene_id: String) -> String:
	var id := scene_id.strip_edges()
	if id.contains("/"):
		id = id.get_file()
	if id.ends_with(".tscn"):
		id = id.trim_suffix(".tscn")
	return str(SCENE_ALIASES.get(id, id))


static func _missing(evidence: Dictionary, fields: Array) -> Array[String]:
	var missing: Array[String] = []
	for field in fields:
		if not evidence.has(field):
			missing.append(str(field))
	return missing


static func _missing_fail(id: String, fields: Array[String]) -> Dictionary:
	return _fail("EVIDENCE_FIELDS_MISSING", "%s 缺少字段：%s" % [id, ", ".join(fields)])


static func _ok(id: String) -> Dictionary:
	return {"ok": true, "scene_id": id}


static func _fail(code: String, detail: String) -> Dictionary:
	return {"ok": false, "error": code, "detail": detail}
