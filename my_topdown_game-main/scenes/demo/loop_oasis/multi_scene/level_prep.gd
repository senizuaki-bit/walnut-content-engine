extends LoopPlayableScene

## Physical preparation room.
##
## The player must walk to the real weapon pickup, equip the supplied source
## weapon, and land a real Bullet collision on an actual source Enemy training
## target. Only that world evidence opens the source chest, door and portal.

const SourceStage := preload("res://scenes/demo/loop_oasis/multi_scene/source_room_stage.gd")
const SceneContract := preload("res://scenes/demo/loop_oasis/multi_scene/LoopSceneContract.gd")
const PLAYER_WEAPON: WeaponResource = preload("res://custom_resource/weapons/range/weapon_pistol/weapon_pistol.tres")
const TRAINING_TARGET_SCENE: PackedScene = preload("res://scenes/enemies/enemy/enemy_1.tscn")
const PANEL_TEXTURE: Texture2D = preload("res://assets/sprites/interface/box.png")
const PLANT_SCENES: Array[PackedScene] = [
	preload("res://scenes/props/plant/plant_1.tscn"),
	preload("res://scenes/props/plant/plant_2.tscn"),
	preload("res://scenes/props/plant/plant_3.tscn"),
	preload("res://scenes/props/plant/plant_4.tscn"),
]

const TOOL_POSITION := Vector2(-104, 24)
const TARGET_POSITION := Vector2(104, -54)
const TOOL_INTERACT_DISTANCE := 58.0
const COLOR_TEXT := Color("#fff7dc")
const COLOR_MUTED := Color("#d7d5c7")
const COLOR_GOLD := Color("#ffd15c")
const COLOR_CYAN := Color("#70e6df")
const COLOR_CORAL := Color("#ff8877")
const COLOR_MINT := Color("#8be59e")

var stage: SourceRoomStage
var tool_sprite: Sprite2D
var tool_pickup_area: Area2D
var training_target: Enemy
var tool_claimed := false
var training_target_hit := false
var shots_fired := 0
var preparation_submitted := false
var portal_entry_observed := false
var transition_locked := false
var test_mode := false
var status_label: Label
var prompt_label: Label
var checklist_label: Label
var route_label: Label
var last_navigation_result: Dictionary = {}


func collect_completion_evidence() -> Dictionary:
	return {
		"tool_claimed": tool_claimed,
		"training_target_hit": training_target_hit,
		"shots_fired": shots_fired,
	}


func _ready() -> void:
	test_mode = "--level-prep-test" in OS.get_cmdline_user_args()
	if test_mode:
		SceneFlow.test_mode = true
	var gate: Dictionary = LoopRunState.can_enter("level_prep")
	if not bool(gate.get("ok", false)):
		_record_error(str(gate.get("error", "LEVEL_PREP_GATE_BLOCKED")))

	stage = SourceStage.new() as SourceRoomStage
	stage.name = "PreparationRoomStage"
	add_child(stage)
	await stage.build({
		"stage_id": "level_prep",
		"title": "转转绿洲岛 · 阿探队长安全整备房",
		"auto_reward_on_clear": false,
		"capture_mode": test_mode,
	})
	stage.player_shot.connect(_on_player_shot)
	stage.portal_entered.connect(_on_portal_entered)
	stage.player_defeated.connect(_on_player_defeated)
	_disarm_player_until_pickup()
	_build_training_world()
	_build_hud()
	_update_hud()
	if test_mode:
		call_deferred("_run_smoke")


func _process(_delta: float) -> void:
	if transition_locked or not is_instance_valid(stage):
		return
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if transition_locked or test_mode:
		return
	if event.is_action_pressed("interact"):
		_try_claim_tool()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_go_to_theme_map()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not tool_claimed:
		_record_error("PREP_TOOL_REQUIRED_BEFORE_SHOOTING")


func _disarm_player_until_pickup() -> void:
	var controller := stage.player.weapon_controller
	var equipped := controller.current_weapon
	controller.current_weapon = null
	if is_instance_valid(equipped):
		equipped.queue_free()
	# Player movement remains active in _physics_process. Only the shooting
	# process is paused so clicking before pickup cannot dereference a null tool.
	stage.player.set_process(false)


