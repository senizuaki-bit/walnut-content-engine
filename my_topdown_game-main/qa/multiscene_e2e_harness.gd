extends LoopPlayableScene

const SceneContract := preload("res://scenes/demo/loop_oasis/multi_scene/LoopSceneContract.gd")
const TAMPERED_SAVE_PATH := "user://loop_run_state_tampered_test.json"

const EXPECTED_REGISTRY := {
	"home": "res://scenes/demo/loop_oasis/home_base.tscn",
	"theme_map": "res://scenes/demo/loop_oasis/multi_scene/theme_map.tscn",
	"level_prep": "res://scenes/demo/loop_oasis/multi_scene/level_prep.tscn",
	"r0_observe": "res://scenes/demo/loop_oasis/multi_scene/r0_observe.tscn",
	"r1_safe_program": "res://scenes/demo/loop_oasis/multi_scene/r1_safe_program.tscn",
	"puzzle_bridge": "res://scenes/demo/loop_oasis/multi_scene/puzzle_bridge.tscn",
	"pulse_defense": "res://scenes/demo/loop_oasis/multi_scene/pulse_defense.tscn",
	"r4_transfer": "res://scenes/demo/loop_oasis/multi_scene/r4_transfer.tscn",
	"boss_guardian": "res://scenes/demo/loop_oasis/multi_scene/boss_guardian.tscn",
	"settlement": "res://scenes/demo/loop_oasis/multi_scene/settlement.tscn",
	"farm": "res://scenes/demo/loop_oasis/multi_scene/farm.tscn",
	"growth": "res://scenes/demo/loop_oasis/multi_scene/growth_chamber.tscn",
	"archive": "res://scenes/demo/loop_oasis/multi_scene/archive_star_map.tscn",
	"workshop": "res://scenes/demo/loop_oasis/multi_scene/workshop_range.tscn",
	"legacy_data_garden": "res://scenes/demo/data_garden/data_garden.tscn",
}

const CONTRACT_IDS := [
	"theme_map",
	"level_prep",
	"r0_observe",
	"r1_safe_program",
	"puzzle_bridge",
	"pulse_defense",
	"r4_transfer",
	"boss_observe",
	"boss_debug",
	"boss_combat",
	"settlement",
	"farm",
	"growth",
	"archive",
	"workshop",
]

const EVIDENCE_FIXTURES := {
	"theme_map": {
		"route_order": "puzzle_first",
		"puzzle_required": true,
		"combat_required": true,
	},
	"level_prep": {
		"tool_claimed": true,
		"training_target_hit": true,
		"shots_fired": 1,
	},
	"r0_observe": {
		"movement_distance": 80.0,
		"action_runs": 1,
		"changed_targets": 1,
		"total_targets": 5,
	},
	"r1_safe_program": {
		"repeat_count": 5,
		"completed_targets": 5,
		"total_targets": 5,
		"trace_steps": 5,
		"used_run_or_step": true,
	},
	"puzzle_bridge": {
		"from_count": 5,
		"to_count": 4,
		"bridge_segments_open": 4,
		"counterfactual_last_dormant": true,
		"player_crossed_exit": true,
	},
	"pulse_defense": {
		"enemies_spawned": 3,
		"enemies_defeated": 3,
		"shots_fired": 3,
		"pulse_uses": 1,
		"player_moved": true,
	},
	"r4_transfer": {
		"repeat_count": 6,
		"completed_targets": 6,
		"total_targets": 6,
		"trace_steps": 6,
	},
	"boss_observe": {
		"observed_beats": 4,
		"player_moved": true,
		"dodged_hazards": 1,
	},
	"boss_debug": {
		"defect_run": true,
		"blocked_hits": 2,
		"condition_changed": true,
		"safe_hits": 2,
		"debug_success": true,
	},
	"boss_combat": {
		"boss_max_hp": 6,
		"boss_hp": 0,
		"hits_landed": 6,
		"shots_fired": 6,
		"debug_clear": true,
	},
	"settlement": {
		"all_gates": true,
		"missing_flags": [],
	},
	"farm": {
		"plots_planted": 4,
		"plots_watered": 4,
		"plots_harvested": 4,
		"repeat_count": 4,
		"seed_available": true,
	},
	"growth": {
		"evidence_nodes": 5,
		"farm_complete": true,
		"crop_available": true,
		"calibration_complete": true,
	},
	"archive": {
		"trace_nodes": 3,
		"ordered": true,
		"program_clear": true,
		"combat_clear": true,
		"farm_clear": true,
	},
	"workshop": {
		"targets_spawned": 3,
		"targets_destroyed": 3,
		"shots_landed": 3,
	},
}

