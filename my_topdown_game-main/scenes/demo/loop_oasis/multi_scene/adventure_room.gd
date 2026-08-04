extends LoopPlayableScene

## Six independent locations share this controller, while SourceRoomStage owns
## the real room/player/weapon/enemy/chest/portal lifecycle from the supplied
## Godot Soul-Knight-style project.

enum BossPhase {
	OBSERVE,
	DEBUG,
	COMBAT,
	COMPLETE,
}

const SourceStage := preload("res://scenes/demo/loop_oasis/multi_scene/source_room_stage.gd")
const SceneContract := preload("res://scenes/demo/loop_oasis/multi_scene/LoopSceneContract.gd")
const PLANT_SCENES: Array[PackedScene] = [
	preload("res://scenes/props/plant/plant_1.tscn"),
	preload("res://scenes/props/plant/plant_2.tscn"),
	preload("res://scenes/props/plant/plant_3.tscn"),
	preload("res://scenes/props/plant/plant_4.tscn"),
]
const ENEMY_WEAPON := preload("res://custom_resource/weapons/enemy_weapons/enemy_pistol/pistol_enemy.tres")
const PANEL_TEXTURE := preload("res://assets/sprites/interface/box.png")
const BUTTON_TEXTURE := preload("res://assets/sprites/interface/Button_Blue.png")
const BAR_UNDER := preload("res://assets/sprites/interface/bar_under.png")
const BAR_OVER := preload("res://assets/sprites/interface/bar_over.png")
const BAR_HEALTH := preload("res://assets/sprites/interface/bar_health.png")

const COLOR_TEXT := Color("#fff7dc")
const COLOR_MUTED := Color("#d7d5c7")
const COLOR_GOLD := Color("#ffd15c")
const COLOR_CYAN := Color("#70e6df")
const COLOR_CORAL := Color("#ff7669")
const COLOR_MINT := Color("#8be59e")

const ROOM_TITLES := {
	"r0_observe": "转转绿洲 · 干涸花园",
	"r1_safe_program": "转转绿洲 · 安全阀门阵",
	"puzzle_bridge": "转转绿洲 · 谜题小桥",
	"pulse_defense": "转转绿洲 · 守护小防线",
	"r4_transfer": "转转绿洲 · 新任务巡查",
	"boss_guardian": "转转绿洲 · 迷糊小伙伴",
}

const ROOM_OBJECTIVES := {
	"r0_observe": "先在房间里观察，再靠近装置按 E；单次指令只会唤醒 1 / 5 株幼苗。",
	"r1_safe_program": "靠近安全阀门台，把循环调到 Repeat(5)，让五个阀门在世界中依次恢复。",
	"puzzle_bridge": "把继承的 5 改成 4；让四段星光桥显形，并亲自走到桥的另一侧。",
	"pulse_defense": "bug 军团已经封门：移动走位、按 Q 释放一次循环脉冲，再用真实射击清场。",
	"r4_transfer": "不显示答案结构；把刚学到的循环规律迁移到六个陌生巡查目标。",
	"boss_guardian": "迷糊小伙伴不是坏人：先躲避并观察四拍，再安全 Debug，最后实战净化。",
}

@export var location_id := "r0_observe"

var stage: SourceRoomStage
var entry_allowed := false
var entry_gate_result: Dictionary = {}
var room_completed := false
var transition_lock := false
var contract_test_mode := false
var capture_mode := false
var capture_name := ""
var active_contract_id := ""

var console_node: Sprite2D
var target_nodes: Array[Sprite2D] = []
var target_active: Array[bool] = []
var repeat_count := 2
var program_steps := 0
var program_used := false
var action_runs := 0
var bridge_segments_open := 0
var puzzle_ready := false
var player_crossed_exit := false
var combat_retry_pending := false

var boss_phase: BossPhase = BossPhase.OBSERVE
var boss: Enemy
var boss_beat_timer := 1.0
var boss_observed_beats := 0
var dodged_hazards := 0
var boss_defect_run := false
var boss_condition_fixed := false
var boss_blocked_hits := 0
var boss_safe_hits := 0
var boss_debug_success := false
var boss_hp := 6
var boss_hits_landed := 0
var boss_shots_fired := 0
var boss_shot_baseline := 0
var last_boss_distance := 0.0
var boss_pattern_index := 0

var objective_label: Label
var progress_label: Label
var feedback_label: Label
var prompt_label: Label
var program_panel: NinePatchRect
var repeat_label: Label
var trace_label: Label
var boss_debug_panel: NinePatchRect
var boss_debug_label: Label
var debug_run_button: Button
var debug_condition_button: Button
var debug_fixed_button: Button
var boss_bar: TextureProgressBar
var boss_bar_label: Label
var failure_panel: NinePatchRect


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_configure_runtime_args(args)
	contract_test_mode = _contract_test_requested(args)
	entry_gate_result = _normalize_gate_result(LoopRunState.can_enter(location_id))
	room_completed = false if capture_mode else _location_completed_in_run_state()
	entry_allowed = bool(entry_gate_result.get("ok", false)) or room_completed or capture_mode or contract_test_mode

	stage = SourceStage.new() as SourceRoomStage
	stage.name = "SourceRoomStage"
	add_child(stage)
	await stage.build({
		"stage_id": location_id,
		"title": str(ROOM_TITLES.get(location_id, location_id)),
		"boss_room": location_id == "boss_guardian",
		"capture_mode": capture_mode or contract_test_mode,
		"auto_reward_on_clear": false,
	})
	_connect_stage_signals()
	_build_world_content()
	_build_ui()

	if not entry_allowed:
		stage.set_player_input(false)
		_set_feedback("入口被 bug 迷雾阻断：%s" % str(entry_gate_result.get("error", "ROOM_GATE_BLOCKED")), true)
	elif room_completed:
		_restore_completed_world()
	else:
		_set_feedback(_initial_feedback())

	if contract_test_mode:
		call_deferred("_run_contract_test_and_quit")
	elif capture_mode:
		call_deferred("_start_room_flow")
		call_deferred("_capture_and_quit")
	else:
		call_deferred("_start_room_flow")


func _process(delta: float) -> void:
	if not entry_allowed or contract_test_mode:
		return
	_update_world_prompt()
	if location_id == "puzzle_bridge" and puzzle_ready and not player_crossed_exit:
		_check_puzzle_crossing()
	if location_id == "boss_guardian" and boss_phase in [BossPhase.OBSERVE, BossPhase.COMBAT]:
		boss_beat_timer -= delta
		if boss_beat_timer <= 0.0:
			boss_beat_timer = 1.05 if boss_phase == BossPhase.OBSERVE else 1.35
			if boss_phase == BossPhase.OBSERVE:
				_boss_observation_beat()
			else:
				_spawn_boss_pattern()
	_update_progress()


