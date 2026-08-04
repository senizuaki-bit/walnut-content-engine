extends "res://scenes/demo/loop_oasis/multi_scene/facility_scene.gd"

## 芽芽家园·编程农场
##
## A real four-plot production loop: walk to plant, configure Repeat at
## Dingdang's console, watch the drone execute each Action, then walk back to
## harvest. The home contract is submitted only after all four physical plots
## have completed that lifecycle.

const PLANT_SCENES: Array[PackedScene] = [
	preload("res://scenes/props/plant/plant_1.tscn"),
	preload("res://scenes/props/plant/plant_2.tscn"),
	preload("res://scenes/props/plant/plant_3.tscn"),
	preload("res://scenes/props/plant/plant_4.tscn"),
]
const DRONE_TEXTURE: Texture2D = preload("res://assets/sprites/items/data_garden_console.png")

const PLOT_COUNT := 4
const INTERACT_DISTANCE := 39.0
const DRONE_SPEED := 145.0
const MIN_REPEAT := 1
const MAX_REPEAT := 6

var plots: Array[Dictionary] = []
var drone_console: Sprite2D
var drone: Sprite2D
var repeat_count := 1
var planted_count := 0
var watered_count := 0
var harvested_count := 0
var seed_was_available := false
var drone_running := false
var drone_action_index := 0


func _build_facility_world() -> void:
	for index in range(PLOT_COUNT):
		var world_position := layout_position("Plot%d" % (index + 1))
		var soil := add_world_marker("PhysicalPlot%d" % (index + 1), world_position, false)
		soil.scale *= Vector2(1.45, 0.82)
		add_world_caption("地块 %d" % (index + 1), world_position, COLOR_MUTED)
		plots.append({
			"position": world_position,
			"soil": soil,
			"plant": null,
			"planted": false,
			"watered": false,
			"harvested": false,
		})

	var console_position := layout_position("DroneConsole")
	drone_console = add_world_console("DingdangRepeatConsole", console_position)
	drone_console.modulate = Color("#ffd15c")
	add_world_caption("叮当 · Repeat", console_position, Color("#ffd15c"))

	drone = Sprite2D.new()
	drone.name = "PhysicalWateringDrone"
	drone.texture = DRONE_TEXTURE
	drone.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	drone.position = console_position + Vector2(0, -24)
	drone.scale = Vector2(0.085, 0.085)
	drone.modulate = Color("#70e6df")
	drone.z_index = 9
	stage.add_child(drone)

	# Source-game plant props frame the room and keep this a home production
	# space rather than another menu or combat arena.
	stage.add_source_prop(PLANT_SCENES[1], Vector2(-145, -94), 0.85)
	stage.add_source_prop(PLANT_SCENES[2], Vector2(145, 65), 0.85)


func _update_facility(delta: float) -> void:
	if not drone_running:
		return
	var plot_index := drone_action_index % PLOT_COUNT
	var target_position: Vector2 = plots[plot_index].position + Vector2(0, -18)
	drone.position = drone.position.move_toward(target_position, DRONE_SPEED * delta)
	drone.rotation = sin(Time.get_ticks_msec() * 0.012) * 0.08
	if drone.position.distance_to(target_position) > 1.0:
		return
	_water_plot(plot_index)
	drone_action_index += 1
	if drone_action_index < repeat_count:
		return
	drone_running = false
	drone.rotation = 0.0
	drone.position = layout_position("DroneConsole") + Vector2(0, -24)
	if repeat_count != PLOT_COUNT:
		fail_facility(
			"FARM_REPEAT_MISMATCH",
			"叮当执行了 Repeat(%d)，但四块地需要恰好四次 Action。" % repeat_count
		)
		return
	_set_feedback("叮当已完成四次真实浇灌。现在走到每块成熟地块旁按 E 收获。")


func _handle_facility_interaction() -> void:
	if player_near(layout_position("DroneConsole"), INTERACT_DISTANCE + 8.0):
		_try_start_drone()
		return
	for index in range(plots.size()):
		var plot: Dictionary = plots[index]
		if not player_near(plot.position, INTERACT_DISTANCE):
			continue
		if not bool(plot.planted):
			_plant_plot(index)
		elif bool(plot.watered) and not bool(plot.harvested):
			_harvest_plot(index)
		elif drone_running:
			_set_feedback("叮当正在按 Action 次序浇灌，请先看完世界中的执行过程。")
		else:
			_set_feedback("这块地已播种；去叮当控制台设置 Repeat 并启动。")
		return
	_set_feedback("没有可互动的地块。请走近发光土壤或叮当控制台。")


func _handle_facility_input(event: InputEvent) -> void:
	if drone_running or not player_near(layout_position("DroneConsole"), INTERACT_DISTANCE + 8.0):
		return
	var next_repeat := repeat_count
	if event.is_action_pressed("ui_left"):
		next_repeat = maxi(MIN_REPEAT, repeat_count - 1)
	elif event.is_action_pressed("ui_right"):
		next_repeat = mini(MAX_REPEAT, repeat_count + 1)
	if next_repeat == repeat_count:
		return
	repeat_count = next_repeat
	_set_feedback("叮当控制台已设为 Repeat(%d)。按 E 执行浇灌 Action。" % repeat_count)
	get_viewport().set_input_as_handled()