var settlement_signal_count := 0
var home_event_order: Array[String] = []
var persistence_verified := false
var gates_verified := false
var fake_world_result: Dictionary = {}
var fake_home_result: Dictionary = {}


func _ready() -> void:
	SceneFlow.test_mode = true
	LoopRunState.test_mode = true
	if not LoopRunState.settlement_committed_once.is_connected(_on_settlement_committed_once):
		LoopRunState.settlement_committed_once.connect(_on_settlement_committed_once)
	if not LoopRunState.state_changed.is_connected(_on_state_changed):
		LoopRunState.state_changed.connect(_on_state_changed)
	call_deferred("_run_harness")


func collect_completion_evidence() -> Dictionary:
	return {}


func _run_harness() -> void:
	if not _test_scene_registry_and_contracts():
		return
	print("MULTISCENE_SCENE_CONTRACT_OK")

	if not _exercise_route("puzzle_first", true):
		return
	print("MULTISCENE_ROUTE_PUZZLE_FIRST_OK")

	if not _exercise_route("combat_first", false):
		return
	print("MULTISCENE_ROUTE_COMBAT_FIRST_OK")

	if not _require(gates_verified, "ROUTE_GATE_MATRIX_NOT_VERIFIED"):
		return
	print("MULTISCENE_GATES_OK")

	if not _require(persistence_verified, "PERSISTENCE_ROUNDTRIP_NOT_VERIFIED"):
		return
	print("MULTISCENE_PERSISTENCE_OK")

	if not _test_popup_and_button_cannot_fake_completion():
		return
	print("MULTISCENE_NO_POPUP_FAKE_OK")

	LoopRunState.reset_for_test(true)
	print("MULTISCENE_E2E_OK")
	get_tree().quit(0)


func _test_scene_registry_and_contracts() -> bool:
	LoopRunState.reset_for_test(true)
	SceneFlow.test_mode = true
	var registry_result: Dictionary = SceneFlow.validate_registry()
	if not _require(bool(registry_result.get("ok", false)), "SCENE_REGISTRY_RESOURCE_MISSING"):
		return false
	if not _require(SceneFlow.REGISTRY.size() == EXPECTED_REGISTRY.size(), "SCENE_REGISTRY_SIZE_MISMATCH"):
		return false
	for scene_id in EXPECTED_REGISTRY:
		if not _require(SceneFlow.REGISTRY.has(scene_id), "SCENE_REGISTRY_ID_MISSING_%s" % scene_id):
			return false
		var expected_path := str(EXPECTED_REGISTRY[scene_id])
		if not _require(str(SceneFlow.REGISTRY[scene_id]) == expected_path, "SCENE_REGISTRY_PATH_MISMATCH_%s" % scene_id):
			return false
		if not _require(ResourceLoader.exists(expected_path, "PackedScene"), "SCENE_PACKED_RESOURCE_MISSING_%s" % scene_id):
			return false

	for contract_id in CONTRACT_IDS:
		var fixture: Dictionary = _fixture(contract_id)
		var valid: Dictionary = SceneContract.validate(contract_id, fixture)
		if not _require(bool(valid.get("ok", false)), "VALID_FIXTURE_REJECTED_%s" % contract_id):
			return false
		var empty: Dictionary = SceneContract.validate(contract_id, {})
		if not _require(not bool(empty.get("ok", false)), "EMPTY_EVIDENCE_ACCEPTED_%s" % contract_id):
			return false

	var unknown_contract: Dictionary = SceneContract.validate("not_registered", {})
	if not _require(
		not bool(unknown_contract.get("ok", false))
		and str(unknown_contract.get("error", "")) == "UNKNOWN_SCENE_ID",
		"UNKNOWN_CONTRACT_NOT_REJECTED"
	):
		return false

	var state_before := _state_signature()
	if not _require(
		not SceneFlow.REGISTRY.has("not_registered"),
		"UNKNOWN_SCENE_FLOW_NOT_REJECTED"
	):
		return false
	if not _require(_state_signature() == state_before, "UNKNOWN_SCENE_MUTATED_STATE"):
		return false

	var legacy_gate: Dictionary = LoopRunState.can_enter("legacy_data_garden")
	if not _require(
		not bool(legacy_gate.get("ok", false))
		and str(legacy_gate.get("error", "")) == "LEGACY_REGRESSION_ONLY",
		"LEGACY_SCENE_BYPASSED_REGRESSION_GATE"
	):
		return false
	return true