func _unhandled_input(event: InputEvent) -> void:
	if not entry_allowed or contract_test_mode or transition_lock:
		return
	if event.is_action_pressed("ui_cancel"):
		if program_panel.visible:
			_close_program_panel()
			get_viewport().set_input_as_handled()
		elif boss_debug_panel.visible:
			_close_boss_debug_panel()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		_handle_world_interaction()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("loop_pulse") and location_id == "pulse_defense":
		stage.use_loop_pulse()
		get_viewport().set_input_as_handled()


func _configure_runtime_args(args: PackedStringArray) -> void:
	for index in range(args.size()):
		var argument := str(args[index])
		if argument == "--scene-capture":
			capture_mode = true
			if index + 1 < args.size() and not str(args[index + 1]).begins_with("--"):
				capture_name = str(args[index + 1])
		elif argument.begins_with("--scene-capture="):
			capture_mode = true
			capture_name = argument.trim_prefix("--scene-capture=")
		elif argument.begins_with("--scene-capture-name="):
			capture_mode = true
			capture_name = argument.trim_prefix("--scene-capture-name=")
	if capture_name.is_empty():
		capture_name = location_id


func _contract_test_requested(args: PackedStringArray) -> bool:
	return "--adventure-room-test" in args or "--scene-contract-test" in args or "--multi-scene-room-test" in args


func _location_completed_in_run_state() -> bool:
	if location_id == "boss_guardian":
		return bool(LoopRunState.room_flags.get("boss_combat", false))
	return LoopRunState.room_done(location_id)


func _connect_stage_signals() -> void:
	stage.player_shot.connect(_on_player_shot)
	stage.enemy_defeated.connect(_on_enemy_defeated)
	stage.room_cleared.connect(_on_stage_room_cleared)
	stage.chest_opened.connect(_on_chest_opened)
	stage.portal_entered.connect(_on_portal_entered)
	stage.player_defeated.connect(_on_player_defeated)
	stage.pulse_used.connect(func(_total: int) -> void: _update_progress())


func _build_world_content() -> void:
	match location_id:
		"r0_observe":
			repeat_count = 1
			console_node = stage.add_console(Vector2(0, 28))
			target_nodes = stage.add_targets(PackedVector2Array([
				Vector2(-128, -82), Vector2(-64, -112), Vector2(0, -122),
				Vector2(64, -112), Vector2(128, -82),
			]))
			_add_cover_props([Vector2(-145, 35), Vector2(145, 35)])
		"r1_safe_program":
			repeat_count = 2
			console_node = stage.add_console(Vector2(0, 40))
			target_nodes = stage.add_targets(PackedVector2Array([
				Vector2(-128, -85), Vector2(-64, -102), Vector2(0, -108),
				Vector2(64, -102), Vector2(128, -85),
			]))
			_add_cover_props([Vector2(-145, 22), Vector2(145, 22)])
		"puzzle_bridge":
			repeat_count = 5
			console_node = stage.add_console(Vector2(-126, 62))
			target_nodes = stage.add_targets(PackedVector2Array([
				Vector2(-112, -14), Vector2(-56, -28), Vector2(0, -34),
				Vector2(56, -28), Vector2(112, -14),
			]))
			_add_cover_props([Vector2(-145, -92), Vector2(145, -92)])
		"pulse_defense":
			_add_cover_props([Vector2(-116, -8), Vector2(116, -8), Vector2(0, -96)])
		"r4_transfer":
			repeat_count = 3
			console_node = stage.add_console(Vector2(0, 50))
			target_nodes = stage.add_targets(PackedVector2Array([
				Vector2(-130, -62), Vector2(-78, -108), Vector2(-24, -82),
				Vector2(30, -108), Vector2(84, -82), Vector2(136, -54),
			]))
			_add_cover_props([Vector2(-148, 30), Vector2(148, 30)])
		"boss_guardian":
			console_node = stage.add_console(Vector2(122, 48))
			console_node.hide()
			_add_cover_props([Vector2(-132, -6), Vector2(132, -6), Vector2(-92, 70), Vector2(92, 70)])
	for _target in target_nodes:
		target_active.append(false)


func _add_cover_props(positions: Array[Vector2]) -> void:
	for index in range(positions.size()):
		stage.add_source_prop(PLANT_SCENES[index % PLANT_SCENES.size()], positions[index], 1.0)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "LearningHud"
	layer.layer = 40
	add_child(layer)

	objective_label = _make_label(str(ROOM_OBJECTIVES.get(location_id, "")), 16, COLOR_TEXT)
	objective_label.position = Vector2(220, 66)
	objective_label.size = Vector2(840, 42)
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.add_theme_color_override("font_outline_color", Color("#080a10"))
	objective_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(objective_label)

	progress_label = _make_label("", 17, COLOR_GOLD)
	progress_label.position = Vector2(930, 18)
	progress_label.size = Vector2(320, 70)
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress_label.add_theme_color_override("font_outline_color", Color("#080a10"))
	progress_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(progress_label)

	feedback_label = _make_label("", 18, COLOR_TEXT)
	feedback_label.position = Vector2(265, 620)
	feedback_label.size = Vector2(750, 58)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.add_theme_color_override("font_outline_color", Color("#080a10"))
	feedback_label.add_theme_constant_override("outline_size", 7)
	layer.add_child(feedback_label)

	prompt_label = _make_label("", 19, COLOR_CYAN)
	prompt_label.position = Vector2(450, 555)
	prompt_label.size = Vector2(380, 44)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.add_theme_color_override("font_outline_color", Color("#080a10"))
	prompt_label.add_theme_constant_override("outline_size", 7)
	layer.add_child(prompt_label)

	var controls := _make_label(_control_help(), 15, COLOR_MUTED)
	controls.position = Vector2(18, 688)
	controls.size = Vector2(1100, 26)
	controls.add_theme_color_override("font_outline_color", Color.BLACK)
	controls.add_theme_constant_override("outline_size", 5)
	layer.add_child(controls)

	_build_program_panel(layer)
	_build_boss_debug_panel(layer)
	_build_boss_bar(layer)
	_build_failure_panel(layer)
	_update_progress()