func _build_training_world() -> void:
	var pedestal := stage.add_console(TOOL_POSITION + Vector2(0, 13))
	pedestal.modulate = Color("#d8c2ff")

	tool_sprite = Sprite2D.new()
	tool_sprite.name = "PhysicalPulseTool"
	tool_sprite.texture = PLAYER_WEAPON.icon
	tool_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tool_sprite.position = TOOL_POSITION + Vector2(0, -18)
	tool_sprite.scale = Vector2(1.8, 1.8)
	tool_sprite.z_index = 7
	stage.add_child(tool_sprite)

	tool_pickup_area = Area2D.new()
	tool_pickup_area.name = "ToolPickupArea"
	tool_pickup_area.position = TOOL_POSITION
	tool_pickup_area.collision_layer = 0
	tool_pickup_area.collision_mask = 2
	var tool_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 42.0
	tool_shape.shape = circle
	tool_pickup_area.add_child(tool_shape)
	stage.add_child(tool_pickup_area)

	training_target = TRAINING_TARGET_SCENE.instantiate() as Enemy
	assert(training_target != null, "LEVEL_PREP_TRAINING_TARGET_SCENE_INVALID")
	training_target.name = "PhysicalTrainingTarget"
	training_target.max_health = 3.0
	training_target.collision_damage = 0.0
	training_target.can_move = false
	training_target.parent_room = stage.level_room
	training_target.position = TARGET_POSITION
	training_target.modulate = Color("#afbf9f")
	stage.add_child(training_target)
	training_target.can_move = false
	training_target.health_component.on_unit_damaged.connect(_on_training_target_damaged)

	_add_world_label(TOOL_POSITION + Vector2(-48, 34), "基础脉冲工具", COLOR_MINT)
	_add_world_label(TARGET_POSITION + Vector2(-48, 28), "安全训练靶", COLOR_CORAL)
	for index in range(PLANT_SCENES.size()):
		var x := -145.0 if index % 2 == 0 else 145.0
		var y := -104.0 if index < 2 else 78.0
		stage.add_source_prop(PLANT_SCENES[index], Vector2(x, y), 1.0)


func _add_world_label(label_position: Vector2, text_value: String, color: Color) -> void:
	var label := Label.new()
	label.text = text_value
	label.position = label_position
	label.size = Vector2(96, 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("#111018"))
	label.add_theme_constant_override("outline_size", 2)
	label.z_index = 9
	stage.add_child(label)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PreparationHud"
	layer.layer = 40
	add_child(layer)

	var objective := _make_label("训练目标：领取实体工具，并用真实子弹命中安全训练靶", 17, COLOR_TEXT)
	objective.position = Vector2(215, 65)
	objective.size = Vector2(850, 40)
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(objective)

	var info_panel := NinePatchRect.new()
	info_panel.position = Vector2(968, 112)
	info_panel.size = Vector2(272, 224)
	info_panel.texture = PANEL_TEXTURE
	info_panel.patch_margin_left = 18
	info_panel.patch_margin_top = 18
	info_panel.patch_margin_right = 18
	info_panel.patch_margin_bottom = 18
	info_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(info_panel)
	var info_title := _make_label("本次出发", 20, COLOR_GOLD)
	info_title.position = Vector2(22, 16)
	info_title.size = Vector2(228, 30)
	info_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_panel.add_child(info_title)
	var info := _make_label("关卡目标\n修复转转绿洲岛的循环异常\n\n通关奖励\n清泉种子、循环魔法碎片\n\n本局能力\n循环脉冲，战斗房按 Q 使用", 14, COLOR_TEXT)
	info.position = Vector2(24, 47)
	info.size = Vector2(224, 156)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_panel.add_child(info)

	route_label = _make_label("", 16, COLOR_GOLD)
	route_label.position = Vector2(930, 18)
	route_label.size = Vector2(320, 68)
	route_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	route_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(route_label)

	checklist_label = _make_label("", 16, COLOR_MUTED)
	checklist_label.position = Vector2(28, 205)
	checklist_label.size = Vector2(250, 82)
	checklist_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(checklist_label)

	prompt_label = _make_label("", 19, COLOR_CYAN)
	prompt_label.position = Vector2(350, 578)
	prompt_label.size = Vector2(580, 50)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(prompt_label)

	status_label = _make_label("小问：先走到左侧工具台旁，按 E 领取工具。", 17, COLOR_TEXT)
	status_label.position = Vector2(250, 630)
	status_label.size = Vector2(780, 42)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(status_label)

	var controls := _make_label("WASD 或方向键移动    E 领取工具    鼠标瞄准并左键射击    Esc 返回路线广场", 15, COLOR_MUTED)
	controls.position = Vector2(20, 686)
	controls.size = Vector2(1150, 28)
	layer.add_child(controls)


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("#080a10"))
	label.add_theme_constant_override("outline_size", 5)
	return label


