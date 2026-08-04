extends "res://scenes/demo/loop_oasis/multi_scene/facility_scene.gd"

## 书书知识星图
##
## A deliberately thin three-step knowledge trace. The player opens each
## source station in order, then physically follows its lit line to the echo
## endpoint. This preserves the memory of program, combat and farm without
## turning the archive into another large mission.

const TRACE_IDS: Array[String] = ["program", "combat", "farm"]
const TRACE_NAMES: Array[String] = ["编程为什么安全", "战斗如何守序", "农场怎样循环"]
const INTERACT_DISTANCE := 37.0
const ECHO_DISTANCE := 24.0

var station_markers: Array[Sprite2D] = []
var echo_markers: Array[Sprite2D] = []
var trace_lines: Array[Line2D] = []
var trace_nodes := 0
var waiting_for_echo := false
var ordered := true
var archive_core: Sprite2D


func _build_facility_world() -> void:
	var core_position := layout_position("ArchiveCore")
	archive_core = add_world_console("ShushuArchiveCore", core_position)
	archive_core.modulate = Color("#8ec5ff")
	add_world_caption("书书 · 知识核心", core_position, Color("#8ec5ff"))

	for index in range(TRACE_IDS.size()):
		var station_position := layout_position("Station%d" % (index + 1))
		var echo_position := layout_position("EchoGoal%d" % (index + 1))
		var station := add_world_marker("ArchiveStation%d" % (index + 1), station_position, index == 0)
		var echo := add_world_marker("ArchiveEcho%d" % (index + 1), echo_position, false)
		echo.hide()
		station_markers.append(station)
		echo_markers.append(echo)
		add_world_caption("%d · %s" % [index + 1, TRACE_NAMES[index]], station_position, COLOR_MUTED)
		add_world_caption("回声 %d" % (index + 1), echo_position, Color("#8ec5ff"))

		var trace_line := Line2D.new()
		trace_line.name = "KnowledgeTrace%d" % (index + 1)
		trace_line.width = 2.5
		trace_line.default_color = Color("#324957")
		trace_line.points = PackedVector2Array([station_position, core_position, echo_position])
		trace_line.z_index = 1
		stage.add_child(trace_line)
		trace_lines.append(trace_line)


func _update_facility(_delta: float) -> void:
	if not waiting_for_echo or trace_nodes >= TRACE_IDS.size():
		return
	var echo_position := layout_position("EchoGoal%d" % (trace_nodes + 1))
	if not player_near(echo_position, ECHO_DISTANCE):
		return
	waiting_for_echo = false
	set_world_marker_active(echo_markers[trace_nodes], true)
	echo_markers[trace_nodes].hide()
	trace_lines[trace_nodes].default_color = Color("#70e6df")
	trace_lines[trace_nodes].width = 4.0
	trace_nodes += 1
	if trace_nodes < TRACE_IDS.size():
		set_world_marker_active(station_markers[trace_nodes], true)
		_set_feedback("第 %d 段知识回声已追到；去读取下一座编号站。" % trace_nodes)
		return
	archive_core.modulate = Color("#70e6df")
	_set_feedback("三段知识轨迹已按序连接到书书核心。")
	request_world_success()


func _handle_facility_interaction() -> void:
	for index in range(station_markers.size()):
		if player_near(layout_position("Station%d" % (index + 1)), INTERACT_DISTANCE):
			_open_station(index)
			return
	if player_near(layout_position("ArchiveCore"), INTERACT_DISTANCE):
		_set_feedback("书书核心只保存你亲自走出的三条轨迹；从左侧编号站开始。")
		return
	_set_feedback("走近左侧编号知识站再按 E。")


