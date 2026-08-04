extends Node

signal state_changed(section: String, key: String, value: Variant)
signal adventure_begun(selected_route: String)
signal settlement_committed_once(rewards: Dictionary)

const SceneContract = preload("res://scenes/demo/loop_oasis/multi_scene/LoopSceneContract.gd")
const SAVE_PATH := "user://loop_run_state_v1.json"
const TEST_SAVE_PATH := "user://loop_run_state_test.json"
const CONTENT_PATH := "res://content/generated/UNIT-DATA-GARDEN-LOOP.json"
const HOME_SCENE := "res://scenes/demo/loop_oasis/home_base.tscn"
const THEME_MAP_SCENE := "res://scenes/demo/loop_oasis/multi_scene/theme_map.tscn"
const LEVEL_PREP_SCENE := "res://scenes/demo/loop_oasis/multi_scene/level_prep.tscn"
const SETTLEMENT_SCENE := "res://scenes/demo/loop_oasis/multi_scene/settlement.tscn"
const FARM_SCENE := "res://scenes/demo/loop_oasis/multi_scene/farm.tscn"
const VALID_ROUTES := ["puzzle_first", "combat_first"]
const REQUIRED_SETTLEMENT_FLAGS := [
	"observe", "program", "puzzle", "combat", "transfer",
	"boss_observe", "boss_debug", "boss_combat",
]
const ROOM_PATHS := {
	"observe": "res://scenes/demo/loop_oasis/multi_scene/r0_observe.tscn",
	"program": "res://scenes/demo/loop_oasis/multi_scene/r1_safe_program.tscn",
	"puzzle": "res://scenes/demo/loop_oasis/multi_scene/puzzle_bridge.tscn",
	"combat": "res://scenes/demo/loop_oasis/multi_scene/pulse_defense.tscn",
	"transfer": "res://scenes/demo/loop_oasis/multi_scene/r4_transfer.tscn",
	"boss_observe": "res://scenes/demo/loop_oasis/multi_scene/boss_guardian.tscn",
	"boss_debug": "res://scenes/demo/loop_oasis/multi_scene/boss_guardian.tscn",
	"boss_combat": "res://scenes/demo/loop_oasis/multi_scene/boss_guardian.tscn",
	"settlement": SETTLEMENT_SCENE,
}
const SCENE_TO_FLAG := {
	"r0_observe": "observe", "r1_safe_program": "program",
	"puzzle_bridge": "puzzle", "pulse_defense": "combat",
	"r4_transfer": "transfer", "boss_observe": "boss_observe",
	"boss_debug": "boss_debug", "boss_combat": "boss_combat",
}
const DEFAULT_INVENTORY := {
	"water_seed": 0, "law_fragment": 0, "crop": 0, "pulse_module": 0,
}
const DEFAULT_HOME_FLAGS := {
	"farm": false, "growth": false, "archive": false, "workshop": false,
}
const INTEGER_EVIDENCE_FIELDS := [
	"action_runs", "changed_targets", "total_targets",
	"repeat_count", "completed_targets", "trace_steps",
	"from_count", "to_count", "bridge_segments_open",
	"enemies_spawned", "enemies_defeated", "shots_fired", "pulse_uses",
	"observed_beats", "dodged_hazards", "blocked_hits", "safe_hits",
	"boss_max_hp", "boss_hp", "hits_landed",
	"plots_planted", "plots_watered", "plots_harvested",
	"evidence_nodes", "trace_nodes",
	"targets_spawned", "targets_destroyed", "shots_landed",
]

var route_order := "puzzle_first"
var room_flags: Dictionary = {}
var inventory: Dictionary = {}
var home_flags: Dictionary = {}
var room_evidence: Dictionary = {}
var home_evidence: Dictionary = {}
var walnut_level := 1
var run_started := false
var settlement_committed := false
var tool_claimed := false
var training_target_hit := false
var current_scene_id := ""
var last_error := ""
var content_unit := ""
var content_version := ""
var content_hash := ""
var test_mode := false


