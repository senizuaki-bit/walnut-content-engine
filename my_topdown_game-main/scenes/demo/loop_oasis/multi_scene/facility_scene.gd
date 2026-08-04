class_name LoopFacilityScene
extends LoopPlayableScene

## Shared shell for the four home facilities.
##
## The shell owns only the source-room adapter, HUD, failure/retry flow and
## contract submission. Every .tscn provides an authored WorldLayout and a
## dedicated controller implements the actual world rules. No HUD control is
## allowed to complete a facility.

const SourceStage := preload("res://scenes/demo/loop_oasis/multi_scene/source_room_stage.gd")
const SEED_TEXTURE := preload("res://assets/sprites/items/data_garden_light_seed.png")
const CONSOLE_TEXTURE := preload("res://assets/sprites/items/data_garden_console.png")

const COLOR_TEXT := Color("#fff7dc")
const COLOR_MUTED := Color("#c8c8bf")
const COLOR_CYAN := Color("#70e6df")
const COLOR_CORAL := Color("#ff8173")
const COLOR_DORMANT := Color("#53656a")

@export var location_id := "farm"
@export var facility_title := "芽芽家园设施"
@export_multiline var facility_objective := "在世界中完成设施任务。"
@export var accent_color := Color("#70e6df")

var stage: SourceRoomStage
var test_mode := false
var capture_mode := false
var scene_succeeded := false
var scene_failed := false
var transition_lock := false
var failure_code := ""

var objective_label: Label
var progress_label: Label
var feedback_label: Label
var prompt_label: Label
var failure_label: Label


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	test_mode = "--facility-test" in args
	capture_mode = "--scene-capture" in args
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	stage = SourceStage.new() as SourceRoomStage
	stage.name = "SourceRoomStage"
	add_child(stage)
	await stage.build({
		"stage_id": location_id,
		"title": facility_title,
		"capture_mode": capture_mode or test_mode,
		"auto_reward_on_clear": false,
	})
	_connect_stage_signals()
	_build_facility_world()
	_build_hud()

	if bool(LoopRunState.home_flags.get(location_id, false)) and not test_mode:
		_restore_completed_facility()
	else:
		_set_feedback(_initial_feedback())

	if test_mode:
		call_deferred("_run_contract_test_and_quit")
	elif capture_mode:
		call_deferred("_capture_and_quit")


func _process(delta: float) -> void:
	if not is_instance_valid(stage):
		return
	if not scene_failed and not test_mode:
		_update_facility(delta)
	_update_hud()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if test_mode:
		return
	if event.is_action_pressed("ui_cancel"):
		_return_home()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		_retry_facility()
		get_viewport().set_input_as_handled()
		return
	if scene_failed or transition_lock:
		return
	if event.is_action_pressed("interact"):
		_handle_facility_interaction()
		get_viewport().set_input_as_handled()
		return
	_handle_facility_input(event)


