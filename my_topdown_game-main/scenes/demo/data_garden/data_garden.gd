extends Node2D

## 数据花园：核桃编程 8–12 分钟纵向切片。
## 目标不是复刻一张静态概念图，而是把“循环改变世界”的因果做成可玩的课堂体验。

enum Stage {
	ARRIVAL,
	OBSERVE,
	PROGRAM,
	COMBAT,
	TRANSFER,
	CONCEPT,
	BOSS,
	COMPLETE,
}

enum LearningPhase {
	WORLD_OBSERVE,
	PREDICT,
	SINGLE_ACTION,
	BUILD_BLOCKS,
	COUNTERFACTUAL,
	TRANSFER,
	CONCEPT_REVEAL,
}

const VIEW_SIZE := Vector2(1280.0, 720.0)
const PLAYER_SPEED := 245.0
const PLAYER_START := Vector2(640.0, 612.0)
const MAIN_CONSOLE := Vector2(640.0, 430.0)
const TRANSFER_CONSOLE := Vector2(1000.0, 258.0)
const OPTIONAL_CONSOLE := Vector2(292.0, 304.0)
const SAVE_PATH := "user://data_garden_progress_v2.json"
const CONTENT_MANIFEST_PATH := "res://content/generated/UNIT-DATA-GARDEN-LOOP.json"
const MAIN_CONTENT_SKIN := "garden_light_seeds"
const TRANSFER_CONTENT_SKIN := "garden_inspection"
const DEFAULT_MAIN_LOOP_TARGET := 4
const DEFAULT_TRANSFER_LOOP_TARGET := 4
const PLAYER_MAX_ENERGY := 5.0
const BOSS_COMBAT_MAX_HEALTH := 6
const XIAO_HETAO_AI_DEFAULT_ENDPOINT := "http://127.0.0.1:8787/api/xiao-hetao/hint"
const LEARNING_EVENT_DEFAULT_ENDPOINT := "http://127.0.0.1:8787/api/learning-events"
const REVIEW_ASSIGNMENT_DEFAULT_ENDPOINT := "http://127.0.0.1:8787/api/review-assignment"
const XIAO_HETAO_AI_TIMEOUT_SECONDS := 8.0

const COLOR_ABYSS := Color("#080918")
const COLOR_VOID := Color("#11122b")
const COLOR_PURPLE := Color("#4b3974")
const COLOR_PURPLE_DARK := Color("#2a2348")
const COLOR_MINT := Color("#69d6ad")
const COLOR_MINT_DARK := Color("#347d70")
const COLOR_CORAL := Color("#f1846c")
const COLOR_GOLD := Color("#ffc75a")
const COLOR_CYAN := Color("#55e6e0")
const COLOR_INK := Color("#17172d")
const COLOR_PANEL := Color("#211f3d")
const COLOR_TEXT := Color("#fff8e8")
const COLOR_MUTED := Color("#bbb7d8")

var stage: Stage = Stage.ARRIVAL
var program_mode := "main"
var repeat_count := 2
var main_loop_target := DEFAULT_MAIN_LOOP_TARGET
var transfer_loop_target := DEFAULT_TRANSFER_LOOP_TARGET
var main_attempts := 0
var main_run_attempts := 0
var hint_requests := 0
var transfer_attempts := 0
var restore_progress := 0.0
var beacon_lit: Array[bool] = []
var movement_seen := false
var weapon_unlocked := false
var companion_aid_available := false
var companion_aid_used := false
var returning_player := false
var test_mode := false
var ai_test_mode := false
var capture_mode := false
var capture_flow_mode := false
var program_step := 0
var learning_phase: LearningPhase = LearningPhase.WORLD_OBSERVE
var observation_done := false
var action_selected := false
var prediction_choice := -1
var prediction_done := false
var single_action_tried := false
var main_pattern_verified := false
var counterfactual_done := false
var concept_revealed := false
var needs_review := false
var puzzle_clear := false
var combat_clear := false
var boss_debug_clear := false
var boss_combat_clear := false
var regular_enemies_defeated := 0
var boss_hits_landed := 0
var last_program_change := "尚未修改程序"
var active_trace_index := -1
var action_dragging := false
var companion_message_deadline := 0
var transfer_checked := 0
var optional_puzzle_completed := false
var optional_puzzle_attempts := 0
var scan_pulse := 0.0
var overflow_pulse := 0.0
var restoration_active := false
var transition_lock := false
var xiao_hetao_request: HTTPRequest
var review_assignment_request: HTTPRequest
var xiao_hetao_ai_endpoint := XIAO_HETAO_AI_DEFAULT_ENDPOINT
var xiao_hetao_request_in_flight := false
var xiao_hetao_fallback_message := ""
var xiao_hetao_student_id := ""
var ai_server_responses := 0
var ai_deepseek_responses := 0
var ai_fallback_responses := 0
var content_runtime: LearningContentRuntime
var learning_event_logger: LearningEventLogger
var content_metadata: Dictionary = {}
var content_engine_ready := false
var last_execution_result: Dictionary = {}
var last_diagnosis_id := "NOT_RUN"
var main_content_skin_id := MAIN_CONTENT_SKIN
var transfer_content_skin_id := TRANSFER_CONTENT_SKIN
var main_world_name := "数据花园"
var main_entity_name := "光种"
var main_action_name := "生长"
var main_console_name := "休眠光种控制台"
var main_objective := ""
var transfer_world_name := "陌生巡检站"
var transfer_entity_name := "巡检目标"
var transfer_action_name := "巡检"
var transfer_console_name := "巡检控制台"
var transfer_objective := ""
var transfer_scenario_frame := "把同一结构迁移到陌生装置"
var active_variant: Dictionary = {}
var active_variant_id := ""

var player_position := PLAYER_START
var player_health := 5
var player_energy := PLAYER_MAX_ENERGY
var touch_cooldown := 0.0
var shot_cooldown := 0.0
var companion_time := 0.0
var idle_time := 0.0
var player_invulnerability := 0.0
var player_hit_flash := 0.0
var energy_regen_timer := 0.0
var player_move_strength := 0.0

var enemies: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var world_motes: Array[Dictionary] = []
var hit_sparks: Array[Dictionary] = []
var enemy_texture: Texture2D
var background_sprite: Sprite2D
var restored_background_sprite: Sprite2D
var player_sprite: Sprite2D
var companion_sprite: Sprite2D
var console_sprite: Sprite2D
var optional_memory_sprite: Sprite2D
var portal_sprite: Sprite2D
var boss_guardian_sprite: Sprite2D
var beacon_sprites: Array[Sprite2D] = []
var beacon_base_scales: Array[Vector2] = []

var ui_layer: CanvasLayer
var ui_root: Control
var status_panel: PanelContainer
var objective_panel: PanelContainer
var mini_map_panel: PanelContainer
var mini_content: Control
var mini_player_dot: ColorRect
var mini_objective_dot: ColorRect
var objective_label: Label
var progress_label: Label
var content_version_label: Label
var audio_toggle_button: Button
var tutorial_panel: PanelContainer
var tutorial_label: Label
var interaction_label: Label
var companion_panel: PanelContainer
var companion_label: Label
var companion_level_label: Label
var hint_dots: Array[ColorRect] = []
var code_panel: Control
var program_device_panel: Panel
var code_title: Label
var code_layer_label: Label
var trace_label: Label
var c_code_label: Label
var observe_button: Button
var repeat_button: Button
var action_button: Button
var run_button: Button
var command_info_label: Label
var prediction_buttons: Array[Button] = []
var drag_ghost: Label
var hint_button: Button
var health_bar: ProgressBar
var energy_bar: ProgressBar
var weapon_badge: PanelContainer
var boss_panel: PanelContainer
var boss_title: Label
var boss_question_label: Label
var boss_feedback_label: Label
var boss_health_bar: ProgressBar
var boss_option_buttons: Array[Button] = []
var aid_button: Button
var summary_panel: PanelContainer
var summary_body: Label
var optional_panel: PanelContainer
var optional_feedback_label: Label
var optional_option_buttons: Array[Button] = []
var stage_banner: PanelContainer
var stage_banner_label: Label
var flash_overlay: ColorRect

var boss_round := 0
var boss_attempts := 0
var boss_total_errors := 0
var boss_health := 2
var boss_debug_observed := false
var boss_condition_weak_only := false
var boss_debug_phase := -1
var boss_weak_open := false
var boss_blocked_hits := 0
var boss_combat_active := false

var beacon_positions := PackedVector2Array()


func _ready() -> void:
	# 本 Demo 使用系统鼠标，避免空的全局自定义光标把指针隐藏。
	Cursor.sprite.texture = null
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var user_args := OS.get_cmdline_user_args()
	ai_test_mode = "--demo-ai-test" in user_args
	test_mode = "--demo-test" in user_args or ai_test_mode
	capture_flow_mode = "--demo-capture-flow" in user_args
	capture_mode = "--demo-capture" in user_args or capture_flow_mode
	RenderingServer.set_default_clear_color(COLOR_ABYSS)
	_load_memory()
	_ensure_xiao_hetao_student_id()
	_setup_content_engine()
	_build_world_nodes()
	_build_ui()
	_setup_xiao_hetao_ai()
	if returning_player:
		_set_restored_alpha(0.18)
	_set_stage(Stage.ARRIVAL)
	queue_redraw()
	if not test_mode and not capture_mode:
		MusicPlayer.play(load("res://assets/sounds/Bg Music.mp3"), true)
	if ai_test_mode:
		call_deferred("_run_ai_integration_test")
	elif test_mode:
		call_deferred("_run_smoke_test")
	elif capture_flow_mode:
		call_deferred("_capture_flow_states")
	elif capture_mode:
		call_deferred("_capture_reference_state")


func _setup_content_engine() -> void:
	content_runtime = LearningContentRuntime.new()
	var manifest_path := OS.get_environment("XIAO_HETAO_CONTENT_MANIFEST").strip_edges()
	if manifest_path.is_empty():
		manifest_path = CONTENT_MANIFEST_PATH
	var loaded := content_runtime.load_manifest(manifest_path)
	content_engine_ready = bool(loaded.get("ok", false))
	if not content_engine_ready:
		push_error("CONTENT_ENGINE_LOAD_FAILED: %s" % str(loaded.get("error", "unknown")))
		return
	content_metadata = content_runtime.metadata()
	main_content_skin_id = content_runtime.get_main_skin_id(MAIN_CONTENT_SKIN)
	transfer_content_skin_id = content_runtime.get_transfer_skin_id(TRANSFER_CONTENT_SKIN)
	var main_display := content_runtime.get_skin_display(main_content_skin_id, {})
	main_world_name = str(main_display.get("world_name", main_world_name))
	main_entity_name = str(main_display.get("entity_name", main_entity_name))
	main_action_name = str(main_display.get("action_name", main_action_name))
	main_console_name = str(main_display.get("console_name", main_console_name))
	main_objective = str(main_display.get("objective", ""))
	var transfer_display := content_runtime.get_skin_display(transfer_content_skin_id, {})
	transfer_world_name = str(transfer_display.get("world_name", transfer_world_name))
	transfer_entity_name = str(transfer_display.get("entity_name", transfer_entity_name))
	transfer_action_name = str(transfer_display.get("action_name", transfer_action_name))
	transfer_console_name = str(transfer_display.get("console_name", transfer_console_name))
	transfer_objective = str(transfer_display.get("objective", ""))
	transfer_scenario_frame = str(transfer_display.get("scenario_frame", transfer_scenario_frame))
	main_loop_target = content_runtime.get_skin_target_count(main_content_skin_id, DEFAULT_MAIN_LOOP_TARGET)
	transfer_loop_target = content_runtime.get_skin_target_count(transfer_content_skin_id, DEFAULT_TRANSFER_LOOP_TARGET)
	active_variant_id = OS.get_environment("XIAO_HETAO_VARIANT_ID").strip_edges()
	active_variant = content_runtime.get_transfer_variant(active_variant_id)
	if not active_variant.is_empty():
		var variant_skin: Dictionary = active_variant.get("skin", {})
		transfer_loop_target = int(active_variant.get("params", {}).get("target_count", transfer_loop_target))
		transfer_entity_name = str(variant_skin.get("entity_name", variant_skin.get("entity_type", transfer_entity_name)))
		transfer_action_name = str(variant_skin.get("action_name", transfer_action_name))
		transfer_objective = str(variant_skin.get("objective", transfer_objective))
		transfer_scenario_frame = str(variant_skin.get("scenario_frame", transfer_scenario_frame))
	_configure_content_targets()
	learning_event_logger = LearningEventLogger.new()
	var event_endpoint := OS.get_environment("XIAO_HETAO_EVENT_ENDPOINT").strip_edges()
	if event_endpoint.is_empty():
		event_endpoint = LEARNING_EVENT_DEFAULT_ENDPOINT
	learning_event_logger.setup(
		content_metadata,
		xiao_hetao_student_id,
		ai_test_mode or (not test_mode and not capture_mode),
		self,
		event_endpoint
	)
	var experiment_variant := OS.get_environment("WALNUT_EXPERIMENT_VARIANT").strip_edges()
	if experiment_variant not in ["A", "B", "基线"]:
		experiment_variant = "基线"
	_log_learning_event("session_started", "arrival", {
		"age_band": "8-12",
		"main_skin": main_content_skin_id,
		"transfer_skin": transfer_content_skin_id,
		"variant_id": active_variant_id,
		"experiment_variant": experiment_variant,
		"data_source": "自动化QA" if ai_test_mode else "自动事件聚合",
	})


func _configure_content_targets() -> void:
	beacon_lit.clear()
	beacon_lit.resize(main_loop_target)
	beacon_lit.fill(false)
	beacon_positions.clear()
	if main_loop_target == 4:
		beacon_positions = PackedVector2Array([
			Vector2(435.0, 330.0),
			Vector2(845.0, 330.0),
			Vector2(845.0, 535.0),
			Vector2(435.0, 535.0),
		])
		return
	var center := Vector2(640.0, 425.0)
	for i in range(main_loop_target):
		var angle := -PI * 0.5 + TAU * float(i) / float(main_loop_target)
		beacon_positions.append(center + Vector2(cos(angle) * 235.0, sin(angle) * 155.0))


func _transfer_target_position(index: int) -> Vector2:
	var spacing := minf(48.0, 216.0 / maxf(1.0, float(transfer_loop_target - 1)))
	var start_x := -spacing * float(transfer_loop_target - 1) * 0.5
	return TRANSFER_CONSOLE + Vector2(start_x + float(index) * spacing, 78.0)


func _log_learning_event(event_name: String, stage_name: String, payload: Dictionary = {}) -> void:
	if learning_event_logger:
		learning_event_logger.log_event(event_name, stage_name, payload)


func _content_program_for(skin_id: String, count: int, node_prefix: String) -> Dictionary:
	var fallback_action := "inspect_next_target" if skin_id == transfer_content_skin_id else "grow_next_seed"
	var action_id := content_runtime.get_skin_action_id(skin_id, fallback_action)
	return content_runtime.make_repeat_program(action_id, count, node_prefix)


func _combat_controls_active() -> bool:
	return stage == Stage.COMBAT or (stage == Stage.BOSS and boss_combat_active)


func _process(delta: float) -> void:
	companion_time += delta
	touch_cooldown = maxf(0.0, touch_cooldown - delta)
	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	player_invulnerability = maxf(0.0, player_invulnerability - delta)
	player_hit_flash = maxf(0.0, player_hit_flash - delta)
	scan_pulse = maxf(0.0, scan_pulse - delta)
	overflow_pulse = maxf(0.0, overflow_pulse - delta)
	_update_vfx(delta)
	_update_energy(delta)
	_update_world_animation(delta)

	_update_player(delta)
	_update_companion(delta)
	_update_combat(delta)
	_update_interaction_prompt()
	_update_minimap()
	if companion_panel and companion_panel.visible and companion_message_deadline > 0 \
			and Time.get_ticks_msec() >= companion_message_deadline and not xiao_hetao_request_in_flight:
		companion_panel.hide()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not action_dragging:
		return
	if event is InputEventMouseMotion:
		drag_ghost.position = event.position + Vector2(14, 12)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var dropped_into_repeat := repeat_button.visible and repeat_button.get_global_rect().grow(16.0).has_point(event.position)
		action_dragging = false
		drag_ghost.hide()
		if dropped_into_repeat:
			_select_action()
		else:
			_set_companion_message("把“%s”拖进橙色的重复结构里。" % (transfer_action_name if program_mode == "transfer" else main_action_name))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_M:
			audio_toggle_button.button_pressed = not audio_toggle_button.button_pressed
			return
		if optional_panel.visible:
			if event.physical_keycode == KEY_ESCAPE:
				_close_optional_puzzle()
			return
		if stage == Stage.ARRIVAL and event.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			movement_seen = true
			_set_stage(Stage.OBSERVE)
		if event.physical_keycode in [KEY_E, KEY_ENTER]:
			if stage == Stage.PROGRAM:
				_run_program()
			else:
				_try_interact()
		elif stage == Stage.PROGRAM and event.physical_keycode in [KEY_1, KEY_O]:
			_observe_targets()
		elif stage == Stage.PROGRAM and event.physical_keycode in [KEY_2, KEY_G]:
			_select_action()
		elif stage == Stage.PROGRAM and event.physical_keycode in [KEY_3, KEY_RIGHT, KEY_UP]:
			_cycle_repeat_count()
		elif event.physical_keycode == KEY_H:
			_request_hint()
		elif event.physical_keycode == KEY_SPACE and _combat_controls_active():
			_shoot_at(_nearest_enemy_position())
		elif event.physical_keycode == KEY_R and stage == Stage.COMPLETE:
			get_tree().reload_current_scene()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and _combat_controls_active():
			_shoot_at(event.position)