func _ready() -> void:
	test_mode = _has_test_argument()
	_reset_memory_defaults()
	# Automated scenes own their fixtures explicitly. Never ingest a previous
	# test process's user:// file during autoload startup; persistence coverage
	# calls load_state() itself after writing a known snapshot.
	if not test_mode:
		load_state()
	if "--loop-run-state-test" in OS.get_cmdline_user_args():
		call_deferred("_run_contract_smoke")


func reset_adventure() -> void:
	room_flags = _fresh_room_flags()
	room_evidence.clear()
	run_started = false
	settlement_committed = false
	tool_claimed = false
	training_target_hit = false
	current_scene_id = ""
	last_error = ""
	state_changed.emit("adventure", "reset", true)
	save()


func begin_adventure(selected_route_order: String = "") -> bool:
	var chosen_route := selected_route_order if not selected_route_order.is_empty() else route_order
	if chosen_route not in VALID_ROUTES:
		return _set_error("INVALID_ROUTE", "未知路线：%s" % chosen_route)
	if not tool_claimed or not training_target_hit:
		return _set_error("PREP_INCOMPLETE", "进入 R0 前必须领取工具并命中训练靶。")
	route_order = chosen_route
	room_flags = _fresh_room_flags()
	room_evidence.clear()
	run_started = true
	settlement_committed = false
	current_scene_id = "observe"
	last_error = ""
	adventure_begun.emit(route_order)
	state_changed.emit("adventure", "run_started", true)
	save()
	return true


func configure_route(selected_route_order: String) -> Dictionary:
	var evidence := {
		"route_order": selected_route_order,
		"puzzle_required": true,
		"combat_required": true,
	}
	var validation: Dictionary = SceneContract.validate("theme_map", evidence)
	if not bool(validation.get("ok", false)):
		return _error_result(str(validation.get("error", "MAP_ROUTE_CONTRACT_INVALID")), str(validation.get("detail", "路线证据无效。")))
	_reset_adventure_memory()
	route_order = selected_route_order
	last_error = ""
	if not save():
		return _error_result("SAVE_FAILED", "路线选择保存失败。")
	return {"ok": true, "route_order": route_order}


func submit_preparation_evidence(evidence: Dictionary) -> Dictionary:
	var validation: Dictionary = SceneContract.validate("level_prep", evidence)
	if not bool(validation.get("ok", false)):
		return _error_result(str(validation.get("error", "PREP_WORLD_EVIDENCE_INVALID")), str(validation.get("detail", "准备场景证据无效。")))
	tool_claimed = true
	training_target_hit = true
	last_error = ""
	if not save():
		return _error_result("SAVE_FAILED", "准备证据保存失败。")
	return {"ok": true, "flag": "level_prep"}


func submit_scene_evidence(scene_id: String, evidence: Dictionary) -> Dictionary:
	if not SCENE_TO_FLAG.has(scene_id):
		return _error_result("UNKNOWN_EVIDENCE_SCENE", "未知证据场景：%s" % scene_id)
	var validation: Dictionary = SceneContract.validate(scene_id, evidence)
	if not bool(validation.get("ok", false)):
		return _error_result(str(validation.get("error", "INVALID_EVIDENCE")), str(validation.get("detail", "证据校验失败。")))
	var flag := str(SCENE_TO_FLAG[scene_id])
	if room_done(flag):
		return {"ok": true, "flag": flag, "idempotent": true}
	var gate := can_enter(flag)
	if not bool(gate.get("ok", false)):
		return _error_result(str(gate.get("error", "ROOM_GATE_BLOCKED")), "房间门禁尚未满足：%s" % flag)
	room_flags[flag] = true
	room_evidence[flag] = evidence.duplicate(true)
	current_scene_id = flag
	last_error = ""
	state_changed.emit("room", flag, true)
	if not save():
		return _error_result("SAVE_FAILED", "房间证据已验证，但状态保存失败。")
	return {"ok": true, "flag": flag}


func mark_room(scene_id: String, completed: bool = true, evidence: Dictionary = {}) -> bool:
	var flag := _normalize_room_id(scene_id)
	if not room_flags.has(flag):
		return _set_error("UNKNOWN_ROOM", "未知房间：%s" % scene_id)
	if not completed:
		room_flags[flag] = false
		room_evidence.erase(flag)
		return save()
	var submit_id := _submit_id_for_flag(flag)
	var result := submit_scene_evidence(submit_id, evidence)
	return bool(result.get("ok", false))


