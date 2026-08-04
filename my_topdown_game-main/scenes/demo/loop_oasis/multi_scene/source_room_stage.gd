class_name SourceRoomStage
extends Node2D

## Adapter around the user-provided Soul-Knight-style Godot modules.
##
## This node owns the physical room lifecycle (player, doors, bullets, enemies,
## chest and portal). Learning scenes consume its signals and may only commit
## progress after observable world events have happened.

signal player_moved(total_distance: float)
signal player_shot(total_shots: int)
signal enemy_spawned(enemy: Enemy, index: int, boss: bool)
signal enemy_defeated(total_defeated: int, total_spawned: int)
signal room_cleared
signal chest_opened
signal portal_entered
signal player_defeated
signal pulse_used(total_uses: int)

const ROOM_SCENE := preload("res://scenes/room/level_one_room/level_one_room.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player_cat/player_cat.tscn")
const PLAYER_RESOURCE := preload("res://custom_resource/player/player_cat/player_cat.tres")
const PLAYER_WEAPON := preload("res://custom_resource/weapons/range/weapon_pistol/weapon_pistol.tres")
const LEVEL_RESOURCE := preload("res://custom_resource/level/one/level_one.tres")
const TARGET_TEXTURE := preload("res://assets/sprites/items/data_garden_light_seed.png")
const CONSOLE_TEXTURE := preload("res://assets/sprites/items/data_garden_console.png")
const COMPANION_TEXTURE := preload("res://assets/sprites/companion/xiao_hetao.png")
const HUD_UNDER := preload("res://assets/sprites/interface/bar_under.png")
const HUD_OVER := preload("res://assets/sprites/interface/bar_over.png")
const HUD_HEALTH := preload("res://assets/sprites/interface/bar_health.png")
const HUD_MANA := preload("res://assets/sprites/interface/bar_mana.png")
const HUD_PLAYER_ICON := preload("res://assets/sprites/players/tile_0004.png")
const HUD_COIN := preload("res://assets/sprites/coin.png")

const DEFAULT_CAMERA_ZOOM := Vector2(2.1, 2.1)
const BOSS_CAMERA_ZOOM := Vector2(1.85, 1.85)
const NORMAL_ENEMY_HP := 2.0

var stage_id := ""
var stage_title := ""
var capture_mode := false
var auto_reward_on_clear := false
var built := false
var room_sealed := false
var combat_active := false
var reward_ready := false
var portal_ready := false
var chest_was_opened := false
var player_distance := 0.0
var shots_fired := 0
var enemies_spawned := 0
var enemies_defeated := 0
var pulse_uses := 0

var level_room: LevelRoom
var player: Player
var companion: Sprite2D
var chest: TreasureBox
var portal: Protal
var enemies: Array[Enemy] = []
var target_nodes: Array[Sprite2D] = []
var console_node: Sprite2D
var boss_enemy: Enemy

var _last_player_position := Vector2.ZERO
var _hud_health: TextureProgressBar
var _hud_mana: TextureProgressBar
var _hud_coin_label: Label
var _tree_node_added_connected := false
var _portal_signal_connected := false


func build(config: Dictionary = {}) -> void:
	if built:
		push_error("SOURCE_ROOM_STAGE_ALREADY_BUILT [%s]" % stage_id)
		return
	stage_id = str(config.get("stage_id", "room"))
	stage_title = str(config.get("title", stage_id))
	capture_mode = bool(config.get("capture_mode", false))
	auto_reward_on_clear = bool(config.get("auto_reward_on_clear", false))
	RenderingServer.set_default_clear_color(Color("#05070d"))
	_ensure_input_actions()
	_build_level_room()
	await get_tree().process_frame
	_prepare_room_doors()
	_build_player(bool(config.get("boss_room", false)))
	_build_companion()
	_build_source_hud()
	_connect_global_observers()
	seal_room()
	built = true


func _exit_tree() -> void:
	if _tree_node_added_connected and get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.disconnect(_on_tree_node_added)
	if _portal_signal_connected and EventBus.rooms.on_portal_reached.is_connected(_on_source_portal_reached):
		EventBus.rooms.on_portal_reached.disconnect(_on_source_portal_reached)
	if Global.player_ref == player:
		Global.player_ref = null


func _process(_delta: float) -> void:
	_update_player_distance()
	_update_companion()
	_update_source_hud()
	_check_reward_state()


func _build_level_room() -> void:
	level_room = ROOM_SCENE.instantiate() as LevelRoom
	assert(level_room != null, "SOURCE_ROOM_LEVEL_SCENE_INVALID")
	add_child(level_room)