func _exercise_route(route: String, exercise_home: bool) -> bool:
	LoopRunState.reset_for_test(true)
	SceneFlow.test_mode = true
	var signal_before := settlement_signal_count

	if not _require_gate_error("r0_observe", "RUN_NOT_STARTED", "%s_R0_EARLY" % route):
		return false

	var route_result: Dictionary = LoopRunState.configure_route(route)
	if not _require(bool(route_result.get("ok", false)), "%s_ROUTE_CONFIGURATION_FAILED" % route):
		return false
	var theme_request: Dictionary = SceneFlow.go("theme_map")
	if not _require(bool(theme_request.get("ok", false)), "%s_THEME_MAP_NAVIGATION_FAILED" % route):
		return false
	var prep_request: Dictionary = SceneFlow.go("level_prep")
	if not _require(bool(prep_request.get("ok", false)), "%s_LEVEL_PREP_NAVIGATION_FAILED" % route):
		return false

	var before_empty_prep := _state_signature()
	var empty_prep: Dictionary = SceneContract.validate("level_prep", {})
	if not _require(
		not bool(empty_prep.get("ok", false))
		and str(empty_prep.get("error", "")) == "EVIDENCE_FIELDS_MISSING",
		"%s_EMPTY_PREP_ACCEPTED" % route
	):
		return false
	if not _require(_state_signature() == before_empty_prep, "%s_EMPTY_PREP_MUTATED_STATE" % route):
		return false

	var prep_result: Dictionary = LoopRunState.submit_preparation_evidence(_fixture("level_prep"))
	if not _require(bool(prep_result.get("ok", false)), "%s_PREP_EVIDENCE_REJECTED" % route):
		return false
	if not _require(LoopRunState.begin_adventure(route), "%s_ADVENTURE_BEGIN_FAILED" % route):
		return false
	if not _require(LoopRunState.route_order == route and LoopRunState.run_started, "%s_RUN_STATE_NOT_STARTED" % route):
		return false
	if not _require_next("r0_observe", "%s_NEXT_R0" % route):
		return false
	if not _require_gate_error("r1_safe_program", "OBSERVE_REQUIRED", "%s_PROGRAM_EARLY" % route):
		return false
	if not _require_gate_error("settlement", "SETTLEMENT_GATES_MISSING", "%s_SETTLEMENT_EARLY" % route):
		return false

	if not _submit_room("r0_observe", "%s_R0" % route):
		return false
	if not _require_next("r1_safe_program", "%s_NEXT_R1" % route):
		return false
	if not _submit_room("r1_safe_program", "%s_R1" % route):
		return false

	if route == "puzzle_first":
		if not _require_gate_ok("puzzle_bridge", "%s_PUZZLE_GATE" % route):
			return false
		if not _require_gate_error("pulse_defense", "COMBAT_GATE_BLOCKED", "%s_COMBAT_EARLY" % route):
			return false
		if not _require_next("puzzle_bridge", "%s_NEXT_PUZZLE" % route):
			return false
		if not _submit_room("puzzle_bridge", "%s_PUZZLE" % route):
			return false
		if not _require_gate_error("r4_transfer", "PUZZLE_COMBAT_REQUIRED", "%s_TRANSFER_AFTER_PUZZLE" % route):
			return false
		if not _require_next("pulse_defense", "%s_NEXT_COMBAT" % route):
			return false
		if not _submit_room("pulse_defense", "%s_COMBAT" % route):
			return false
	else:
		if not _require_gate_ok("pulse_defense", "%s_COMBAT_GATE" % route):
			return false
		if not _require_gate_error("puzzle_bridge", "PUZZLE_GATE_BLOCKED", "%s_PUZZLE_EARLY" % route):
			return false
		if not _require_next("pulse_defense", "%s_NEXT_COMBAT" % route):
			return false
		if not _submit_room("pulse_defense", "%s_COMBAT" % route):
			return false
		if not _require_gate_error("r4_transfer", "PUZZLE_COMBAT_REQUIRED", "%s_TRANSFER_AFTER_COMBAT" % route):
			return false
		if not _require_next("puzzle_bridge", "%s_NEXT_PUZZLE" % route):
			return false
		if not _submit_room("puzzle_bridge", "%s_PUZZLE" % route):
			return false

	if not _require_next("r4_transfer", "%s_NEXT_TRANSFER" % route):
		return false
	if not _submit_room("r4_transfer", "%s_TRANSFER" % route):
		return false
	if not _require_gate_ok("boss_observe", "%s_BOSS_OBSERVE_GATE" % route):
		return false
	if not _require_gate_error("boss_debug", "BOSS_OBSERVE_REQUIRED", "%s_BOSS_DEBUG_EARLY" % route):
		return false
	if not _require_next("boss_guardian", "%s_NEXT_BOSS_OBSERVE" % route):
		return false
	var boss_request: Dictionary = SceneFlow.go("boss_guardian")
	if not _require(bool(boss_request.get("ok", false)), "%s_BOSS_SCENE_NAVIGATION_FAILED" % route):
		return false

	if not _submit_room("boss_observe", "%s_BOSS_OBSERVE" % route):
		return false
	if not _require_gate_error("boss_combat", "BOSS_DEBUG_REQUIRED", "%s_BOSS_COMBAT_EARLY" % route):
		return false
	if not _require_next("boss_guardian", "%s_NEXT_BOSS_DEBUG" % route):
		return false
	if not _submit_room("boss_debug", "%s_BOSS_DEBUG" % route):
		return false
	if not _require_gate_ok("boss_combat", "%s_BOSS_COMBAT_GATE" % route):
		return false
	if not _require_next("boss_guardian", "%s_NEXT_BOSS_COMBAT" % route):
		return false
	if not _submit_room("boss_combat", "%s_BOSS_COMBAT" % route):
		return false

	if not _require(LoopRunState.missing_required_rooms().is_empty(), "%s_REQUIRED_ROOMS_STILL_MISSING" % route):
		return false
	if not _require(LoopRunState.room_evidence.size() == 8, "%s_ROOM_EVIDENCE_COUNT_MISMATCH" % route):
		return false
	for flag in LoopRunState.REQUIRED_SETTLEMENT_FLAGS:
		if not _require(
			LoopRunState.room_evidence.has(flag)
			and not Dictionary(LoopRunState.room_evidence[flag]).is_empty(),
			"%s_ROOM_EVIDENCE_EMPTY_%s" % [route, flag]
		):
			return false
	if not _require_next("settlement", "%s_NEXT_SETTLEMENT" % route):
		return false
	var settlement_request: Dictionary = SceneFlow.go("settlement")
	if not _require(bool(settlement_request.get("ok", false)), "%s_SETTLEMENT_NAVIGATION_FAILED" % route):
		return false

	var seed_before := int(LoopRunState.inventory.get("water_seed", 0))
	var fragment_before := int(LoopRunState.inventory.get("law_fragment", 0))
	if not _require(LoopRunState.commit_settlement(), "%s_SETTLEMENT_COMMIT_FAILED" % route):
		return false
	if not _require(
		int(LoopRunState.inventory.get("water_seed", 0)) == seed_before + 1
		and int(LoopRunState.inventory.get("law_fragment", 0)) == fragment_before + 1,
		"%s_SETTLEMENT_REWARD_MISMATCH" % route
	):
		return false
	var reward_snapshot := LoopRunState.inventory.duplicate(true)
	if not _require(LoopRunState.commit_settlement(), "%s_SETTLEMENT_IDEMPOTENT_CALL_FAILED" % route):
		return false
	if not _require(LoopRunState.inventory == reward_snapshot, "%s_SETTLEMENT_REWARDED_TWICE" % route):
		return false
	if not _require(settlement_signal_count == signal_before + 1, "%s_SETTLEMENT_SIGNAL_NOT_IDEMPOTENT" % route):
		return false

	if exercise_home and not _exercise_home_sequence_and_persistence():
		return false
	gates_verified = true
	return true