func room_done(scene_id: String) -> bool:
	return bool(room_flags.get(_normalize_room_id(scene_id), false))


func can_enter(scene_id: String) -> Dictionary:
	var raw_id := _scene_basename(scene_id)
	match raw_id:
		"home", "home_base", "theme_map", "farm", "growth", "growth_chamber", "archive", "archive_star_map", "workshop", "workshop_range":
			return {"ok": true}
		"level_prep":
			return {"ok": true} if route_order in VALID_ROUTES else {"ok": false, "error": "ROUTE_NOT_SELECTED"}
		"settlement":
			return {"ok": true} if _all_required_rooms_done() else {"ok": false, "error": "SETTLEMENT_GATES_MISSING"}
		"boss_guardian":
			return {"ok": true} if run_started and room_done("transfer") else {"ok": false, "error": "TRANSFER_REQUIRED"}
		"legacy_data_garden":
			return {"ok": false, "error": "LEGACY_REGRESSION_ONLY"}
	var room_id := _normalize_room_id(raw_id)
	if not room_flags.has(room_id):
		return {"ok": false, "error": "UNKNOWN_SCENE_ID"}
	if not run_started:
		return {"ok": false, "error": "RUN_NOT_STARTED"}
	match room_id:
		"observe": return {"ok": true}
		"program": return {"ok": true} if room_done("observe") else {"ok": false, "error": "OBSERVE_REQUIRED"}
		"puzzle":
			var puzzle_ok := room_done("program") and (route_order == "puzzle_first" or room_done("combat"))
			return {"ok": true} if puzzle_ok else {"ok": false, "error": "PUZZLE_GATE_BLOCKED"}
		"combat":
			var combat_ok := room_done("program") and (route_order == "combat_first" or room_done("puzzle"))
			return {"ok": true} if combat_ok else {"ok": false, "error": "COMBAT_GATE_BLOCKED"}
		"transfer": return {"ok": true} if room_done("puzzle") and room_done("combat") else {"ok": false, "error": "PUZZLE_COMBAT_REQUIRED"}
		"boss_observe": return {"ok": true} if room_done("transfer") else {"ok": false, "error": "TRANSFER_REQUIRED"}
		"boss_debug": return {"ok": true} if room_done("boss_observe") else {"ok": false, "error": "BOSS_OBSERVE_REQUIRED"}
		"boss_combat": return {"ok": true} if room_done("boss_debug") else {"ok": false, "error": "BOSS_DEBUG_REQUIRED"}
	return {"ok": false, "error": "UNKNOWN_SCENE_ID"}


func next_room_path(_from_scene_id: String = "") -> String:
	if not run_started:
		return THEME_MAP_SCENE
	for room_id in _route_sequence():
		if not room_done(room_id):
			var gate := can_enter(room_id)
			if bool(gate.get("ok", false)):
				last_error = ""
				return str(ROOM_PATHS[room_id])
			_set_error(str(gate.get("error", "NEXT_ROOM_BLOCKED")), "下一房间被门禁阻止：%s" % room_id)
			return ""
	if bool(can_enter("settlement").get("ok", false)):
		return SETTLEMENT_SCENE
	_set_error("SETTLEMENT_GATE_BLOCKED", "结算门禁尚未全部满足。")
	return ""


func missing_required_rooms() -> Array[String]:
	var missing: Array[String] = []
	for room_id in REQUIRED_SETTLEMENT_FLAGS:
		if not room_done(room_id):
			missing.append(room_id)
	return missing


func commit_settlement() -> bool:
	if settlement_committed:
		last_error = ""
		return true
	var missing := missing_required_rooms()
	var validation: Dictionary = SceneContract.validate("settlement", {
		"all_gates": missing.is_empty(),
		"missing_flags": missing,
	})
	if not bool(validation.get("ok", false)):
		return _set_error(str(validation.get("error", "SETTLEMENT_EVIDENCE_INVALID")), str(validation.get("detail", "结算证据不完整。")))
	var before := _snapshot()
	inventory["water_seed"] = int(inventory.get("water_seed", 0)) + 1
	inventory["law_fragment"] = int(inventory.get("law_fragment", 0)) + 1
	settlement_committed = true
	last_error = ""
	var rewards := {"water_seed": 1, "law_fragment": 1}
	if not save():
		_apply_snapshot(before)
		return false
	settlement_committed_once.emit(rewards)
	state_changed.emit("settlement", "committed", true)
	return true