func _open_station(index: int) -> void:
	if waiting_for_echo:
		_set_feedback("先沿当前亮起的星线走到右侧回声端点。")
		return
	if index < trace_nodes:
		_set_feedback("第 %d 段轨迹已经存入书书核心。" % (index + 1))
		return
	if index != trace_nodes:
		ordered = false
		fail_facility(
			"ARCHIVE_TRACE_ORDER_BROKEN",
			"知识星图必须按 1→2→3 回放；当前应读取第 %d 站。" % (trace_nodes + 1)
		)
		return
	if not _trace_prerequisite_ready(index):
		fail_facility(
			"ARCHIVE_TRACE_SOURCE_MISSING",
			"还没有“%s”的真实世界完成记录。" % TRACE_NAMES[index]
		)
		return
	waiting_for_echo = true
	trace_lines[index].default_color = Color("#8ec5ff")
	trace_lines[index].width = 3.0
	echo_markers[index].show()
	set_world_marker_active(echo_markers[index], true)
	_set_feedback("第 %d 站已打开。沿亮线走到右侧回声端点，不需要战斗。" % (index + 1))


func _trace_prerequisite_ready(index: int) -> bool:
	match TRACE_IDS[index]:
		"program", "combat":
			return bool(LoopRunState.room_flags.get(TRACE_IDS[index], false))
		"farm":
			return bool(LoopRunState.home_flags.get("farm", false))
		_:
			return false


func collect_completion_evidence() -> Dictionary:
	return {
		"trace_nodes": trace_nodes,
		"ordered": ordered,
		"program_clear": bool(LoopRunState.room_flags.get("program", false)),
		"combat_clear": bool(LoopRunState.room_flags.get("combat", false)),
		"farm_clear": bool(LoopRunState.home_flags.get("farm", false)),
	}


func _progress_text() -> String:
	return "知识轨迹 %d/3\n当前：%s\n顺序：1 → 2 → 3" % [
		trace_nodes,
		"追踪回声" if waiting_for_echo else "读取编号站",
	]


func _context_prompt() -> String:
	if waiting_for_echo:
		return "沿亮起的星线走到右侧回声"
	for index in range(station_markers.size()):
		if player_near(layout_position("Station%d" % (index + 1)), INTERACT_DISTANCE):
			return "E 读取第 %d 段：%s" % [index + 1, TRACE_NAMES[index]]
	return "从左侧 1 号知识站开始"


func _initial_feedback() -> String:
	return "书书把知识压成三条短轨迹：读取编号站，再亲自走到它的回声。"


func _success_feedback() -> String:
	return "编程、战斗与农场三段轨迹已按序存入知识星图。"


func _restore_facility_world() -> void:
	trace_nodes = TRACE_IDS.size()
	waiting_for_echo = false
	ordered = true
	for index in range(station_markers.size()):
		set_world_marker_active(station_markers[index], true)
		echo_markers[index].hide()
		trace_lines[index].default_color = Color("#70e6df")
		trace_lines[index].width = 4.0
	archive_core.modulate = Color("#70e6df")


func run_contract_test() -> bool:
	LoopRunState.room_flags["program"] = true
	LoopRunState.room_flags["combat"] = true
	LoopRunState.inventory["water_seed"] = 1
	var farm_result := LoopRunState.commit_home_activity("farm", {
		"plots_planted": 4,
		"plots_watered": 4,
		"plots_harvested": 4,
		"repeat_count": 4,
		"seed_available": true,
	})
	assert(bool(farm_result.get("ok", false)), "知识星图测试前置农场必须有效")
	for index in range(TRACE_IDS.size()):
		teleport_player_to(layout_position("Station%d" % (index + 1)))
		_handle_facility_interaction()
		assert(waiting_for_echo, "编号知识站必须由近身互动打开")
		teleport_player_to(layout_position("EchoGoal%d" % (index + 1)))
		_update_facility(0.0)
	await get_tree().process_frame
	assert(scene_succeeded and trace_nodes == 3, "知识星图只能在走完三条轨迹后成功")
	assert(bool(LoopRunState.home_flags.get("archive", false)), "知识星图合同必须写入完成标记")
	return true