func _update_prompt() -> void:
	if not is_instance_valid(prompt_label):
		return
	if not tool_claimed:
		if stage.player_position().distance_to(TOOL_POSITION) <= TOOL_INTERACT_DISTANCE:
			prompt_label.text = "按 E 领取并装备基础脉冲工具"
		else:
			prompt_label.text = "走近左侧实体工具台"
	elif not training_target_hit:
		prompt_label.text = "瞄准右侧训练靶并左键射击"
	elif preparation_submitted:
		prompt_label.text = "穿过房间上方出现的实体星光门"


func _try_claim_tool() -> Dictionary:
	if tool_claimed:
		status_label.text = "基础脉冲工具已经装备，请实际命中右侧训练靶。"
		return {"ok": true, "idempotent": true}
	if stage.player_position().distance_to(TOOL_POSITION) > TOOL_INTERACT_DISTANCE:
		_record_error("TOOL_PICKUP_OUT_OF_RANGE")
		return {"ok": false, "error": "TOOL_PICKUP_OUT_OF_RANGE"}
	var controller := stage.player.weapon_controller
	controller.equip_weapon(PLAYER_WEAPON)
	if not is_instance_valid(controller.current_weapon):
		_record_error("TOOL_EQUIP_FAILED")
		return {"ok": false, "error": "TOOL_EQUIP_FAILED"}
	tool_claimed = true
	tool_sprite.hide()
	tool_pickup_area.monitoring = false
	stage.player.set_process(true)
	status_label.text = "工具已装备。现在用鼠标瞄准右侧训练靶并左键射击。"
	_update_hud()
	return {"ok": true, "tool_claimed": true}


func _on_player_shot(total_shots: int) -> void:
	shots_fired = total_shots
	_update_hud()
	if training_target_hit:
		call_deferred("_submit_preparation_if_ready")


func _on_training_target_damaged(_amount: float) -> void:
	if training_target_hit:
		return
	training_target_hit = true
	if is_instance_valid(training_target):
		training_target.modulate = COLOR_MINT
	status_label.text = "真实子弹已命中训练靶，正在核验世界证据。"
	_update_hud()
	call_deferred("_submit_preparation_if_ready")


func _submit_preparation_if_ready() -> Dictionary:
	if preparation_submitted:
		return {"ok": true, "idempotent": true}
	var evidence := collect_completion_evidence()
	var validation: Dictionary = SceneContract.validate("level_prep", evidence)
	if not bool(validation.get("ok", false)):
		if training_target_hit and shots_fired < 1:
			_record_error("PREP_SHOT_OBSERVER_PENDING")
		return validation
	var result: Dictionary = LoopRunState.submit_preparation_evidence(evidence)
	if not bool(result.get("ok", false)):
		_record_error(str(result.get("error", "PREP_EVIDENCE_REJECTED")))
		return result
	preparation_submitted = true
	stage.complete_noncombat_room(true)
	status_label.text = "整备完成。上方实体星光门已开启，穿过它进入 R0 观察房。"
	_update_hud()
	return result


func _update_hud() -> void:
	if is_instance_valid(route_label):
		route_label.text = "本次路线\n先谜题，后战斗" if LoopRunState.route_order == "puzzle_first" else "本次路线\n先战斗，后谜题"
	if is_instance_valid(checklist_label):
		var tool_state := "已装备" if tool_claimed else "未领取"
		var hit_state := "已命中" if training_target_hit else "未命中"
		checklist_label.text = "实体工具：%s\n训练靶：%s\n真实射击：%d 次" % [tool_state, hit_state, shots_fired]
		checklist_label.add_theme_color_override("font_color", COLOR_MINT if preparation_submitted else COLOR_MUTED)