func _exercise_home_sequence_and_persistence() -> bool:
	home_event_order.clear()
	var home_request: Dictionary = SceneFlow.go("home")
	if not _require(bool(home_request.get("ok", false)), "HOME_NAVIGATION_FAILED"):
		return false

	var seed_before := int(LoopRunState.inventory.get("water_seed", 0))
	var crop_before := int(LoopRunState.inventory.get("crop", 0))
	if not _submit_home_activity("farm", "HOME_FARM"):
		return false
	if not _require(
		int(LoopRunState.inventory.get("water_seed", 0)) == seed_before - 1
		and int(LoopRunState.inventory.get("crop", 0)) == crop_before + 1,
		"HOME_FARM_RESOURCE_FLOW_MISMATCH"
	):
		return false

	if not _submit_home_activity("growth", "HOME_GROWTH"):
		return false
	if not _require(
		int(LoopRunState.inventory.get("crop", 0)) == crop_before
		and LoopRunState.walnut_level >= 2,
		"HOME_GROWTH_RESOURCE_FLOW_MISMATCH"
	):
		return false

	if not _submit_home_activity("archive", "HOME_ARCHIVE"):
		return false
	var module_before := int(LoopRunState.inventory.get("pulse_module", 0))
	if not _submit_home_activity("workshop", "HOME_WORKSHOP"):
		return false
	if not _require(
		int(LoopRunState.inventory.get("pulse_module", 0)) == module_before + 1,
		"HOME_WORKSHOP_REWARD_MISMATCH"
	):
		return false

	var expected_order: Array[String] = ["farm", "growth", "archive", "workshop"]
	if not _require(home_event_order == expected_order, "HOME_ACTIVITY_ORDER_MISMATCH"):
		return false
	if not _require(LoopRunState.home_evidence.size() == 4, "HOME_EVIDENCE_COUNT_MISMATCH"):
		return false
	for activity_id in ["farm", "growth", "archive", "workshop"]:
		if not _require(
			LoopRunState.home_evidence.has(activity_id)
			and not Dictionary(LoopRunState.home_evidence[activity_id]).is_empty(),
			"HOME_EVIDENCE_EMPTY_%s" % activity_id
		):
			return false

	var before_idempotent_farm := _state_signature()
	var farm_again: Dictionary = submit_home_evidence("farm", _fixture("farm"))
	if not _require(
		bool(farm_again.get("ok", false)) and bool(farm_again.get("idempotent", false)),
		"HOME_FARM_NOT_IDEMPOTENT"
	):
		return false
	if not _require(_state_signature() == before_idempotent_farm, "HOME_FARM_IDEMPOTENT_CALL_MUTATED_STATE"):
		return false
	if not _require(home_event_order == expected_order, "HOME_FARM_IDEMPOTENT_CALL_EMITTED_EVENT"):
		return false

	if not _require(LoopRunState.save(), "PERSISTENCE_SAVE_FAILED"):
		return false
	var expected_state := _state_signature()
	LoopRunState.reset_for_test(false)
	if not _require(LoopRunState.load_state(), "PERSISTENCE_LOAD_FAILED"):
		return false
	var restored_state := _state_signature()
	if restored_state != expected_state:
		for field in expected_state:
			if expected_state[field] != restored_state.get(field):
				print(
					"MULTISCENE_PERSISTENCE_DIFF field=%s expected=%s actual=%s"
					% [field, JSON.stringify(expected_state[field]), JSON.stringify(restored_state.get(field))]
				)
	if not _require(restored_state == expected_state, "PERSISTENCE_ROUNDTRIP_MISMATCH"):
		return false
	if not _require(LoopRunState.room_evidence.size() == 8, "PERSISTENCE_ROOM_EVIDENCE_COUNT_MISMATCH"):
		return false
	if not _require(LoopRunState.home_evidence.size() == 4, "PERSISTENCE_HOME_EVIDENCE_COUNT_MISMATCH"):
		return false

	var after_load_state := _state_signature()
	var after_load_inventory := LoopRunState.inventory.duplicate(true)
	if not _require(LoopRunState.commit_settlement(), "PERSISTENCE_SETTLEMENT_IDEMPOTENT_FAILED"):
		return false
	if not _require(
		_state_signature() == after_load_state
		and LoopRunState.inventory == after_load_inventory,
		"PERSISTENCE_SETTLEMENT_IDEMPOTENT_MUTATION"
	):
		return false
	for activity_id in ["farm", "growth", "archive", "workshop"]:
		var before_repeat := _state_signature()
		var repeat_result: Dictionary = submit_home_evidence(activity_id, _fixture(activity_id))
		if not _require(
			bool(repeat_result.get("ok", false)) and bool(repeat_result.get("idempotent", false)),
			"PERSISTENCE_HOME_NOT_IDEMPOTENT_%s" % activity_id
		):
			return false
		if not _require(_state_signature() == before_repeat, "PERSISTENCE_HOME_REPEAT_MUTATED_%s" % activity_id):
			return false
	if not _test_tampered_save_rejection():
		return false
	persistence_verified = true
	return true


