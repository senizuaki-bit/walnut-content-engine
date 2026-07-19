class_name Arena
extends Node2D

@export var arena_cursor: Texture2D
@export var levels: Array[LevelResource]
@export var coin_sound: AudioStream


@onready var health_bar: TextureProgressBar = %HealthBar
@onready var mana_bar: TextureProgressBar = %ManaBar
@onready var map_controller: MapController = %MapController
@onready var enemy_spawner: EnemySpawner = %EnemySpawner
@onready var total_coins: Label = %TotalCoins
@onready var dungeon: Node2D = %Dungeon
@onready var title: Label = %Title


var player_instance: Player
var current_room: LevelRoom
var level_resource: LevelResource
var current_level_index := 0
var current_sub_level_index := 1
var start_room_coord: Vector2i
var end_room_coord: Vector2i
var store_room_coord: Vector2i = Vector2i.MAX
var grid_cell_size: Vector2i
var grid: Dictionary[Vector2i, LevelRoom] = {}
var directions := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]


func _ready() -> void:
	Cursor.sprite.texture = arena_cursor
	set_title()
	EventBus.rooms.on_player_room_entered.connect(_on_player_room_entered)
	EventBus.rooms.on_room_cleared.connect(_on_room_cleared)
	EventBus.player.on_player_health_updated.connect(_on_player_health_updated)
	EventBus.shop.on_coin_picked.connect(_on_coin_picked)
	EventBus.rooms.on_portal_reached.connect(_on_portal_reached)
	level_resource = levels[current_level_index]
	generrate_dungeon()


func _process(_delta: float) -> void:
	total_coins.text = str(Global.conis)
	if is_instance_valid(Global.player_ref):
		mana_bar.value = Global.player_ref.current_mana / Global.player_ref.player_resource.magic


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		current_room.unlock_room()
		current_room.is_cleared = true

func set_title() -> void:
	title.text = "%s-%s" % [current_level_index + 1, current_sub_level_index]


func generrate_dungeon() -> void:
	for node: Node2D in dungeon.get_children():
		node.queue_free()
	await get_tree().process_frame
	if player_instance:
		player_instance.queue_free()
		Global.player_ref = null
	map_controller.reset()
	for node: Node in map_controller.get_children():
		node.queue_free()
	grid_cell_size = level_resource.room_size + level_resource.corridor_size
	generate_level_layout()
	# 建议将select_special_rooms放在generate_level_layout内
	# select_special_rooms需要等待布局完成后执行
	# 临时注释方便调试
	load_game_selection()


func generate_level_layout() -> void:
	var current_coord := Vector2i.ZERO
	grid.clear()
	print("创建布局...")
	grid[current_coord] = null
	while grid.size() <= level_resource.num_rooms:
		if randf() > 0.5: 
			current_coord = grid.keys().pick_random()
		var random_direction = directions.pick_random()
		var next_coord = current_coord + random_direction
		var attempts = 0
		while grid.has(next_coord) and attempts < level_resource.num_rooms:
			random_direction =  directions.pick_random()
			next_coord = current_coord + random_direction
			attempts += 1
		if not grid.has(next_coord):
			grid[next_coord] = null
	print("布局已生成：：：--->", grid.keys())
	select_special_rooms()



func create_rooms() -> void:
	print("开始创建房间...")
	for room_coord: Vector2i in grid.keys():
		var room_instance: LevelRoom = level_resource.room_scene.instantiate() as LevelRoom
		dungeon.add_child(room_instance)
		if room_coord == store_room_coord:
			room_instance.is_cleared = true
			room_instance.setup_room_as_shop(level_resource)
		if room_coord == end_room_coord:
			room_instance.is_cleared = true
			room_instance.setup_room_as_protal()
		room_instance.crete_props(level_resource)
		room_instance.position = room_coord * grid_cell_size
		grid[room_coord] = room_instance
		cennect_rooms(room_coord, room_instance)
	print("房间创建完毕...")
	grid[Vector2i.ZERO].is_cleared = true
	create_corridors()


