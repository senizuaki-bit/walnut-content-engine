extends "res://scenes/demo/loop_oasis/multi_scene/facility_scene.gd"

## 小核桃成长舱
##
## The player reconstructs five pieces of real adventure history in order,
## offers the farm crop at the pod, then walks a three-point calibration path.
## Xiao Hetao visibly changes at each point; no card or HUD action can trigger
## the breakthrough.

const PLANT_SCENES: Array[PackedScene] = [
	preload("res://scenes/props/plant/plant_1.tscn"),
	preload("res://scenes/props/plant/plant_4.tscn"),
]
const EVIDENCE_IDS: Array[String] = [
	"program", "combat", "transfer", "boss_debug", "boss_combat",
]
const EVIDENCE_NAMES: Array[String] = [
	"编程轨迹", "战斗节奏", "迁移桥", "安全 Debug", "Boss 净化",
]
const INTERACT_DISTANCE := 36.0
const CALIBRATION_DISTANCE := 24.0

var evidence_markers: Array[Sprite2D] = []
var calibration_markers: Array[Sprite2D] = []
var evidence_nodes := 0
var calibration_started := false
var calibration_step := 0
var calibration_complete := false
var growth_pod: Sprite2D


func _build_facility_world() -> void:
	for index in range(EVIDENCE_IDS.size()):
		var marker_position := layout_position("Evidence%d" % (index + 1))
		var marker := add_world_marker("GrowthEvidence%d" % (index + 1), marker_position, index == 0)
		evidence_markers.append(marker)
		add_world_caption("%d · %s" % [index + 1, EVIDENCE_NAMES[index]], marker_position, COLOR_MUTED)

	var pod_position := layout_position("GrowthPod")
	growth_pod = add_world_console("XiaoHetaoGrowthPod", pod_position)
	growth_pod.modulate = Color("#d8c2ff")
	add_world_caption("小核桃成长舱", pod_position, Color("#d8c2ff"))
	stage.add_source_prop(PLANT_SCENES[0], pod_position + Vector2(-26, 16), 0.72)
	stage.add_source_prop(PLANT_SCENES[1], pod_position + Vector2(27, 16), 0.72)

	for index in range(3):
		var calibration_position := layout_position("Calibration%d" % (index + 1))
		var calibration := add_world_marker(
			"BreakthroughCalibration%d" % (index + 1),
			calibration_position,
			false
		)
		calibration.hide()
		calibration_markers.append(calibration)
		add_world_caption("校准 %d" % (index + 1), calibration_position, Color("#9d8cff"))

	stage.companion.modulate = Color("#b7c7c0")


func _update_facility(_delta: float) -> void:
	if not calibration_started or calibration_complete or calibration_step >= calibration_markers.size():
		return
	var active_position := layout_position("Calibration%d" % (calibration_step + 1))
	if not player_near(active_position, CALIBRATION_DISTANCE):
		return
	var active_marker := calibration_markers[calibration_step]
	set_world_marker_active(active_marker, false)
	active_marker.hide()
	calibration_step += 1
	stage.companion.scale = Vector2.ONE * (0.026 + calibration_step * 0.006)
	stage.companion.modulate = Color("#c6f6be").lerp(Color("#ffd15c"), calibration_step / 3.0)
	if calibration_step < calibration_markers.size():
		var next_marker := calibration_markers[calibration_step]
		next_marker.show()
		set_world_marker_active(next_marker, true)
		_set_feedback("小核桃完成校准 %d/3；继续亲自走到下一束突破光。" % calibration_step)
		return
	calibration_complete = true
	growth_pod.modulate = Color("#ffd15c")
	_set_feedback("小核桃完成三点空间校准，伙伴突破已在世界中发生。")
	request_world_success()


func _handle_facility_interaction() -> void:
	for index in range(evidence_markers.size()):
		if player_near(layout_position("Evidence%d" % (index + 1)), INTERACT_DISTANCE):
			_scan_evidence(index)
			return
	if player_near(layout_position("GrowthPod"), INTERACT_DISTANCE + 8.0):
		_start_calibration()
		return
	_set_feedback("走近编号证据节点或中央成长舱再按 E。")


func _scan_evidence(index: int) -> void:
	if index < evidence_nodes:
		_set_feedback("%s 已经接入成长舱。" % EVIDENCE_NAMES[index])
		return
	if index != evidence_nodes:
		fail_facility(
			"GROWTH_EVIDENCE_ORDER_BROKEN",
			"成长记录必须按 1→5 接入；当前应读取 %s。" % EVIDENCE_NAMES[evidence_nodes]
		)
		return
	var evidence_id := EVIDENCE_IDS[index]
	if not bool(LoopRunState.room_flags.get(evidence_id, false)):
		fail_facility(
			"GROWTH_EVIDENCE_SOURCE_MISSING",
			"冒险记录中还没有“%s”的真实完成证据。" % EVIDENCE_NAMES[index]
		)
		return
	set_world_marker_active(evidence_markers[index], true)
	evidence_nodes += 1
	if evidence_nodes < evidence_markers.size():
		set_world_marker_active(evidence_markers[evidence_nodes], true)
	_set_feedback("已接入 %s，成长证据 %d/5。" % [EVIDENCE_NAMES[index], evidence_nodes])