func _prepare_room_doors() -> void:
	level_room.open_well(Vector2i.UP)
	level_room.open_well(Vector2i.DOWN)
	level_room.close_all_walls()
	level_room.open_well(Vector2i.UP)
	level_room.open_well(Vector2i.DOWN)


func _build_player(boss_room: bool) -> void:
	Global.selected_player = PLAYER_RESOURCE
	Global.selected_weapon = PLAYER_WEAPON
	player = PLAYER_SCENE.instantiate() as Player
	assert(player != null, "SOURCE_ROOM_PLAYER_SCENE_INVALID")
	add_child(player)
	player.global_position = level_room.player_spawn_ponsition.global_position
	player.weapon_controller.equip_weapon(PLAYER_WEAPON)
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera:
		camera.zoom = BOSS_CAMERA_ZOOM if boss_room else DEFAULT_CAMERA_ZOOM
		camera.position = Vector2(0, -30 if boss_room else -40)
		camera.position_smoothing_enabled = false
	Global.player_ref = player
	_last_player_position = player.global_position
	player.health_component.on_unit_dead.connect(_on_player_dead)


func _build_companion() -> void:
	companion = Sprite2D.new()
	companion.name = "XiaoHetaoCompanion"
	companion.texture = COMPANION_TEXTURE
	companion.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	companion.scale = Vector2(0.026, 0.026)
	companion.position = player.position + Vector2(28, 2)
	companion.z_index = 10
	add_child(companion)


func _build_source_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SourceHud"
	layer.layer = 20
	add_child(layer)

	var player_icon := TextureRect.new()
	player_icon.position = Vector2(20, 18)
	player_icon.size = Vector2(72, 72)
	player_icon.texture = HUD_PLAYER_ICON
	player_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	player_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	player_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(player_icon)

	_hud_health = _make_source_bar(Vector2(20, 94), HUD_HEALTH)
	layer.add_child(_hud_health)
	_hud_mana = _make_source_bar(Vector2(20, 120), HUD_MANA)
	layer.add_child(_hud_mana)

	var coin_icon := TextureRect.new()
	coin_icon.position = Vector2(22, 153)
	coin_icon.size = Vector2(28, 28)
	coin_icon.texture = HUD_COIN
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(coin_icon)
	_hud_coin_label = Label.new()
	_hud_coin_label.position = Vector2(58, 151)
	_hud_coin_label.size = Vector2(110, 32)
	_hud_coin_label.add_theme_font_size_override("font_size", 22)
	_hud_coin_label.add_theme_color_override("font_color", Color.WHITE)
	_hud_coin_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud_coin_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(_hud_coin_label)

	var title_label := Label.new()
	title_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title_label.position = Vector2(-290, 18)
	title_label.size = Vector2(580, 44)
	title_label.text = stage_title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 25)
	title_label.add_theme_color_override("font_color", Color("#fff6d6"))
	title_label.add_theme_color_override("font_outline_color", Color("#15100a"))
	title_label.add_theme_constant_override("outline_size", 7)
	layer.add_child(title_label)


func _make_source_bar(position_value: Vector2, progress_texture: Texture2D) -> TextureProgressBar:
	var bar := TextureProgressBar.new()
	bar.position = position_value
	bar.size = Vector2(150, 22)
	bar.max_value = 1.0
	bar.step = 0.01
	bar.value = 1.0
	bar.nine_patch_stretch = true
	bar.stretch_margin_left = 3
	bar.stretch_margin_right = 3
	bar.texture_under = HUD_UNDER
	bar.texture_over = HUD_OVER
	bar.texture_progress = progress_texture
	bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return bar


func _update_source_hud() -> void:
	if is_instance_valid(player):
		var health_max := maxf(player.health_component.max_health, 1.0)
		_hud_health.value = player.health_component.current_health / health_max
		_hud_mana.value = player.current_mana / maxf(player.player_resource.magic, 1.0)
	_hud_coin_label.text = str(int(Global.conis))


func _connect_global_observers() -> void:
	if not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)
		_tree_node_added_connected = true
	if not EventBus.rooms.on_portal_reached.is_connected(_on_source_portal_reached):
		EventBus.rooms.on_portal_reached.connect(_on_source_portal_reached)
		_portal_signal_connected = true


func seal_room() -> void:
	if not is_instance_valid(level_room):
		push_error("SOURCE_ROOM_SEAL_WITHOUT_ROOM [%s]" % stage_id)
		return
	level_room.lock_room()
	room_sealed = true


