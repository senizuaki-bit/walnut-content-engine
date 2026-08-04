extends "res://scenes/demo/loop_oasis/multi_scene/facility_scene.gd"

## 叮当师傅工坊
##
## This is a no-pressure calibration room, never a second battlefield. Three
## source Enemy bodies are adapted into static target rigs solely so the real
## pistol Bullet collision path remains intact. They cannot move, attack, touch
## damage or detect the player.

const PLAYER_WEAPON: WeaponResource = preload(
	"res://custom_resource/weapons/range/weapon_pistol/weapon_pistol.tres"
)
const TRAINING_TARGET_SCENE: PackedScene = preload("res://scenes/enemies/enemy/enemy_1.tscn")
const TARGET_COUNT := 3
const MAX_CALIBRATION_SHOTS := 6
const INTERACT_DISTANCE := 44.0

var workbench: Sprite2D
var tool_sprite: Sprite2D
var target_backplates: Array[Sprite2D] = []
var physical_targets: Array[Enemy] = []
var target_hits: Dictionary = {}
var tool_claimed := false
var targets_spawned := 0
var targets_destroyed := 0
var shots_landed := 0
var shots_fired := 0
var budget_check_pending := false


func _build_facility_world() -> void:
	var workbench_position := layout_position("Workbench")
	workbench = add_world_console("DingdangCalibrationWorkbench", workbench_position)
	workbench.modulate = Color("#ffd15c")
	add_world_caption("叮当师傅 · 校准台", workbench_position, Color("#ffd15c"))

	tool_sprite = Sprite2D.new()
	tool_sprite.name = "PhysicalCalibrationTool"
	tool_sprite.texture = PLAYER_WEAPON.icon
	tool_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tool_sprite.position = workbench_position + Vector2(0, -23)
	tool_sprite.scale = Vector2(1.65, 1.65)
	tool_sprite.z_index = 8
	stage.add_child(tool_sprite)

	for index in range(TARGET_COUNT):
		var target_position := layout_position("Target%d" % (index + 1))
		var backplate := add_world_marker("StaticTargetBackplate%d" % (index + 1), target_position, false)
		backplate.scale *= 1.22
		target_backplates.append(backplate)
		add_world_caption("安全靶 %d" % (index + 1), target_position, Color("#ff9f8f"))

	# Keep walking active but make pre-pickup clicks inert and null-safe.
	var equipped := stage.player.weapon_controller.current_weapon
	stage.player.weapon_controller.current_weapon = null
	if is_instance_valid(equipped):
		equipped.queue_free()
	stage.player.set_process(false)


func _handle_facility_interaction() -> void:
	if not player_near(layout_position("Workbench"), INTERACT_DISTANCE):
		_set_feedback("走近叮当师傅的左侧校准台再按 E 领取工具。")
		return
	if tool_claimed:
		_set_feedback("校准工具已领取；瞄准三座静止安全靶并用真实子弹射击。")
		return
	_claim_tool_and_spawn_targets()


func _handle_facility_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not tool_claimed:
			_set_feedback("[WORKSHOP_TOOL_REQUIRED] 先走到叮当校准台按 E 领取工具。")


func _claim_tool_and_spawn_targets() -> void:
	var controller := stage.player.weapon_controller
	controller.equip_weapon(PLAYER_WEAPON)
	if not is_instance_valid(controller.current_weapon):
		fail_facility("WORKSHOP_TOOL_EQUIP_FAILED", "叮当校准工具没有正确装入真实 WeaponController。")
		return
	tool_claimed = true
	tool_sprite.hide()
	workbench.modulate = Color("#8be59e")
	stage.player.set_process(true)
	_spawn_static_targets()
	_set_feedback("三座安全靶已升起。它们不会移动或攻击；用真实子弹逐座校准。")


func _spawn_static_targets() -> void:
	if not physical_targets.is_empty() or targets_spawned > 0:
		return
	for index in range(TARGET_COUNT):
		var target := TRAINING_TARGET_SCENE.instantiate() as Enemy
		assert(target != null, "WORKSHOP_STATIC_TARGET_SCENE_INVALID")
		target.name = "PhysicalStaticTarget%d" % (index + 1)
		target.max_health = 1.0
		target.collision_damage = 0.0
		target.can_move = false
		target.parent_room = stage.level_room
		target.position = layout_position("Target%d" % (index + 1))
		target.modulate = Color("#b8c7a9")
		stage.add_child(target)
		# Retain the Enemy collision body for real Bullet hits, but disable every
		# behavior that could turn this calibration rig into a battle.
		target.can_move = false
		target.velocity = Vector2.ZERO
		target.collision_damage = 0.0
		target.set_process(false)
		target.set_physics_process(false)
		target.player_detector.set_deferred("monitoring", false)
		target.health_component.on_unit_damaged.connect(_on_target_damaged.bind(target))
		target.health_component.on_unit_dead.connect(_on_target_destroyed.bind(target))
		physical_targets.append(target)
		targets_spawned += 1
		set_world_marker_active(target_backplates[index], true)


func _on_target_damaged(amount: float, target: Enemy) -> void:
	if scene_failed or amount <= 0.0 or not is_instance_valid(target):
		return
	var target_id := target.get_instance_id()
	if target_hits.has(target_id):
		return
	target_hits[target_id] = true
	shots_landed += 1
	target.modulate = Color("#8be59e")
	_set_feedback("真实子弹命中安全靶，校准命中 %d/3。" % shots_landed)