func _test_tampered_save_rejection() -> bool:
	if not _require(LoopRunState.save(TAMPERED_SAVE_PATH), "TAMPERED_SAVE_FIXTURE_WRITE_FAILED"):
		return false
	var read_file := FileAccess.open(TAMPERED_SAVE_PATH, FileAccess.READ)
	if not _require(read_file != null, "TAMPERED_SAVE_FIXTURE_READ_FAILED"):
		return false
	var parsed: Variant = JSON.parse_string(read_file.get_as_text())
	read_file = null
	if not _require(parsed is Dictionary, "TAMPERED_SAVE_FIXTURE_JSON_INVALID"):
		return false
	var tampered: Dictionary = parsed
	var tampered_room_evidence: Dictionary = tampered.get("room_evidence", {}).duplicate(true)
	tampered_room_evidence["observe"] = {}
	tampered["room_evidence"] = tampered_room_evidence
	var write_file := FileAccess.open(TAMPERED_SAVE_PATH, FileAccess.WRITE)
	if not _require(write_file != null, "TAMPERED_SAVE_REWRITE_FAILED"):
		return false
	write_file.store_string(JSON.stringify(tampered, "\t"))
	write_file = null

	var before_load := _state_signature()
	var load_accepted := LoopRunState.load_state(TAMPERED_SAVE_PATH, false)
	var load_error := LoopRunState.last_error
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(TAMPERED_SAVE_PATH))
	if not _require(remove_error == OK, "TAMPERED_SAVE_CLEANUP_FAILED"):
		return false
	if not _require(not load_accepted, "TAMPERED_SAVE_ACCEPTED"):
		return false
	if not _require(load_error == "SAVE_EVIDENCE_INVALID", "TAMPERED_SAVE_ERROR_MISMATCH"):
		return false
	return _require(_state_signature() == before_load, "TAMPERED_SAVE_MUTATED_MEMORY")