func _draw() -> void:
	_draw_actor_shadows()
	_draw_loop_path()
	_draw_transfer_area()
	_draw_boss_debug_state()
	_draw_projectiles()
	_draw_combat_overlays()
	_draw_feedback_fx()


func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), COLOR_ABYSS)
	for i in range(26):
		var x := float((i * 193) % 1280)
		var y := float((i * 89 + 37) % 620)
		var glow := COLOR_CYAN if i % 3 == 0 else COLOR_PURPLE
		draw_circle(Vector2(x, y), 2.0 + float(i % 3), Color(glow, 0.22))

	# 数据深渊中的断裂方块，提供轻微纵深但不抢交互焦点。
	for i in range(14):
		var block_pos := Vector2(float((i * 107 + 31) % 1240), float((i * 151 + 80) % 650))
		draw_rect(Rect2(block_pos, Vector2(12.0, 12.0)), Color(COLOR_PURPLE, 0.16), false, 2.0)


func _draw_island() -> void:
	var left_color := COLOR_PURPLE.lerp(COLOR_MINT_DARK, restore_progress * 0.88)
	var left_highlight := COLOR_PURPLE_DARK.lerp(COLOR_MINT, restore_progress * 0.72)

	var island := PackedVector2Array([
		Vector2(150, 164), Vector2(262, 105), Vector2(468, 82), Vector2(640, 106),
		Vector2(826, 84), Vector2(1040, 132), Vector2(1128, 238), Vector2(1092, 456),
		Vector2(980, 562), Vector2(764, 595), Vector2(640, 566), Vector2(516, 595),
		Vector2(304, 562), Vector2(174, 454),
	])
	draw_colored_polygon(island, COLOR_VOID)
	draw_polyline(island + PackedVector2Array([island[0]]), Color("#7769a7"), 6.0, true)

	var left_half := PackedVector2Array([
		Vector2(166, 180), Vector2(270, 124), Vector2(472, 101), Vector2(640, 122),
		Vector2(640, 548), Vector2(512, 576), Vector2(310, 544), Vector2(192, 444),
	])
	var right_half := PackedVector2Array([
		Vector2(640, 122), Vector2(820, 103), Vector2(1028, 149), Vector2(1110, 245),
		Vector2(1072, 443), Vector2(968, 542), Vector2(765, 576), Vector2(640, 548),
	])
	draw_colored_polygon(left_half, left_color)
	draw_colored_polygon(right_half, COLOR_MINT_DARK)

	# 柔和的地表斑块让左右“修复前 / 修复后”形成可读对比。
	for i in range(18):
		var p := Vector2(235.0 + float((i * 83) % 760), 180.0 + float((i * 47) % 320))
		var c := left_highlight if p.x < 640.0 else COLOR_MINT
		draw_circle(p, 8.0 + float(i % 5), Color(c, 0.34))

	# 初极狭的入口石桥。
	draw_rect(Rect2(588, 548, 104, 172), COLOR_PURPLE_DARK)
	draw_line(Vector2(588, 548), Vector2(588, 720), Color("#7a6ca5"), 5.0)
	draw_line(Vector2(692, 548), Vector2(692, 720), Color("#7a6ca5"), 5.0)
	for y in range(560, 720, 34):
		draw_rect(Rect2(596, y, 88, 22), Color("#5b527d"))


func _draw_loop_path() -> void:
	if beacon_positions.is_empty():
		return
	var loop_points := beacon_positions.duplicate()
	if beacon_positions.size() > 1:
		loop_points.append(beacon_positions[0])
	var path_color := Color(COLOR_GOLD, 0.92 if stage >= Stage.COMBAT else 0.48)
	if loop_points.size() > 1:
		draw_polyline(loop_points, path_color, 8.0, true)

	for i in range(beacon_positions.size()):
		var lit: bool = beacon_lit[i]
		var outer := COLOR_GOLD if lit else Color("#70618f")
		var inner := COLOR_CYAN if lit else Color("#3d315e")
		draw_circle(beacon_positions[i], 34.0, Color(COLOR_INK, 0.94))
		draw_arc(beacon_positions[i], 34.0, 0.0, TAU, 32, outer, 5.0, true)
		draw_circle(beacon_positions[i], 19.0, Color(inner, 0.74))
		if lit:
			draw_circle(beacon_positions[i], 49.0, Color(COLOR_GOLD, 0.08))
		if i == active_trace_index:
			draw_arc(beacon_positions[i], 47.0, -PI * 0.5, PI * 1.5, 36, COLOR_CYAN, 7.0, true)

	if active_trace_index >= 0 and active_trace_index < beacon_positions.size():
		var trace_from := MAIN_CONSOLE if active_trace_index == 0 else beacon_positions[active_trace_index - 1]
		var trace_to := beacon_positions[active_trace_index]
		draw_line(trace_from, trace_to, Color(COLOR_CYAN, 0.9), 10.0, true)

	if stage == Stage.OBSERVE:
		var focus_radius := 58.0 + sin(companion_time * 3.0) * 5.0
		draw_arc(MAIN_CONSOLE, focus_radius, 0.0, TAU, 40, Color(COLOR_CYAN, 0.72), 4.0, true)


func _draw_boss_debug_state() -> void:
	if stage != Stage.BOSS or not boss_guardian_sprite or not boss_guardian_sprite.visible:
		return
	var center := boss_guardian_sprite.position
	if boss_combat_active:
		draw_circle(center + Vector2(0, -12), 22.0, Color(COLOR_CORAL, 0.92))
		draw_circle(center + Vector2(0, -12), 42.0, Color(COLOR_GOLD, 0.16))
		draw_arc(center, 72.0, -2.75, -1.82, 16, Color(COLOR_CYAN, 0.42), 5.0, true)
		draw_arc(center, 72.0, -1.32, -0.38, 16, Color(COLOR_CYAN, 0.42), 5.0, true)
		return
	if boss_weak_open:
		draw_circle(center + Vector2(0, -12), 17.0, Color(COLOR_CORAL, 0.78))
		draw_circle(center + Vector2(0, -12), 31.0, Color(COLOR_CORAL, 0.14))
		draw_arc(center, 58.0, -0.55, 0.55, 18, COLOR_GOLD, 5.0, true)
	else:
		draw_arc(center, 66.0, 0.0, TAU, 44, Color(COLOR_CYAN, 0.82), 8.0, true)
		draw_circle(center, 72.0, Color(COLOR_CYAN, 0.07))


func _draw_tree_terminal() -> void:
	var tree_base := Vector2(640.0, 170.0)
	var tree_color := COLOR_CORAL.lerp(COLOR_GOLD, restore_progress)
	draw_line(tree_base + Vector2(0, 96), tree_base + Vector2(0, 8), Color("#6d443d"), 34.0, true)
	draw_line(tree_base + Vector2(0, 44), tree_base + Vector2(-72, -4), Color("#6d443d"), 20.0, true)
	draw_line(tree_base + Vector2(0, 44), tree_base + Vector2(72, -4), Color("#6d443d"), 20.0, true)
	draw_circle(tree_base + Vector2(-76, -6), 50.0, Color(tree_color, 0.74))
	draw_circle(tree_base + Vector2(0, -24), 62.0, Color(tree_color, 0.82))
	draw_circle(tree_base + Vector2(78, -6), 50.0, Color(tree_color, 0.74))
	draw_rect(Rect2(tree_base + Vector2(-34, 44), Vector2(68, 52)), Color(COLOR_INK, 0.92))
	draw_rect(Rect2(tree_base + Vector2(-24, 54), Vector2(48, 28)), Color(COLOR_CYAN, 0.34), true)


func _draw_transfer_area() -> void:
	var unlocked := stage >= Stage.TRANSFER
	var gate_color := COLOR_CYAN if unlocked else Color("#5f587b")
	# 背景里已经有完整的门体，这里只叠加可交互的状态光，避免“UI 栏杆”破坏场景。
	draw_circle(TRANSFER_CONSOLE, 28.0, Color(gate_color, 0.10 if unlocked else 0.05))
	draw_arc(TRANSFER_CONSOLE, 30.0, 0.0, TAU, 28, gate_color, 3.0, true)
	for i in range(transfer_loop_target):
		var sprout_pos := _transfer_target_position(i)
		var sprout_color := COLOR_GOLD if i < transfer_checked else gate_color
		draw_line(sprout_pos, sprout_pos + Vector2(0, -18), sprout_color, 4.0)
		draw_circle(sprout_pos + Vector2(-7, -20), 8.0, Color(sprout_color, 0.82))
		draw_circle(sprout_pos + Vector2(7, -20), 8.0, Color(sprout_color, 0.82))
	if stage == Stage.TRANSFER and not optional_puzzle_completed:
		var optional_radius := 38.0 + sin(companion_time * 2.8) * 5.0
		draw_arc(OPTIONAL_CONSOLE, optional_radius, 0.0, TAU, 28, Color("#c49bffb8"), 4.0, true)


func _draw_projectiles() -> void:
	for projectile in projectiles:
		var trail_start: Vector2 = projectile.position - projectile.velocity.normalized() * 18.0
		draw_line(trail_start, projectile.position, Color(COLOR_CYAN, 0.55), 5.0, true)
		draw_circle(projectile.position, 7.0, COLOR_GOLD)
		draw_circle(projectile.position, 14.0, Color(COLOR_GOLD, 0.12))


func _draw_actor_shadows() -> void:
	if stage != Stage.COMPLETE and (stage != Stage.BOSS or boss_combat_active):
		draw_colored_polygon(PackedVector2Array([
			player_position + Vector2(-28, 31), player_position + Vector2(28, 31),
			player_position + Vector2(20, 39), player_position + Vector2(-20, 39),
		]), Color("#090b18a0"))
	for enemy in enemies:
		var p: Vector2 = enemy.position
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(-23, 23), p + Vector2(23, 23), p + Vector2(17, 30), p + Vector2(-17, 30),
		]), Color("#090b1888"))


func _draw_combat_overlays() -> void:
	if not _combat_controls_active():
		return
	for enemy in enemies:
		var p: Vector2 = enemy.position
		var hp_ratio := clampf(float(enemy.hp) / float(enemy.get("max_hp", 2)), 0.0, 1.0)
		draw_rect(Rect2(p + Vector2(-25, -39), Vector2(50, 7)), Color("#17172dcc"), true)
		draw_rect(Rect2(p + Vector2(-23, -37), Vector2(46.0 * hp_ratio, 3)), COLOR_CORAL, true)
		if p.distance_to(player_position) < 110.0:
			draw_arc(p, 43.0, 0.0, TAU, 28, Color(COLOR_CORAL, 0.52), 3.0, true)


func _draw_feedback_fx() -> void:
	if scan_pulse > 0.0:
		var scan_progress := 1.0 - scan_pulse
		for p in beacon_positions:
			draw_arc(p, 38.0 + scan_progress * 26.0, 0.0, TAU, 32, Color(COLOR_CYAN, scan_pulse * 0.8), 4.0, true)
	if overflow_pulse > 0.0:
		var overflow_pos := beacon_positions[0] + Vector2(-58, -40)
		draw_arc(overflow_pos, 18.0 + (1.0 - overflow_pulse) * 18.0, 0.0, TAU, 24, Color(COLOR_CORAL, overflow_pulse), 5.0, true)
	for mote in world_motes:
		draw_circle(mote.position, float(mote.size), Color(mote.color, float(mote.life)))
	for spark in hit_sparks:
		draw_line(spark.position, spark.position - spark.velocity.normalized() * 10.0, Color(spark.color, float(spark.life)), 3.0, true)


func _update_vfx(delta: float) -> void:
	for i in range(world_motes.size() - 1, -1, -1):
		var mote := world_motes[i]
		mote.position += mote.velocity * delta
		mote.life -= delta * 0.72
		if float(mote.life) <= 0.0:
			world_motes.remove_at(i)
	for i in range(hit_sparks.size() - 1, -1, -1):
		var spark := hit_sparks[i]
		spark.position += spark.velocity * delta
		spark.velocity *= maxf(0.0, 1.0 - delta * 4.0)
		spark.life -= delta * 1.8
		if float(spark.life) <= 0.0:
			hit_sparks.remove_at(i)
	if player_sprite:
		player_sprite.modulate = Color("#ff9b8f") if player_hit_flash > 0.0 else Color.WHITE


func _update_energy(delta: float) -> void:
	if not _combat_controls_active() or player_energy >= PLAYER_MAX_ENERGY:
		return
	energy_regen_timer += delta
	if energy_regen_timer >= 0.62:
		energy_regen_timer = 0.0
		player_energy = minf(PLAYER_MAX_ENERGY, player_energy + 1.0)
		if energy_bar:
			energy_bar.value = player_energy


func _spawn_world_motes(center: Vector2, amount: int, color: Color, spread: float = 120.0) -> void:
	for i in range(amount):
		var angle := TAU * float(i) / float(maxi(1, amount)) + randf_range(-0.18, 0.18)
		world_motes.append({
			"position": center + Vector2.from_angle(angle) * randf_range(12.0, spread * 0.36),
			"velocity": Vector2.from_angle(angle) * randf_range(spread * 0.28, spread),
			"life": randf_range(0.55, 1.0),
			"size": randf_range(2.0, 5.0),
			"color": color,
		})


func _spawn_hit_sparks(center: Vector2, color: Color, amount: int = 8) -> void:
	for i in range(amount):
		var angle := TAU * float(i) / float(maxi(1, amount)) + randf_range(-0.3, 0.3)
		hit_sparks.append({
			"position": center,
			"velocity": Vector2.from_angle(angle) * randf_range(80.0, 180.0),
			"life": randf_range(0.45, 0.85),
			"color": color,
		})


