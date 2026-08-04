extends LoopPlayableScene

## Physical route plaza for the first island.
##
## The supplied Soul-Knight-style LevelRoom, Player and portal animation own
## the visible world. Route choice is accepted only after the player walks to
## one of the two portal terminals and presses E.

const SourceStage := preload("res://scenes/demo/loop_oasis/multi_scene/source_room_stage.gd")
const SceneContract := preload("res://scenes/demo/loop_oasis/multi_scene/LoopSceneContract.gd")
const PORTAL_SCENE: PackedScene = preload("res://scenes/ui/protal/protal.tscn")
const PLANT_SCENES: Array[PackedScene] = [
	preload("res://scenes/props/plant/plant_1.tscn"),
	preload("res://scenes/props/plant/plant_2.tscn"),
	preload("res://scenes/props/plant/plant_3.tscn"),
	preload("res://scenes/props/plant/plant_4.tscn"),
]
const CAPTAIN_TEXTURE: Texture2D = preload("res://assets/sprites/players/tile_0000.png")
const GUIDE_TEXTURE: Texture2D = preload("res://assets/sprites/players/tile_0008.png")
const PANEL_TEXTURE: Texture2D = preload("res://assets/sprites/interface/box.png")

const PUZZLE_FIRST := "puzzle_first"
const COMBAT_FIRST := "combat_first"
const PUZZLE_PORTAL_POSITION := Vector2(-92, -58)
const COMBAT_PORTAL_POSITION := Vector2(92, -58)
const INTERACT_DISTANCE := 58.0
const COLOR_TEXT := Color("#fff7dc")
const COLOR_MUTED := Color("#d7d5c7")
const COLOR_GOLD := Color("#ffd15c")
const COLOR_CYAN := Color("#70e6df")
const COLOR_CORAL := Color("#ff8877")
const COLOR_MINT := Color("#8be59e")

var stage: SourceRoomStage
var route_portals: Dictionary = {}
var route_tints := {
	PUZZLE_FIRST: COLOR_MINT,
	COMBAT_FIRST: COLOR_CORAL,
}
var selected_route := PUZZLE_FIRST
var focused_route := ""
var transition_locked := false
var test_mode := false
var status_label: Label
var prompt_label: Label
var route_summary_label: Label
var last_navigation_result: Dictionary = {}


func collect_completion_evidence() -> Dictionary:
	return {
		"route_order": selected_route,
		"puzzle_required": true,
		"combat_required": true,
	}


func _ready() -> void:
	test_mode = "--theme-map-test" in OS.get_cmdline_user_args()
	if test_mode:
		SceneFlow.test_mode = true
	var gate: Dictionary = LoopRunState.can_enter("theme_map")
	if not bool(gate.get("ok", false)):
		_record_error(str(gate.get("error", "THEME_MAP_GATE_BLOCKED")))
	selected_route = LoopRunState.route_order if LoopRunState.route_order in LoopRunState.VALID_ROUTES else PUZZLE_FIRST

	stage = SourceStage.new() as SourceRoomStage
	stage.name = "RoutePlazaStage"
	add_child(stage)
	await stage.build({
		"stage_id": "theme_map",
		"title": "星光群岛 · 转转绿洲岛路线广场",
		"auto_reward_on_clear": false,
		"capture_mode": test_mode,
	})
	stage.player_defeated.connect(_on_player_defeated)
	_build_route_plaza()
	_build_hud()
	_update_focus(true)
	if test_mode:
		call_deferred("_run_smoke")


func _process(_delta: float) -> void:
	if transition_locked or not is_instance_valid(stage):
		return
	_update_focus(false)


func _unhandled_input(event: InputEvent) -> void:
	if transition_locked or test_mode:
		return
	if event.is_action_pressed("interact"):
		_activate_focused_route()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_go_home()
		get_viewport().set_input_as_handled()


func _build_route_plaza() -> void:
	_add_route_portal(PUZZLE_FIRST, PUZZLE_PORTAL_POSITION, COLOR_MINT)
	_add_route_portal(COMBAT_FIRST, COMBAT_PORTAL_POSITION, COLOR_CORAL)
	_add_world_actor(CAPTAIN_TEXTURE, Vector2(-132, 49), "阿探队长", Color("#f3cf82"))
	_add_world_actor(GUIDE_TEXTURE, Vector2(132, 49), "小问", Color("#b8dfff"))
	for index in range(PLANT_SCENES.size()):
		var x := -146.0 if index % 2 == 0 else 146.0
		var y := -108.0 if index < 2 else 82.0
		stage.add_source_prop(PLANT_SCENES[index], Vector2(x, y), 1.0)