func commit_home_activity(scene_id: String, evidence: Dictionary) -> Dictionary:
	var activity_id := _normalize_home_id(scene_id)
	if activity_id not in DEFAULT_HOME_FLAGS:
		return _error_result("UNKNOWN_HOME_ACTIVITY", "未知家园活动：%s" % scene_id)
	var validation: Dictionary = SceneContract.validate(activity_id, evidence)
	if not bool(validation.get("ok", false)):
		return _error_result(str(validation.get("error", "INVALID_HOME_EVIDENCE")), str(validation.get("detail", "家园证据校验失败。")))
	if bool(home_flags.get(activity_id, false)):
		return {"ok": true, "flag": activity_id, "idempotent": true}
	var before := _snapshot()
	match activity_id:
		"farm":
			if int(inventory.get("water_seed", 0)) < 1:
				return _error_result("WATER_SEED_MISSING", "编程农场缺少清泉种子。")
			inventory["water_seed"] = int(inventory["water_seed"]) - 1
			inventory["crop"] = int(inventory.get("crop", 0)) + 1
		"growth":
			if int(inventory.get("crop", 0)) < 1:
				return _error_result("CROP_MISSING", "成长舱缺少突破作物。")
			inventory["crop"] = int(inventory["crop"]) - 1
			walnut_level = maxi(walnut_level, 2)
		"workshop":
			inventory["pulse_module"] = int(inventory.get("pulse_module", 0)) + 1
		"archive":
			pass
	home_flags[activity_id] = true
	home_evidence[activity_id] = evidence.duplicate(true)
	last_error = ""
	state_changed.emit("home", activity_id, true)
	if not save():
		_apply_snapshot(before)
		return _error_result("SAVE_FAILED", "家园活动已验证，但状态保存失败。")
	return {"ok": true, "flag": activity_id}


func save(path: String = "") -> bool:
	var target_path := path if not path.is_empty() else _active_save_path()
	var payload := JSON.stringify(_snapshot(), "\t")
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		return _set_error("SAVE_OPEN_FAILED", "无法写入状态文件：%s" % target_path)
	file.store_string(payload)
	file = null
	var verify_file := FileAccess.open(target_path, FileAccess.READ)
	if verify_file == null:
		return _set_error("SAVE_VERIFY_OPEN_FAILED", "状态写入后无法复读：%s" % target_path)
	var verify_text := verify_file.get_as_text()
	var verify_value: Variant = JSON.parse_string(verify_text)
	if verify_text != payload or not verify_value is Dictionary:
		return _set_error("SAVE_VERIFY_FAILED", "状态写后校验失败：%s" % target_path)
	last_error = ""
	return true


func save_state() -> Dictionary:
	var ok := save()
	return {"ok": true, "path": _active_save_path()} if ok else {"ok": false, "error": last_error}


func load_state(path: String = "", report_errors: bool = true) -> bool:
	var target_path := path if not path.is_empty() else _active_save_path()
	if not FileAccess.file_exists(target_path):
		return false
	var file := FileAccess.open(target_path, FileAccess.READ)
	if file == null:
		return _set_error("LOAD_OPEN_FAILED", "无法读取状态文件：%s" % target_path, report_errors)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return _set_error("LOAD_JSON_INVALID", "状态文件不是有效对象：%s" % target_path, report_errors)
	var evidence_validation := _validate_persisted_evidence(parsed)
	if not bool(evidence_validation.get("ok", false)):
		return _set_error(
			"SAVE_EVIDENCE_INVALID",
			str(evidence_validation.get("detail", "存档完成状态与世界证据不一致。")),
			report_errors
		)
	var saved_hash := str(parsed.get("content_hash", ""))
	if not saved_hash.is_empty() and not content_hash.is_empty() and saved_hash != content_hash:
		_apply_profile_snapshot(parsed)
		_reset_adventure_memory()
		return _set_error(
			"CONTENT_HASH_MISMATCH",
			"存档内容哈希与活动内容不一致；已保留长期家园状态并拒绝恢复中间局。",
			report_errors
		)
	_apply_snapshot(parsed)
	last_error = ""
	state_changed.emit("state", "loaded", true)
	return true