func _connect_stage_signals() -> void:
	stage.player_moved.connect(_on_stage_player_moved)
	stage.player_shot.connect(_on_stage_player_shot)
	stage.enemy_spawned.connect(_on_stage_enemy_spawned)
	stage.enemy_defeated.connect(_on_stage_enemy_defeated)
	stage.room_cleared.connect(_on_stage_room_cleared)
	stage.player_defeated.connect(_on_stage_player_defeated)
	stage.chest_opened.connect(_on_stage_chest_opened)
	stage.portal_entered.connect(_on_stage_portal_entered)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "FacilityHud"
	layer.layer = 40
	add_child(layer)

	objective_label = _make_label(facility_objective, 16, COLOR_TEXT)
	objective_label.position = Vector2(240, 66)
	objective_label.size = Vector2(800, 44)
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.add_theme_color_override("font_outline_color", Color("#07090e"))
	objective_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(objective_label)

	progress_label = _make_label("", 17, accent_color)
	progress_label.position = Vector2(918, 18)
	progress_label.size = Vector2(334, 72)
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress_label.add_theme_color_override("font_outline_color", Color("#07090e"))
	progress_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(progress_label)

	feedback_label = _make_label("", 18, COLOR_TEXT)
	feedback_label.position = Vector2(245, 618)
	feedback_label.size = Vector2(790, 58)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.add_theme_color_override("font_outline_color", Color("#07090e"))
	feedback_label.add_theme_constant_override("outline_size", 7)
	layer.add_child(feedback_label)

	# Facility-specific prompt and failure text are HUD-only; neither writes progress.

	prompt_label = _make_label("", 19, COLOR_CYAN)
	prompt_label.position = Vector2(380, 556)
	prompt_label.size = Vector2(520, 44)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.add_theme_color_override("font_outline_color", Color("#07090e"))
	prompt_label.add_theme_constant_override("outline_size", 7)
	layer.add_child(prompt_label)

	var controls_label := _make_label(
		"WASD / 方向键移动 | 鼠标瞄准射击 | E 互动 | R 重试 | Esc 回芽芽家园",
		14,
		COLOR_MUTED
	)
	controls_label.position = Vector2(250, 684)
	controls_label.size = Vector2(780, 28)
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_label.add_theme_color_override("font_outline_color", Color("#07090e"))
	controls_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(controls_label)

	failure_label = _make_label("", 16, COLOR_CORAL)
	failure_label.position = Vector2(260, 505)
	failure_label.size = Vector2(760, 54)
	failure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	failure_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	failure_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	failure_label.add_theme_color_override("font_outline_color", Color("#07090e"))
	failure_label.add_theme_constant_override("outline_size", 7)
	failure_label.hide()
	layer.add_child(failure_label)


func _update_hud() -> void:
	if not is_instance_valid(progress_label):
		return
	progress_label.text = _progress_text()
	prompt_label.text = "" if scene_failed or scene_succeeded else _context_prompt()


func request_world_success() -> bool:
	if scene_succeeded or scene_failed or transition_lock:
		return false
	transition_lock = true
	var evidence := collect_completion_evidence()
	var result := submit_home_evidence(location_id, evidence)
	if not bool(result.get("ok", false)):
		transition_lock = false
		fail_facility(
			str(result.get("error", "FACILITY_CONTRACT_REJECTED")),
			str(result.get("detail", "世界行为证据未通过校验。"))
		)
		return false
	scene_succeeded = true
	transition_lock = false
	stage.complete_noncombat_room(false)
	_set_feedback(_success_feedback())
	_on_facility_succeeded()
	return true


func fail_facility(code: String, detail: String) -> void:
	if scene_succeeded or scene_failed:
		return
	scene_failed = true
	failure_code = code
	if is_instance_valid(stage):
		stage.set_player_input(false)
	if is_instance_valid(failure_label):
		failure_label.text = "%s\n[%s] 按 R 无损重试；Esc 返回芽芽家园。" % [detail, code]
		failure_label.show()
	_set_feedback("这次尝试没有写入家园进度。")
	push_error("FACILITY_WORLD_ATTEMPT_FAILED [%s/%s]: %s" % [location_id, code, detail])


func _retry_facility() -> void:
	if transition_lock:
		return
	transition_lock = true
	var error := get_tree().reload_current_scene()
	if error != OK:
		transition_lock = false
		push_error("FACILITY_RETRY_RELOAD_FAILED [%s]: %s" % [location_id, error])


func _restore_completed_facility() -> void:
	scene_succeeded = true
	_restore_facility_world()
	stage.reveal_portal_for_completed_room()
	_set_feedback("这里已经完成。打开的出口可以回到芽芽家园。")


func _return_home() -> void:
	if transition_lock:
		return
	transition_lock = true
	stage.set_player_input(false)
	var result := navigate_to("home")
	if not bool(result.get("ok", false)):
		transition_lock = false
		stage.set_player_input(true)