func _plant_plot(index: int) -> void:
	if int(LoopRunState.inventory.get("water_seed", 0)) < 1:
		fail_facility("FARM_CLEARWATER_SEED_MISSING", "背包里没有清泉种子，先完成一次冒险结算再来。")
		return
	var plot: Dictionary = plots[index]
	seed_was_available = true
	plot.planted = true
	plot.plant = stage.add_source_prop(PLANT_SCENES[index % 2], plot.position + Vector2(0, -7), 0.82)
	plots[index] = plot
	planted_count += 1
	set_world_marker_active(plot.soil as Sprite2D, true)
	_set_feedback("地块 %d 已播种。清泉种子会在合同验证成功时统一结算。" % (index + 1))


func _try_start_drone() -> void:
	if drone_running:
		_set_feedback("叮当正在执行 Repeat(%d)，请观察它逐格移动。" % repeat_count)
		return
	if planted_count != PLOT_COUNT:
		_set_feedback("先走到四块地旁逐一播种，目前 %d/%d。" % [planted_count, PLOT_COUNT])
		return
	if harvested_count > 0:
		_set_feedback("浇灌已结束，请继续收获成熟作物。")
		return
	drone_running = true
	drone_action_index = 0
	_set_feedback("叮当开始执行：Repeat(%d) { Action：移动并浇灌下一块地 }。" % repeat_count)


func _water_plot(index: int) -> void:
	var plot: Dictionary = plots[index]
	if not bool(plot.watered):
		plot.watered = true
		watered_count += 1
	if is_instance_valid(plot.plant):
		(plot.plant as Node2D).queue_free()
	plot.plant = stage.add_source_prop(PLANT_SCENES[2 + index % 2], plot.position + Vector2(0, -8), 0.96)
	plots[index] = plot
	set_world_marker_active(plot.soil as Sprite2D, true)
	_set_feedback("Action %d/%d：地块 %d 已在世界中浇灌。" % [drone_action_index + 1, repeat_count, index + 1])


func _harvest_plot(index: int) -> void:
	var plot: Dictionary = plots[index]
	if bool(plot.harvested):
		return
	plot.harvested = true
	if is_instance_valid(plot.plant):
		(plot.plant as Node2D).queue_free()
	plot.plant = null
	plots[index] = plot
	harvested_count += 1
	set_world_marker_active(plot.soil as Sprite2D, false)
	_set_feedback("地块 %d 已收获，真实收获进度 %d/%d。" % [index + 1, harvested_count, PLOT_COUNT])
	if harvested_count == PLOT_COUNT:
		request_world_success()


func collect_completion_evidence() -> Dictionary:
	return {
		"plots_planted": planted_count,
		"plots_watered": watered_count,
		"plots_harvested": harvested_count,
		"repeat_count": repeat_count,
		"seed_available": seed_was_available,
	}


func _progress_text() -> String:
	return "播种 %d/4\n浇灌 %d/4 · 收获 %d/4\nRepeat(%d)" % [
		planted_count, watered_count, harvested_count, repeat_count
	]


func _context_prompt() -> String:
	if player_near(layout_position("DroneConsole"), INTERACT_DISTANCE + 8.0):
		return "← / → 调 Repeat(%d)，E 启动 Action" % repeat_count
	for index in range(plots.size()):
		var plot: Dictionary = plots[index]
		if not player_near(plot.position, INTERACT_DISTANCE):
			continue
		if not bool(plot.planted):
			return "E 播下清泉种子"
		if bool(plot.watered) and not bool(plot.harvested):
			return "E 收获成熟作物"
		return "等待叮当执行浇灌"
	return "走近四块地或右侧叮当控制台"


func _initial_feedback() -> String:
	return "生产循环：先逐块播种，再在叮当控制台配置 Repeat，最后逐块收获。"


func _success_feedback() -> String:
	return "四块地完成播种、Repeat(4) 浇灌和真实收获；突破作物已生成。"


func _restore_facility_world() -> void:
	repeat_count = PLOT_COUNT
	planted_count = PLOT_COUNT
	watered_count = PLOT_COUNT
	harvested_count = PLOT_COUNT
	seed_was_available = true
	for index in range(plots.size()):
		var plot: Dictionary = plots[index]
		plot.planted = true
		plot.watered = true
		plot.harvested = true
		plot.plant = stage.add_source_prop(PLANT_SCENES[2 + index % 2], plot.position + Vector2(0, -8), 0.9)
		plots[index] = plot
		set_world_marker_active(plot.soil as Sprite2D, true)


func run_contract_test() -> bool:
	LoopRunState.inventory["water_seed"] = 1
	for index in range(plots.size()):
		teleport_player_to(plots[index].position)
		_handle_facility_interaction()
	assert(planted_count == PLOT_COUNT, "农场测试必须通过四次近身互动播种")
	repeat_count = PLOT_COUNT
	teleport_player_to(layout_position("DroneConsole"))
	_handle_facility_interaction()
	assert(drone_running, "叮当必须由控制台近身互动启动")
	for _step in range(16):
		_update_facility(1.0)
		if not drone_running:
			break
	assert(watered_count == PLOT_COUNT and not scene_failed, "Repeat(4) 必须浇灌四块地")
	for index in range(plots.size()):
		teleport_player_to(plots[index].position)
		_handle_facility_interaction()
	await get_tree().process_frame
	assert(scene_succeeded, "农场只能在四次真实收获后成功")
	assert(bool(LoopRunState.home_flags.get("farm", false)), "农场合同必须写入完成标记")
	assert(int(LoopRunState.inventory.get("water_seed", 0)) == 0, "成功后必须消费一枚清泉种子")
	assert(int(LoopRunState.inventory.get("crop", 0)) == 1, "成功后必须生成突破作物")
	return true