func _test_popup_and_button_cannot_fake_completion() -> bool:
	LoopRunState.reset_for_test(true)
	var route_result: Dictionary = LoopRunState.configure_route("puzzle_first")
	if not _require(bool(route_result.get("ok", false)), "FAKE_UI_ROUTE_CONFIGURATION_FAILED"):
		return false
	var prep_result: Dictionary = LoopRunState.submit_preparation_evidence(_fixture("level_prep"))
	if not _require(bool(prep_result.get("ok", false)), "FAKE_UI_PREP_FAILED"):
		return false
	if not _require(LoopRunState.begin_adventure("puzzle_first"), "FAKE_UI_ADVENTURE_BEGIN_FAILED"):
		return false

	var popup := PopupPanel.new()
	popup.name = "ContractCannotBeFakedPopup"
	var world_button := Button.new()
	world_button.name = "FakeWorldCompletionButton"
	world_button.text = "完成房间"
	var home_button := Button.new()
	home_button.name = "FakeHomeCompletionButton"
	home_button.text = "完成家园"
	popup.add_child(world_button)
	popup.add_child(home_button)
	add_child(popup)
	world_button.pressed.connect(_on_fake_world_pressed)
	home_button.pressed.connect(_on_fake_home_pressed)

	fake_world_result.clear()
	var before_world_click := _state_signature()
	world_button.pressed.emit()
	if not _require(not bool(fake_world_result.get("ok", false)), "POPUP_EMPTY_WORLD_EVIDENCE_ACCEPTED"):
		popup.queue_free()
		return false
	if not _require(str(fake_world_result.get("error", "")) == "EVIDENCE_FIELDS_MISSING", "POPUP_WORLD_ERROR_MISMATCH"):
		popup.queue_free()
		return false
	if not _require(not LoopRunState.room_done("observe"), "POPUP_WORLD_BUTTON_SET_ROOM_FLAG"):
		popup.queue_free()
		return false
	if not _require(_state_signature() == before_world_click, "POPUP_WORLD_BUTTON_MUTATED_STATE"):
		popup.queue_free()
		return false

	LoopRunState.inventory["water_seed"] = 1
	fake_home_result.clear()
	var before_home_click := _state_signature()
	home_button.pressed.emit()
	if not _require(not bool(fake_home_result.get("ok", false)), "POPUP_EMPTY_HOME_EVIDENCE_ACCEPTED"):
		popup.queue_free()
		return false
	if not _require(str(fake_home_result.get("error", "")) == "EVIDENCE_FIELDS_MISSING", "POPUP_HOME_ERROR_MISMATCH"):
		popup.queue_free()
		return false
	if not _require(not bool(LoopRunState.home_flags.get("farm", false)), "POPUP_HOME_BUTTON_SET_FLAG"):
		popup.queue_free()
		return false
	if not _require(_state_signature() == before_home_click, "POPUP_HOME_BUTTON_MUTATED_STATE"):
		popup.queue_free()
		return false
	popup.queue_free()
	return true