func _add_route_portal(route_id: String, portal_position: Vector2, tint: Color) -> void:
	var portal := PORTAL_SCENE.instantiate() as Protal
	assert(portal != null, "THEME_MAP_PORTAL_SCENE_INVALID")
	portal.name = "PuzzleFirstPortal" if route_id == PUZZLE_FIRST else "CombatFirstPortal"
	stage.add_child(portal)
	portal.position = portal_position
	portal.scale = Vector2(1.55, 1.55)
	portal.modulate = tint
	portal.collision_mask = 0
	portal.monitoring = false
	portal.monitorable = false
	var shape := portal.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape:
		shape.disabled = true
	route_portals[route_id] = portal
	var title := "先完成谜题" if route_id == PUZZLE_FIRST else "先完成战斗"
	var subtitle := "随后完成战斗" if route_id == PUZZLE_FIRST else "随后完成谜题"
	_add_world_label(portal_position + Vector2(-52, 31), title, tint, 9)
	_add_world_label(portal_position + Vector2(-52, 43), subtitle, COLOR_TEXT, 7)


func _add_world_actor(texture: Texture2D, actor_position: Vector2, actor_name: String, tint: Color) -> void:
	var actor := Sprite2D.new()
	actor.name = actor_name
	actor.texture = texture
	actor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	actor.position = actor_position
	actor.scale = Vector2(1.55, 1.55)
	actor.modulate = tint
	actor.z_index = 4
	stage.add_child(actor)
	_add_world_label(actor_position + Vector2(-42, 14), actor_name, COLOR_TEXT, 7)


func _add_world_label(label_position: Vector2, text_value: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = label_position
	label.size = Vector2(104, 15)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("#111018"))
	label.add_theme_constant_override("outline_size", 2)
	label.z_index = 8
	stage.add_child(label)
	return label


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "RoutePlazaHud"
	layer.layer = 40
	add_child(layer)

	var objective := _make_label("选择房间先后顺序；谜题与战斗都是通往 Boss 的必经房间", 17, COLOR_TEXT)
	objective.position = Vector2(215, 65)
	objective.size = Vector2(850, 40)
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(objective)

	var rules_panel := NinePatchRect.new()
	rules_panel.position = Vector2(986, 118)
	rules_panel.size = Vector2(254, 178)
	rules_panel.texture = PANEL_TEXTURE
	rules_panel.patch_margin_left = 18
	rules_panel.patch_margin_top = 18
	rules_panel.patch_margin_right = 18
	rules_panel.patch_margin_bottom = 18
	rules_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(rules_panel)
	var rules_title := _make_label("路线合同", 19, COLOR_GOLD)
	rules_title.position = Vector2(22, 18)
	rules_title.size = Vector2(210, 28)
	rules_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rules_panel.add_child(rules_title)
	var rules := _make_label("共同前置：观察房、安全编程房\n路线差异：谜题与战斗的先后\n共同收束：陌生巡查、Boss、结算", 14, COLOR_TEXT)
	rules.position = Vector2(22, 50)
	rules.size = Vector2(210, 92)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rules_panel.add_child(rules)

	route_summary_label = _make_label("", 16, COLOR_GOLD)
	route_summary_label.position = Vector2(930, 18)
	route_summary_label.size = Vector2(320, 68)
	route_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	route_summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(route_summary_label)

	prompt_label = _make_label("", 19, COLOR_CYAN)
	prompt_label.position = Vector2(360, 584)
	prompt_label.size = Vector2(560, 48)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(prompt_label)

	status_label = _make_label("阿探队长：走近一座星光门，再按 E 确认路线。", 17, COLOR_TEXT)
	status_label.position = Vector2(280, 632)
	status_label.size = Vector2(720, 42)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(status_label)

	var controls := _make_label("WASD 或方向键移动    E 确认路线    Esc 返回芽芽家园", 15, COLOR_MUTED)
	controls.position = Vector2(20, 686)
	controls.size = Vector2(1000, 28)
	layer.add_child(controls)
	_update_route_summary()


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("#080a10"))
	label.add_theme_constant_override("outline_size", 5)
	return label


func _update_focus(force: bool) -> void:
	var next_focus := _route_near_player()
	if not force and next_focus == focused_route:
		return
	focused_route = next_focus
	for route_id in route_portals:
		var portal := route_portals[route_id] as Protal
		if not is_instance_valid(portal):
			continue
		var focused := str(route_id) == focused_route
		portal.scale = Vector2.ONE * (1.78 if focused else 1.55)
		portal.modulate = Color.WHITE if focused else route_tints[route_id]
	if not is_instance_valid(prompt_label):
		return
	match focused_route:
		PUZZLE_FIRST:
			prompt_label.text = "按 E 选择：先谜题，后战斗"
		COMBAT_FIRST:
			prompt_label.text = "按 E 选择：先战斗，后谜题"
		_:
			prompt_label.text = "走近任意一座实体星光门"