func _build_program_panel(layer: CanvasLayer) -> void:
	program_panel = _make_nine_patch(Rect2(896, 148, 352, 390))
	layer.add_child(program_panel)
	var title := _make_label("世界编程装置", 24, COLOR_TEXT)
	title.position = Vector2(26, 22)
	title.size = Vector2(300, 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	program_panel.add_child(title)
	repeat_label = _make_label("", 25, COLOR_GOLD)
	repeat_label.position = Vector2(58, 72)
	repeat_label.size = Vector2(236, 48)
	repeat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	repeat_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	program_panel.add_child(repeat_label)

	var minus := _make_source_button("－", 24)
	minus.position = Vector2(38, 138)
	minus.size = Vector2(82, 48)
	minus.pressed.connect(func() -> void: _adjust_repeat(-1))
	program_panel.add_child(minus)
	var plus := _make_source_button("＋", 24)
	plus.position = Vector2(232, 138)
	plus.size = Vector2(82, 48)
	plus.pressed.connect(func() -> void: _adjust_repeat(1))
	program_panel.add_child(plus)

	var reset := _make_source_button("重置", 17)
	reset.position = Vector2(38, 204)
	reset.size = Vector2(124, 46)
	reset.pressed.connect(_reset_program)
	program_panel.add_child(reset)
	var run := _make_source_button("运行", 18)
	run.position = Vector2(190, 204)
	run.size = Vector2(124, 46)
	run.pressed.connect(func() -> void: await _run_program())
	program_panel.add_child(run)

	trace_label = _make_label("程序改变的是房间里的实体目标。", 15, COLOR_MUTED)
	trace_label.position = Vector2(28, 270)
	trace_label.size = Vector2(296, 52)
	trace_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trace_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	program_panel.add_child(trace_label)
	var close := _make_source_button("返回房间", 16)
	close.position = Vector2(92, 326)
	close.size = Vector2(168, 42)
	close.pressed.connect(_close_program_panel)
	program_panel.add_child(close)
	program_panel.hide()
	_update_program_ui()


func _build_boss_debug_panel(layer: CanvasLayer) -> void:
	boss_debug_panel = _make_nine_patch(Rect2(858, 132, 390, 440))
	layer.add_child(boss_debug_panel)
	var title := _make_label("安全 Debug 台", 25, COLOR_TEXT)
	title.position = Vector2(30, 22)
	title.size = Vector2(330, 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_debug_panel.add_child(title)
	boss_debug_label = _make_label("", 17, COLOR_MUTED)
	boss_debug_label.position = Vector2(34, 76)
	boss_debug_label.size = Vector2(322, 116)
	boss_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boss_debug_panel.add_child(boss_debug_label)
	debug_run_button = _make_source_button("运行错乱程序", 17)
	debug_run_button.position = Vector2(46, 214)
	debug_run_button.size = Vector2(298, 48)
	debug_run_button.pressed.connect(func() -> void: await _run_boss_debug_trace())
	boss_debug_panel.add_child(debug_run_button)
	debug_condition_button = _make_source_button("改为：弱点显形才攻击", 16)
	debug_condition_button.position = Vector2(46, 278)
	debug_condition_button.size = Vector2(298, 48)
	debug_condition_button.pressed.connect(_toggle_boss_condition)
	boss_debug_panel.add_child(debug_condition_button)
	debug_fixed_button = _make_source_button("重新运行修正程序", 17)
	debug_fixed_button.position = Vector2(46, 342)
	debug_fixed_button.size = Vector2(298, 48)
	debug_fixed_button.pressed.connect(func() -> void: await _run_boss_debug_trace())
	boss_debug_panel.add_child(debug_fixed_button)
	boss_debug_panel.hide()
	_update_boss_debug_ui()


func _build_boss_bar(layer: CanvasLayer) -> void:
	boss_bar = TextureProgressBar.new()
	boss_bar.position = Vector2(380, 132)
	boss_bar.size = Vector2(520, 28)
	boss_bar.max_value = 6.0
	boss_bar.value = 6.0
	boss_bar.nine_patch_stretch = true
	boss_bar.stretch_margin_left = 3
	boss_bar.stretch_margin_right = 3
	boss_bar.texture_under = BAR_UNDER
	boss_bar.texture_over = BAR_OVER
	boss_bar.texture_progress = BAR_HEALTH
	boss_bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(boss_bar)
	boss_bar_label = _make_label("迷糊小伙伴 · bug 迷雾", 17, COLOR_TEXT)
	boss_bar_label.position = Vector2(380, 105)
	boss_bar_label.size = Vector2(520, 26)
	boss_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_bar_label.add_theme_color_override("font_outline_color", Color.BLACK)
	boss_bar_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(boss_bar_label)
	boss_bar.visible = location_id == "boss_guardian"
	boss_bar_label.visible = location_id == "boss_guardian"


func _build_failure_panel(layer: CanvasLayer) -> void:
	failure_panel = _make_nine_patch(Rect2(390, 230, 500, 250))
	layer.add_child(failure_panel)
	var title := _make_label("bug 迷雾缠结更深了", 28, COLOR_TEXT)
	title.position = Vector2(34, 34)
	title.size = Vector2(432, 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	failure_panel.add_child(title)
	var copy := _make_label("没有资源惩罚；重新进入本房间即可继续观察和尝试。", 18, COLOR_MUTED)
	copy.position = Vector2(52, 92)
	copy.size = Vector2(396, 54)
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	failure_panel.add_child(copy)
	var retry := _make_source_button("立即重试", 20)
	retry.position = Vector2(150, 168)
	retry.size = Vector2(200, 52)
	retry.pressed.connect(func() -> void: get_tree().reload_current_scene())
	failure_panel.add_child(retry)
	failure_panel.hide()


func _start_room_flow() -> void:
	if not entry_allowed or room_completed:
		return
	match location_id:
		"pulse_defense":
			await stage.spawn_wave(3, 2.0)
			_set_feedback("木门已经封闭。先移动，再按 Q 让循环脉冲作用于全部 bug，最后逐个射击清场。")
		"boss_guardian":
			_start_or_restore_boss()


func _restore_completed_world() -> void:
	for index in range(target_nodes.size()):
		_set_target_active(index, location_id != "puzzle_bridge" or index < 4)
	if location_id == "puzzle_bridge":
		bridge_segments_open = 4
		puzzle_ready = true
		player_crossed_exit = true
	if location_id == "boss_guardian":
		boss_phase = BossPhase.COMPLETE
		if is_instance_valid(console_node):
			console_node.hide()
		boss_bar.value = 0.0
		boss_bar_label.text = "迷糊小伙伴 · 已恢复清醒"
	stage.reveal_portal_for_completed_room()
	_set_feedback("本房间的世界证据已经保存。先经过实体宝箱，再走入星光传送门。")


func _update_world_prompt() -> void:
	prompt_label.text = ""
	if program_panel.visible or boss_debug_panel.visible or failure_panel.visible:
		return
	if is_instance_valid(console_node) and console_node.visible and stage.player_position().distance_to(console_node.global_position) <= 54.0:
		match location_id:
			"r0_observe":
				prompt_label.text = "[E] 执行一次"
			"boss_guardian":
				if boss_phase == BossPhase.DEBUG:
					prompt_label.text = "[E] 打开安全 Debug 台"
			_:
				prompt_label.text = "[E] 打开世界编程装置"
	elif stage.portal_ready:
		prompt_label.text = "走入星光传送门继续"
	elif is_instance_valid(stage.chest) and not stage.chest_was_opened:
		prompt_label.text = "走近宝箱领取世界内奖励"


func _handle_world_interaction() -> void:
	if not is_instance_valid(console_node) or not console_node.visible:
		return
	if stage.player_position().distance_to(console_node.global_position) > 54.0:
		_set_feedback("需要先走到实体装置旁边。", true)
		return
	match location_id:
		"r0_observe":
			_r0_single_action()
		"r1_safe_program", "puzzle_bridge", "r4_transfer":
			_open_program_panel()
		"boss_guardian":
			if boss_phase == BossPhase.DEBUG:
				_open_boss_debug_panel()


func _r0_single_action() -> void:
	if room_completed or action_runs > 0:
		return
	if stage.player_distance < 40.0:
		_set_feedback("先在房间里走动观察至少 40 距离；世界证据不能由按钮替代。", true)
		return
	action_runs = 1
	_set_target_active(0, true)
	var result := _submit_current_evidence("r0_observe")
	if bool(result.get("ok", false)):
		room_completed = true
		stage.complete_noncombat_room(false)
		_set_feedback("事实已验证：一次动作只改变 1 / 5。木门已打开，实体宝箱已经出现。")
	else:
		_set_feedback("世界证据被拒绝：%s" % str(result.get("error", "UNKNOWN_CONTRACT_ERROR")), true)


func _open_program_panel() -> void:
	if room_completed:
		return
	program_panel.show()
	stage.set_player_input(false)
	_update_program_ui()


func _close_program_panel() -> void:
	program_panel.hide()
	stage.set_player_input(true)


func _adjust_repeat(delta: int) -> void:
	repeat_count = clampi(repeat_count + delta, 1, 8)
	_update_program_ui()


func _reset_program() -> void:
	program_steps = 0
	program_used = false
	bridge_segments_open = 0
	puzzle_ready = false
	player_crossed_exit = false
	for index in range(target_nodes.size()):
		_set_target_active(index, false)
	trace_label.text = "世界目标已复位；通关状态没有被改写。"
	_update_program_ui()


func _run_program() -> void:
	if room_completed:
		return
	program_used = true
	program_steps = 0
	for index in range(target_nodes.size()):
		var active := index < repeat_count
		_set_target_active(index, active)
		if active:
			program_steps += 1
			trace_label.text = "运行轨迹：第 %d 步改变了世界目标 %d。" % [program_steps, index + 1]
			await get_tree().create_timer(0.08 if contract_test_mode else 0.18).timeout
	match location_id:
		"r1_safe_program":
			if repeat_count == 5 and _active_target_count() == 5:
				_finish_program_room("r1_safe_program", "五个安全阀门已依次恢复；实体宝箱已经出现。")
			else:
				_set_feedback("当前世界只恢复了 %d / 5 个阀门；继续调整 Repeat。" % _active_target_count(), true)
		"puzzle_bridge":
			if repeat_count == 4 and _active_target_count() == 4 and not target_active[4]:
				bridge_segments_open = 4
				puzzle_ready = true
				_close_program_panel()
				_set_feedback("四段星光桥已经显形，第五目标保持休眠。现在亲自走到房间上侧。")
			else:
				_set_feedback("谜题需要 5 → 4，且第五目标必须保持休眠。", true)
		"r4_transfer":
			if repeat_count == 6 and _active_target_count() == 6:
				_finish_program_room("r4_transfer", "六个陌生巡查目标全部恢复；迁移证据已写入。")
			else:
				_set_feedback("还有陌生目标没有恢复；继续观察并调整循环次数。", true)
	_update_program_ui()


func _finish_program_room(contract_id: String, message: String) -> void:
	var result := _submit_current_evidence(contract_id)
	if bool(result.get("ok", false)):
		room_completed = true
		_close_program_panel()
		stage.complete_noncombat_room(false)
		_set_feedback(message)
	else:
		_set_feedback("世界证据被拒绝：%s" % str(result.get("error", "UNKNOWN_CONTRACT_ERROR")), true)


func _check_puzzle_crossing() -> void:
	if stage.player_position().y > -74.0:
		return
	player_crossed_exit = true
	var result := _submit_current_evidence("puzzle_bridge")
	if bool(result.get("ok", false)):
		room_completed = true
		stage.complete_noncombat_room(false)
		_set_feedback("你亲自穿过了四段星光桥；反事实目标仍保持休眠，宝箱已经出现。")
	else:
		player_crossed_exit = false
		_set_feedback("跨越证据被拒绝：%s" % str(result.get("error", "UNKNOWN_CONTRACT_ERROR")), true)

func _on_player_shot(total_shots: int) -> void:
	if location_id == "boss_guardian" and boss_phase == BossPhase.COMBAT:
		boss_shots_fired = maxi(0, total_shots - boss_shot_baseline)
	_update_progress()


func _on_enemy_defeated(_total_defeated: int, _total_spawned: int) -> void:
	_update_progress()


func _on_stage_room_cleared() -> void:
	if location_id != "pulse_defense" or room_completed or combat_retry_pending:
		return
	var result := _submit_current_evidence("pulse_defense")
	if bool(result.get("ok", false)):
		room_completed = true
		stage.complete_noncombat_room(false)
		_set_feedback("bug 军团已被清除，木门打开，战利品宝箱已经落在房间中央。")
		return
	combat_retry_pending = true
	_set_feedback("清场了，但世界证据不完整（%s）。房间会补充一波，让你完成移动、脉冲和射击。" % str(result.get("error", "EVIDENCE_INCOMPLETE")), true)
	call_deferred("_retry_combat_wave")


func _retry_combat_wave() -> void:
	await get_tree().create_timer(0.55 if contract_test_mode else 1.2).timeout
	if room_completed:
		combat_retry_pending = false
		return
	await stage.spawn_wave(3, 2.0)
	combat_retry_pending = false


func _on_chest_opened() -> void:
	_set_feedback("奖励已从实体宝箱中领取；星光传送门现在显形。")


func _on_portal_entered() -> void:
	if not room_completed or transition_lock:
		push_error("PORTAL_ENTERED_BEFORE_CONTRACT [%s]" % location_id)
		_set_feedback("传送门拒绝了未完成的世界证据。", true)
		return
	_go_to_next_scene()


func _on_player_defeated() -> void:
	transition_lock = true
	program_panel.hide()
	boss_debug_panel.hide()
	failure_panel.show()
	_set_feedback("本次尝试没有写入完成状态。")


func _start_or_restore_boss() -> void:
	boss = stage.spawn_boss(6.0)
	_connect_boss(boss)
	if bool(LoopRunState.room_flags.get("boss_debug", false)):
		_start_boss_combat()
	elif bool(LoopRunState.room_flags.get("boss_observe", false)):
		boss_phase = BossPhase.DEBUG
		boss.can_move = false
		stage.combat_active = false
		console_node.show()
		_set_feedback("观察证据已保存。走到右侧安全 Debug 台，运行错乱程序并修改条件。")
	else:
		boss_phase = BossPhase.OBSERVE
		boss.can_move = false
		stage.combat_active = true
		last_boss_distance = stage.player_distance
		boss_beat_timer = 0.7
		_set_feedback("保持移动，观察四拍并躲开真实弹幕；此阶段攻击会被 bug 迷雾挡回。")
	_update_boss_visuals()


func _connect_boss(enemy: Enemy) -> void:
	if not is_instance_valid(enemy):
		push_error("BOSS_INSTANCE_MISSING")
		return
	enemy.health_component.on_unit_damaged.connect(_on_boss_damaged)
	enemy.health_component.on_unit_dead.connect(_on_boss_dead)


func _boss_observation_beat() -> void:
	if boss_phase != BossPhase.OBSERVE or not is_instance_valid(boss):
		return
	boss_observed_beats += 1
	var moved_this_beat := stage.player_distance - last_boss_distance
	if moved_this_beat >= 8.0 or stage.player_position().distance_to(boss.global_position) >= 90.0:
		dodged_hazards += 1
	last_boss_distance = stage.player_distance
	_spawn_boss_pattern()
	if boss_observed_beats < 4:
		_set_feedback("第 %d 拍：%s。继续移动观察。" % [boss_observed_beats, "弱点闪现" if boss_observed_beats % 2 == 0 else "护盾闭合"])
		return
	var result := _submit_current_evidence("boss_observe")
	if bool(result.get("ok", false)):
		boss_phase = BossPhase.DEBUG
		boss.can_move = false
		stage.combat_active = false
		console_node.show()
		_clear_enemy_bullets()
		_set_feedback("四拍规律已记录。现在走到右侧安全 Debug 台，不会直接伤害伙伴。")
	else:
		_set_feedback("观察还不完整（%s）；继续移动并躲过下一拍。" % str(result.get("error", "OBSERVE_EVIDENCE_INCOMPLETE")), true)
	_update_boss_visuals()


func _spawn_boss_pattern() -> void:
	if not is_instance_valid(boss):
		return
	boss_pattern_index += 1
	var angles: Array[float] = []
	if boss_pattern_index % 2 == 1:
		for index in range(8):
			angles.append(float(index) * TAU / 8.0)
	else:
		var aim := boss.global_position.angle_to_point(stage.player_position())
		for offset in [-0.34, -0.17, 0.0, 0.17, 0.34]:
			angles.append(aim + float(offset))
	for angle in angles:
		var bullet := ENEMY_WEAPON.bullte_scene.instantiate() as Bullet
		if bullet == null:
			push_error("BOSS_PATTERN_BULLET_INVALID")
			continue
		get_tree().root.add_child(bullet)
		bullet.setup(ENEMY_WEAPON)
		bullet.global_position = boss.global_position
		bullet.global_rotation = angle


func _clear_enemy_bullets() -> void:
	for node in get_tree().root.get_children():
		if node is Bullet and (node as Bullet).weapon_resource == ENEMY_WEAPON:
			node.queue_free()


func _on_boss_damaged(_amount: float) -> void:
	if not is_instance_valid(boss):
		return
	if boss_phase != BossPhase.COMBAT:
		boss.health_component.current_health = boss.health_component.max_health
		boss_hp = 6
		_set_feedback("bug 迷雾挡回了攻击；先完成观察和安全 Debug。", true)
		_update_boss_visuals()
		return
	boss_hits_landed += 1
	boss_hp = maxi(0, int(ceil(boss.health_component.current_health)))
	_update_boss_visuals()


func _open_boss_debug_panel() -> void:
	if boss_phase != BossPhase.DEBUG:
		return
	boss_debug_panel.show()
	stage.set_player_input(false)
	_update_boss_debug_ui()


func _close_boss_debug_panel() -> void:
	boss_debug_panel.hide()
	stage.set_player_input(true)


func _run_boss_debug_trace() -> void:
	if boss_phase != BossPhase.DEBUG:
		return
	if not boss_defect_run:
		boss_defect_run = true
		boss_blocked_hits = 0
		for _step in range(4):
			await get_tree().create_timer(0.05 if contract_test_mode else 0.16).timeout
			if _step % 2 == 0:
				boss_blocked_hits += 1
		_set_feedback("错乱程序撞上护盾 %d 次。它没有直接完成净化。" % boss_blocked_hits)
	elif boss_condition_fixed:
		boss_safe_hits = 0
		for _step in range(4):
			await get_tree().create_timer(0.05 if contract_test_mode else 0.16).timeout
			if _step % 2 == 1:
				boss_safe_hits += 1
		boss_debug_success = boss_safe_hits == 2 and boss_blocked_hits >= 2
		var result := _submit_current_evidence("boss_debug")
		if bool(result.get("ok", false)):
			_close_boss_debug_panel()
			_start_boss_combat()
			_set_feedback("Debug 成功：攻击只在弱点显形时执行。现在用真实射击完成净化。")
		else:
			boss_debug_success = false
			_set_feedback("Debug 证据被拒绝：%s" % str(result.get("error", "UNKNOWN_CONTRACT_ERROR")), true)
	_update_boss_debug_ui()


func _toggle_boss_condition() -> void:
	if not boss_defect_run:
		_set_feedback("先运行一次错乱程序，观察失败轨迹。", true)
		return
	boss_condition_fixed = true
	_set_feedback("条件已经改为：仅在弱点显形时攻击。现在重新运行。")
	_update_boss_debug_ui()


func _start_boss_combat() -> void:
	if not is_instance_valid(boss):
		boss = stage.spawn_boss(6.0)
		_connect_boss(boss)
	boss_phase = BossPhase.COMBAT
	boss.can_move = true
	boss.health_component.init_health(6.0)
	boss_hp = 6
	boss_hits_landed = 0
	boss_shot_baseline = stage.shots_fired
	boss_shots_fired = 0
	stage.combat_active = true
	stage.seal_room()
	console_node.hide()
	boss_beat_timer = 0.8
	_update_boss_visuals()


func _on_boss_dead() -> void:
	if boss_phase != BossPhase.COMBAT:
		return
	boss_hp = 0
	boss_shots_fired = maxi(boss_shots_fired, stage.shots_fired - boss_shot_baseline)
	var result := _submit_current_evidence("boss_combat")
	if bool(result.get("ok", false)):
		boss_phase = BossPhase.COMPLETE
		room_completed = true
		stage.complete_noncombat_room(false)
		_clear_enemy_bullets()
		_set_feedback("迷糊小伙伴抖掉了 bug 迷雾，恢复清醒；循环魔法碎片就在实体宝箱里。")
	else:
		_set_feedback("净化证据被拒绝（%s）；Boss 战将显式重开。" % str(result.get("error", "BOSS_EVIDENCE_INCOMPLETE")), true)
		call_deferred("_retry_boss_combat")
	_update_boss_visuals()


func _retry_boss_combat() -> void:
	await get_tree().create_timer(0.45 if contract_test_mode else 1.0).timeout
	if room_completed:
		return
	boss = stage.spawn_boss(6.0)
	_connect_boss(boss)
	_start_boss_combat()


func _update_boss_visuals() -> void:
	if not boss_bar:
		return
	boss_bar.value = float(boss_hp)
	match boss_phase:
		BossPhase.OBSERVE:
			boss_bar_label.text = "迷糊小伙伴 · 观察 bug 节拍"
			if is_instance_valid(boss):
				boss.modulate = Color("#9f91b9")
		BossPhase.DEBUG:
			boss_bar_label.text = "迷糊小伙伴 · 安全 Debug"
			if is_instance_valid(boss):
				boss.modulate = Color("#bcaed0")
		BossPhase.COMBAT:
			boss_bar_label.text = "迷糊小伙伴 · 净化 %d / 6" % boss_hp
			if is_instance_valid(boss):
				boss.modulate = Color("#d2c5e7")
		BossPhase.COMPLETE:
			boss_bar_label.text = "迷糊小伙伴 · 已恢复清醒"
			boss_bar.value = 0.0

func collect_completion_evidence() -> Dictionary:
	match location_id:
		"r0_observe":
			return {
				"movement_distance": stage.player_distance,
				"action_runs": action_runs,
				"changed_targets": _active_target_count(),
				"total_targets": target_active.size(),
			}
		"r1_safe_program":
			return {
				"repeat_count": repeat_count,
				"completed_targets": _active_target_count(),
				"total_targets": 5,
				"trace_steps": program_steps,
				"used_run_or_step": program_used,
			}
		"puzzle_bridge":
			return {
				"from_count": 5,
				"to_count": repeat_count,
				"bridge_segments_open": bridge_segments_open,
				"counterfactual_last_dormant": target_active.size() == 5 and not target_active[4],
				"player_crossed_exit": player_crossed_exit,
			}
		"pulse_defense":
			return {
				"enemies_spawned": stage.enemies_spawned,
				"enemies_defeated": stage.enemies_defeated,
				"shots_fired": stage.shots_fired,
				"pulse_uses": stage.pulse_uses,
				"player_moved": stage.player_distance >= 40.0,
			}
		"r4_transfer":
			return {
				"repeat_count": repeat_count,
				"completed_targets": _active_target_count(),
				"total_targets": 6,
				"trace_steps": program_steps,
			}
		"boss_guardian":
			match active_contract_id:
				"boss_observe":
					return {
						"observed_beats": boss_observed_beats,
						"player_moved": stage.player_distance >= 40.0,
						"dodged_hazards": dodged_hazards,
					}
				"boss_debug":
					return {
						"defect_run": boss_defect_run,
						"blocked_hits": boss_blocked_hits,
						"condition_changed": boss_condition_fixed,
						"safe_hits": boss_safe_hits,
						"debug_success": boss_debug_success,
					}
				"boss_combat":
					return {
						"boss_max_hp": 6,
						"boss_hp": boss_hp,
						"hits_landed": boss_hits_landed,
						"shots_fired": boss_shots_fired,
						"debug_clear": bool(LoopRunState.room_flags.get("boss_debug", false)),
					}
	return {}


func _submit_current_evidence(contract_id: String) -> Dictionary:
	active_contract_id = contract_id
	var evidence := collect_completion_evidence()
	active_contract_id = ""
	if contract_test_mode:
		print("CONTRACT_EVIDENCE=", contract_id, " ", JSON.stringify(evidence))
	var result := submit_world_evidence(contract_id, evidence)
	if not bool(result.get("ok", false)):
		push_error("WORLD_EVIDENCE_REJECTED [%s]: %s" % [contract_id, str(result.get("error", "UNKNOWN"))])
	return result


func _update_progress() -> void:
	if not progress_label or not is_instance_valid(stage):
		return
	match location_id:
		"r0_observe":
			progress_label.text = "观察移动 %.0f / 40\n世界变化 %d / 5" % [stage.player_distance, _active_target_count()]
		"r1_safe_program":
			progress_label.text = "Repeat %d · 轨迹 %d\n阀门 %d / 5" % [repeat_count, program_steps, _active_target_count()]
		"puzzle_bridge":
			progress_label.text = "5 → %d · 桥段 %d / 4\n%s" % [repeat_count, bridge_segments_open, "已亲自穿过" if player_crossed_exit else "等待跨越"]
		"pulse_defense":
			progress_label.text = "bug %d / %d\n射击 %d · 脉冲 %d" % [stage.enemies_defeated, stage.enemies_spawned, stage.shots_fired, stage.pulse_uses]
		"r4_transfer":
			progress_label.text = "陌生目标 %d / 6\n轨迹 %d" % [_active_target_count(), program_steps]
		"boss_guardian":
			match boss_phase:
				BossPhase.OBSERVE:
					progress_label.text = "观察 %d / 4\n躲避 %d" % [boss_observed_beats, dodged_hazards]
				BossPhase.DEBUG:
					progress_label.text = "反弹 %d · 安全命中 %d\n条件 %s" % [boss_blocked_hits, boss_safe_hits, "已修正" if boss_condition_fixed else "待修正"]
				BossPhase.COMBAT:
					progress_label.text = "净化 HP %d / 6\n命中 %d · 射击 %d" % [boss_hp, boss_hits_landed, boss_shots_fired]
				BossPhase.COMPLETE:
					progress_label.text = "观察 ✓ · Debug ✓\n净化 ✓"
	if room_completed:
		progress_label.text += "\n出口已开放"
	_update_program_ui()


func _update_program_ui() -> void:
	if not repeat_label or not trace_label:
		return
	repeat_label.text = "Repeat(%d)" % repeat_count


func _update_boss_debug_ui() -> void:
	if not boss_debug_label:
		return
	if not boss_defect_run:
		boss_debug_label.text = "错乱程序：Repeat(4) { attack(); }\n先运行，观察哪些节拍撞上护盾。"
	else:
		boss_debug_label.text = "失败轨迹：第 1、3 拍被挡回。\n当前条件：%s" % ("仅弱点显形时攻击" if boss_condition_fixed else "每一拍都攻击")
	debug_run_button.visible = not boss_defect_run
	debug_condition_button.visible = boss_defect_run and not boss_condition_fixed
	debug_fixed_button.visible = boss_defect_run and boss_condition_fixed


func _set_target_active(index: int, active: bool) -> void:
	if index < 0 or index >= target_active.size():
		push_error("TARGET_INDEX_OUT_OF_RANGE [%s]: %d" % [location_id, index])
		return
	target_active[index] = active
	stage.set_target_active(target_nodes[index], active)


func _active_target_count() -> int:
	var count := 0
	for active in target_active:
		if active:
			count += 1
	return count


func _set_feedback(message: String, is_error: bool = false) -> void:
	if not feedback_label:
		return
	feedback_label.text = message
	feedback_label.add_theme_color_override("font_color", COLOR_CORAL if is_error else COLOR_TEXT)


func _initial_feedback() -> String:
	match location_id:
		"r0_observe":
			return "房门已经封闭。先走动观察，再靠近中央装置按 E。"
		"r1_safe_program":
			return "安全阀门停住了。走到中央装置旁按 E，程序必须真实改变五个阀门。"
		"puzzle_bridge":
			return "当前程序继承了 Repeat(5)。走到左侧装置，将它修正成四段桥。"
		"pulse_defense":
			return "木门会在 bug 军团出现时锁死；所有战斗证据来自真实移动、子弹与死亡事件。"
		"r4_transfer":
			return "六个陌生目标没有结构提示；走到中央装置独立迁移循环规律。"
		"boss_guardian":
			return "迷糊小伙伴被 bug 迷雾缠住；攻击不是第一步，先观察。"
	return ""


func _control_help() -> String:
	if location_id == "pulse_defense":
		return "WASD / 方向键移动 · 鼠标瞄准与左键射击 · Q 循环脉冲"
	if location_id == "boss_guardian":
		return "WASD / 方向键移动 · 鼠标瞄准与左键射击 · E 实体装置"
	return "WASD / 方向键移动 · E 实体装置 · 鼠标瞄准与左键射击"


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_nine_patch(rect: Rect2) -> NinePatchRect:
	var panel := NinePatchRect.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.texture = PANEL_TEXTURE
	panel.patch_margin_left = 18
	panel.patch_margin_top = 18
	panel.patch_margin_right = 18
	panel.patch_margin_bottom = 18
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return panel


func _make_source_button(text_value: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text_value
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	var normal := StyleBoxTexture.new()
	normal.texture = BUTTON_TEXTURE
	var hover := StyleBoxTexture.new()
	hover.texture = BUTTON_TEXTURE
	hover.modulate_color = Color("#b9ffeb")
	var pressed := StyleBoxTexture.new()
	pressed.texture = BUTTON_TEXTURE
	pressed.modulate_color = Color("#ffd782")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	return button


func _normalize_gate_result(value: Variant) -> Dictionary:
	if value is Dictionary:
		var result: Dictionary = value.duplicate(true)
		if not result.has("ok"):
			return {"ok": false, "error": "MALFORMED_GATE_RESULT"}
		return result
	if value is bool:
		return {"ok": value, "error": "" if value else "ROOM_GATE_BLOCKED"}
	return {"ok": false, "error": "INVALID_GATE_RESULT_TYPE"}


func _go_to_next_scene() -> void:
	if transition_lock or not room_completed:
		return
	transition_lock = true
	var next_path := LoopRunState.next_room_path(location_id)
	if next_path.is_empty():
		transition_lock = false
		_set_feedback("下一场景门禁未满足：%s" % LoopRunState.last_error, true)
		return
	var next_id := next_path.get_file().trim_suffix(".tscn")
	var result := navigate_to(next_id)
	if not bool(result.get("ok", false)):
		transition_lock = false
		_set_feedback("场景跳转失败：%s" % str(result.get("error", "UNKNOWN_NAVIGATION_ERROR")), true)


func _capture_and_quit() -> void:
	var capture_warmup := 0.75
	if location_id == "boss_guardian" and "combat" in capture_name.to_lower():
		# Exercise the real post-Debug combat transition and projectile pattern so
		# visual QA can compare an active boss state, not only the observe phase.
		boss_debug_success = true
		_start_boss_combat()
		_spawn_boss_pattern()
		_set_feedback("安全 Debug 已完成。现在通过真实射击和闪避完成净化。")
		capture_warmup = 0.14
	await get_tree().create_timer(capture_warmup).timeout
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() == "headless":
		push_error("Adventure room capture requires a rendering display")
		get_tree().quit(2)
		return
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("ADVENTURE_CAPTURE_EMPTY [%s]" % location_id)
		get_tree().quit(2)
		return
	var directory := ProjectSettings.globalize_path("res://qa/multi-scene")
	var mkdir_error := DirAccess.make_dir_recursive_absolute(directory)
	if mkdir_error != OK:
		push_error("ADVENTURE_CAPTURE_DIR_ERROR: %s" % mkdir_error)
		get_tree().quit(2)
		return
	var output := directory.path_join("adventure-%s.png" % _safe_capture_name(capture_name))
	var error := image.save_png(output)
	print("MULTI_SCENE_CAPTURE=", output, " ERROR=", error)
	# Active combat captures intentionally leave real bullets in flight. Release
	# those root-level source nodes before quitting so visual QA is log-clean.
	for node in get_tree().root.get_children():
		if node is Bullet or node is GPUParticles2D:
			node.queue_free()
	for _frame in range(2):
		await get_tree().process_frame
	get_tree().quit(0 if error == OK else 2)


func _safe_capture_name(raw_name: String) -> String:
	var safe_name := raw_name.strip_edges().get_file().trim_suffix(".png")
	for invalid_character in [":", "/", "\\", "?", "*", "\"", "<", ">", "|"]:
		safe_name = safe_name.replace(invalid_character, "_")
	return location_id if safe_name.is_empty() else safe_name

func _run_contract_test_and_quit() -> void:
	var ok := await run_contract_test()
	get_tree().quit(0 if ok else 2)


func run_contract_test() -> bool:
	var isolated_state = load("res://scenes/demo/loop_oasis/multi_scene/loop_run_state.gd").new()
	isolated_state.reset_for_test(false)
	var illegal_gate := _normalize_gate_result(isolated_state.can_enter(location_id))
	isolated_state.free()
	assert(not bool(illegal_gate.get("ok", false)), "非法直载必须被房间门禁拒绝")
	assert(not str(illegal_gate.get("error", "")).is_empty(), "门禁拒绝必须包含机器可读错误码")

	_prepare_contract_run()
	entry_gate_result = _normalize_gate_result(LoopRunState.can_enter(location_id))
	entry_allowed = bool(entry_gate_result.get("ok", false))
	assert(entry_allowed, "合同测试 fixture 未打开合法入口：%s" % location_id)
	room_completed = false
	_reset_contract_visuals()
	for contract_id in _contract_ids_for_room():
		var canonical := _canonical_flag(contract_id)
		assert(not bool(LoopRunState.room_flags.get(canonical, false)))
		var rejected: Dictionary = SceneContract.validate(contract_id, {})
		assert(not bool(rejected.get("ok", false)), "缺字段证据必须被拒绝：%s" % contract_id)
		assert(not str(rejected.get("error", "")).is_empty(), "拒绝结果必须带错误码：%s" % contract_id)
		assert(not bool(LoopRunState.room_flags.get(canonical, false)), "拒绝证据不得污染进度：%s" % canonical)

	match location_id:
		"r0_observe":
			stage.player_distance = 48.0
			_r0_single_action()
			assert(action_runs == 1 and _active_target_count() == 1)
			assert(bool(LoopRunState.room_flags.get("observe", false)))
		"r1_safe_program":
			repeat_count = 5
			_reset_program()
			await _run_program()
			assert(program_steps == 5 and _active_target_count() == 5)
			assert(bool(LoopRunState.room_flags.get("program", false)))
		"puzzle_bridge":
			repeat_count = 4
			_reset_program()
			await _run_program()
			assert(puzzle_ready and bridge_segments_open == 4 and not target_active[4])
			assert(not bool(LoopRunState.room_flags.get("puzzle", false)), "打开桥不能冒充实际跨越")
			stage.teleport_player(Vector2(0, -92))
			_check_puzzle_crossing()
			assert(player_crossed_exit and bool(LoopRunState.room_flags.get("puzzle", false)))
		"pulse_defense":
			stage.player_distance = 52.0
			stage.enemies_spawned = 3
			stage.enemies_defeated = 3
			stage.shots_fired = 3
			stage.pulse_uses = 1
			var combat_result := _submit_current_evidence("pulse_defense")
			assert(bool(combat_result.get("ok", false)))
			room_completed = true
			assert(bool(LoopRunState.room_flags.get("combat", false)))
		"r4_transfer":
			repeat_count = 6
			_reset_program()
			await _run_program()
			assert(program_steps == 6 and _active_target_count() == 6)
			assert(bool(LoopRunState.room_flags.get("transfer", false)))
		"boss_guardian":
			stage.player_distance = 64.0
			boss_observed_beats = 4
			dodged_hazards = 2
			var observe_result := _submit_current_evidence("boss_observe")
			assert(bool(observe_result.get("ok", false)))
			boss_phase = BossPhase.DEBUG
			boss_defect_run = true
			boss_blocked_hits = 2
			var bad_debug: Dictionary = SceneContract.validate("boss_debug", collect_completion_evidence_for("boss_debug"))
			assert(not bool(bad_debug.get("ok", false)), "只有失败轨迹不能直接完成 Debug")
			boss_condition_fixed = true
			boss_safe_hits = 2
			boss_debug_success = true
			var debug_result := _submit_current_evidence("boss_debug")
			assert(bool(debug_result.get("ok", false)))
			assert(not room_completed, "Debug 不能直接完成 Boss")
			boss_phase = BossPhase.COMBAT
			boss_hp = 0
			boss_hits_landed = 6
			boss_shots_fired = 6
			var boss_result := _submit_current_evidence("boss_combat")
			assert(bool(boss_result.get("ok", false)))
			room_completed = true
			assert(bool(LoopRunState.room_flags.get("boss_combat", false)))

	print("ADVENTURE_ROOM_CONTRACT_OK=", location_id)
	return true


func collect_completion_evidence_for(contract_id: String) -> Dictionary:
	active_contract_id = contract_id
	var evidence := collect_completion_evidence()
	active_contract_id = ""
	return evidence


func _reset_contract_visuals() -> void:
	action_runs = 0
	program_steps = 0
	program_used = false
	bridge_segments_open = 0
	puzzle_ready = false
	player_crossed_exit = false
	for index in range(target_nodes.size()):
		_set_target_active(index, false)
	stage.player_distance = 0.0
	stage.shots_fired = 0
	stage.enemies_spawned = 0
	stage.enemies_defeated = 0
	stage.pulse_uses = 0
	boss_observed_beats = 0
	dodged_hazards = 0
	boss_defect_run = false
	boss_condition_fixed = false
	boss_blocked_hits = 0
	boss_safe_hits = 0
	boss_debug_success = false
	boss_hp = 6
	boss_hits_landed = 0
	boss_shots_fired = 0


func _prepare_contract_run() -> void:
	LoopRunState.reset_for_test(false)
	LoopRunState.tool_claimed = true
	LoopRunState.training_target_hit = true
	var route := "combat_first" if location_id == "pulse_defense" else "puzzle_first"
	assert(LoopRunState.begin_adventure(route))
	var prerequisites: Array[String] = []
	match location_id:
		"r1_safe_program":
			prerequisites = ["r0_observe"]
		"puzzle_bridge":
			prerequisites = ["r0_observe", "r1_safe_program"]
		"pulse_defense":
			prerequisites = ["r0_observe", "r1_safe_program"]
		"r4_transfer":
			prerequisites = ["r0_observe", "r1_safe_program", "puzzle_bridge", "pulse_defense"]
		"boss_guardian":
			prerequisites = ["r0_observe", "r1_safe_program", "puzzle_bridge", "pulse_defense", "r4_transfer"]
	for contract_id in prerequisites:
		var result := submit_world_evidence(contract_id, _valid_fixture_evidence(contract_id))
		assert(bool(result.get("ok", false)), "前置合同 fixture 被拒绝：%s" % contract_id)


func _valid_fixture_evidence(contract_id: String) -> Dictionary:
	match contract_id:
		"r0_observe":
			return {"movement_distance": 48.0, "action_runs": 1, "changed_targets": 1, "total_targets": 5}
		"r1_safe_program":
			return {"repeat_count": 5, "completed_targets": 5, "total_targets": 5, "trace_steps": 5, "used_run_or_step": true}
		"puzzle_bridge":
			return {"from_count": 5, "to_count": 4, "bridge_segments_open": 4, "counterfactual_last_dormant": true, "player_crossed_exit": true}
		"pulse_defense":
			return {"enemies_spawned": 3, "enemies_defeated": 3, "shots_fired": 3, "pulse_uses": 1, "player_moved": true}
		"r4_transfer":
			return {"repeat_count": 6, "completed_targets": 6, "total_targets": 6, "trace_steps": 6}
	return {}


func _contract_ids_for_room() -> Array[String]:
	if location_id == "boss_guardian":
		return ["boss_observe", "boss_debug", "boss_combat"]
	return [location_id]


func _canonical_flag(contract_id: String) -> String:
	var mapping := {
		"r0_observe": "observe",
		"r1_safe_program": "program",
		"puzzle_bridge": "puzzle",
		"pulse_defense": "combat",
		"r4_transfer": "transfer",
		"boss_observe": "boss_observe",
		"boss_debug": "boss_debug",
		"boss_combat": "boss_combat",
	}
	return str(mapping.get(contract_id, contract_id))