func _on_fake_world_pressed() -> void:
	var evidence := collect_completion_evidence()
	fake_world_result = SceneContract.validate("r0_observe", evidence)
	if bool(fake_world_result.get("ok", false)):
		fake_world_result = submit_world_evidence("r0_observe", evidence)


func _on_fake_home_pressed() -> void:
	var evidence := collect_completion_evidence()
	fake_home_result = SceneContract.validate("farm", evidence)
	if bool(fake_home_result.get("ok", false)):
		fake_home_result = submit_home_evidence("farm", evidence)


func _on_settlement_committed_once(_rewards: Dictionary) -> void:
	settlement_signal_count += 1


func _on_state_changed(section: String, key: String, value: Variant) -> void:
	if section == "home" and bool(value):
		home_event_order.append(key)


func _fixture(contract_id: String) -> Dictionary:
	return EVIDENCE_FIXTURES.get(contract_id, {}).duplicate(true)


func _submit_room(contract_id: String, context: String) -> bool:
	var fixture := _fixture(contract_id)
	var before_empty := _state_signature()
	var empty_result: Dictionary = SceneContract.validate(contract_id, {})
	if not _require(
		not bool(empty_result.get("ok", false))
		and str(empty_result.get("error", "")) == "EVIDENCE_FIELDS_MISSING",
		"%s_EMPTY_EVIDENCE_ACCEPTED" % context
	):
		return false
	if not _require(_state_signature() == before_empty, "%s_EMPTY_EVIDENCE_MUTATED_STATE" % context):
		return false
	var result: Dictionary = submit_world_evidence(contract_id, fixture)
	if not _require(bool(result.get("ok", false)), "%s_EVIDENCE_REJECTED" % context):
		return false
	var flag := str(result.get("flag", ""))
	if not _require(not flag.is_empty() and LoopRunState.room_done(flag), "%s_FLAG_NOT_SET" % context):
		return false
	if not _require(LoopRunState.room_evidence.has(flag), "%s_EVIDENCE_NOT_STORED" % context):
		return false
	if not _require(LoopRunState.room_evidence[flag] == fixture, "%s_EVIDENCE_STORAGE_MISMATCH" % context):
		return false

	var completed_state := _state_signature()
	var empty_after_completion: Dictionary = SceneContract.validate(contract_id, {})
	if not _require(
		not bool(empty_after_completion.get("ok", false))
		and str(empty_after_completion.get("error", "")) == "EVIDENCE_FIELDS_MISSING",
		"%s_EMPTY_EVIDENCE_ACCEPTED_AFTER_COMPLETION" % context
	):
		return false
	if not _require(_state_signature() == completed_state, "%s_EMPTY_AFTER_COMPLETION_MUTATED_STATE" % context):
		return false
	var repeat_result: Dictionary = submit_world_evidence(contract_id, fixture)
	if not _require(
		bool(repeat_result.get("ok", false)) and bool(repeat_result.get("idempotent", false)),
		"%s_VALID_REPEAT_NOT_IDEMPOTENT" % context
	):
		return false
	return _require(_state_signature() == completed_state, "%s_VALID_REPEAT_MUTATED_STATE" % context)