func _route_near_player() -> String:
	if not is_instance_valid(stage) or not is_instance_valid(stage.player):
		return ""
	var player_position := stage.player_position()
	var best_route := ""
	var best_distance := INTERACT_DISTANCE
	for route_id in route_portals:
		var portal := route_portals[route_id] as Protal
		if not is_instance_valid(portal):
			continue
		var distance := player_position.distance_to(portal.global_position)
		if distance <= best_distance:
			best_distance = distance
			best_route = str(route_id)
	return best_route


func _activate_focused_route() -> Dictionary:
	var route_id := _route_near_player()
	if route_id.is_empty():
		_record_error("ROUTE_TERMINAL_OUT_OF_RANGE")
		return {"ok": false, "error": "ROUTE_TERMINAL_OUT_OF_RANGE"}
	return _commit_route_and_depart(route_id)


func _commit_route_and_depart(route_id: String) -> Dictionary:
	if route_id not in LoopRunState.VALID_ROUTES:
		_record_error("MAP_ROUTE_CONTRACT_INVALID")
		return {"ok": false, "error": "MAP_ROUTE_CONTRACT_INVALID"}
	selected_route = route_id
	var evidence := collect_completion_evidence()
	var contract_result: Dictionary = SceneContract.validate("theme_map", evidence)
	if not bool(contract_result.get("ok", false)):
		_record_error(str(contract_result.get("error", "MAP_ROUTE_CONTRACT_INVALID")))
		return contract_result
	var state_result: Dictionary = LoopRunState.configure_route(str(evidence.route_order))
	if not bool(state_result.get("ok", false)):
		_record_error(str(state_result.get("error", "MAP_ROUTE_SAVE_FAILED")))
		return state_result
	_update_route_summary()
	status_label.text = "路线已记录。谜题与战斗都不会被跳过，正在进入实体整备房。"
	transition_locked = true
	stage.set_player_input(false)
	last_navigation_result = navigate_to("level_prep")
	if not bool(last_navigation_result.get("ok", false)):
		transition_locked = false
		stage.set_player_input(true)
		_record_error(str(last_navigation_result.get("error", "SCENE_FLOW_FAILED")))
	return last_navigation_result


func _update_route_summary() -> void:
	if not is_instance_valid(route_summary_label):
		return
	route_summary_label.text = "当前路线\n先谜题，后战斗" if selected_route == PUZZLE_FIRST else "当前路线\n先战斗，后谜题"


func _go_home() -> void:
	transition_locked = true
	var result := navigate_to("home")
	if not bool(result.get("ok", false)):
		transition_locked = false
		_record_error(str(result.get("error", "SCENE_FLOW_FAILED")))


func _on_player_defeated() -> void:
	_record_error("ROUTE_PLAZA_PLAYER_DEFEATED")
	status_label.text = "路线广场发生异常，按 Esc 安全返回芽芽家园。"


func _record_error(code: String) -> void:
	print("THEME_MAP_ERROR=", code)
	if is_instance_valid(status_label):
		status_label.text = "路线广场暂时无法继续：%s" % code
		status_label.add_theme_color_override("font_color", COLOR_CORAL)


func _run_smoke() -> void:
	LoopRunState.reset_for_test()
	SceneFlow.test_mode = true
	var rejected: Dictionary = SceneContract.validate("theme_map", {
		"route_order": "skip_core_rooms",
		"puzzle_required": false,
		"combat_required": false,
	})
	assert(not bool(rejected.get("ok", false)), "非法路线必须被静态合同拒绝")
	assert(str(rejected.get("error", "")) == "MAP_ROUTE_CONTRACT_INVALID")
	stage.teleport_player(COMBAT_PORTAL_POSITION)
	await get_tree().physics_frame
	assert(_route_near_player() == COMBAT_FIRST, "玩家必须真实靠近战斗优先星光门")
	var request := _activate_focused_route()
	assert(bool(request.get("ok", false)), str(request.get("error", "")))
	assert(selected_route == COMBAT_FIRST)
	assert(LoopRunState.route_order == COMBAT_FIRST)
	assert(bool(collect_completion_evidence().puzzle_required))
	assert(bool(collect_completion_evidence().combat_required))
	assert(str(request.get("scene_id", "")) == "level_prep")
	print("THEME_MAP_SMOKE_OK")
	stage.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)
