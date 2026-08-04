extends LoopPlayableScene

const COLOR_PANEL := Color("#211f3d")
const COLOR_PURPLE := Color("#5b4387")
const COLOR_MINT := Color("#69d6ad")
const COLOR_CORAL := Color("#f1846c")
const COLOR_GOLD := Color("#ffc75a")
const COLOR_CYAN := Color("#55e6e0")
const COLOR_TEXT := Color("#fff8e8")
const COLOR_MUTED := Color("#c7c2dc")

var status_label: Label
var reward_label: Label
var gate_grid: GridContainer
var home_button: Button
var farm_button: Button
var test_mode := false


func collect_completion_evidence() -> Dictionary:
	var missing := LoopRunState.missing_required_rooms()
	return {"all_gates": missing.is_empty(), "missing_flags": missing}


func _ready() -> void:
	test_mode = "--settlement-test" in OS.get_cmdline_user_args()
	_build_visuals()
	if test_mode:
		SceneFlow.test_mode = true
		call_deferred("_run_smoke")
		return
	_commit_and_render()


func _build_visuals() -> void:
	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = load("res://assets/backgrounds/data_garden_world_restored.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.modulate = Color("#b9abdc")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.04, 0.035, 0.12, 0.64)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var card := Panel.new()
	card.position = Vector2(54, 34)
	card.size = Vector2(1172, 590)
	card.add_theme_stylebox_override("panel", _style_box(Color("#17172df2"), COLOR_MINT, 28, 3))
	add_child(card)
	_make_label(card, "转转绿洲岛 · 净化完成", Vector2(34, 18), Vector2(660, 48), 34, COLOR_TEXT)
	_make_label(card, "结算只认世界证据；重复进入不会重复发奖", Vector2(36, 66), Vector2(760, 28), 15, COLOR_MUTED)

	var guardian := TextureRect.new()
	guardian.position = Vector2(912, 18)
	guardian.size = Vector2(210, 140)
	guardian.texture = load("res://assets/sprites/enemies/data_garden_guardian.png")
	guardian.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	guardian.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	guardian.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	guardian.modulate = Color("#8ee3bf")
	card.add_child(guardian)

	var gates_panel := Panel.new()
	gates_panel.position = Vector2(34, 116)
	gates_panel.size = Vector2(704, 316)
	gates_panel.add_theme_stylebox_override("panel", _style_box(Color("#232142"), COLOR_PURPLE, 20, 2))
	card.add_child(gates_panel)
	_make_label(gates_panel, "八项必经门禁", Vector2(22, 14), Vector2(340, 30), 21, COLOR_TEXT)
	gate_grid = GridContainer.new()
	gate_grid.columns = 2
	gate_grid.position = Vector2(22, 58)
	gate_grid.size = Vector2(658, 232)
	gate_grid.add_theme_constant_override("h_separation", 12)
	gate_grid.add_theme_constant_override("v_separation", 10)
	gates_panel.add_child(gate_grid)

	var reward_panel := Panel.new()
	reward_panel.position = Vector2(764, 172)
	reward_panel.size = Vector2(370, 260)
	reward_panel.add_theme_stylebox_override("panel", _style_box(Color("#28234a"), COLOR_GOLD, 20, 2))
	card.add_child(reward_panel)
	_make_label(reward_panel, "带回芽芽家园", Vector2(22, 14), Vector2(320, 30), 21, COLOR_TEXT)
	_add_reward_art(reward_panel)
	reward_label = _make_label(reward_panel, "等待门禁核验……", Vector2(24, 178), Vector2(320, 56), 16, COLOR_MUTED)
	reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	status_label = _make_label(card, "", Vector2(36, 454), Vector2(1070, 34), 16, COLOR_MUTED)
	home_button = _make_button(card, "返回芽芽家园", Vector2(690, 510), Vector2(194, 56), COLOR_PURPLE)
	home_button.pressed.connect(func() -> void: _go("home"))
	farm_button = _make_button(card, "直接去编程农场  →", Vector2(902, 510), Vector2(232, 56), COLOR_MINT)
	farm_button.pressed.connect(func() -> void: _go("farm"))


func _add_reward_art(parent: Control) -> void:
	var seed := TextureRect.new()
	seed.position = Vector2(30, 62)
	seed.size = Vector2(104, 92)
	seed.texture = load("res://assets/sprites/items/data_garden_light_seed.png")
	seed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seed.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	seed.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(seed)
	_make_label(parent, "清泉种子 ×1", Vector2(132, 74), Vector2(200, 28), 18, COLOR_MINT)
	_make_label(parent, "循环魔法碎片 ×1", Vector2(132, 110), Vector2(220, 28), 18, COLOR_GOLD)


func _commit_and_render() -> void:
	_refresh_gates()
	var gate: Dictionary = LoopRunState.can_enter("settlement")
	if not bool(gate.get("ok", false)):
		var code := str(gate.get("error", "SETTLEMENT_GATES_MISSING"))
		status_label.text = "结算被阻止：%s · 缺少 %s" % [code, ", ".join(LoopRunState.missing_required_rooms())]
		status_label.add_theme_color_override("font_color", COLOR_CORAL)
		reward_label.text = "奖励尚未写入；请返回缺失房间。"
		home_button.disabled = true
		farm_button.disabled = true
		push_error("[Settlement] %s" % code)
		return
	var already_committed := LoopRunState.settlement_committed
	if not LoopRunState.commit_settlement():
		status_label.text = "奖励提交失败：%s" % LoopRunState.last_error
		status_label.add_theme_color_override("font_color", COLOR_CORAL)
		home_button.disabled = true
		farm_button.disabled = true
		return
	status_label.text = "八项门禁全部通过；奖励事务%s。" % ("已存在，本次未重复发放" if already_committed else "已原子提交")
	status_label.add_theme_color_override("font_color", COLOR_MINT)
	reward_label.text = "当前库存：清泉种子 %d · 循环魔法碎片 %d" % [int(LoopRunState.inventory.water_seed), int(LoopRunState.inventory.law_fragment)]
	home_button.disabled = false
	farm_button.disabled = false
	_refresh_gates()


func _refresh_gates() -> void:
	for child in gate_grid.get_children():
		child.queue_free()
	var labels := {
		"observe": "R0 世界观察", "program": "R1 5/5 轨迹",
		"puzzle": "谜桥 5→4", "combat": "实体敌人清零",
		"transfer": "陌生迁移 6/6", "boss_observe": "伙伴四拍观察",
		"boss_debug": "条件 Debug", "boss_combat": "迷雾净化 6 HP",
	}
	for flag in LoopRunState.REQUIRED_SETTLEMENT_FLAGS:
		var done := LoopRunState.room_done(flag)
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(320, 48)
		chip.add_theme_stylebox_override("panel", _style_box(Color("#24453d") if done else Color("#332b45"), COLOR_MINT if done else Color("#716b82"), 13, 2))
		gate_grid.add_child(chip)
		var label := _make_label(chip, "%s · %s" % ["完成" if done else "待完成", labels[flag]], Vector2(14, 5), Vector2(288, 38), 15, COLOR_TEXT if done else COLOR_MUTED)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _go(scene_id: String) -> void:
	var result := navigate_to(scene_id)
	if not bool(result.get("ok", false)):
		var code := str(result.get("error", "SCENE_FLOW_FAILED"))
		status_label.text = "无法转场：%s" % code
		status_label.add_theme_color_override("font_color", COLOR_CORAL)


func _make_label(parent: Node, text_value: String, pos: Vector2, label_size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = pos
	label.size = label_size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


func _make_button(parent: Node, text_value: String, pos: Vector2, button_size: Vector2, accent: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = pos
	button.size = button_size
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _style_box(COLOR_PANEL, accent, 16, 2))
	button.add_theme_stylebox_override("hover", _style_box(COLOR_PANEL.lightened(0.12), accent, 16, 3))
	button.add_theme_stylebox_override("disabled", _style_box(Color("#29283b"), Color("#5c596d"), 16, 1))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	return button


func _style_box(fill: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style


func _run_smoke() -> void:
	LoopRunState.reset_for_test()
	assert(bool(LoopRunState.configure_route("puzzle_first").get("ok", false)))
	assert(bool(LoopRunState.submit_preparation_evidence({
		"tool_claimed": true,
		"training_target_hit": true,
		"shots_fired": 1,
	}).get("ok", false)))
	assert(LoopRunState.begin_adventure("puzzle_first"))
	var fixtures := {
		"r0_observe": {"movement_distance": 48.0, "action_runs": 1, "changed_targets": 1, "total_targets": 5},
		"r1_safe_program": {"repeat_count": 5, "completed_targets": 5, "total_targets": 5, "trace_steps": 5, "used_run_or_step": true},
		"puzzle_bridge": {"from_count": 5, "to_count": 4, "bridge_segments_open": 4, "counterfactual_last_dormant": true, "player_crossed_exit": true},
		"pulse_defense": {"enemies_spawned": 3, "enemies_defeated": 3, "shots_fired": 3, "pulse_uses": 1, "player_moved": true},
		"r4_transfer": {"repeat_count": 6, "completed_targets": 6, "total_targets": 6, "trace_steps": 6},
		"boss_observe": {"observed_beats": 4, "player_moved": true, "dodged_hazards": 1},
		"boss_debug": {"defect_run": true, "blocked_hits": 2, "condition_changed": true, "safe_hits": 2, "debug_success": true},
		"boss_combat": {"boss_max_hp": 6, "boss_hp": 0, "hits_landed": 6, "shots_fired": 6, "debug_clear": true},
	}
	for contract_id in fixtures:
		var result: Dictionary = LoopRunState.submit_scene_evidence(contract_id, fixtures[contract_id])
		assert(bool(result.get("ok", false)), str(result.get("error", "")))
	assert(bool(LoopRunState.can_enter("settlement").get("ok", false)))
	assert(LoopRunState.commit_settlement())
	assert(LoopRunState.commit_settlement())
	assert(int(LoopRunState.inventory.get("water_seed", 0)) == 1)
	assert(int(LoopRunState.inventory.get("law_fragment", 0)) == 1)
	assert(not bool(LoopRunState.home_flags.get("archive", false)))
	print("SETTLEMENT_SMOKE_OK")
	get_tree().quit(0)