func _submit_home_activity(activity_id: String, context: String) -> bool:
	var navigation: Dictionary = SceneFlow.go(activity_id)
	if not _require(bool(navigation.get("ok", false)), "%s_NAVIGATION_FAILED" % context):
		return false
	var fixture := _fixture(activity_id)
	var before_empty := _state_signature()
	var empty_result: Dictionary = SceneContract.validate(activity_id, {})
	if not _require(
		not bool(empty_result.get("ok", false))
		and str(empty_result.get("error", "")) == "EVIDENCE_FIELDS_MISSING",
		"%s_EMPTY_EVIDENCE_ACCEPTED" % context
	):
		return false
	if not _require(_state_signature() == before_empty, "%s_EMPTY_EVIDENCE_MUTATED_STATE" % context):
		return false
	var result: Dictionary = submit_home_evidence(activity_id, fixture)
	if not _require(bool(result.get("ok", false)), "%s_EVIDENCE_REJECTED" % context):
		return false
	if not _require(bool(LoopRunState.home_flags.get(activity_id, false)), "%s_FLAG_NOT_SET" % context):
		return false
	if not _require(LoopRunState.home_evidence.has(activity_id), "%s_EVIDENCE_NOT_STORED" % context):
		return false
	if not _require(LoopRunState.home_evidence[activity_id] == fixture, "%s_EVIDENCE_STORAGE_MISMATCH" % context):
		return false

	var completed_state := _state_signature()
	var empty_after_completion: Dictionary = SceneContract.validate(activity_id, {})
	if not _require(
		not bool(empty_after_completion.get("ok", false))
		and str(empty_after_completion.get("error", "")) == "EVIDENCE_FIELDS_MISSING",
		"%s_EMPTY_EVIDENCE_ACCEPTED_AFTER_COMPLETION" % context
	):
		return false
	if not _require(_state_signature() == completed_state, "%s_EMPTY_AFTER_COMPLETION_MUTATED_STATE" % context):
		return false
	var repeat_result: Dictionary = submit_home_evidence(activity_id, fixture)
	if not _require(
		bool(repeat_result.get("ok", false)) and bool(repeat_result.get("idempotent", false)),
		"%s_VALID_REPEAT_NOT_IDEMPOTENT" % context
	):
		return false
	return _require(_state_signature() == completed_state, "%s_VALID_REPEAT_MUTATED_STATE" % context)


func _require_next(scene_id: String, context: String) -> bool:
	var expected := str(EXPECTED_REGISTRY.get(scene_id, ""))
	var actual := LoopRunState.next_room_path()
	return _require(not expected.is_empty() and actual == expected, "%s_PATH_MISMATCH" % context)


func _require_gate_ok(scene_id: String, context: String) -> bool:
	var gate: Dictionary = LoopRunState.can_enter(scene_id)
	return _require(bool(gate.get("ok", false)), "%s_GATE_REJECTED" % context)


func _require_gate_error(scene_id: String, expected_error: String, context: String) -> bool:
	var gate: Dictionary = LoopRunState.can_enter(scene_id)
	return _require(
		not bool(gate.get("ok", false)) and str(gate.get("error", "")) == expected_error,
		"%s_GATE_ERROR_MISMATCH" % context
	)


func _state_signature() -> Dictionary:
	return {
		"content_unit": LoopRunState.content_unit,
		"content_version": LoopRunState.content_version,
		"content_hash": LoopRunState.content_hash,
		"route_order": LoopRunState.route_order,
		"room_flags": LoopRunState.room_flags.duplicate(true),
		"inventory": LoopRunState.inventory.duplicate(true),
		"home_flags": LoopRunState.home_flags.duplicate(true),
		"room_evidence": LoopRunState.room_evidence.duplicate(true),
		"home_evidence": LoopRunState.home_evidence.duplicate(true),
		"walnut_level": LoopRunState.walnut_level,
		"run_started": LoopRunState.run_started,
		"settlement_committed": LoopRunState.settlement_committed,
		"tool_claimed": LoopRunState.tool_claimed,
		"training_target_hit": LoopRunState.training_target_hit,
		"current_scene_id": LoopRunState.current_scene_id,
	}


func _require(condition: bool, code: String) -> bool:
	if condition:
		return true
	push_error("MULTISCENE_E2E_FAIL [%s]" % code)
	get_tree().quit(2)
	return false