func _build_world_nodes() -> void:
	background_sprite = Sprite2D.new()
	background_sprite.texture = content_runtime.load_skin_texture(main_content_skin_id, "background_before", "res://assets/backgrounds/data_garden_world.png")
	background_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background_sprite.centered = false
	if background_sprite.texture:
		var texture_size := background_sprite.texture.get_size()
		background_sprite.scale = VIEW_SIZE / texture_size
	background_sprite.position = Vector2.ZERO
	background_sprite.z_index = -50
	add_child(background_sprite)

	restored_background_sprite = Sprite2D.new()
	restored_background_sprite.texture = content_runtime.load_skin_texture(main_content_skin_id, "background_after", "res://assets/backgrounds/data_garden_world_restored.png")
	restored_background_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	restored_background_sprite.centered = false
	if restored_background_sprite.texture:
		restored_background_sprite.scale = VIEW_SIZE / restored_background_sprite.texture.get_size()
	restored_background_sprite.position = Vector2.ZERO
	restored_background_sprite.modulate = Color(1, 1, 1, 0)
	restored_background_sprite.z_index = -49
	add_child(restored_background_sprite)

	player_sprite = Sprite2D.new()
	player_sprite.texture = load("res://assets/sprites/players/data_garden_student.png")
	player_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	player_sprite.scale = Vector2(0.078, 0.078)
	player_sprite.position = player_position
	player_sprite.z_index = 12
	add_child(player_sprite)

	companion_sprite = Sprite2D.new()
	# 小核桃是产品身份，不属于世界皮肤；任何内容包都不得覆盖原版形象。
	companion_sprite.texture = load("res://assets/sprites/companion/xiao_hetao.png")
	companion_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fit_sprite(companion_sprite, 78.0)
	companion_sprite.position = player_position + Vector2(64, -12)
	companion_sprite.z_index = 13
	add_child(companion_sprite)

	console_sprite = Sprite2D.new()
	console_sprite.texture = content_runtime.load_skin_texture(main_content_skin_id, "console", "res://assets/sprites/items/data_garden_console.png")
	console_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fit_sprite(console_sprite, 108.0)
	console_sprite.position = MAIN_CONSOLE
	console_sprite.z_index = 5
	add_child(console_sprite)

	optional_memory_sprite = Sprite2D.new()
	optional_memory_sprite.texture = content_runtime.load_skin_texture(main_content_skin_id, "target_entity", "res://assets/sprites/items/data_garden_light_seed.png")
	optional_memory_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fit_sprite(optional_memory_sprite, 66.0)
	optional_memory_sprite.position = OPTIONAL_CONSOLE
	optional_memory_sprite.modulate = Color("#b98cff")
	optional_memory_sprite.z_index = 5
	optional_memory_sprite.hide()
	add_child(optional_memory_sprite)

	portal_sprite = Sprite2D.new()
	portal_sprite.texture = load("res://assets/sprites/Dimensional_Portal.png")
	portal_sprite.hframes = 3
	portal_sprite.vframes = 6
	portal_sprite.frame = 1
	portal_sprite.scale = Vector2(2.4, 2.4)
	portal_sprite.position = Vector2(1000, 176)
	portal_sprite.hide()
	portal_sprite.z_index = 2
	add_child(portal_sprite)

	for i in range(beacon_positions.size()):
		var sprite := Sprite2D.new()
		sprite.texture = content_runtime.load_skin_texture(main_content_skin_id, "target_entity", "res://assets/sprites/items/data_garden_light_seed.png")
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_fit_sprite(sprite, 90.0)
		beacon_base_scales.append(sprite.scale)
		sprite.position = beacon_positions[i]
		var dormant_colors := [Color("#bda5e8"), Color("#f2a89b"), Color("#99c7e6"), Color("#b8d7a2")]
		sprite.modulate = dormant_colors[i % dormant_colors.size()] * 0.72
		sprite.z_index = 4
		add_child(sprite)
		beacon_sprites.append(sprite)

	enemy_texture = load("res://assets/sprites/enemies/Sprites/tile_0000.png")
	boss_guardian_sprite = Sprite2D.new()
	boss_guardian_sprite.texture = load("res://assets/sprites/enemies/data_garden_guardian.png")
	boss_guardian_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	boss_guardian_sprite.scale = Vector2(0.2, 0.2)
	boss_guardian_sprite.position = Vector2(1120, 270)
	boss_guardian_sprite.modulate = Color.WHITE
	boss_guardian_sprite.z_index = 9
	boss_guardian_sprite.hide()
	add_child(boss_guardian_sprite)


func _fit_sprite(sprite: Sprite2D, longest_side: float) -> void:
	if not sprite.texture:
		return
	var texture_size := sprite.texture.get_size()
	var source_side := maxf(texture_size.x, texture_size.y)
	if source_side > 0.0:
		var factor := longest_side / source_side
		sprite.scale = Vector2(factor, factor)


func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 20
	add_child(ui_layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(ui_root)

	_build_status_ui()
	_build_tutorial_ui()
	_build_companion_ui()
	_build_program_ui()
	_build_boss_ui()
	_build_summary_ui()
	_build_optional_ui()
	_build_feedback_ui()


func _build_status_ui() -> void:
	status_panel = _make_panel(Rect2(18, 18, 210, 76), Color("#17172dcf"), Color("#8175aa"), 12)
	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 7)
	status_panel.add_child(status_box)

	var health_row := HBoxContainer.new()
	status_box.add_child(health_row)
	health_row.add_child(_make_label("生命", 14, COLOR_TEXT, Vector2(42, 0)))
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(136, 18)
	health_bar.max_value = 5
	health_bar.value = player_health
	health_bar.show_percentage = false
	health_bar.add_theme_stylebox_override("background", _style_box(Color("#332943"), Color.TRANSPARENT, 8))
	health_bar.add_theme_stylebox_override("fill", _style_box(COLOR_CORAL, Color.TRANSPARENT, 8))
	health_row.add_child(health_bar)

	var energy_row := HBoxContainer.new()
	status_box.add_child(energy_row)
	energy_row.add_child(_make_label("能量", 14, COLOR_TEXT, Vector2(42, 0)))
	energy_bar = ProgressBar.new()
	energy_bar.custom_minimum_size = Vector2(136, 18)
	energy_bar.max_value = 5
	energy_bar.value = player_energy
	energy_bar.show_percentage = false
	energy_bar.add_theme_stylebox_override("background", _style_box(Color("#292f4b"), Color.TRANSPARENT, 8))
	energy_bar.add_theme_stylebox_override("fill", _style_box(COLOR_CYAN, Color.TRANSPARENT, 8))
	energy_row.add_child(energy_bar)

	objective_panel = _make_panel(Rect2(420, 16, 440, 60), Color("#17172dcc"), Color("#8175aa"), 13)
	var objective_box := VBoxContainer.new()
	objective_box.alignment = BoxContainer.ALIGNMENT_CENTER
	objective_panel.add_child(objective_box)
	objective_label = _make_label("", 20, COLOR_TEXT)
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_box.add_child(objective_label)
	progress_label = _make_label("", 13, COLOR_MUTED)
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_box.add_child(progress_label)

	var content_hash := str(content_metadata.get("content_hash", ""))
	content_version_label = _make_label(
		"内容引擎 · v%s · 主任务 %d / 迁移 %d · %s" % [
			str(content_metadata.get("version", "未加载")),
			main_loop_target,
			transfer_loop_target,
			content_hash.left(8),
		],
		12,
		COLOR_CYAN
	)
	content_version_label.position = Vector2(430, 79)
	content_version_label.size = Vector2(420, 24)
	content_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_version_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content_version_label.add_theme_stylebox_override("normal", _style_box(Color("#17172dbb"), Color("#347d70"), 9, 1))
	ui_root.add_child(content_version_label)

	audio_toggle_button = _make_button("", Color("#3d365d"), 15)
	audio_toggle_button.position = Vector2(892, 20)
	audio_toggle_button.size = Vector2(166, 42)
	audio_toggle_button.toggle_mode = true
	audio_toggle_button.toggled.connect(_on_audio_toggled)
	ui_root.add_child(audio_toggle_button)
	_refresh_audio_toggle()

	mini_map_panel = _make_panel(Rect2(1084, 18, 174, 124), Color("#17172de8"), Color("#8175aa"), 14)
	mini_content = Control.new()
	mini_content.custom_minimum_size = Vector2(146, 100)
	mini_map_panel.add_child(mini_content)
	var mini_title := _make_label(main_world_name, 15, COLOR_TEXT)
	mini_title.position = Vector2(42, -2)
	mini_title.size = Vector2(90, 24)
	mini_content.add_child(mini_title)
	var blocks := [
		Rect2(74, 38, 28, 24), Rect2(74, 66, 28, 28), Rect2(42, 66, 28, 28),
		Rect2(106, 66, 28, 28), Rect2(74, 98, 28, 14),
	]
	for i in range(blocks.size()):
		var block := ColorRect.new()
		block.position = blocks[i].position
		block.size = blocks[i].size
		block.color = COLOR_MINT if i in [1, 3] else COLOR_PURPLE
		mini_content.add_child(block)
	mini_objective_dot = ColorRect.new()
	mini_objective_dot.size = Vector2(9, 9)
	mini_objective_dot.color = COLOR_GOLD
	mini_content.add_child(mini_objective_dot)
	mini_player_dot = ColorRect.new()
	mini_player_dot.size = Vector2(9, 9)
	mini_player_dot.color = COLOR_CYAN
	mini_content.add_child(mini_player_dot)
	# 比赛演示默认让世界成为主角；战斗信息按需出现，地图不常驻。
	status_panel.hide()
	mini_map_panel.hide()

	weapon_badge = _make_panel(Rect2(22, 126, 238, 52), Color("#211f3de8"), COLOR_GOLD, 12)
	var weapon_label := _make_label("光种发射器 · 空格/点击", 16, COLOR_GOLD)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weapon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	weapon_badge.add_child(weapon_label)
	weapon_badge.hide()


func _on_audio_toggled(is_on: bool) -> void:
	Global.set_audio_enabled(is_on, not test_mode and not capture_mode)
	_refresh_audio_toggle()


func _refresh_audio_toggle() -> void:
	if not audio_toggle_button:
		return
	var is_on := Global.is_audio_enabled()
	audio_toggle_button.set_pressed_no_signal(is_on)
	audio_toggle_button.text = "声音：%s  M" % ("开" if is_on else "关")
	audio_toggle_button.tooltip_text = "点击或按 M %s音乐和音效" % ("关闭" if is_on else "开启")


func _build_tutorial_ui() -> void:
	tutorial_panel = _make_panel(Rect2(914, 624, 346, 74), Color("#17172dd8"), COLOR_CYAN, 14)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	tutorial_panel.add_child(box)
	tutorial_label = _make_label("", 17, COLOR_TEXT)
	tutorial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(tutorial_label)

	interaction_label = _make_label("", 20, COLOR_TEXT)
	interaction_label.position = Vector2(440, 512)
	interaction_label.size = Vector2(400, 50)
	interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	interaction_label.add_theme_stylebox_override("normal", _style_box(Color("#17172de8"), COLOR_GOLD, 14, 2))
	ui_root.add_child(interaction_label)
	interaction_label.hide()


func _build_companion_ui() -> void:
	companion_panel = _make_panel(Rect2(22, 574, 430, 124), Color("#fff6e8ee"), COLOR_PURPLE, 15)
	var companion_content := Control.new()
	companion_content.custom_minimum_size = Vector2(404, 100)
	companion_panel.add_child(companion_content)
	var avatar := TextureRect.new()
	avatar.texture = load("res://assets/sprites/companion/xiao_hetao.png")
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	avatar.custom_minimum_size = Vector2(64, 64)
	avatar.position = Vector2(4, 26)
	avatar.size = Vector2(64, 64)
	companion_content.add_child(avatar)

	companion_level_label = _make_label("小核桃 · Lv.1", 15, COLOR_PURPLE_DARK)
	companion_level_label.position = Vector2(76, 4)
	companion_level_label.size = Vector2(236, 24)
	companion_content.add_child(companion_level_label)

	companion_label = _make_label("", 16, Color("#2c2743"))
	companion_label.position = Vector2(76, 29)
	companion_label.size = Vector2(316, 54)
	companion_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	companion_content.add_child(companion_label)

	var dots_box := HBoxContainer.new()
	dots_box.position = Vector2(80, 85)
	dots_box.size = Vector2(160, 18)
	dots_box.add_theme_constant_override("separation", 9)
	companion_content.add_child(dots_box)
	for i in range(5):
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.color = Color("#d6d0df")
		dots_box.add_child(dot)
		hint_dots.append(dot)

	hint_button = _make_button("提示  H", COLOR_PURPLE, 16)
	hint_button.position = Vector2(312, 82)
	hint_button.size = Vector2(78, 30)
	hint_button.pressed.connect(_request_hint)
	companion_content.add_child(hint_button)