func _on_target_destroyed(target: Enemy) -> void:
	if scene_failed:
		return
	targets_destroyed += 1
	var target_index := physical_targets.find(target)
	if target_index >= 0 and target_index < target_backplates.size():
		set_world_marker_active(target_backplates[target_index], false)
	if targets_destroyed == TARGET_COUNT:
		call_deferred("_finish_target_calibration")


func _finish_target_calibration() -> void:
	if scene_failed or scene_succeeded:
		return
	if shots_landed < TARGET_COUNT:
		fail_facility("WORKSHOP_HIT_EVIDENCE_INCOMPLETE", "靶体已变化，但没有观测到三次真实子弹碰撞。")
		return
	request_world_success()


func _on_facility_player_shot(total_shots: int) -> void:
	shots_fired = total_shots
	if total_shots < MAX_CALIBRATION_SHOTS or targets_destroyed == TARGET_COUNT or budget_check_pending:
		return
	# Stop new shots, then allow the last real bullet to finish its flight before
	# deciding whether this finite calibration pass missed too many times.
	budget_check_pending = true
	stage.player.set_process(false)
	call_deferred("_check_shot_budget_after_flight", total_shots)


func _check_shot_budget_after_flight(snapshot_shots: int) -> void:
	await get_tree().create_timer(1.1).timeout
	budget_check_pending = false
	if scene_succeeded or scene_failed or targets_destroyed == TARGET_COUNT:
		return
	if shots_fired != snapshot_shots:
		return
	fail_facility(
		"WORKSHOP_CALIBRATION_CHARGE_SPENT",
		"本轮六发校准能量用完，但仍有 %d 座安全靶未命中。" % (TARGET_COUNT - targets_destroyed)
	)


func collect_completion_evidence() -> Dictionary:
	return {
		"targets_spawned": targets_spawned,
		"targets_destroyed": targets_destroyed,
		"shots_landed": shots_landed,
	}


func _progress_text() -> String:
	return "安全靶 %d/3\n真实命中 %d/3\n校准能量 %d/%d" % [
		targets_destroyed,
		shots_landed,
		maxi(MAX_CALIBRATION_SHOTS - shots_fired, 0),
		MAX_CALIBRATION_SHOTS,
	]


func _context_prompt() -> String:
	if not tool_claimed:
		if player_near(layout_position("Workbench"), INTERACT_DISTANCE):
			return "E 领取并装备叮当校准工具"
		return "走近左侧叮当校准台"
	return "鼠标瞄准静止安全靶 · 左键发射真实子弹"


func _initial_feedback() -> String:
	return "这是无伤害、无倒计时的校准空间。先走到叮当师傅的工具台。"


func _success_feedback() -> String:
	return "三座静止安全靶均由真实子弹命中；工坊校准完成。"


func _restore_facility_world() -> void:
	tool_claimed = true
	targets_spawned = TARGET_COUNT
	targets_destroyed = TARGET_COUNT
	shots_landed = TARGET_COUNT
	tool_sprite.hide()
	workbench.modulate = Color("#8be59e")
	for backplate in target_backplates:
		set_world_marker_active(backplate, false)


func _fire_real_test_shot(target: Enemy) -> void:
	assert(tool_claimed, "工坊测试射击前必须近身领取工具")
	assert(is_instance_valid(target), "工坊测试必须瞄准实际 Enemy 靶体")
	var controller := stage.player.weapon_controller
	var aim_point := target.global_position + Vector2(0, -8)
	controller.target_position = aim_point
	controller.rotate_weapon()
	var active_weapon_resource := controller.current_weapon.weapon_resource
	var original_spread := active_weapon_resource.spread
	active_weapon_resource.spread = 0.0
	controller.current_weapon.use_weapon()
	active_weapon_resource.spread = original_spread


func run_contract_test() -> bool:
	teleport_player_to(layout_position("Workbench"))
	await get_tree().physics_frame
	_handle_facility_interaction()
	assert(tool_claimed and targets_spawned == TARGET_COUNT, "领取工具后必须升起三座实体安全靶")
	var test_targets := physical_targets.duplicate()
	for target in test_targets:
		assert(is_instance_valid(target), "每座工坊靶必须是实际 Enemy 实体")
		stage.teleport_player(target.global_position + Vector2(-56, 0))
		await get_tree().physics_frame
		_fire_real_test_shot(target)
		for _frame in range(180):
			if not is_instance_valid(target):
				break
			await get_tree().process_frame
		assert(not is_instance_valid(target), "真实 Bullet 必须击毁当前静止安全靶")
	for _frame in range(30):
		if scene_succeeded:
			break
		await get_tree().process_frame
	assert(scene_succeeded, "工坊只能在三座实体靶被真实子弹击毁后成功")
	assert(targets_destroyed == TARGET_COUNT and shots_landed >= TARGET_COUNT)
	assert(bool(LoopRunState.home_flags.get("workshop", false)), "工坊合同必须写入完成标记")
	assert(int(LoopRunState.inventory.get("pulse_module", 0)) == 1, "工坊完成后必须生成脉冲模块")
	return true