func _on_stage_player_moved(total_distance: float) -> void:
	_on_facility_player_moved(total_distance)


func _on_stage_player_shot(total_shots: int) -> void:
	_on_facility_player_shot(total_shots)


func _on_stage_enemy_spawned(enemy: Enemy, index: int, boss: bool) -> void:
	_on_facility_enemy_spawned(enemy, index, boss)


func _on_stage_enemy_defeated(total_defeated: int, total_spawned: int) -> void:
	_on_facility_enemy_defeated(total_defeated, total_spawned)


func _on_stage_room_cleared() -> void:
	_on_facility_room_cleared()


func _on_stage_player_defeated() -> void:
	fail_facility("PLAYER_DEFEATED", "小骑士需要先休整一下。")


func _on_stage_chest_opened() -> void:
	_set_feedback("设施回馈已确认，出口正在打开。")
	_on_facility_chest_opened()


func _on_stage_portal_entered() -> void:
	if not scene_succeeded:
		push_error("FACILITY_PORTAL_BEFORE_SUCCESS [%s]" % location_id)
		return
	_return_home()


func layout_position(marker_name: String) -> Vector2:
	var marker := get_node_or_null("WorldLayout/%s" % marker_name) as Marker2D
	if marker == null:
		push_error("FACILITY_LAYOUT_MARKER_MISSING [%s/%s]" % [location_id, marker_name])
		return Vector2.ZERO
	return stage.to_local(marker.global_position) if is_instance_valid(stage) else marker.position


func add_world_marker(marker_name: String, world_position: Vector2, active: bool = false) -> Sprite2D:
	var marker := Sprite2D.new()
	marker.name = marker_name
	marker.texture = SEED_TEXTURE
	marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	marker.position = world_position
	var source_side := maxf(marker.texture.get_size().x, marker.texture.get_size().y)
	var factor := 27.0 / source_side if source_side > 0.0 else 1.0
	marker.scale = Vector2(factor, factor)
	marker.z_index = 4
	stage.add_child(marker)
	set_world_marker_active(marker, active)
	return marker


func add_world_console(marker_name: String, world_position: Vector2) -> Sprite2D:
	var console := Sprite2D.new()
	console.name = marker_name
	console.texture = CONSOLE_TEXTURE
	console.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	console.position = world_position
	var source_side := maxf(console.texture.get_size().x, console.texture.get_size().y)
	var factor := 40.0 / source_side if source_side > 0.0 else 1.0
	console.scale = Vector2(factor, factor)
	console.z_index = 4
	stage.add_child(console)
	return console