func _on_portal_entered() -> void:
	portal_entry_observed = true
	if transition_locked:
		return
	if not preparation_submitted:
		_record_error("PREP_PORTAL_OPENED_WITHOUT_EVIDENCE")
		return
	if not LoopRunState.begin_adventure(LoopRunState.route_order):
		_record_error(LoopRunState.last_error if not LoopRunState.last_error.is_empty() else "BEGIN_ADVENTURE_FAILED")
		return
	transition_locked = true
	stage.set_player_input(false)
	last_navigation_result = navigate_to("r0_observe")
	if not bool(last_navigation_result.get("ok", false)):
		transition_locked = false
		stage.set_player_input(true)
		_record_error(str(last_navigation_result.get("error", "SCENE_FLOW_FAILED")))


func _go_to_theme_map() -> void:
	transition_locked = true
	var result := navigate_to("theme_map")
	if not bool(result.get("ok", false)):
		transition_locked = false
		_record_error(str(result.get("error", "SCENE_FLOW_FAILED")))


func _on_player_defeated() -> void:
	_record_error("LEVEL_PREP_PLAYER_DEFEATED")
	status_label.text = "安全整备中断。按 Esc 返回路线广场后可以无损重试。"


func _record_error(code: String) -> void:
	print("LEVEL_PREP_ERROR=", code)
	if is_instance_valid(status_label):
		status_label.text = "整备房暂时无法继续：%s" % code
		status_label.add_theme_color_override("font_color", COLOR_CORAL)


func _fire_training_shot_for_test() -> void:
	assert(tool_claimed, "测试射击前必须真实装备工具")
	assert(is_instance_valid(training_target), "训练靶必须是实际 Enemy")
	var controller := stage.player.weapon_controller
	var aim_point := training_target.global_position + Vector2(0, -8)
	controller.target_position = aim_point
	controller.rotate_weapon()
	var active_weapon_resource := controller.current_weapon.weapon_resource
	var original_spread := active_weapon_resource.spread
	active_weapon_resource.spread = 0.0
	controller.current_weapon.use_weapon()
	active_weapon_resource.spread = original_spread


func _run_smoke() -> void:
	LoopRunState.reset_for_test()
	SceneFlow.test_mode = true
	var route_result: Dictionary = LoopRunState.configure_route("puzzle_first")
	assert(bool(route_result.get("ok", false)), str(route_result.get("error", "")))
	var rejected: Dictionary = SceneContract.validate("level_prep", {})
	assert(not bool(rejected.get("ok", false)), "缺少世界证据必须被静态合同拒绝")
	assert(str(rejected.get("error", "")) == "EVIDENCE_FIELDS_MISSING")

	stage.teleport_player(TOOL_POSITION)
	await get_tree().physics_frame
	var pickup_result := _try_claim_tool()
	assert(bool(pickup_result.get("ok", false)), str(pickup_result.get("error", "")))
	assert(tool_claimed)
	assert(is_instance_valid(stage.player.weapon_controller.current_weapon), "工具必须装备到真实 WeaponController")

	stage.teleport_player(training_target.global_position + Vector2(-56, 0))
	await get_tree().physics_frame
	_fire_training_shot_for_test()
	for _frame in range(180):
		if preparation_submitted:
			break
		await get_tree().process_frame
	assert(training_target_hit, "真实 Bullet 必须碰撞实际 Enemy 训练靶")
	assert(shots_fired >= 1, "SourceRoomStage 必须观察到真实射击")
	assert(preparation_submitted, "有效世界证据必须提交整备合同")
	assert(LoopRunState.tool_claimed and LoopRunState.training_target_hit)
	assert(stage.portal_ready and is_instance_valid(stage.portal), "整备完成后必须出现实体星光门")

	stage.teleport_player(Vector2(0, -52))
	await get_tree().physics_frame
	stage.teleport_player(stage.portal.global_position)
	for _frame in range(12):
		if portal_entry_observed:
			break
		await get_tree().physics_frame
	assert(portal_entry_observed, "玩家必须真实穿过星光门")
	assert(LoopRunState.run_started)
	assert(bool(last_navigation_result.get("ok", false)), str(last_navigation_result.get("error", "")))
	assert(str(last_navigation_result.get("scene_id", "")) == "r0_observe")
	print("LEVEL_PREP_SMOKE_OK")
	await get_tree().create_timer(1.4).timeout
	stage.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)