func unlock_room() -> void:
	if not is_instance_valid(level_room):
		push_error("SOURCE_ROOM_UNLOCK_WITHOUT_ROOM [%s]" % stage_id)
		return
	level_room.unlock_room()
	room_sealed = false


func set_player_input(enabled: bool) -> void:
	if not is_instance_valid(player):
		return
	player.can_move = enabled
	player.set_process(enabled)
	player.set_physics_process(enabled)
	if not enabled:
		player.velocity = Vector2.ZERO


func player_position() -> Vector2:
	if is_instance_valid(player):
		return player.global_position
	return Vector2.ZERO


func teleport_player(world_position: Vector2) -> void:
	if not is_instance_valid(player):
		push_error("SOURCE_ROOM_TELEPORT_WITHOUT_PLAYER [%s]" % stage_id)
		return
	player.global_position = world_position
	_last_player_position = world_position


func add_console(local_position: Vector2) -> Sprite2D:
	if is_instance_valid(console_node):
		return console_node
	console_node = _add_scaled_sprite("WorldConsole", CONSOLE_TEXTURE, local_position, 38.0)
	return console_node


func add_targets(local_positions: PackedVector2Array) -> Array[Sprite2D]:
	for target in target_nodes:
		if is_instance_valid(target):
			target.queue_free()
	target_nodes.clear()
	for index in range(local_positions.size()):
		var target := _add_scaled_sprite("WorldTarget%02d" % index, TARGET_TEXTURE, local_positions[index], 27.0)
		set_target_active(target, false)
		target_nodes.append(target)
	return target_nodes


func add_source_prop(scene: PackedScene, local_position: Vector2, scale_value: float = 1.0) -> Node2D:
	var prop := scene.instantiate() as Node2D
	if prop == null:
		push_error("SOURCE_ROOM_PROP_INVALID [%s]" % stage_id)
		return null
	prop.position = local_position
	prop.scale = Vector2(scale_value, scale_value)
	add_child(prop)
	return prop


func set_target_active(target: Sprite2D, active: bool) -> void:
	if not is_instance_valid(target):
		return
	target.modulate = Color.WHITE if active else Color("#51656a")
	target.self_modulate.a = 1.0 if active else 0.72


func complete_noncombat_room(show_open_chest: bool = false) -> void:
	if reward_ready:
		return
	unlock_room()
	combat_active = false
	reward_ready = true
	_spawn_chest(show_open_chest)


func spawn_wave(count: int = 3, hit_points: float = NORMAL_ENEMY_HP) -> void:
	if count <= 0:
		push_error("SOURCE_ROOM_INVALID_WAVE_COUNT [%s]: %d" % [stage_id, count])
		return
	combat_active = true
	seal_room()
	var positions := PackedVector2Array([
		Vector2(-118, -76), Vector2(0, -112), Vector2(118, -76),
		Vector2(-132, 20), Vector2(132, 20), Vector2(0, -42),
	])
	for index in range(count):
		var spawn_position := positions[index % positions.size()]
		if not capture_mode:
			var marker := Global.SPAWN_MARKER.instantiate() as SpawnMarker
			add_child(marker)
			marker.position = spawn_position
			await marker.animation_player.animation_finished
		_spawn_enemy(index, spawn_position, hit_points, false)


func spawn_boss(hit_points: float = 6.0) -> Enemy:
	combat_active = true
	seal_room()
	# Keep the guardian below the compact objective/HP band so both the actor
	# and its emitted projectile patterns stay readable during observation.
	boss_enemy = _spawn_enemy(3, Vector2(0, 24), hit_points, true)
	if is_instance_valid(boss_enemy):
		boss_enemy.scale = Vector2(2.0, 2.0)
	return boss_enemy


func _spawn_enemy(index: int, local_position: Vector2, hit_points: float, boss: bool) -> Enemy:
	var enemy_scene: PackedScene = LEVEL_RESOURCE.enemy_scenes[index % LEVEL_RESOURCE.enemy_scenes.size()]
	var enemy := enemy_scene.instantiate() as Enemy
	assert(enemy != null, "SOURCE_ROOM_ENEMY_SCENE_INVALID")
	enemy.max_health = hit_points
	enemy.parent_room = level_room
	enemy.position = local_position
	enemy.modulate = Color("#a7b59a") if not boss else Color("#c5b5db")
	add_child(enemy)
	enemies.append(enemy)
	enemies_spawned += 1
	enemy.health_component.on_unit_dead.connect(func() -> void: _on_enemy_dead(enemy))
	enemy_spawned.emit(enemy, enemies_spawned - 1, boss)
	return enemy