func cennect_rooms(room_coord: Vector2i, room_instance: LevelRoom) -> void:
	for direction: Vector2i in directions:
		var neighbor_coord = room_coord + direction
		if grid.has(neighbor_coord):
			room_instance.open_well(direction)


func create_corridors() -> void:
	print("开始创建过道...")
	for room_coord:Vector2i in grid.keys():
		var room_instance = grid[room_coord]
		for direction: Vector2i in directions:
			var neighbor_coord = room_coord + direction
			if grid.has(neighbor_coord):
				var corridor: Node2D
				var corridor_position: Vector2i
				if direction == Vector2i.RIGHT:
					corridor = level_resource.h_corridor.instantiate()
					corridor_position = room_instance.position + Vector2(grid_cell_size.x / 2.0, 0.0)
					dungeon.add_child(corridor)
					corridor.position = corridor_position
				elif direction == Vector2i.DOWN:
					corridor = level_resource.v_corridor.instantiate()
					corridor_position = room_instance.position + Vector2(0.0, grid_cell_size.y / 2.0)
					dungeon.add_child(corridor)
					corridor.position = corridor_position
	print("过道创建完毕...")

func select_special_rooms() -> void:
	start_room_coord = Vector2.ZERO
	end_room_coord = find_farthest_room()
	print("起始房间：：：--->", start_room_coord)
	print("结束房间：：：--->", end_room_coord)
	var candidate_coord = grid.keys()
	candidate_coord.erase(start_room_coord)
	candidate_coord.erase(end_room_coord)
	if candidate_coord.is_empty(): return
	store_room_coord = candidate_coord.pick_random()
	create_rooms()


func find_farthest_room() -> Vector2i:
	var farthest_room_coord := start_room_coord
	var max_dist := 0.0
	for room_coord: Vector2i in grid.keys():
		var dist = start_room_coord.distance_to(room_coord)
		if dist > max_dist:
			max_dist = dist
			farthest_room_coord = room_coord
	return farthest_room_coord


func load_game_selection() -> void:
	player_instance = Global.get_player_scene().instantiate() as Player
	add_child(player_instance)
	player_instance.weapon_controller.equip_weapon(Global.selected_weapon)
	player_instance.global_position = grid[Vector2i.ZERO].player_spawn_ponsition.global_position
	Global.player_ref = player_instance

func find_coord_from_room(room: LevelRoom) -> Vector2i:
	for coord: Vector2i in grid:
		if grid[coord] == room:
			return coord
	return Vector2i.MAX


func _on_coin_picked() -> void:
	SFXPlayer.play(coin_sound)


func _on_portal_reached() -> void:
	await Transition.show_transition_in().finished
	if current_sub_level_index < level_resource.num_sub_levels:
		current_sub_level_index += 1
		generrate_dungeon()
	else :
		current_level_index += 1
		if current_level_index < levels.size():
			current_sub_level_index = 1
			level_resource = levels[current_level_index]
			generrate_dungeon()
		else :
			Transition.transition_to("res://scenes/ui/main_menu/main_menu.tscn")
			print("没有更多层级！")
	await Transition.show_transition_out().finished
	set_title()


func _on_player_room_entered(room: LevelRoom) -> void:
	if current_room == room: return
	current_room = room
	var absolute_coord = find_coord_from_room(room)
	var relative_coord = absolute_coord - start_room_coord
	map_controller.update_on_room_entered(relative_coord)
	if not room.is_cleared:
		room.lock_room()
		enemy_spawner.spawn_enemies(level_resource, current_room)


func _on_room_cleared() -> void:
	current_room.unlock_room()
	current_room.is_cleared = true
	var tile_position = current_room.get_free_spawn_position()
	var chest_position = current_room.to_global(tile_position)
	var chest_instance: TreasureBox = Global.TREASURE_BOX.instantiate()
	dungeon.call_deferred("add_child", chest_instance)
	chest_instance.global_position = chest_position


func _on_player_health_updated(current_health: float, max_health: float) -> void:
	health_bar.value = current_health / max_health
