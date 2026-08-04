extends Node

const REGISTRY := {
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
const LEGACY_ARGS := ["--demo-test", "--demo-ai-test", "--demo-capture", "--demo-capture-flow"]

var last_request: Dictionary = {"ok": false, "scene_id": "", "scene_path": "", "error": "NO_REQUEST"}
var test_mode := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	test_mode = (
		"--scene-flow-test" in args
		or "--multi-scene-test" in args
		or "--home-test" in args
		or "--home-capture" in args
	)
	if "--scene-flow-test" in args:
		call_deferred("_run_smoke")


func go(scene_id: String) -> Dictionary:
	if not REGISTRY.has(scene_id):
		return _reject(scene_id, "", "UNKNOWN_SCENE_ID")
	var scene_path := str(REGISTRY[scene_id])
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		return _reject(scene_id, scene_path, "SCENE_RESOURCE_MISSING")
	if scene_id == "legacy_data_garden":
		if not _legacy_regression_requested():
			return _reject(scene_id, scene_path, "LEGACY_REGRESSION_ONLY")
	else:
		var gate: Dictionary = LoopRunState.can_enter(scene_id)
		if not bool(gate.get("ok", false)):
			return _reject(scene_id, scene_path, str(gate.get("error", "SCENE_GATE_BLOCKED")))
	last_request = {"ok": true, "scene_id": scene_id, "scene_path": scene_path, "error": ""}
	if test_mode and scene_id != "legacy_data_garden":
		return last_request.duplicate(true)
	var change_error := get_tree().change_scene_to_file(scene_path)
	if change_error != OK:
		return _reject(scene_id, scene_path, "SCENE_CHANGE_FAILED_%d" % change_error)
	return last_request.duplicate(true)


func get_last_request() -> Dictionary:
	return last_request.duplicate(true)


func validate_registry() -> Dictionary:
	var missing: Array[String] = []
	for scene_id in REGISTRY:
		var scene_path := str(REGISTRY[scene_id])
		if not ResourceLoader.exists(scene_path, "PackedScene"):
			missing.append("%s=%s" % [scene_id, scene_path])
	return {"ok": missing.is_empty(), "missing": missing}


func _legacy_regression_requested() -> bool:
	var args := OS.get_cmdline_user_args()
	for flag in LEGACY_ARGS:
		if flag in args:
			return true
	return false


func _reject(scene_id: String, scene_path: String, code: String) -> Dictionary:
	last_request = {"ok": false, "scene_id": scene_id, "scene_path": scene_path, "error": code}
	push_error("[SceneFlow] %s scene_id=%s path=%s" % [code, scene_id, scene_path])
	return last_request.duplicate(true)


func _run_smoke() -> void:
	var registry_result := validate_registry()
	assert(
		bool(registry_result.get("ok", false)),
		"Scene registry missing: %s" % [registry_result.get("missing", [])]
	)
	var request := go("theme_map")
	assert(bool(request.get("ok", false)))
	assert(get_last_request() == request)
	print("SCENE_FLOW_SMOKE_OK")
	get_tree().quit(0)