func use_loop_pulse() -> void:
	if not combat_active or enemies.is_empty():
		return
	pulse_uses += 1
	for enemy in enemies.duplicate():
		if not is_instance_valid(enemy) or enemy.is_killed:
			continue
		Global.create_explosion(enemy.global_position)
		enemy.health_component.take_damage(1.0)
	pulse_used.emit(pulse_uses)


func damage_all_enemies_for_test(amount: float) -> void:
	for enemy in enemies.duplicate():
		if is_instance_valid(enemy) and not enemy.is_killed:
			enemy.health_component.take_damage(amount)


func _on_enemy_dead(enemy: Enemy) -> void:
	if not enemies.has(enemy):
		return
	enemies.erase(enemy)
	enemies_defeated += 1
	enemy_defeated.emit(enemies_defeated, enemies_spawned)
	if combat_active and enemies.is_empty():
		combat_active = false
		room_cleared.emit()
		if auto_reward_on_clear:
			unlock_room()
			reward_ready = true
			_spawn_chest(false)


func _spawn_chest(opened: bool) -> void:
	if is_instance_valid(chest):
		return
	chest = Global.TREASURE_BOX.instantiate() as TreasureBox
	assert(chest != null, "SOURCE_ROOM_CHEST_SCENE_INVALID")
	add_child(chest)
	chest.position = Vector2(0, -30)
	if opened:
		chest.collected = true
		chest.chest_close.hide()
		chest.chest_open.show()
		chest_was_opened = true
		chest_opened.emit()
		_spawn_portal()


func _check_reward_state() -> void:
	if not is_instance_valid(chest) or chest_was_opened:
		return
	if chest.collected:
		chest_was_opened = true
		chest_opened.emit()
		_spawn_portal()


func _spawn_portal() -> void:
	if is_instance_valid(portal):
		return
	portal = Global.PROTAL.instantiate() as Protal
	assert(portal != null, "SOURCE_ROOM_PORTAL_SCENE_INVALID")
	add_child(portal)
	portal.position = Vector2(0, -104)
	portal.scale = Vector2(1.35, 1.35)
	portal_ready = true


func reveal_portal_for_completed_room() -> void:
	if not reward_ready:
		complete_noncombat_room(true)
	elif not is_instance_valid(portal):
		_spawn_portal()


func _on_source_portal_reached() -> void:
	if not portal_ready or not is_instance_valid(portal):
		push_error("SOURCE_ROOM_UNEXPECTED_PORTAL_SIGNAL [%s]" % stage_id)
		return
	portal_entered.emit()


func _on_tree_node_added(node: Node) -> void:
	if node is Bullet:
		call_deferred("_classify_bullet", node)


func _classify_bullet(node: Node) -> void:
	if not is_instance_valid(node) or not node is Bullet:
		return
	var bullet := node as Bullet
	if bullet.weapon_resource == PLAYER_WEAPON:
		shots_fired += 1
		player_shot.emit(shots_fired)


func _update_player_distance() -> void:
	if not is_instance_valid(player):
		return
	var current := player.global_position
	var delta_distance := _last_player_position.distance_to(current)
	if delta_distance > 0.01 and delta_distance < 80.0:
		player_distance += delta_distance
		player_moved.emit(player_distance)
	_last_player_position = current


func _update_companion() -> void:
	if not is_instance_valid(player) or not is_instance_valid(companion):
		return
	var desired := player.position + Vector2(28 if player.direction.x >= 0.0 else -28, 3)
	companion.position = companion.position.lerp(desired, 0.12)


func _on_player_dead() -> void:
	set_process(false)
	player_defeated.emit()


func _add_scaled_sprite(node_name: String, texture: Texture2D, local_position: Vector2, longest_side: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = local_position
	var texture_size := texture.get_size()
	var source_side := maxf(texture_size.x, texture_size.y)
	if source_side > 0.0:
		var factor := longest_side / source_side
		sprite.scale = Vector2(factor, factor)
	sprite.z_index = 3
	add_child(sprite)
	return sprite


func _ensure_input_actions() -> void:
	_ensure_key_action("interact", KEY_E)
	_ensure_key_action("loop_pulse", KEY_Q)


func _ensure_key_action(action_name: StringName, physical_key: Key) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	var event := InputEventKey.new()
	event.physical_keycode = physical_key
	InputMap.action_add_event(action_name, event)