func load(path: String = "", report_errors: bool = true) -> bool:
	return load_state(path, report_errors)


func reset_for_test(delete_saved_file: bool = true) -> void:
	test_mode = true
	_reset_memory_defaults()
	if delete_saved_file and FileAccess.file_exists(TEST_SAVE_PATH):
		var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
		var remove_error := DirAccess.remove_absolute(absolute_path)
		if remove_error != OK:
			push_error("[LoopRunState] RESET_FILE_FAILED：%s" % absolute_path)
	state_changed.emit("state", "test_reset", true)


func _snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"content_unit": content_unit,
		"content_version": content_version,
		"content_hash": content_hash,
		"route_order": route_order,
		"room_flags": room_flags.duplicate(true),
		"inventory": inventory.duplicate(true),
		"home_flags": home_flags.duplicate(true),
		"room_evidence": room_evidence.duplicate(true),
		"home_evidence": home_evidence.duplicate(true),
		"walnut_level": walnut_level,
		"run_started": run_started,
		"settlement_committed": settlement_committed,
		"tool_claimed": tool_claimed,
		"training_target_hit": training_target_hit,
		"current_scene_id": current_scene_id,
	}


func _validate_persisted_evidence(data: Dictionary) -> Dictionary:
	for dictionary_field in ["room_flags", "home_flags", "room_evidence", "home_evidence"]:
		if data.has(dictionary_field) and not data[dictionary_field] is Dictionary:
			return {"ok": false, "detail": "%s 必须是对象。" % dictionary_field}

	var saved_room_flags := _dictionary_or_empty(data.get("room_flags", {}))
	var saved_room_evidence := _dictionary_or_empty(data.get("room_evidence", {}))
	for raw_flag in saved_room_flags:
		var flag := str(raw_flag)
		if flag not in REQUIRED_SETTLEMENT_FLAGS:
			return {"ok": false, "detail": "存档包含未知房间标记：%s" % flag}
		if not saved_room_flags[raw_flag] is bool:
			return {"ok": false, "detail": "房间标记必须是布尔值：%s" % flag}
	for raw_evidence_flag in saved_room_evidence:
		var evidence_flag := str(raw_evidence_flag)
		if evidence_flag not in REQUIRED_SETTLEMENT_FLAGS or not bool(saved_room_flags.get(evidence_flag, false)):
			return {"ok": false, "detail": "房间证据没有对应的完成标记：%s" % evidence_flag}
	for flag in REQUIRED_SETTLEMENT_FLAGS:
		if not bool(saved_room_flags.get(flag, false)):
			continue
		var evidence := _dictionary_or_empty(saved_room_evidence.get(flag, {}))
		if evidence.is_empty():
			return {"ok": false, "detail": "已完成房间缺少世界证据：%s" % flag}
		var contract_id := _submit_id_for_flag(flag)
		var validation: Dictionary = SceneContract.validate(contract_id, evidence)
		if not bool(validation.get("ok", false)):
			return {
				"ok": false,
				"detail": "房间证据未通过合同：%s/%s" % [flag, validation.get("error", "INVALID_EVIDENCE")],
			}

	var saved_home_flags := _dictionary_or_empty(data.get("home_flags", {}))
	var saved_home_evidence := _dictionary_or_empty(data.get("home_evidence", {}))
	for raw_activity in saved_home_flags:
		var activity_id := str(raw_activity)
		if activity_id not in DEFAULT_HOME_FLAGS:
			return {"ok": false, "detail": "存档包含未知家园标记：%s" % activity_id}
		if not saved_home_flags[raw_activity] is bool:
			return {"ok": false, "detail": "家园标记必须是布尔值：%s" % activity_id}
	for raw_home_evidence in saved_home_evidence:
		var evidence_activity := str(raw_home_evidence)
		if evidence_activity not in DEFAULT_HOME_FLAGS or not bool(saved_home_flags.get(evidence_activity, false)):
			return {"ok": false, "detail": "家园证据没有对应的完成标记：%s" % evidence_activity}
	for activity_id in DEFAULT_HOME_FLAGS:
		if not bool(saved_home_flags.get(activity_id, false)):
			continue
		var evidence := _dictionary_or_empty(saved_home_evidence.get(activity_id, {}))
		if evidence.is_empty():
			return {"ok": false, "detail": "已完成家园活动缺少证据：%s" % activity_id}
		var validation: Dictionary = SceneContract.validate(activity_id, evidence)
		if not bool(validation.get("ok", false)):
			return {
				"ok": false,
				"detail": "家园证据未通过合同：%s/%s" % [activity_id, validation.get("error", "INVALID_EVIDENCE")],
			}
	return {"ok": true}