func _start_calibration() -> void:
	if calibration_started:
		_set_feedback("校准已经开始；请亲自走过当前发亮的校准点。")
		return
	if evidence_nodes != EVIDENCE_IDS.size():
		_set_feedback("成长舱还缺证据：请从编号 %d 继续读取。" % (evidence_nodes + 1))
		return
	if not bool(LoopRunState.home_flags.get("farm", false)):
		fail_facility("GROWTH_FARM_PREREQUISITE_MISSING", "小核桃突破前需要先完成芽芽家园·编程农场。")
		return
	if int(LoopRunState.inventory.get("crop", 0)) < 1:
		fail_facility("GROWTH_CROP_MISSING", "成长舱没有检测到编程农场产出的突破作物。")
		return
	calibration_started = true
	calibration_step = 0
	calibration_markers[0].show()
	set_world_marker_active(calibration_markers[0], true)
	growth_pod.modulate = Color("#9d8cff")
	_set_feedback("作物已放入成长舱。和小核桃一起走过三束校准光。")


func collect_completion_evidence() -> Dictionary:
	return {
		"evidence_nodes": evidence_nodes,
		"farm_complete": bool(LoopRunState.home_flags.get("farm", false)),
		"crop_available": int(LoopRunState.inventory.get("crop", 0)) >= 1,
		"calibration_complete": calibration_complete,
	}


func _progress_text() -> String:
	return "冒险证据 %d/5\n成长校准 %d/3\n伙伴：%s" % [
		evidence_nodes,
		calibration_step,
		"突破完成" if calibration_complete else "小核桃",
	]


func _context_prompt() -> String:
	for index in range(evidence_markers.size()):
		if player_near(layout_position("Evidence%d" % (index + 1)), INTERACT_DISTANCE):
			return "E 接入 %d · %s" % [index + 1, EVIDENCE_NAMES[index]]
	if player_near(layout_position("GrowthPod"), INTERACT_DISTANCE + 8.0):
		return "E 放入突破作物并启动成长校准"
	if calibration_started:
		return "走到当前发亮的校准点"
	return "按 1→5 走访证据节点"


func _initial_feedback() -> String:
	return "从 1 号节点开始，按顺序重走五段真实冒险证据。"


func _success_feedback() -> String:
	return "五类证据与农场作物完成融合，小核桃已经可见地突破成长。"


func _restore_facility_world() -> void:
	evidence_nodes = EVIDENCE_IDS.size()
	calibration_started = true
	calibration_step = calibration_markers.size()
	calibration_complete = true
	for marker in evidence_markers:
		set_world_marker_active(marker, true)
	for marker in calibration_markers:
		marker.hide()
	stage.companion.scale = Vector2(0.044, 0.044)
	stage.companion.modulate = Color("#ffd15c")
	growth_pod.modulate = Color("#ffd15c")


func run_contract_test() -> bool:
	for evidence_id in EVIDENCE_IDS:
		LoopRunState.room_flags[evidence_id] = true
	LoopRunState.inventory["water_seed"] = 1
	var farm_result := LoopRunState.commit_home_activity("farm", {
		"plots_planted": 4,
		"plots_watered": 4,
		"plots_harvested": 4,
		"repeat_count": 4,
		"seed_available": true,
	})
	assert(bool(farm_result.get("ok", false)), "成长舱测试前置农场必须有效")
	for index in range(EVIDENCE_IDS.size()):
		teleport_player_to(layout_position("Evidence%d" % (index + 1)))
		_handle_facility_interaction()
	assert(evidence_nodes == 5, "五个证据节点必须由五次近身互动接入")
	teleport_player_to(layout_position("GrowthPod"))
	_handle_facility_interaction()
	assert(calibration_started, "成长校准必须由成长舱近身互动启动")
	for index in range(calibration_markers.size()):
		teleport_player_to(layout_position("Calibration%d" % (index + 1)))
		_update_facility(0.0)
	await get_tree().process_frame
	assert(scene_succeeded and calibration_complete, "成长舱只能在走完三点校准后成功")
	assert(bool(LoopRunState.home_flags.get("growth", false)), "成长舱合同必须写入完成标记")
	assert(int(LoopRunState.inventory.get("crop", 0)) == 0, "成长突破必须消费一份作物")
	assert(LoopRunState.walnut_level >= 2, "小核桃成长等级必须提升")
	return true