func _build_program_ui() -> void:
	# 编程装置停靠在左侧空地：光种阵列（环形布局最左约 x=405）与中央法则台完整留在视野里。
	code_panel = Control.new()
	code_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	code_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	ui_root.add_child(code_panel)

	program_device_panel = Panel.new()
	program_device_panel.position = Vector2(25, 226)
	program_device_panel.size = Vector2(330, 302)
	program_device_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	program_device_panel.add_theme_stylebox_override("panel", _style_box(Color("#17172de0"), Color("#73688f"), 18, 2))
	code_panel.add_child(program_device_panel)

	code_title = _make_label(main_console_name, 20, COLOR_TEXT)
	code_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_title.position = Vector2(40, 238)
	code_title.size = Vector2(300, 34)
	code_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	code_panel.add_child(code_title)

	code_layer_label = _make_label("第 1 层 · 世界行为", 15, COLOR_CYAN)
	code_layer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_layer_label.position = Vector2(40, 272)
	code_layer_label.size = Vector2(300, 26)
	code_panel.add_child(code_layer_label)

	trace_label = _make_label("%d 个%s正在等待。" % [main_loop_target, main_entity_name], 15, COLOR_MUTED)
	trace_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trace_label.position = Vector2(40, 298)
	trace_label.size = Vector2(300, 40)
	trace_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	code_panel.add_child(trace_label)

	c_code_label = _make_label("for (int i = 0; i < %d; i++) {\n    grow();\n}" % main_loop_target, 18, Color("#b9ffe7"))
	c_code_label.position = Vector2(65, 304)
	c_code_label.size = Vector2(250, 116)
	c_code_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c_code_label.hide()
	code_panel.add_child(c_code_label)

	observe_button = _make_command_button("观察 %d 个%s" % [main_loop_target, main_entity_name], Color("#615377"), 17)
	repeat_button = _make_command_button("重复 [ ] 次\n拖入动作", COLOR_CORAL, 16)
	action_button = _make_command_button(_action_button_text(main_action_name), COLOR_MINT_DARK, 14)
	run_button = _make_command_button("试运行：%s一次" % main_action_name, Color("#f56f38"), 17)
	observe_button.position = Vector2(50, 344)
	repeat_button.position = Vector2(185, 344)
	action_button.position = Vector2(50, 344)
	run_button.position = Vector2(50, 414)
	observe_button.size = Vector2(280, 52)
	action_button.size = Vector2(124, 58)
	repeat_button.size = Vector2(145, 58)
	run_button.size = Vector2(280, 50)
	observe_button.tooltip_text = "只观察世界，不提前告诉概念名称（快捷键 1 / O）"
	action_button.tooltip_text = "把动作拖进重复结构（快捷键 2 / G 可作为无障碍操作）"
	repeat_button.tooltip_text = "动作放入后调整执行次数（快捷键 3 / 方向键右）"
	run_button.tooltip_text = "按当前结构真实运行（回车）"
	for button in [observe_button, repeat_button, action_button, run_button]:
		code_panel.add_child(button)
	observe_button.pressed.connect(_observe_targets)
	action_button.pressed.connect(_select_action)
	action_button.button_down.connect(_begin_action_drag)
	repeat_button.pressed.connect(_cycle_repeat_count)
	run_button.pressed.connect(_run_program)

	var prediction_texts := ["亮起 1 颗", "全部亮起", "没有变化"]
	for i in range(prediction_texts.size()):
		var prediction := _make_button(prediction_texts[i], Color("#443b63"), 13)
		prediction.position = Vector2(40 + i * 100, 344)
		prediction.size = Vector2(96, 50)
		prediction.pressed.connect(_choose_prediction.bind(i))
		code_panel.add_child(prediction)
		prediction_buttons.append(prediction)

	drag_ghost = _make_label(main_action_name, 16, COLOR_TEXT)
	drag_ghost.size = Vector2(128, 38)
	drag_ghost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drag_ghost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_ghost.add_theme_stylebox_override("normal", _style_box(Color("#347d70e8"), COLOR_CYAN, 8, 2))
	drag_ghost.hide()
	code_panel.add_child(drag_ghost)

	var footer := _make_label("先观察，不急着认识术语。", 13, COLOR_MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.position = Vector2(40, 474)
	footer.size = Vector2(300, 38)
	footer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	code_panel.add_child(footer)
	command_info_label = footer
	code_panel.hide()


func _build_boss_ui() -> void:
	boss_panel = _make_panel(Rect2(350, 382, 580, 316), Color("#17172dea"), COLOR_GOLD, 18, 3)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	boss_panel.add_child(box)
	boss_title = _make_label("守门者 · Debug 战", 22, COLOR_GOLD)
	boss_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(boss_title)
	boss_health_bar = ProgressBar.new()
	boss_health_bar.custom_minimum_size = Vector2(0, 16)
	boss_health_bar.max_value = 2
	boss_health_bar.value = 2
	boss_health_bar.show_percentage = false
	boss_health_bar.add_theme_stylebox_override("background", _style_box(Color("#382b4b"), Color.TRANSPARENT, 9))
	boss_health_bar.add_theme_stylebox_override("fill", _style_box(COLOR_GOLD, Color.TRANSPARENT, 9))
	box.add_child(boss_health_bar)
	boss_question_label = _make_label("", 17, COLOR_TEXT)
	boss_question_label.custom_minimum_size = Vector2(0, 62)
	boss_question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boss_question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_question_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(boss_question_label)
	boss_feedback_label = _make_label("", 15, COLOR_MUTED)
	boss_feedback_label.custom_minimum_size = Vector2(0, 38)
	boss_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(boss_feedback_label)
	for i in range(3):
		var option := _make_button("", Color("#3d365d"), 15)
		option.custom_minimum_size = Vector2(0, 38)
		option.pressed.connect(_boss_debug_action.bind(i))
		box.add_child(option)
		boss_option_buttons.append(option)
	aid_button = _make_button("小核桃：回放执行轨迹（本局 1 次）", COLOR_PURPLE, 14)
	aid_button.custom_minimum_size = Vector2(0, 36)
	aid_button.pressed.connect(_use_companion_aid)
	box.add_child(aid_button)
	boss_panel.hide()


func _build_summary_ui() -> void:
	summary_panel = _make_panel(Rect2(240, 72, 800, 612), Color("#fff8ecfa"), COLOR_GOLD, 24, 5)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	summary_panel.add_child(box)
	var title := _make_label("花园记住了你", 34, COLOR_PURPLE_DARK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := _make_label("不是因为得了三颗星，而是因为你真的改变了世界规则。", 20, Color("#554c6d"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	summary_body = _make_label("", 18, Color("#2c2743"))
	summary_body.custom_minimum_size = Vector2(0, 262)
	summary_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(summary_body)
	var replay := _make_button("重新体验  R", Color("#f56f38"), 20)
	replay.custom_minimum_size = Vector2(0, 52)
	replay.pressed.connect(func() -> void: get_tree().reload_current_scene())
	box.add_child(replay)
	var home_button := _make_button("带着水脉种子返回芽心基地", COLOR_MINT_DARK, 18)
	home_button.custom_minimum_size = Vector2(0, 50)
	home_button.pressed.connect(_return_home)
	box.add_child(home_button)
	var stay_button := _make_button("留在修复后的花园", COLOR_PURPLE, 18)
	stay_button.custom_minimum_size = Vector2(0, 44)
	stay_button.pressed.connect(_stay_in_restored_garden)
	box.add_child(stay_button)
	summary_panel.hide()


func _stay_in_restored_garden() -> void:
	summary_panel.hide()
	companion_panel.show()
	_set_companion_message("你可以在这里看看自己留下的光。按 R 随时重新挑战。")


func _return_home() -> void:
	get_tree().change_scene_to_file("res://scenes/demo/loop_oasis/home_base.tscn")


func _build_optional_ui() -> void:
	optional_panel = _make_panel(Rect2(330, 164, 620, 414), Color("#17172df7"), Color("#b98cff"), 22, 4)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 11)
	optional_panel.add_child(box)
	var title := _make_label("可选谜题 · 记忆晶体", 27, Color("#d8c1ff"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var optional_question := _make_label("晶体要“闪烁 3 次、停顿、再闪烁 3 次”。哪段程序最清楚？", 20, COLOR_TEXT)
	optional_question.custom_minimum_size = Vector2(0, 68)
	optional_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	optional_question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	optional_question.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(optional_question)
	var options := [
		"A. 重复 6 次：闪烁",
		"B. 重复 3 次：闪烁；停顿；重复 3 次：闪烁",
		"C. 一直重复：闪烁",
	]
	for i in range(options.size()):
		var option := _make_button(options[i], Color("#463867"), 17)
		option.custom_minimum_size = Vector2(0, 52)
		option.pressed.connect(_answer_optional_puzzle.bind(i))
		box.add_child(option)
		optional_option_buttons.append(option)
	optional_feedback_label = _make_label("这是自由探索，不影响主线通关。", 16, COLOR_MUTED)
	optional_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	optional_feedback_label.custom_minimum_size = Vector2(0, 30)
	box.add_child(optional_feedback_label)
	var skip := _make_button("先离开，继续主线", COLOR_PURPLE, 16)
	skip.custom_minimum_size = Vector2(0, 42)
	skip.pressed.connect(_close_optional_puzzle)
	box.add_child(skip)
	optional_panel.hide()


func _build_feedback_ui() -> void:
	stage_banner = _make_panel(Rect2(430, 126, 420, 64), Color("#17172df2"), COLOR_GOLD, 16, 3)
	stage_banner_label = _make_label("", 22, COLOR_TEXT)
	stage_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stage_banner.add_child(stage_banner_label)
	stage_banner.hide()

	flash_overlay = ColorRect.new()
	flash_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_overlay.color = Color(1, 1, 1, 0)
	flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(flash_overlay)


func _update_player(delta: float) -> void:
	var can_move := (stage in [Stage.ARRIVAL, Stage.OBSERVE, Stage.COMBAT, Stage.TRANSFER] or _combat_controls_active()) and not optional_panel.visible
	var direction := Vector2.ZERO
	if can_move and not test_mode and not capture_mode:
		direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if direction.length() > 0.05:
			idle_time = 0.0
			movement_seen = true
			player_position += direction.normalized() * PLAYER_SPEED * delta
			player_sprite.flip_h = direction.x < -0.05
			if stage == Stage.ARRIVAL:
				_set_stage(Stage.OBSERVE)
		else:
			idle_time += delta
			if idle_time > 5.5 and stage == Stage.ARRIVAL:
				_set_companion_message("先试试 W A S D 或方向键。今天只先学这一件事。")

		if player_position.y > 540.0:
			player_position.x = clampf(player_position.x, 600.0, 680.0)
		else:
			player_position.x = clampf(player_position.x, 180.0, 1100.0)
		player_position.y = clampf(player_position.y, 146.0, 684.0)

	player_move_strength = move_toward(player_move_strength, 1.0 if direction.length() > 0.05 else 0.0, delta * 7.0)
	var walk_bob := sin(companion_time * 11.0) * 3.5 * player_move_strength
	player_sprite.position = player_position + Vector2(0, walk_bob)
	player_sprite.rotation = sin(companion_time * 8.0) * 0.025 * player_move_strength


func _update_companion(delta: float) -> void:
	var target := player_position + Vector2(62.0 if not player_sprite.flip_h else -62.0, -8.0 + sin(companion_time * 3.1) * 8.0)
	companion_sprite.position = companion_sprite.position.lerp(target, minf(1.0, delta * 5.5))


func _update_world_animation(_delta: float) -> void:
	if portal_sprite and portal_sprite.visible:
		portal_sprite.frame = int(companion_time * 8.0) % 18
	if console_sprite:
		var console_glow := 0.92 + sin(companion_time * 2.4) * 0.08
		console_sprite.modulate = Color(console_glow, console_glow, 1.0, 1.0)
	for i in range(beacon_sprites.size()):
		if beacon_lit[i]:
			var pulse := 0.082 + sin(companion_time * 3.3 + float(i)) * 0.003
			beacon_sprites[i].scale = Vector2(pulse, pulse)
			beacon_sprites[i].rotation = sin(companion_time * 1.8 + float(i)) * 0.018
		else:
			beacon_sprites[i].rotation = 0.0
	if boss_guardian_sprite and boss_guardian_sprite.visible:
		boss_guardian_sprite.position.y = 270.0 + sin(companion_time * 2.2) * 7.0


func _update_minimap() -> void:
	if not mini_player_dot or not mini_objective_dot:
		return
	var normalized_player := Vector2(
		inverse_lerp(180.0, 1100.0, player_position.x),
		inverse_lerp(146.0, 684.0, player_position.y)
	)
	mini_player_dot.position = Vector2(42, 36) + normalized_player * Vector2(92, 66)
	var objective_world := MAIN_CONSOLE
	if stage in [Stage.TRANSFER, Stage.BOSS, Stage.COMPLETE] or (stage == Stage.PROGRAM and program_mode == "transfer"):
		objective_world = TRANSFER_CONSOLE
	var normalized_objective := Vector2(
		inverse_lerp(180.0, 1100.0, objective_world.x),
		inverse_lerp(146.0, 684.0, objective_world.y)
	)
	mini_objective_dot.position = Vector2(42, 36) + normalized_objective * Vector2(92, 66)


func _update_interaction_prompt() -> void:
	if stage == Stage.OBSERVE and player_position.distance_to(MAIN_CONSOLE) < 100.0:
		interaction_label.text = "E  观察中央法则台"
		interaction_label.show()
	elif stage == Stage.TRANSFER and not optional_puzzle_completed and player_position.distance_to(OPTIONAL_CONSOLE) < 105.0:
		interaction_label.text = "E  可选探索：唤醒记忆晶体"
		interaction_label.show()
	elif stage == Stage.TRANSFER and player_position.distance_to(TRANSFER_CONSOLE) < 105.0:
		interaction_label.text = "E  启动陌生巡检器（无提示迁移）"
		interaction_label.show()
	else:
		interaction_label.hide()


func _try_interact() -> void:
	if stage == Stage.OBSERVE and player_position.distance_to(MAIN_CONSOLE) < 110.0:
		_show_program("main")
	elif stage == Stage.TRANSFER and not optional_puzzle_completed and player_position.distance_to(OPTIONAL_CONSOLE) < 115.0:
		_open_optional_puzzle()
	elif stage == Stage.TRANSFER and player_position.distance_to(TRANSFER_CONSOLE) < 115.0:
		_show_program("transfer")


func _open_optional_puzzle() -> void:
	# 模态题面优先级高于短暂的阶段横幅，避免两层信息互相遮挡。
	stage_banner.hide()
	optional_panel.show()
	tutorial_panel.hide()
	interaction_label.hide()
	optional_feedback_label.text = "这是自由探索，不影响主线通关。"
	optional_feedback_label.add_theme_color_override("font_color", COLOR_MUTED)
	optional_option_buttons[0].grab_focus()


func _close_optional_puzzle() -> void:
	optional_panel.hide()
	if stage == Stage.TRANSFER:
		tutorial_panel.show()


func _answer_optional_puzzle(index: int) -> void:
	optional_puzzle_attempts += 1
	if index == 1:
		optional_puzzle_completed = true
		optional_panel.hide()
		tutorial_panel.show()
		optional_memory_sprite.modulate = COLOR_GOLD
		optional_memory_sprite.scale = Vector2(0.058, 0.058)
		_spawn_world_motes(OPTIONAL_CONSOLE, 30, Color("#c49bff"), 170.0)
		_show_stage_banner("可选谜题完成 · 你在世界留下了一朵记忆光", Color("#c49bff"))
		_set_companion_message("你发现了两段重复结构之间的停顿。这朵记忆光是你自己留下的。")
		_play_sfx("res://assets/sounds/chest.ogg")
		_log_learning_event("optional_explore_completed", "transfer", {
			"attempts": optional_puzzle_attempts,
			"persistent_world_change": "memory_light_enabled",
		})
	else:
		optional_feedback_label.text = "这段程序没有保留中间的“停顿”。再读一次执行顺序。"
		optional_feedback_label.add_theme_color_override("font_color", COLOR_CORAL)
		_play_sfx("res://assets/sounds/error-b.ogg")


func _show_program(mode: String) -> void:
	program_mode = mode
	repeat_count = 2
	program_step = 0
	active_trace_index = -1
	c_code_label.hide()
	_update_repeat_button()
	code_panel.show()
	tutorial_panel.hide()
	interaction_label.hide()
	if mode == "main":
		learning_phase = LearningPhase.WORLD_OBSERVE
		observation_done = false
		action_selected = false
		prediction_choice = -1
		prediction_done = false
		single_action_tried = false
		main_pattern_verified = false
		counterfactual_done = false
		code_title.text = main_console_name
		code_layer_label.text = "第 1 层 · 世界行为"
		trace_label.text = "%d 个%s正在等待。" % [main_loop_target, main_entity_name]
		action_button.text = _action_button_text(main_action_name)
		observe_button.text = "观察 %d 个%s" % [main_loop_target, main_entity_name]
		command_info_label.text = "先观察，不急着认识术语。"
		_set_program_step(0)
		_set_companion_message("先别写代码。看看这 %d 个%s，世界会先告诉你规律。" % [main_loop_target, main_entity_name])
	else:
		learning_phase = LearningPhase.TRANSFER
		observation_done = true
		action_selected = false
		if active_variant_id.is_empty():
			code_title.text = "%s · %d 个目标" % [transfer_console_name, transfer_loop_target]
			code_layer_label.text = "迁移应用 · 不再提示结构名称"
			trace_label.text = "任务：%s" % (transfer_objective if not transfer_objective.is_empty() else "依次完成 %d 个目标" % transfer_loop_target)
		else:
			code_title.text = "回访新题 · %d 个目标" % transfer_loop_target
			code_layer_label.text = "新题已切换 · 独立迁移同一规律"
			trace_label.text = "目标：%d 个%s\n动作：%s" % [transfer_loop_target, transfer_entity_name, transfer_action_name]
		action_button.text = _action_button_text(transfer_action_name)
		action_button.tooltip_text = "把“%s”拖进重复结构" % transfer_action_name
		observe_button.text = "目标：%d 个" % transfer_loop_target
		command_info_label.text = "把刚才形成的结构迁移到新装置。"
		observation_done = true
		_set_program_step(3)
		_set_companion_message(transfer_scenario_frame)
	stage = Stage.PROGRAM
	_update_objective()


func _set_program_step(next_step: int) -> void:
	program_step = clampi(next_step, 0, 3)
	observe_button.hide()
	action_button.hide()
	repeat_button.hide()
	run_button.hide()
	for prediction in prediction_buttons:
		prediction.hide()
	if program_mode == "concept":
		c_code_label.show()
		run_button.text = "进入 Debug 战"
		run_button.show()
		return
	if program_mode == "transfer":
		action_button.show()
		repeat_button.show()
		run_button.text = "运行%s程序" % transfer_action_name
		run_button.visible = action_selected
		return
	match program_step:
		0:
			observe_button.show()
		1:
			for prediction in prediction_buttons:
				prediction.show()
		2:
			run_button.text = "试运行：%s一次" % main_action_name
			run_button.show()
		3:
			action_button.show()
			repeat_button.show()
			run_button.text = "运行并观察轨迹"
			run_button.visible = action_selected


func _observe_targets() -> void:
	if stage != Stage.PROGRAM:
		return
	if program_mode == "transfer":
		_set_companion_message("目标已经写在%s上：%d 个目标。结构要由你自己迁移。" % [transfer_console_name, transfer_loop_target])
		return
	observation_done = true
	scan_pulse = 1.0
	observe_button.text = "已观察 · %d 颗" % main_loop_target
	learning_phase = LearningPhase.PREDICT
	_set_program_step(1)
	for p in beacon_positions:
		_spawn_world_motes(p, 5, COLOR_CYAN, 56.0)
	_play_sfx("res://assets/sounds/select-a.ogg")
	trace_label.text = "预测：只执行一次“%s”，世界会怎样？" % main_action_name
	command_info_label.text = "先预测，再让真实世界验证。"
	_set_companion_message("%d 个%s都在等待。先预测：如果只做一次“%s”，会改变几个？" % [main_loop_target, main_entity_name, main_action_name])


func _choose_prediction(index: int) -> void:
	if stage != Stage.PROGRAM or program_mode != "main" or learning_phase != LearningPhase.PREDICT:
		return
	prediction_choice = clampi(index, 0, prediction_buttons.size() - 1)
	prediction_done = true
	learning_phase = LearningPhase.SINGLE_ACTION
	for i in range(prediction_buttons.size()):
		prediction_buttons[i].disabled = i == prediction_choice
	trace_label.text = "你的预测：%s" % prediction_buttons[prediction_choice].text
	command_info_label.text = "现在运行一次，用世界反馈验证预测。"
	_set_program_step(2)
	_set_companion_message("预测已经记下。答案不由我宣布，按“试运行”让%s自己回答。" % main_entity_name)


func _run_single_growth_trial() -> void:
	transition_lock = true
	for i in range(main_loop_target):
		beacon_lit[i] = false
		_update_beacon_sprite(i)
	active_trace_index = 0
	trace_label.text = "执行：grow()  →  %s 1" % main_entity_name
	queue_redraw()
	if not test_mode:
		await get_tree().create_timer(0.45).timeout
	beacon_lit[0] = true
	_update_beacon_sprite(0)
	_spawn_world_motes(beacon_positions[0], 16, COLOR_GOLD, 90.0)
	_play_sfx("res://assets/sounds/coin-a.ogg")
	if not test_mode:
		await get_tree().create_timer(0.38).timeout
	active_trace_index = -1
	single_action_tried = true
	learning_phase = LearningPhase.BUILD_BLOCKS
	code_layer_label.text = "第 2 层 · 自然语言指令"
	trace_label.text = "让每一个%s都执行一次“%s”。" % [main_entity_name, main_action_name]
	command_info_label.text = "把“%s”拖进重复结构，再决定次数。" % main_action_name
	_set_program_step(3)
	var result_text := "你的预测被世界验证了：一次动作只唤醒一颗。" if prediction_choice == 0 else "世界给出了新证据：一次动作只唤醒一颗。修改你的想法就是真正的学习。"
	_set_companion_message(result_text)
	transition_lock = false


func _begin_action_drag() -> void:
	if not action_button.visible or transition_lock or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	action_dragging = true
	drag_ghost.text = _compact_action_name(transfer_action_name if program_mode == "transfer" else main_action_name, 5)
	drag_ghost.position = get_viewport().get_mouse_position() + Vector2(14, 12)
	drag_ghost.show()


func _select_action() -> void:
	if stage != Stage.PROGRAM:
		return
	if program_mode == "main" and not single_action_tried:
		_set_companion_message("先预测并试运行一次“%s”，再开始编排。" % main_action_name)
		return
	action_selected = true
	last_program_change = "把%s放进重复结构" % (transfer_action_name if program_mode == "transfer" else main_action_name)
	action_button.text = _action_button_text(transfer_action_name if program_mode == "transfer" else main_action_name, true)
	if program_mode == "main":
		code_layer_label.text = "第 3 层 · 积木 / 流程结构"
	_set_program_step(3)
	_update_repeat_button()
	_spawn_world_motes(beacon_positions[0], 10, COLOR_MINT, 72.0)
	_play_sfx("res://assets/sounds/button_select.wav")
	if program_mode == "main":
		_set_companion_message("“%s”已经进入结构。现在调整次数，再观察每一行怎样改变世界。" % main_action_name)
	else:
		_set_companion_message("%s动作已经放入。接下来由你决定它要执行几次。" % transfer_action_name)


func _cycle_repeat_count() -> void:
	if stage != Stage.PROGRAM:
		return
	if program_mode == "main" and not action_selected:
		_set_companion_message("先把“%s”拖进橙色结构，再设置次数。" % main_action_name)
		return
	if program_mode == "transfer" and not action_selected:
		_set_companion_message("先把“%s”拖进橙色结构。" % transfer_action_name)
		return
	repeat_count += 1
	if repeat_count > maxi(main_loop_target, transfer_loop_target) + 1:
		repeat_count = 1
	_update_repeat_button()
	_set_program_step(3)
	last_program_change = "把执行次数改为 %d" % repeat_count
	_play_sfx("res://assets/sounds/button_hover.wav")


func _update_repeat_button() -> void:
	if repeat_button:
		var action_name := transfer_action_name if program_mode == "transfer" else main_action_name
		repeat_button.text = "重复 %d 次\n└ %s" % [repeat_count, action_name] if action_selected else "重复 [ ] 次\n拖入动作"
		if action_selected and trace_label and learning_phase in [LearningPhase.BUILD_BLOCKS, LearningPhase.COUNTERFACTUAL, LearningPhase.TRANSFER]:
			trace_label.text = "重复 %d 次 { %s }" % [repeat_count, action_name]


func _run_program() -> void:
	if stage not in [Stage.PROGRAM, Stage.CONCEPT] or run_button.disabled or transition_lock:
		return
	run_button.disabled = true
	if program_mode == "concept":
		code_panel.hide()
		await _start_boss()
	elif program_mode == "main" and learning_phase == LearningPhase.SINGLE_ACTION:
		await _run_single_growth_trial()
	elif program_mode == "main":
		if not action_selected:
			_set_companion_message("先把动作放进结构，程序才可以运行。")
		else:
			await _run_main_loop()
	elif program_mode == "transfer":
		if not action_selected:
			_set_companion_message("先把%s动作放进结构。" % transfer_action_name)
		else:
			await _run_transfer_loop()
	else:
		await _run_main_loop()
	run_button.disabled = false


func _run_main_loop() -> void:
	transition_lock = true
	main_attempts += 1
	main_run_attempts += 1
	for i in range(beacon_lit.size()):
		beacon_lit[i] = false
		_update_beacon_sprite(i)
	queue_redraw()

	_play_sfx("res://assets/sounds/button_select.wav")
	if not content_engine_ready:
		_set_companion_message("内容包没有加载成功，请让老师重新启动课程。")
		transition_lock = false
		return
	var run_phase: String = str(LearningPhase.keys()[learning_phase]).to_lower()
	var program := _content_program_for(main_content_skin_id, repeat_count, "main")
	last_execution_result = content_runtime.execute(program, main_content_skin_id)
	last_diagnosis_id = str(last_execution_result.get("diagnosis", {}).get("id", "INVALID_PROGRAM"))
	var executed := int(last_execution_result.get("completed_targets", 0))
	for trace_event in last_execution_result.get("trace", []):
		var event_name := str(trace_event.get("event_name", ""))
		if event_name == "action_effect_applied":
			var target_index := int(trace_event.get("target_index", -1))
			active_trace_index = target_index
			trace_label.text = "高亮：第 %d / %d 次  →  grow()" % [int(trace_event.get("iteration", 0)) + 1, repeat_count]
			queue_redraw()
			if not test_mode:
				await get_tree().create_timer(0.24).timeout
			if target_index >= 0 and target_index < beacon_lit.size():
				beacon_lit[target_index] = true
				_update_beacon_sprite(target_index)
				_spawn_world_motes(beacon_positions[target_index], 12, COLOR_GOLD, 76.0)
				_play_sfx("res://assets/sounds/coin-a.ogg")
		elif event_name == "action_no_target":
			active_trace_index = -1
			trace_label.text = "第 %d 次：没有对应目标，执行溢出" % (int(trace_event.get("iteration", 0)) + 1)
			overflow_pulse = 1.0
			_spawn_hit_sparks(beacon_positions[0] + Vector2(-48, -28), COLOR_CORAL, 14)
			_play_sfx("res://assets/sounds/error-a.ogg")
			if not test_mode:
				await get_tree().create_timer(0.28).timeout
	active_trace_index = -1
	queue_redraw()
	var event_payload := {
		"skin_id": main_content_skin_id,
		"program": program,
		"repeat_count": repeat_count,
		"target_count": main_loop_target,
		"attempt_index": main_run_attempts,
		"learning_phase": run_phase,
		"diagnosis_id": last_diagnosis_id,
		"trace_summary": content_runtime.trace_summary(last_execution_result),
	}
	_log_learning_event("counterfactual_run" if learning_phase == LearningPhase.COUNTERFACTUAL else "program_run", "program", event_payload)

	if learning_phase == LearningPhase.COUNTERFACTUAL:
		if repeat_count == main_loop_target - 1 and last_diagnosis_id == "COUNT_TOO_SMALL":
			counterfactual_done = true
			puzzle_clear = true
			trace_label.text = "反事实成立：%d 次只点亮前 %d 颗，第 %d 颗保持休眠。" % [main_loop_target - 1, main_loop_target - 1, main_loop_target]
			command_info_label.text = "修改数字改变了世界结果；证据已经留下。"
			_set_restored_alpha(0.52)
			_set_companion_message("你亲手证明了：把 %d 改成 %d，最后一颗真的不会亮。现在把这个结构带到陌生装置。" % [main_loop_target, main_loop_target - 1])
			_show_stage_banner("反事实验证 · 最后一个%s保持原状" % main_entity_name, COLOR_CYAN)
			companion_aid_available = true
			if not test_mode:
				await get_tree().create_timer(1.05).timeout
			code_panel.hide()
			await _enter_regular_combat()
		else:
			trace_label.text = "反事实实验需要把刚才的 %d 改成 %d。" % [main_loop_target, main_loop_target - 1]
			_set_companion_message("这一步不是再找正确答案，而是做对照实验：只把 %d 改成 %d，再运行一次。" % [main_loop_target, main_loop_target - 1])
	elif last_diagnosis_id == "SUCCESS":
		main_pattern_verified = true
		learning_phase = LearningPhase.COUNTERFACTUAL
		_set_restored_alpha(0.68)
		code_layer_label.text = "第 3 层 · 执行轨迹与反事实"
		var trace_steps := PackedStringArray()
		for i in range(main_loop_target):
			trace_steps.append(str(i + 1))
		trace_label.text = "运行轨迹：%s，%d 颗依次亮起。" % [" → ".join(trace_steps), main_loop_target]
		command_info_label.text = "反事实实验：只把 %d 改成 %d，再运行。" % [main_loop_target, main_loop_target - 1]
		_set_companion_message("%d 颗按执行顺序亮了。先别记术语：把 %d 改成 %d，看看最后一颗会不会保持休眠。" % [main_loop_target, main_loop_target, main_loop_target - 1])
		_show_stage_banner("预测被验证 · 现在修改一个数字做对照", COLOR_GOLD)
		_log_learning_event("surprise_triggered", "program", {
			"surprise_id": str(content_runtime.manifest.get("surprise", {}).get("id", "garden_restore")),
			"student_triggered": true,
		})
	else:
		_set_restored_alpha(float(executed) / float(main_loop_target) * 0.34)
		var feedback := "程序真实执行了 %d 次。观察还有哪些%s没有按预期变化。" % [repeat_count, main_entity_name]
		if last_diagnosis_id == "COUNT_TOO_LARGE":
			feedback = "前 %d 颗都亮了，但第 %d 次没有目标，世界出现了溢出波纹。少执行一次试试。" % [main_loop_target, main_loop_target + 1]
		_set_companion_message(feedback)
		trace_label.text = "结果：点亮 %d / %d；诊断 %s。" % [executed, main_loop_target, last_diagnosis_id]
	transition_lock = false


func _set_restored_alpha(value: float) -> void:
	restore_progress = clampf(value, 0.0, 1.0)
	if restored_background_sprite:
		restored_background_sprite.modulate.a = restore_progress


func _celebrate_restoration() -> void:
	restoration_active = true
	code_panel.hide()
	_show_stage_banner("法则已生效 · %s正在重生" % main_world_name, COLOR_GOLD)
	_play_sfx("res://assets/sounds/chest.ogg")
	if test_mode:
		_set_restored_alpha(1.0)
		flash_overlay.color.a = 0.0
	else:
		var restore_tween := create_tween().set_parallel(true)
		restore_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		restore_tween.tween_property(restored_background_sprite, "modulate:a", 1.0, 1.8)
		restore_tween.tween_property(flash_overlay, "color:a", 0.42, 0.28)
		for p in beacon_positions:
			_spawn_world_motes(p, 24, COLOR_GOLD, 150.0)
		_spawn_world_motes(Vector2(640, 280), 42, COLOR_CYAN, 260.0)
		await get_tree().create_timer(0.32).timeout
		var fade_tween := create_tween()
		fade_tween.tween_property(flash_overlay, "color:a", 0.0, 0.82)
		await get_tree().create_timer(1.62).timeout
	_set_restored_alpha(1.0)
	restoration_active = false


func _enter_regular_combat() -> void:
	await _celebrate_restoration()
	combat_clear = false
	regular_enemies_defeated = 0
	weapon_unlocked = true
	player_health = 5
	player_energy = PLAYER_MAX_ENERGY
	player_position = Vector2(640, 505)
	player_sprite.position = player_position
	status_panel.show()
	weapon_badge.show()
	_set_stage(Stage.COMBAT)
	_spawn_buglings()
	_log_learning_event("combat_started", "combat", {
		"puzzle_clear": puzzle_clear,
		"enemy_count": enemies.size(),
		"required_for_progress": true,
	})
	_set_companion_message("循环装置已经修复，光种发射器解锁。清除 3 只错误怪后，迁移通道才会开启。")


func _finish_regular_combat() -> void:
	if combat_clear:
		return
	combat_clear = true
	weapon_unlocked = false
	projectiles.clear()
	weapon_badge.hide()
	status_panel.hide()
	_log_learning_event("combat_cleared", "combat", {
		"puzzle_clear": puzzle_clear,
		"combat_clear": true,
		"enemies_defeated": regular_enemies_defeated,
	})
	_set_stage(Stage.TRANSFER)
	portal_sprite.show()
	_show_stage_banner("错误已清除 · 迁移通道开启", COLOR_CYAN)
	_set_companion_message("错误怪已清除。右侧出现陌生巡检器——这次试试独立迁移。")


func _show_stage_banner(message: String, border_color: Color = COLOR_GOLD) -> void:
	stage_banner_label.text = message
	stage_banner.add_theme_stylebox_override("panel", _style_box(Color("#17172df2"), border_color, 16, 3))
	stage_banner.modulate.a = 1.0
	stage_banner.show()
	if not test_mode:
		var banner_tween := create_tween()
		banner_tween.tween_interval(1.45)
		banner_tween.tween_property(stage_banner, "modulate:a", 0.0, 0.42)
		banner_tween.tween_callback(stage_banner.hide)


func _run_transfer_loop() -> void:
	transition_lock = true
	transfer_attempts += 1
	transfer_checked = 0
	if not content_engine_ready:
		_set_companion_message("内容包没有加载成功，请让老师重新启动课程。")
		transition_lock = false
		return
	var program := _content_program_for(transfer_content_skin_id, repeat_count, "transfer")
	last_execution_result = content_runtime.execute(program, transfer_content_skin_id, transfer_loop_target)
	last_diagnosis_id = str(last_execution_result.get("diagnosis", {}).get("id", "INVALID_PROGRAM"))
	for trace_event in last_execution_result.get("trace", []):
		var event_name := str(trace_event.get("event_name", ""))
		if event_name == "action_effect_applied":
			var target_index := int(trace_event.get("target_index", -1))
			transfer_checked = maxi(transfer_checked, target_index + 1)
			trace_label.text = "%s轨迹：第 %d / %d 个目标" % [transfer_action_name, target_index + 1, repeat_count]
			_spawn_world_motes(_transfer_target_position(target_index) + Vector2(0, -24), 10, COLOR_GOLD, 64.0)
			_play_sfx("res://assets/sounds/coin-b.ogg")
		elif event_name == "action_no_target":
			overflow_pulse = 1.0
			_play_sfx("res://assets/sounds/error-b.ogg")
		if not test_mode:
			await get_tree().create_timer(0.36).timeout
	_log_learning_event("transfer_run", "transfer", {
		"skin_id": transfer_content_skin_id,
		"variant_id": active_variant_id,
		"program": program,
		"repeat_count": repeat_count,
		"target_count": transfer_loop_target,
		"attempt_index": transfer_attempts,
		"first_attempt": transfer_attempts == 1,
		"diagnosis_id": last_diagnosis_id,
		"trace_summary": content_runtime.trace_summary(last_execution_result),
	})
	if last_diagnosis_id == "SUCCESS":
		_set_companion_message("你没有看到提示词，却让同一结构在陌生装置里生效了。现在给它一个正式名字。")
		_show_stage_banner("迁移成功 · 同一条规律在新世界生效", COLOR_CYAN)
		if not test_mode:
			await get_tree().create_timer(1.15).timeout
		_reveal_loop_concept()
	else:
		var transfer_feedback := "%s停下了。这里不公布答案，比较目标数量与实际执行轨迹。" % transfer_console_name
		if last_diagnosis_id == "COUNT_TOO_LARGE":
			transfer_feedback = "%d 个目标都完成了，但多出的%s没有对象。把程序收得更准确一些。" % [transfer_loop_target, transfer_action_name]
		_set_companion_message(transfer_feedback)
	transition_lock = false


func _reveal_loop_concept() -> void:
	stage = Stage.CONCEPT
	program_mode = "concept"
	learning_phase = LearningPhase.CONCEPT_REVEAL
	concept_revealed = true
	code_panel.show()
	code_title.text = "你刚才创造的结构"
	code_layer_label.text = "第 4 层 · C 语言代码"
	trace_label.text = "重复执行同一段动作的结构，叫作“循环”。"
	c_code_label.text = "for (int i = 0; i < %d; i++) {\n    grow();\n}" % main_loop_target
	command_info_label.text = "世界直觉 → 自然语言 → 积木结构 → C 代码"
	_set_program_step(3)
	for i in range(main_loop_target):
		beacon_lit[i] = true
		_update_beacon_sprite(i)
	_set_restored_alpha(1.0)
	companion_level_label.text = "小核桃 · Lv.2 · 学习伙伴"
	_set_companion_message("你刚才使用的结构叫循环。代码只是把你已经理解的规律写得更精确。", true)
	_show_stage_banner("概念命名 · 循环", COLOR_GOLD)
	_log_learning_event("concept_revealed", "concept", {
		"concept_id": str(content_runtime.manifest.get("concept", {}).get("concept_id", "CONCEPT-LOOP-COUNT")),
		"code_layer": "c_language_code",
	})
	_update_objective()


func _request_hint() -> void:
	if stage == Stage.PROGRAM and program_mode == "main":
		if xiao_hetao_request_in_flight:
			return
		hint_requests += 1
		var hint_level := mini(hint_requests, 5)
		_update_hint_dots(hint_level)
		var local_message := _local_main_hint(hint_level)
		_log_learning_event("hint_requested", "program", {
			"hint_level": hint_level,
			"diagnosis_id": last_diagnosis_id,
			"answer_revealed": hint_level >= 5,
			"program": _current_program_text(),
		})
		if hint_level >= 5:
			_apply_level_five_hint()
		_request_xiao_hetao_hint(local_message)
	elif stage == Stage.PROGRAM and program_mode == "transfer":
		_set_companion_message("这是迁移任务。我只帮你重读目标：%s" % (transfer_objective if not transfer_objective.is_empty() else "需要依次完成 %d 个目标" % transfer_loop_target))
	elif stage == Stage.COMBAT:
		_set_companion_message("移动躲开错误怪，点击它们或按空格发射光种。")
	elif stage == Stage.BOSS:
		if boss_combat_active:
			_set_companion_message("护盾已经解除。保持移动，点击守门者或按空格自动瞄准。")
		else:
			_set_companion_message("回放执行轨迹：第 1、3 拍出现护盾。检查条件块在什么状态下允许攻击。")
	else:
		_set_companion_message("先完成眼前这一小步。我一直在旁边。")


func _local_main_hint(level: int) -> String:
	if content_engine_ready:
		for hint in content_runtime.manifest.get("hint_policy", []):
			if int(hint.get("level", 0)) == level:
				return str(hint.get("template", "")).replace("{main_target}", str(main_loop_target)).replace("{main_entity}", main_entity_name).replace("{main_action}", main_action_name)
	var messages := [
		"你愿意求助很好。先确认目标：你希望所有%s都完成变化，对吗？" % main_entity_name,
		"观察运行结果：哪一颗没有按预期变化？先比较亮起数量和目标数量。",
		"“%s”动作已经有效，可能出错的是橙色结构里的执行次数。" % main_action_name,
		"看执行轨迹：每执行一次只亮一颗。补齐最后一颗所需的那一步。",
		"完整结构是“重复 %d 次：%s”。这次会标记为需要复练，仍由你亲手运行。" % [main_loop_target, main_action_name],
	]
	return messages[clampi(level - 1, 0, messages.size() - 1)]


func _apply_level_five_hint() -> void:
	needs_review = true
	last_program_change = "查看了完整结构，等待学生亲手修改"


func _current_program_text() -> String:
	if learning_phase == LearningPhase.SINGLE_ACTION:
		return "%s一次" % main_action_name
	if not action_selected:
		return "重复 ? 次 { 空槽 }"
	return "重复 %d 次 { %s }" % [repeat_count, transfer_action_name if program_mode == "transfer" else main_action_name]


func _detected_error_type() -> String:
	if not observation_done:
		return "尚未观察目标"
	if not prediction_done:
		return "尚未形成预测"
	if not single_action_tried:
		return "尚未运行单次动作"
	if not action_selected:
		return "动作尚未放入重复结构"
	if learning_phase == LearningPhase.COUNTERFACTUAL and repeat_count != main_loop_target - 1:
		return "反事实次数尚未改为%d" % (main_loop_target - 1)
	if repeat_count < main_loop_target:
		return "执行次数偏少"
	if repeat_count > main_loop_target:
		return "执行次数偏多"
	return "未发现确定性错误"


func _setup_xiao_hetao_ai() -> void:
	var configured_endpoint := OS.get_environment("XIAO_HETAO_AI_ENDPOINT").strip_edges()
	if not configured_endpoint.is_empty():
		xiao_hetao_ai_endpoint = configured_endpoint
	_ensure_xiao_hetao_student_id()
	xiao_hetao_request = HTTPRequest.new()
	xiao_hetao_request.name = "XiaoHetaoAIRequest"
	xiao_hetao_request.timeout = XIAO_HETAO_AI_TIMEOUT_SECONDS
	add_child(xiao_hetao_request)
	xiao_hetao_request.request_completed.connect(_on_xiao_hetao_request_completed)
	if active_variant_id.is_empty() and not test_mode and not capture_mode:
		review_assignment_request = HTTPRequest.new()
		review_assignment_request.name = "ReviewAssignmentRequest"
		review_assignment_request.timeout = 4.0
		add_child(review_assignment_request)
		review_assignment_request.request_completed.connect(_on_review_assignment_completed)
		var assignment_endpoint := OS.get_environment("XIAO_HETAO_REVIEW_ASSIGNMENT_ENDPOINT").strip_edges()
		if assignment_endpoint.is_empty():
			assignment_endpoint = REVIEW_ASSIGNMENT_DEFAULT_ENDPOINT
		review_assignment_request.request("%s?student_id=%s" % [assignment_endpoint, xiao_hetao_student_id.uri_encode()])


func _on_review_assignment_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		return
	if str(parsed.get("content_version", "")) != str(content_metadata.get("version", "")):
		return
	var variant_id := str(parsed.get("variant_id", ""))
	var variant := content_runtime.get_transfer_variant(variant_id)
	if variant.is_empty():
		return
	active_variant_id = variant_id
	active_variant = variant
	var variant_skin: Dictionary = active_variant.get("skin", {})
	transfer_loop_target = int(active_variant.get("params", {}).get("target_count", transfer_loop_target))
	transfer_entity_name = str(variant_skin.get("entity_name", variant_skin.get("entity_type", transfer_entity_name)))
	transfer_action_name = str(variant_skin.get("action_name", transfer_action_name))
	transfer_objective = str(variant_skin.get("objective", transfer_objective))
	transfer_scenario_frame = str(variant_skin.get("scenario_frame", transfer_scenario_frame))
	_update_objective()


func _ensure_xiao_hetao_student_id() -> void:
	if not xiao_hetao_student_id.is_empty():
		return
	var random_bytes := Crypto.new().generate_random_bytes(12)
	xiao_hetao_student_id = "student_%s" % random_bytes.hex_encode()


func _request_xiao_hetao_hint(local_fallback: String) -> void:
	xiao_hetao_fallback_message = local_fallback
	if capture_mode or (test_mode and not ai_test_mode) or not xiao_hetao_request:
		ai_fallback_responses += 1
		_set_companion_message(local_fallback)
		return

	var payload := {
		"student_id": xiao_hetao_student_id,
		"unit_id": str(content_metadata.get("unit_id", "")),
		"content_version": str(content_metadata.get("version", "")),
		"content_hash": str(content_metadata.get("content_hash", "")),
		"age_band": "8-12",
		"stage": "main_loop",
		"repeat_count": repeat_count,
		"lit_targets": _lit_beacon_count(),
		"failed_attempts": main_run_attempts,
		"hint_requests": hint_requests,
		"hint_level": mini(maxi(hint_requests, 1), 5),
		"observation_done": observation_done,
		"action_selected": action_selected,
		"action_name": main_action_name if action_selected else "未选择",
		"learning_phase": LearningPhase.keys()[learning_phase].to_lower(),
		"current_program": _current_program_text(),
		"last_change": last_program_change,
		"error_type": _detected_error_type(),
		"diagnosis_id": last_diagnosis_id,
		"execution_trace_summary": content_runtime.trace_summary(last_execution_result) if not last_execution_result.is_empty() else {},
		"prediction": prediction_buttons[prediction_choice].text if prediction_choice >= 0 else "尚未预测",
		"needs_review": needs_review,
	}
	xiao_hetao_request_in_flight = true
	hint_button.disabled = true
	hint_button.text = "思考中…"
	_set_companion_message("让我看看你刚才是怎么尝试的……")
	var request_error := xiao_hetao_request.request(
		xiao_hetao_ai_endpoint,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if request_error != OK:
		_finish_xiao_hetao_request(false, "")


func _on_xiao_hetao_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	var message := ""
	var source := ""
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if parsed is Dictionary:
			message = str(parsed.get("message", "")).strip_edges().left(80)
			source = str(parsed.get("source", ""))
	_finish_xiao_hetao_request(not message.is_empty(), message, source)


func _finish_xiao_hetao_request(success: bool, message: String, source: String = "") -> void:
	xiao_hetao_request_in_flight = false
	if hint_button:
		hint_button.disabled = false
		hint_button.text = "提示  H"
	var still_relevant := stage == Stage.PROGRAM and program_mode == "main"
	if success:
		ai_server_responses += 1
		if source == "deepseek":
			ai_deepseek_responses += 1
			if companion_level_label and stage == Stage.PROGRAM:
				companion_level_label.text = "小核桃 · Lv.1 · AI在线"
		if still_relevant:
			_set_companion_message(message)
	else:
		ai_fallback_responses += 1
		if still_relevant:
			_set_companion_message(xiao_hetao_fallback_message)
	_log_learning_event("hint_delivered", "program", {
		"hint_level": mini(maxi(hint_requests, 1), 5),
		"source": source if success and not source.is_empty() else "local_fallback",
		"answer_revealed": hint_requests >= 5,
		"needs_review": needs_review,
	})


func _spawn_buglings() -> void:
	_clear_enemies()
	var positions := [Vector2(360, 245), Vector2(640, 220), Vector2(920, 245)]
	for i in range(positions.size()):
		var sprite := Sprite2D.new()
		sprite.texture = enemy_texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = Vector2(3.3, 3.3)
		var enemy_color: Color = [Color("#d78aff"), Color("#ff8f8f"), Color("#8fcbff")][i]
		sprite.modulate = enemy_color
		sprite.position = positions[i]
		sprite.z_index = 10
		add_child(sprite)
		enemies.append({
			"node": sprite,
			"position": positions[i],
			"hp": 2,
			"max_hp": 2,
			"speed": 38.0 + i * 7.0,
			"base_color": enemy_color,
			"hit_flash": 0.0,
			"is_boss": false,
		})
		_spawn_world_motes(positions[i], 14, enemy_color, 96.0)
	_play_sfx("res://assets/sounds/spawn.ogg")
	_show_stage_banner("调试战 · 清除 3 只错误怪", COLOR_CORAL)
	player_energy = PLAYER_MAX_ENERGY
	energy_bar.value = player_energy
	_update_objective()


func _update_combat(delta: float) -> void:
	if not _combat_controls_active():
		return

	for enemy in enemies:
		enemy.hit_flash = maxf(0.0, float(enemy.hit_flash) - delta)
		enemy.node.modulate = Color.WHITE if float(enemy.hit_flash) > 0.0 else enemy.base_color
		var enemy_pos: Vector2 = enemy.position
		var distance := enemy_pos.distance_to(player_position)
		var contact_radius := float(enemy.get("contact_radius", 70.0))
		if distance > contact_radius:
			enemy_pos = enemy_pos.move_toward(player_position, float(enemy.speed) * delta)
			enemy.position = enemy_pos
			enemy.node.position = enemy_pos
		elif touch_cooldown <= 0.0 and player_invulnerability <= 0.0:
			player_health -= 1
			health_bar.value = player_health
			touch_cooldown = 1.2
			player_invulnerability = 1.2
			player_hit_flash = 0.32
			var push_direction := enemy_pos.direction_to(player_position)
			player_position += push_direction * 62.0
			_spawn_hit_sparks(player_position, COLOR_CORAL, 12)
			_play_sfx("res://assets/sounds/hurt-a.ogg")
			_set_companion_message("没关系，先拉开距离再发射。错误是可以被调试的。")
			if player_health <= 0:
				player_health = 5
				health_bar.value = player_health
				player_position = Vector2(640, 505)
				player_invulnerability = 2.2
				_show_stage_banner("小核桃已把你重启到安全点", COLOR_CYAN)
				_set_companion_message("失败不会清空进度。我帮你回到安全点，我们换个节奏再试。")

	for i in range(projectiles.size() - 1, -1, -1):
		var projectile := projectiles[i]
		projectile.position += projectile.velocity * delta
		projectile.life -= delta
		var hit := false
		for j in range(enemies.size() - 1, -1, -1):
			var hit_radius := float(enemies[j].get("hit_radius", 30.0))
			if projectile.position.distance_to(enemies[j].position) < hit_radius:
				enemies[j].hp -= 1
				enemies[j].hit_flash = 0.16
				if bool(enemies[j].get("is_boss", false)):
					boss_health = int(enemies[j].hp)
					boss_health_bar.value = boss_health
					boss_hits_landed += 1
				var knock_direction: Vector2 = player_position.direction_to(enemies[j].position)
				enemies[j].position += knock_direction * 14.0
				enemies[j].node.position = enemies[j].position
				_spawn_hit_sparks(projectile.position, COLOR_GOLD, 9)
				_play_sfx("res://assets/sounds/enemy_hurt_1.ogg")
				hit = true
				if int(enemies[j].hp) <= 0:
					_spawn_world_motes(enemies[j].position, 18, enemies[j].base_color, 132.0)
					_play_sfx("res://assets/sounds/explosion-a.ogg")
					if bool(enemies[j].get("is_boss", false)):
						enemies[j].node.hide()
					else:
						regular_enemies_defeated += 1
						enemies[j].node.queue_free()
					enemies.remove_at(j)
					_update_objective()
				break
		if hit or float(projectile.life) <= 0.0:
			projectiles.remove_at(i)

	if enemies.is_empty():
		if stage == Stage.COMBAT and weapon_unlocked:
			_finish_regular_combat()
		elif stage == Stage.BOSS and boss_combat_active:
			_finish_boss_combat()


func _shoot_at(target: Vector2) -> void:
	if not _combat_controls_active() or shot_cooldown > 0.0:
		return
	if player_energy < 1.0:
		_set_companion_message("能量正在回充。先移动躲开，等蓝色能量条恢复。")
		return
	var direction := player_position.direction_to(target)
	if direction.length() < 0.1:
		direction = Vector2.UP
	projectiles.append({
		"position": player_position + direction * 26.0,
		"velocity": direction * 520.0,
		"life": 1.4,
	})
	shot_cooldown = 0.22
	player_energy -= 1.0
	energy_bar.value = player_energy
	energy_regen_timer = 0.0
	_play_sfx("res://assets/sounds/shoot-c.ogg")


func _nearest_enemy_position() -> Vector2:
	if enemies.is_empty():
		return player_position + Vector2.UP * 200.0
	var nearest: Vector2 = enemies[0].position
	var best := player_position.distance_squared_to(nearest)
	for enemy in enemies:
		var distance := player_position.distance_squared_to(enemy.position)
		if distance < best:
			best = distance
			nearest = enemy.position
	return nearest


func _start_boss() -> void:
	stage = Stage.BOSS
	boss_round = 0
	boss_health = 2
	boss_attempts = 0
	boss_debug_observed = false
	boss_condition_weak_only = false
	boss_debug_phase = -1
	boss_weak_open = false
	boss_blocked_hits = 0
	boss_debug_clear = false
	boss_combat_clear = false
	boss_combat_active = false
	boss_hits_landed = 0
	_clear_enemies()
	boss_health_bar.max_value = 2
	boss_health_bar.value = boss_health
	boss_panel.show()
	boss_guardian_sprite.show()
	companion_panel.hide()
	tutorial_panel.hide()
	interaction_label.hide()
	stage_banner.hide()
	_update_boss_debug_ui()
	_update_objective()
	_play_sfx("res://assets/sounds/spawn.ogg")
	if not test_mode:
		await get_tree().create_timer(0.15).timeout


func _update_boss_debug_ui() -> void:
	boss_title.text = "守门者 · Debug 战"
	if boss_condition_weak_only:
		boss_question_label.text = "重复 4 次 {\n  如果 弱点暴露：攻击();\n}"
	else:
		boss_question_label.text = "缺陷程序：重复 4 次 { 攻击(); }"
	boss_feedback_label.text = "先运行，不猜答案。观察：护盾 → 弱点 → 护盾 → 弱点。"
	boss_feedback_label.add_theme_color_override("font_color", COLOR_MUTED)
	boss_option_buttons[0].text = "▶ 运行缺陷程序，观察真实结果"
	boss_option_buttons[0].visible = not boss_debug_observed
	boss_option_buttons[1].text = "条件块：%s" % ("仅在弱点暴露时攻击" if boss_condition_weak_only else "每一拍都攻击（点击修改）")
	boss_option_buttons[1].visible = boss_debug_observed
	boss_option_buttons[2].text = "▶ 运行修改后的程序"
	boss_option_buttons[2].visible = boss_debug_observed and boss_condition_weak_only
	for button in boss_option_buttons:
		button.disabled = transition_lock
	aid_button.visible = boss_debug_observed and companion_aid_available and not companion_aid_used


func _boss_debug_action(index: int) -> void:
	if stage != Stage.BOSS or transition_lock:
		return
	match index:
		0:
			await _run_boss_debug_program()
		1:
			boss_condition_weak_only = not boss_condition_weak_only
			last_program_change = "Boss 条件改为：%s" % ("仅弱点暴露时攻击" if boss_condition_weak_only else "每一拍攻击")
			_update_boss_debug_ui()
			boss_feedback_label.text = "条件已经写进程序。重新运行，让世界验证它。"
			boss_feedback_label.add_theme_color_override("font_color", COLOR_CYAN)
		2:
			await _run_boss_debug_program()


func _run_boss_debug_program() -> void:
	transition_lock = true
	boss_blocked_hits = 0
	boss_health = 2
	boss_health_bar.value = boss_health
	for button in boss_option_buttons:
		button.disabled = true
	for beat in range(4):
		boss_debug_phase = beat
		boss_weak_open = beat % 2 == 1
		boss_title.text = "执行追踪 · 第 %d / 4 拍" % (beat + 1)
		var should_attack := boss_weak_open if boss_condition_weak_only else true
		if boss_weak_open:
			boss_feedback_label.text = "第 %d 拍：弱点暴露%s" % [beat + 1, " → attack()" if should_attack else " → 跳过"]
			boss_feedback_label.add_theme_color_override("font_color", COLOR_GOLD)
		else:
			boss_feedback_label.text = "第 %d 拍：护盾开启%s" % [beat + 1, " → attack() 被反弹" if should_attack else " → 条件为假，安全跳过"]
			boss_feedback_label.add_theme_color_override("font_color", COLOR_CYAN if not should_attack else COLOR_CORAL)
		queue_redraw()
		if not test_mode:
			await get_tree().create_timer(0.34).timeout
		if should_attack:
			if boss_weak_open:
				boss_health -= 1
				boss_health_bar.value = boss_health
				_spawn_world_motes(boss_guardian_sprite.position, 18, COLOR_GOLD, 132.0)
				_play_sfx("res://assets/sounds/explosion-b.ogg")
			else:
				boss_blocked_hits += 1
				player_health = maxi(1, player_health - 1)
				health_bar.value = player_health
				_spawn_hit_sparks(boss_guardian_sprite.position, COLOR_CORAL, 12)
				_play_sfx("res://assets/sounds/error-c.ogg")
		if not test_mode:
			await get_tree().create_timer(0.26).timeout

	boss_debug_phase = -1
	boss_weak_open = false
	queue_redraw()
	_log_learning_event("boss_debug_run", "boss", {
		"condition_weak_only": boss_condition_weak_only,
		"blocked_hits": boss_blocked_hits,
		"weak_point_hits": 2 - boss_health,
		"success": boss_condition_weak_only and boss_blocked_hits == 0 and boss_health <= 0,
	})
	if boss_condition_weak_only and boss_blocked_hits == 0 and boss_health <= 0:
		boss_debug_clear = true
		boss_feedback_label.text = "护盾阶段全部跳过，两次攻击都命中弱点。护盾已经解除。"
		boss_feedback_label.add_theme_color_override("font_color", COLOR_MINT)
		transition_lock = false
		if not test_mode:
			await get_tree().create_timer(0.72).timeout
		_enter_boss_combat()
		return

	boss_attempts += 1
	boss_total_errors += 1
	boss_debug_observed = true
	boss_health = 2
	boss_health_bar.value = boss_health
	_update_boss_debug_ui()
	boss_feedback_label.text = "第 1、3 拍撞上护盾，伤害被回滚。修改攻击条件，再运行。"
	boss_feedback_label.add_theme_color_override("font_color", COLOR_CORAL)
	transition_lock = false
	for button in boss_option_buttons:
		button.disabled = false


func _enter_boss_combat() -> void:
	boss_combat_active = true
	boss_combat_clear = false
	boss_health = BOSS_COMBAT_MAX_HEALTH
	boss_hits_landed = 0
	boss_weak_open = true
	boss_guardian_sprite.position = Vector2(930, 285)
	boss_guardian_sprite.modulate = Color.WHITE
	boss_guardian_sprite.show()
	boss_health_bar.max_value = BOSS_COMBAT_MAX_HEALTH
	boss_health_bar.value = boss_health
	boss_panel.position = Vector2(420, 102)
	boss_panel.size = Vector2(440, 126)
	boss_title.text = "守门者 · 护盾已解除"
	boss_question_label.hide()
	boss_feedback_label.text = "移动躲避 · 点击守门者 / 空格自动瞄准"
	boss_feedback_label.add_theme_color_override("font_color", COLOR_GOLD)
	for button in boss_option_buttons:
		button.hide()
	aid_button.hide()
	boss_panel.show()
	player_position = Vector2(640, 520)
	player_sprite.position = player_position
	player_health = maxi(player_health, 3)
	player_energy = PLAYER_MAX_ENERGY
	health_bar.value = player_health
	energy_bar.value = player_energy
	status_panel.show()
	weapon_badge.show()
	weapon_unlocked = true
	enemies.append({
		"node": boss_guardian_sprite,
		"position": boss_guardian_sprite.position,
		"hp": BOSS_COMBAT_MAX_HEALTH,
		"max_hp": BOSS_COMBAT_MAX_HEALTH,
		"speed": 31.0,
		"base_color": Color.WHITE,
		"hit_flash": 0.0,
		"is_boss": true,
		"hit_radius": 64.0,
		"contact_radius": 104.0,
	})
	_show_stage_banner("Debug 成功 · 亲手完成战斗收束", COLOR_GOLD)
	_set_companion_message("条件程序已经解除护盾。现在由你移动和射击，完成最后的世界修复。")
	_log_learning_event("boss_combat_started", "boss", {
		"boss_debug_clear": boss_debug_clear,
		"boss_health": BOSS_COMBAT_MAX_HEALTH,
		"required_for_progress": true,
	})
	_update_objective()


func _finish_boss_combat() -> void:
	if not boss_combat_active or boss_combat_clear:
		return
	boss_combat_active = false
	boss_combat_clear = true
	weapon_unlocked = false
	projectiles.clear()
	boss_guardian_sprite.hide()
	boss_panel.hide()
	status_panel.hide()
	weapon_badge.hide()
	_log_learning_event("boss_combat_cleared", "boss", {
		"boss_debug_clear": boss_debug_clear,
		"boss_combat_clear": true,
		"hits_landed": boss_hits_landed,
	})
	_complete_demo()


func _use_companion_aid() -> void:
	if companion_aid_used or stage != Stage.BOSS or transition_lock:
		return
	companion_aid_used = true
	aid_button.hide()
	boss_feedback_label.text = "轨迹回放：护盾出现在第 1、3 拍。检查条件块何时允许 attack()。"
	boss_feedback_label.add_theme_color_override("font_color", COLOR_CYAN)
	_play_sfx("res://assets/sounds/select-a.ogg")


func _complete_demo() -> void:
	stage = Stage.COMPLETE
	_set_restored_alpha(1.0)
	for i in range(main_loop_target):
		beacon_lit[i] = true
		_update_beacon_sprite(i)
	boss_panel.hide()
	boss_guardian_sprite.hide()
	portal_sprite.hide()
	companion_panel.hide()
	stage_banner.hide()
	companion_level_label.text = "小核桃 · Lv.2 · 循环伙伴"
	var aid_record := "回放了 1 次执行轨迹" if companion_aid_used else "未使用轨迹回放"
	var optional_record := "已完成（尝试 %d 次）" % optional_puzzle_attempts if optional_puzzle_completed else "选择跳过"
	var ai_record := "，其中 DeepSeek 个性化 %d 次" % ai_deepseek_responses if ai_deepseek_responses > 0 else ""
	var review_record := "需要安排一次同知识点复练" if needs_review else "已独立完成，无强制复练标记"
	summary_body.text = "本关学习证据\n\n" \
		+ "1. 感知与预测：观察 %d 颗休眠光种，并先预测单次生长结果。\n" % main_loop_target \
		+ "2. 解谜验证：逐行追踪世界变化，完成 %d→%d 反事实（运行 %d 次，求助 %d 次%s）。\n" % [main_loop_target, main_loop_target - 1, main_run_attempts, hint_requests, ai_record] \
		+ "3. 必经战斗：清除 %d 只错误怪，战斗完成标记已写入。\n" % regular_enemies_defeated \
		+ "4. 陌生迁移：独立控制巡检器检查 %d 个目标（尝试 %d 次）。\n" % [transfer_loop_target, transfer_attempts] \
		+ "5. 抽象命名：从世界行为、自然语言、积木结构显形到 C 语言 for 代码。\n" \
		+ "6. Boss 双阶段：修复攻击条件，再亲手命中 %d 次完成战斗收束（错误运行 %d 次，%s）。\n" % [boss_hits_landed, boss_total_errors, aid_record] \
		+ "7. 自由探索：记忆晶体谜题%s；%s。\n\n" % [optional_record, review_record] \
		+ "世界留痕：花园永久记住了修复状态，小核桃升至 Lv.2。"
	summary_panel.show()
	_spawn_world_motes(Vector2(640, 360), 64, COLOR_GOLD, 360.0)
	_play_sfx("res://assets/sounds/chest.ogg")
	_update_objective()
	_log_learning_event("session_completed", "complete", {
		"main_run_attempts": main_run_attempts,
		"hint_requests": hint_requests,
		"counterfactual_pass": counterfactual_done,
		"transfer_attempts": transfer_attempts,
		"concept_revealed": concept_revealed,
		"boss_errors": boss_total_errors,
		"puzzle_clear": puzzle_clear,
		"combat_clear": combat_clear,
		"boss_debug_clear": boss_debug_clear,
		"boss_combat_clear": boss_combat_clear,
		"optional_explore_completed": optional_puzzle_completed,
		"needs_review": needs_review,
	})
	_save_memory(true)
	if not test_mode:
		await get_tree().create_timer(0.1).timeout


func _set_stage(next_stage: Stage) -> void:
	stage = next_stage
	_log_learning_event("stage_entered", Stage.keys()[stage].to_lower(), {})
	match stage:
		Stage.ARRIVAL:
			tutorial_panel.show()
			tutorial_label.text = "只先学一个操作\nW A S D / 方向键移动"
			if returning_player:
				_set_companion_message("你回来了。花园还记得上次的光；我已切到练习模式，陪你重新挑战。")
			else:
				_set_companion_message("欢迎来到数据花园。我会陪你试，但不会替你做。")
		Stage.OBSERVE:
			tutorial_panel.show()
			tutorial_label.text = "沿石桥进入花园\n靠近发光的中央法则台"
			_set_companion_message("你已经会移动了。现在去看看，为什么花园只有一半醒着。")
		Stage.COMBAT:
			tutorial_panel.show()
			tutorial_label.text = "解谜获得武器\n移动躲避 · 点击目标 / 空格发射"
		Stage.TRANSFER:
			tutorial_panel.show()
			tutorial_label.text = "主线：前往右上巡检器\n可选：左侧记忆晶体"
			optional_memory_sprite.show()
		Stage.CONCEPT:
			tutorial_panel.hide()
		Stage.BOSS:
			tutorial_panel.hide()
			optional_memory_sprite.hide()
		Stage.COMPLETE:
			tutorial_panel.hide()
			optional_memory_sprite.visible = optional_puzzle_completed
	_update_objective()


func _update_objective() -> void:
	match stage:
		Stage.ARRIVAL:
			objective_label.text = "进入%s" % main_world_name
			progress_label.text = "新手引导 1 / 3 · 移动"
		Stage.OBSERVE:
			objective_label.text = "观察失灵的世界法则"
			progress_label.text = "新手引导 2 / 3 · 靠近并按 E"
		Stage.PROGRAM:
			if program_mode == "transfer":
				objective_label.text = transfer_objective if not transfer_objective.is_empty() else "把同一结构迁移到%s" % transfer_world_name
				progress_label.text = "%s %d 个目标 · 已尝试 %d 次" % [transfer_action_name, transfer_loop_target, transfer_attempts]
			else:
				objective_label.text = main_objective if not main_objective.is_empty() else "让 %d 个%s依次完成变化" % [main_loop_target, main_entity_name]
				var phase_names := ["观察", "预测", "单次验证", "编排与追踪", "反事实 %d→%d" % [main_loop_target, main_loop_target - 1], "迁移", "概念命名"]
				progress_label.text = "%s · 点亮 %d / %d · 求助 %d 次" % [phase_names[learning_phase], _lit_beacon_count(), main_loop_target, hint_requests]
		Stage.COMBAT:
			objective_label.text = "用光种发射器清除错误怪"
			progress_label.text = "剩余 %d 只 · 空格自动瞄准" % enemies.size()
		Stage.TRANSFER:
			objective_label.text = "前往%s" % transfer_world_name
			progress_label.text = "不提示结构名称 · %d 个目标" % transfer_loop_target
		Stage.CONCEPT:
			objective_label.text = "给刚才的结构一个名字"
			progress_label.text = "第 4 层 · C 语言代码已显形"
		Stage.BOSS:
			if boss_combat_active:
				objective_label.text = "护盾已解除 · 完成战斗收束"
				progress_label.text = "守门者能量 %d / %d · 移动躲避并射击" % [boss_health, BOSS_COMBAT_MAX_HEALTH]
			else:
				objective_label.text = "Debug 守门者的攻击程序"
				progress_label.text = "观察轨迹 → 修改条件 → 重新运行"
		Stage.COMPLETE:
			objective_label.text = "%s已记住你的规则" % main_world_name
			progress_label.text = "循环掌握 · 迁移验证通过"


func _set_companion_message(message: String, persistent: bool = false) -> void:
	if companion_label:
		companion_label.text = message
		companion_panel.show()
		companion_message_deadline = 0 if persistent else Time.get_ticks_msec() + 7800


func _play_sfx(path: String) -> void:
	if test_mode or capture_mode:
		return
	SFXPlayer.play(load(path))


func _update_hint_dots(count: int) -> void:
	for i in range(hint_dots.size()):
		hint_dots[i].color = COLOR_CORAL if i < mini(count, 5) else Color("#d6d0df")
	_update_objective()


func _update_beacon_sprite(index: int) -> void:
	if index < 0 or index >= beacon_sprites.size():
		return
	var dormant_colors := [Color("#bda5e8"), Color("#f2a89b"), Color("#99c7e6"), Color("#b8d7a2")]
	beacon_sprites[index].modulate = Color.WHITE if beacon_lit[index] else dormant_colors[index % dormant_colors.size()] * 0.72
	var base_scale := beacon_base_scales[index] if index < beacon_base_scales.size() else Vector2(0.072, 0.072)
	beacon_sprites[index].scale = base_scale * 1.14 if beacon_lit[index] else base_scale
	_update_objective()


func _lit_beacon_count() -> int:
	var count := 0
	for lit in beacon_lit:
		if lit:
			count += 1
	return count


func _clear_enemies() -> void:
	for enemy in enemies:
		if is_instance_valid(enemy.node):
			enemy.node.queue_free()
	enemies.clear()


func _load_memory() -> void:
	if test_mode or capture_mode:
		return
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		returning_player = bool(parsed.get("garden_restored", false))
		xiao_hetao_student_id = str(parsed.get("ai_student_id", ""))
		needs_review = bool(parsed.get("needs_review", false))


func _save_memory(completed: bool) -> void:
	if test_mode or capture_mode:
		return
	var data := {
		"garden_restored": completed or returning_player,
		"walnut_level": 2 if completed or returning_player else 1,
		"main_loop_attempts": main_attempts,
		"main_run_attempts": main_run_attempts,
		"hint_requests": hint_requests,
		"transfer_attempts": transfer_attempts,
		"boss_errors": boss_total_errors,
		"companion_aid_used": companion_aid_used,
		"optional_puzzle_completed": optional_puzzle_completed,
		"optional_puzzle_attempts": optional_puzzle_attempts,
		"needs_review": needs_review,
		"concept_revealed": concept_revealed,
		"counterfactual_done": counterfactual_done,
		"puzzle_clear": puzzle_clear,
		"combat_clear": combat_clear,
		"boss_debug_clear": boss_debug_clear,
		"boss_combat_clear": boss_combat_clear,
		"regular_enemies_defeated": regular_enemies_defeated,
		"boss_hits_landed": boss_hits_landed,
		"content_unit_id": str(content_metadata.get("unit_id", "")),
		"content_version": str(content_metadata.get("version", "")),
		"content_hash": str(content_metadata.get("content_hash", "")),
		"ai_student_id": xiao_hetao_student_id,
		"ai_server_responses": ai_server_responses,
		"ai_deepseek_responses": ai_deepseek_responses,
		"ai_fallback_responses": ai_fallback_responses,
		"saved_at": Time.get_datetime_string_from_system(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))


func _run_smoke_test() -> void:
	# 用真实控制器方法验证完整认知链，而不是只检查按钮能否点击。
	test_mode = true
	assert(content_engine_ready)
	assert(audio_toggle_button)
	var initial_audio_state := Global.is_audio_enabled()
	_on_audio_toggled(not initial_audio_state)
	assert(Global.is_audio_enabled() == not initial_audio_state)
	assert(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) == initial_audio_state)
	assert(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")) == initial_audio_state)
	_on_audio_toggled(initial_audio_state)
	assert(Global.is_audio_enabled() == initial_audio_state)
	assert(main_loop_target >= 2 and transfer_loop_target >= 2)
	assert(beacon_lit.size() == main_loop_target and beacon_positions.size() == main_loop_target)
	repeat_count = 2
	needs_review = false
	_apply_level_five_hint()
	assert(needs_review and repeat_count == 2)
	needs_review = false
	var runtime_under := content_runtime.execute(_content_program_for(main_content_skin_id, main_loop_target - 1, "contract_under"), main_content_skin_id)
	assert(runtime_under.diagnosis.id == "COUNT_TOO_SMALL")
	assert(runtime_under.completed_targets == main_loop_target - 1)
	var runtime_over := content_runtime.execute(_content_program_for(main_content_skin_id, main_loop_target + 1, "contract_over"), main_content_skin_id)
	assert(runtime_over.diagnosis.id == "COUNT_TOO_LARGE")
	assert(runtime_over.no_target_actions == 1)
	var runtime_transfer := content_runtime.execute(_content_program_for(transfer_content_skin_id, transfer_loop_target, "contract_transfer"), transfer_content_skin_id, transfer_loop_target)
	assert(runtime_transfer.diagnosis.id == "SUCCESS")
	assert(runtime_transfer.template_id == runtime_under.template_id)
	var missing_repeat_program := {
		"type": "Sequence",
		"node_id": "contract_missing_sequence",
		"children": [{"type": "Action", "node_id": "contract_missing_action", "action_id": "grow_next_seed"}],
	}
	var runtime_missing := content_runtime.execute(missing_repeat_program, main_content_skin_id)
	assert(runtime_missing.diagnosis.id == "MISSING_REPEAT")
	var runtime_wrong := content_runtime.execute(content_runtime.make_repeat_program("inspect_next_target", main_loop_target, "contract_wrong"), main_content_skin_id)
	assert(runtime_wrong.diagnosis.id == "WRONG_ACTION")
	var runtime_limited := content_runtime.execute(_content_program_for(main_content_skin_id, 120, "contract_limit"), main_content_skin_id)
	assert(runtime_limited.diagnosis.id == "STEP_LIMIT_EXCEEDED")
	var synthetic_event := learning_event_logger.log_event("program_run", "contract", {"diagnosis_id": "SUCCESS"})
	assert(synthetic_event.content_hash == content_metadata.content_hash)
	assert(synthetic_event.event_schema_version == "1.0.0")
	assert(int(synthetic_event.elapsed_ms) >= 0)
	stage = Stage.PROGRAM
	program_mode = "main"
	learning_phase = LearningPhase.WORLD_OBSERVE
	_observe_targets()
	assert(observation_done and learning_phase == LearningPhase.PREDICT)
	_choose_prediction(0)
	assert(prediction_done and learning_phase == LearningPhase.SINGLE_ACTION)
	await _run_single_growth_trial()
	assert(single_action_tried and _lit_beacon_count() == 1)
	assert(learning_phase == LearningPhase.BUILD_BLOCKS)
	_select_action()
	assert(action_selected and program_step == 3)

	repeat_count = main_loop_target
	await _run_main_loop()
	assert(stage == Stage.PROGRAM)
	assert(main_pattern_verified and learning_phase == LearningPhase.COUNTERFACTUAL)
	assert(_lit_beacon_count() == main_loop_target)
	assert(last_diagnosis_id == "SUCCESS")

	repeat_count = main_loop_target - 1
	await _run_main_loop()
	assert(counterfactual_done and puzzle_clear and stage == Stage.COMBAT)
	assert(_lit_beacon_count() == main_loop_target - 1)
	assert(not beacon_lit[main_loop_target - 1])
	assert(enemies.size() == 3 and weapon_unlocked)
	for enemy in enemies:
		enemy.hp = 1
		projectiles.append({
			"position": enemy.position,
			"velocity": Vector2.ZERO,
			"life": 1.0,
		})
	_update_combat(0.0)
	assert(combat_clear and regular_enemies_defeated == 3 and stage == Stage.TRANSFER)

	_open_optional_puzzle()
	_answer_optional_puzzle(0)
	assert(not optional_puzzle_completed)
	_answer_optional_puzzle(1)
	assert(optional_puzzle_completed)

	_show_program("transfer")
	_select_action()
	assert(program_mode == "transfer" and action_selected)
	repeat_count = transfer_loop_target - 1
	await _run_transfer_loop()
	assert(stage == Stage.PROGRAM and transfer_checked == transfer_loop_target - 1)
	assert(last_diagnosis_id == "COUNT_TOO_SMALL")
	repeat_count = transfer_loop_target
	await _run_transfer_loop()
	assert(stage == Stage.CONCEPT and concept_revealed)
	assert(last_diagnosis_id == "SUCCESS")
	assert(c_code_label.visible and "for (int i = 0; i < %d; i++)" % main_loop_target in c_code_label.text)

	await _start_boss()
	assert(stage == Stage.BOSS and not boss_debug_observed)
	await _run_boss_debug_program()
	assert(stage == Stage.BOSS and boss_debug_observed)
	assert(boss_total_errors == 1 and boss_blocked_hits == 2)
	_use_companion_aid()
	assert(companion_aid_used)
	boss_condition_weak_only = true
	_update_boss_debug_ui()
	await _run_boss_debug_program()
	assert(stage == Stage.BOSS and boss_debug_clear and boss_combat_active)
	assert(enemies.size() == 1 and not boss_combat_clear)
	enemies[0].hp = 1
	boss_health = 1
	boss_health_bar.value = 1
	projectiles.append({
		"position": enemies[0].position,
		"velocity": Vector2.ZERO,
		"life": 1.0,
	})
	_update_combat(0.0)
	assert(stage == Stage.COMPLETE)
	assert(boss_combat_clear)
	assert(summary_panel.visible)
	assert(puzzle_clear and combat_clear and counterfactual_done and concept_revealed)
	print("DATA_GARDEN_SMOKE_OK")
	_quit_after_cleanup()


func _run_ai_integration_test() -> void:
	stage = Stage.PROGRAM
	program_mode = "main"
	main_attempts = 0
	main_run_attempts = 0
	hint_requests = 0
	_request_hint()
	var deadline := Time.get_ticks_msec() + 10000
	while xiao_hetao_request_in_flight and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if xiao_hetao_request_in_flight or ai_server_responses < 1 or companion_label.text.strip_edges().is_empty():
		push_error("XIAO_HETAO_GODOT_AI_FAILED")
		get_tree().quit(1)
		return
	_log_learning_event("session_completed", "complete", {
		"main_run_attempts": 0,
		"hint_requests": hint_requests,
		"counterfactual_pass": false,
		"transfer_attempts": 0,
		"concept_revealed": false,
		"optional_explore_completed": false,
		"needs_review": false,
	})
	var event_deadline := Time.get_ticks_msec() + 10000
	while learning_event_logger and (learning_event_logger.upload_in_flight or not learning_event_logger.upload_queue.is_empty()) and Time.get_ticks_msec() < event_deadline:
		await get_tree().process_frame
	if not learning_event_logger or learning_event_logger.failed_uploads > 0 or learning_event_logger.upload_in_flight or not learning_event_logger.upload_queue.is_empty():
		push_error("LEARNING_EVENT_GODOT_UPLOAD_FAILED")
		get_tree().quit(1)
		return
	print("XIAO_HETAO_GODOT_AI_OK")
	print("LEARNING_EVENT_GODOT_OK %s" % learning_event_logger.session_id)
	_quit_after_cleanup()


func _capture_reference_state() -> void:
	# 主视觉展示代码块与世界同步执行，而不是传统全屏编辑器。
	capture_mode = true
	player_position = Vector2(640, 452)
	player_sprite.position = player_position
	companion_sprite.position = player_position + Vector2(66, -8)
	stage = Stage.PROGRAM
	program_mode = "main"
	_show_program("main")
	observation_done = true
	prediction_done = true
	prediction_choice = 0
	single_action_tried = true
	action_selected = true
	learning_phase = LearningPhase.BUILD_BLOCKS
	program_step = 3
	repeat_count = main_loop_target
	beacon_lit.fill(false)
	for i in range(mini(2, main_loop_target)):
		beacon_lit[i] = true
	_set_restored_alpha(0.36)
	for i in range(main_loop_target):
		_update_beacon_sprite(i)
	_set_program_step(3)
	_update_repeat_button()
	active_trace_index = 1
	code_layer_label.text = "第 3 层 · 积木 / 流程结构"
	trace_label.text = "高亮：第 2 / %d 次  →  grow()" % main_loop_target
	_set_companion_message("代码正在逐行高亮；每执行一次，世界中的一颗光种同步亮起。")
	_update_hint_dots(1)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var qa_dir := ProjectSettings.globalize_path("res://qa")
	DirAccess.make_dir_recursive_absolute(qa_dir)
	var output := qa_dir.path_join("data-garden-implementation.png")
	if DisplayServer.get_name() == "headless":
		push_error("Reference capture requires a rendering display: %s" % output)
		get_tree().quit(2)
		return
	var viewport_texture := get_viewport().get_texture()
	if viewport_texture == null:
		push_error("Reference capture requires a rendering display: %s" % output)
		get_tree().quit(2)
		return
	var image := viewport_texture.get_image()
	if image == null or image.is_empty():
		push_error("Reference capture returned an empty image: %s" % output)
		get_tree().quit(2)
		return
	var error := image.save_png(output)
	print("DATA_GARDEN_CAPTURE=", output, " ERROR=", error)
	if error != OK:
		get_tree().quit(2)
		return
	_quit_after_cleanup()


func _capture_flow_states() -> void:
	var qa_dir := ProjectSettings.globalize_path("res://qa/audit-current")
	DirAccess.make_dir_recursive_absolute(qa_dir)
	test_mode = true
	await _save_flow_capture(qa_dir, "01-arrival-v3.png")

	player_position = Vector2(640, 474)
	player_sprite.position = player_position
	companion_sprite.position = player_position + Vector2(62, -8)
	_show_program("main")
	await _save_flow_capture(qa_dir, "02-world-observe-v3.png")

	_observe_targets()
	await _save_flow_capture(qa_dir, "03-predict-v3.png")
	_choose_prediction(0)
	await _run_single_growth_trial()
	await _save_flow_capture(qa_dir, "04-natural-language-v3.png")

	_select_action()
	repeat_count = main_loop_target
	_update_repeat_button()
	await _save_flow_capture(qa_dir, "05-block-program-v3.png")
	await _run_main_loop()
	await _save_flow_capture(qa_dir, "06-trace-four-v3.png")

	repeat_count = main_loop_target - 1
	_update_repeat_button()
	await _run_main_loop()
	await _save_flow_capture(qa_dir, "07-counterfactual-v3.png")
	await _save_flow_capture(qa_dir, "08-combat-room-v4.png")
	regular_enemies_defeated = enemies.size()
	_clear_enemies()
	_finish_regular_combat()

	player_position = Vector2(920, 330)
	player_sprite.position = player_position
	companion_sprite.position = player_position + Vector2(-62, -8)
	_show_program("transfer")
	_select_action()
	repeat_count = transfer_loop_target
	_update_repeat_button()
	await _save_flow_capture(qa_dir, "09-transfer-v4.png")
	await _run_transfer_loop()
	await _save_flow_capture(qa_dir, "10-c-code-reveal-v4.png")

	code_panel.hide()
	await _start_boss()
	await _save_flow_capture(qa_dir, "11-debug-boss-before-v4.png")
	await _run_boss_debug_program()
	await _save_flow_capture(qa_dir, "12-debug-trace-v4.png")
	boss_condition_weak_only = true
	_update_boss_debug_ui()
	await _save_flow_capture(qa_dir, "13-debug-fixed-v4.png")
	await _run_boss_debug_program()
	await _save_flow_capture(qa_dir, "14-boss-combat-v4.png")
	enemies[0].hp = 1
	boss_health = 1
	boss_health_bar.value = 1
	projectiles.append({
		"position": enemies[0].position,
		"velocity": Vector2.ZERO,
		"life": 1.0,
	})
	_update_combat(0.0)
	await _save_flow_capture(qa_dir, "15-complete-v4.png")
	print("DATA_GARDEN_FLOW_CAPTURE=", qa_dir)
	_quit_after_cleanup()


func _save_flow_capture(qa_dir: String, filename: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var output := qa_dir.path_join(filename)
	if DisplayServer.get_name() == "headless":
		push_error("Flow capture requires a rendering display: %s" % output)
		get_tree().quit(2)
		return
	var viewport_texture := get_viewport().get_texture()
	if viewport_texture == null:
		push_error("Flow capture requires a rendering display: %s" % output)
		get_tree().quit(2)
		return
	var image := viewport_texture.get_image()
	if image == null or image.is_empty():
		push_error("Flow capture returned an empty image: %s" % output)
		get_tree().quit(2)
		return
	var error := image.save_png(output)
	if error != OK:
		push_error("Failed to save flow capture: %s" % output)
		get_tree().quit(2)


func _quit_after_cleanup() -> void:
	var tree := get_tree()
	var timer := tree.create_timer(0.08)
	timer.timeout.connect(tree.quit.bind(0))
	queue_free()


func _make_panel(rect: Rect2, color: Color, border: Color, radius: int, border_width: int = 2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", _style_box(color, border, radius, border_width))
	ui_root.add_child(panel)
	return panel


func _style_box(color: Color, border: Color, radius: int, border_width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 12
	style.content_margin_top = 10
	style.content_margin_right = 12
	style.content_margin_bottom = 10
	return style


func _make_label(text_value: String, font_size: int, color: Color, minimum: Vector2 = Vector2.ZERO) -> Label:
	var label := Label.new()
	label.text = text_value
	label.custom_minimum_size = minimum
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(text_value: String, color: Color, font_size: int) -> Button:
	var button := Button.new()
	button.text = text_value
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _style_box(color, color.lightened(0.18), 12, 2))
	button.add_theme_stylebox_override("hover", _style_box(color.lightened(0.12), COLOR_GOLD, 12, 3))
	button.add_theme_stylebox_override("pressed", _style_box(color.darkened(0.1), COLOR_CYAN, 12, 3))
	button.add_theme_stylebox_override("focus", _style_box(Color.TRANSPARENT, COLOR_CYAN, 12, 3))
	button.add_theme_stylebox_override("disabled", _style_box(Color("#4b4759"), Color("#6b657b"), 12, 2))
	return button


func _compact_action_name(value: String, maximum: int = 6) -> String:
	var text := value.strip_edges()
	if text.length() <= maximum:
		return text
	return "%s…" % text.left(maxi(1, maximum - 1))


func _action_button_text(action_name: String, placed: bool = false) -> String:
	return "%s\n%s" % ["已放入" if placed else "拖动动作", _compact_action_name(action_name)]


func _make_command_button(text_value: String, color: Color, font_size: int) -> Button:
	var button := Button.new()
	button.text = text_value
	button.clip_text = true
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var state_color := color
		var border := color.lightened(0.24)
		if state == "hover":
			state_color = color.lightened(0.12)
			border = COLOR_GOLD
		elif state == "pressed":
			state_color = color.darkened(0.12)
			border = COLOR_CYAN
		elif state == "disabled":
			state_color = Color("#4b4759")
			border = Color("#6b657b")
		var style := _style_box(state_color, border, 6, 3)
		style.shadow_color = Color("#17142ca8")
		style.shadow_size = 6
		style.shadow_offset = Vector2(0, 6)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("focus", _style_box(Color.TRANSPARENT, COLOR_CYAN, 6, 3))
	return button