func _apply_snapshot(data: Dictionary) -> void:
	route_order = str(data.get("route_order", "puzzle_first"))
	if route_order not in VALID_ROUTES:
		route_order = "puzzle_first"
	room_flags = _merge_defaults(_fresh_room_flags(), data.get("room_flags", {}))
	inventory = _merge_defaults(DEFAULT_INVENTORY, data.get("inventory", {}))
	home_flags = _merge_defaults(DEFAULT_HOME_FLAGS, data.get("home_flags", {}))
	room_evidence = _normalize_evidence_store(data.get("room_evidence", {}))
	home_evidence = _normalize_evidence_store(data.get("home_evidence", {}))
	walnut_level = maxi(1, int(data.get("walnut_level", 1)))
	run_started = bool(data.get("run_started", false))
	settlement_committed = bool(data.get("settlement_committed", false))
	tool_claimed = bool(data.get("tool_claimed", false))
	training_target_hit = bool(data.get("training_target_hit", false))
	current_scene_id = str(data.get("current_scene_id", ""))


func _reset_memory_defaults() -> void:
	var active_content := _read_active_content_identity()
	content_unit = str(active_content.get("unit_id", ""))
	content_version = str(active_content.get("version", ""))
	content_hash = str(active_content.get("content_hash", ""))
	route_order = "puzzle_first"
	room_flags = _fresh_room_flags()
	inventory = DEFAULT_INVENTORY.duplicate(true)
	home_flags = DEFAULT_HOME_FLAGS.duplicate(true)
	room_evidence = {}
	home_evidence = {}
	walnut_level = 1
	run_started = false
	settlement_committed = false
	tool_claimed = false
	training_target_hit = false
	current_scene_id = ""
	last_error = ""


func _fresh_room_flags() -> Dictionary:
	var flags := {}
	for room_id in REQUIRED_SETTLEMENT_FLAGS:
		flags[room_id] = false
	return flags


func _route_sequence() -> Array[String]:
	var sequence: Array[String] = ["observe", "program"]
	if route_order == "combat_first":
		sequence.append_array(["combat", "puzzle"])
	else:
		sequence.append_array(["puzzle", "combat"])
	sequence.append_array(["transfer", "boss_observe", "boss_debug", "boss_combat"])
	return sequence


func _all_required_rooms_done() -> bool:
	return missing_required_rooms().is_empty()


func _scene_basename(scene_id: String) -> String:
	var cleaned := scene_id.strip_edges()
	if cleaned.contains("/"):
		cleaned = cleaned.get_file()
	if cleaned.ends_with(".tscn"):
		cleaned = cleaned.trim_suffix(".tscn")
	return cleaned


func _normalize_room_id(scene_id: String) -> String:
	var raw_id := _scene_basename(scene_id)
	if SCENE_TO_FLAG.has(raw_id):
		return str(SCENE_TO_FLAG[raw_id])
	var aliases := {
		"r0": "observe", "r1": "program", "boss": "boss_observe",
		"boss_guardian": "boss_observe", "result": "settlement",
	}
	return str(aliases.get(raw_id, raw_id))


func _submit_id_for_flag(flag: String) -> String:
	for submit_id in SCENE_TO_FLAG:
		if str(SCENE_TO_FLAG[submit_id]) == flag:
			return str(submit_id)
	return flag