func add_world_caption(caption: String, world_position: Vector2, color: Color = COLOR_TEXT) -> Label:
	var label := _make_label(caption, 9, color)
	label.position = world_position + Vector2(-56, 21)
	label.size = Vector2(112, 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_outline_color", Color("#07090e"))
	label.add_theme_constant_override("outline_size", 4)
	label.z_index = 8
	stage.add_child(label)
	return label


func set_world_marker_active(marker: Sprite2D, active: bool) -> void:
	if not is_instance_valid(marker):
		return
	marker.modulate = Color.WHITE if active else COLOR_DORMANT
	marker.self_modulate.a = 1.0 if active else 0.72


func player_near(world_position: Vector2, radius: float = 38.0) -> bool:
	return (
		is_instance_valid(stage)
		and stage.player_position().distance_to(stage.to_global(world_position)) <= radius
	)


func teleport_player_to(world_position: Vector2) -> void:
	if not is_instance_valid(stage):
		push_error("FACILITY_TELEPORT_WITHOUT_STAGE [%s]" % location_id)
		return
	stage.teleport_player(stage.to_global(world_position))


func _set_feedback(message: String) -> void:
	if is_instance_valid(feedback_label):
		feedback_label.text = message


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _initial_feedback() -> String:
	return "走近世界中的设施并按 E 互动。"


func _success_feedback() -> String:
	return "真实世界行为已完成验证。打开宝箱后从出口返回芽芽家园。"


func _progress_text() -> String:
	return ""


func _context_prompt() -> String:
	return ""


func _build_facility_world() -> void:
	push_error("%s must implement _build_facility_world()" % get_script().resource_path)


func _update_facility(_delta: float) -> void:
	pass


func _handle_facility_interaction() -> void:
	pass


func _handle_facility_input(_event: InputEvent) -> void:
	pass


func _restore_facility_world() -> void:
	pass


func _on_facility_succeeded() -> void:
	pass


func _on_facility_player_moved(_total_distance: float) -> void:
	pass


func _on_facility_player_shot(_total_shots: int) -> void:
	pass


func _on_facility_enemy_spawned(_enemy: Enemy, _index: int, _boss: bool) -> void:
	pass


func _on_facility_enemy_defeated(_total_defeated: int, _total_spawned: int) -> void:
	pass


func _on_facility_room_cleared() -> void:
	pass


func _on_facility_chest_opened() -> void:
	pass


func run_contract_test() -> bool:
	push_error("%s must implement run_contract_test()" % get_script().resource_path)
	return false


func _run_contract_test_and_quit() -> void:
	LoopRunState.reset_for_test()
	var ok := await run_contract_test()
	if ok:
		print("FACILITY_SCENE_OK ", location_id)
	LoopRunState.reset_for_test(true)
	await _cleanup_runtime_nodes()
	get_tree().quit(0 if ok else 2)


func _capture_and_quit() -> void:
	await get_tree().create_timer(0.75).timeout
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() == "headless":
		push_error("Facility capture requires a rendering display")
		get_tree().quit(2)
		return
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("FACILITY_CAPTURE_EMPTY [%s]" % location_id)
		get_tree().quit(2)
		return
	var directory := ProjectSettings.globalize_path("res://qa/multi-scene")
	var mkdir_error := DirAccess.make_dir_recursive_absolute(directory)
	if mkdir_error != OK:
		push_error("FACILITY_CAPTURE_DIR_ERROR: %s" % mkdir_error)
		get_tree().quit(2)
		return
	var output := directory.path_join("facility-%s.png" % location_id)
	var error := image.save_png(output)
	print("MULTI_SCENE_CAPTURE=", output, " ERROR=", error)
	await _cleanup_runtime_nodes()
	get_tree().quit(0 if error == OK else 2)


func _cleanup_runtime_nodes() -> void:
	# Source bullets/effects live at SceneTree root and the stage owns source
	# player/weapon resources. Release both before a short-lived test process
	# exits so successful runs do not hide ObjectDB/resource leak warnings.
	for child in get_tree().root.get_children():
		if child is Bullet or child is GPUParticles2D or child is Coin:
			child.queue_free()
	if is_instance_valid(stage):
		# This cleanup runs only immediately before process exit. Freeing the
		# stage synchronously guarantees its chest collision cannot enqueue a
		# new sound after the audio singleton has been drained.
		stage.free()
		stage = null
	# Drain deferred collision signals before cleaning the global sound player.
	# A chest created underneath the player can otherwise start its sound one
	# frame after the facility has already requested shutdown.
	for _frame in range(2):
		await get_tree().process_frame
	# The real treasure chest starts the global SFX autoload. Stop that stream
	# explicitly as short-lived test processes can otherwise exit while the OGG
	# playback object is still active and report a false-clean resource leak.
	if is_instance_valid(SFXPlayer):
		SFXPlayer.stop()
		for audio_player in SFXPlayer.get_children():
			if audio_player is AudioStreamPlayer:
				audio_player.stream = null
		SFXPlayer.free()
	# Give Godot's audio worker one real-time mix interval to release the OGG
	# playback object before the short-lived test process exits. Rendering frames
	# alone can advance too quickly in headless mode and expose a race.
	await get_tree().create_timer(0.35, true, false, true).timeout
	for _frame in range(3):
		await get_tree().process_frame