func _normalize_home_id(scene_id: String) -> String:
	var raw_id := _scene_basename(scene_id)
	var aliases := {
		"growth_chamber": "growth",
		"archive_star_map": "archive",
		"workshop_range": "workshop",
	}
	return str(aliases.get(raw_id, raw_id))


func _merge_defaults(defaults: Dictionary, value: Variant) -> Dictionary:
	var merged := defaults.duplicate(true)
	if value is Dictionary:
		for key in value:
			if merged.has(key):
				match typeof(defaults[key]):
					TYPE_INT:
						merged[key] = int(value[key])
					TYPE_FLOAT:
						merged[key] = float(value[key])
					TYPE_BOOL:
						merged[key] = bool(value[key])
					TYPE_STRING:
						merged[key] = str(value[key])
					_:
						merged[key] = value[key]
	return merged


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value.duplicate(true) if value is Dictionary else {}


func _normalize_evidence_store(value: Variant) -> Dictionary:
	var store := _dictionary_or_empty(value)
	for scene_id in store:
		if not store[scene_id] is Dictionary:
			continue
		var evidence: Dictionary = store[scene_id].duplicate(true)
		for field in INTEGER_EVIDENCE_FIELDS:
			if evidence.has(field):
				evidence[field] = int(evidence[field])
		store[scene_id] = evidence
	return store


func _set_error(code: String, detail: String, report_error: bool = true) -> bool:
	last_error = code
	if report_error:
		push_error("[LoopRunState] %s：%s" % [code, detail])
	return false


func _error_result(code: String, detail: String) -> Dictionary:
	_set_error(code, detail)
	return {"ok": false, "error": code}


func _active_save_path() -> String:
	return TEST_SAVE_PATH if test_mode else SAVE_PATH


func _has_test_argument() -> bool:
	var args := OS.get_cmdline_user_args()
	for flag in ["--loop-run-state-test", "--scene-flow-test", "--multi-scene-test", "--theme-map-test", "--level-prep-test", "--settlement-test", "--facility-test", "--room-scene-test", "--home-test", "--home-capture", "--adventure-room-test", "--scene-contract-test", "--multi-scene-room-test", "--scene-capture"]:
		if flag in args:
			return true
	return false


func _read_active_content_identity() -> Dictionary:
	var file := FileAccess.open(CONTENT_PATH, FileAccess.READ)
	if file == null:
		push_error("[LoopRunState] CONTENT_MANIFEST_MISSING：%s" % CONTENT_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("[LoopRunState] CONTENT_MANIFEST_INVALID：%s" % CONTENT_PATH)
		return {}
	return {
		"unit_id": str(parsed.get("unit_id", "")),
		"version": str(parsed.get("version", "")),
		"content_hash": str(parsed.get("content_hash", "")),
	}


func _apply_profile_snapshot(data: Dictionary) -> void:
	inventory = _merge_defaults(DEFAULT_INVENTORY, data.get("inventory", {}))
	home_flags = _merge_defaults(DEFAULT_HOME_FLAGS, data.get("home_flags", {}))
	home_evidence = _normalize_evidence_store(data.get("home_evidence", {}))
	walnut_level = maxi(1, int(data.get("walnut_level", 1)))


func _reset_adventure_memory() -> void:
	route_order = "puzzle_first"
	room_flags = _fresh_room_flags()
	room_evidence = {}
	run_started = false
	settlement_committed = false
	tool_claimed = false
	training_target_hit = false
	current_scene_id = ""


func _run_contract_smoke() -> void:
	reset_for_test()
	assert(bool(configure_route("puzzle_first").get("ok", false)))
	var prep := {"tool_claimed": true, "training_target_hit": true, "shots_fired": 1}
	assert(bool(submit_preparation_evidence(prep).get("ok", false)))
	assert(begin_adventure("puzzle_first"))
	assert(bool(can_enter("r0_observe").get("ok", false)))
	assert(not bool(can_enter("r1_safe_program").get("ok", false)))
	print("LOOP_RUN_STATE_SMOKE_OK")
	get_tree().quit(0)
