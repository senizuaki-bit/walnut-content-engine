class_name LevelRoom
extends Node2D

@export var item_positions: Array[Marker2D]


@onready var tile_data: TileMapLayer = %TileData
@onready var player_spawn_ponsition: Marker2D = %PlayerSpawnPonsition

@onready var room_doors: Dictionary[Vector2i, TileMapLayer] = {
	Vector2i.UP: %DoorsUp,
	Vector2i.DOWN: %DoorsDown,
	Vector2i.LEFT: %DoorsLeft,
	Vector2i.RIGHT: %DoorsRight
}

@onready var room_walls: Dictionary[Vector2i, TileMapLayer] = {
	Vector2i.UP: %WallsUp,
	Vector2i.DOWN: %WallsDown,
	Vector2i.LEFT: %WallsLeft,
	Vector2i.RIGHT: %WallsRight
}

var tiles: Array[Vector2i]
var is_cleared: bool


func _ready() -> void:
	close_all_walls()
	register_tiles()


func register_tiles() -> void:
	for tile in tile_data.get_used_cells():
		tiles.append(tile)


func get_free_spawn_position() -> Vector2:
	var tile_coord = tiles.pick_random()
	return tile_data.map_to_local(tile_coord)


func setup_room_as_shop(data: LevelResource) -> void:
	if data.store_resource.is_empty(): return
	for marker: Marker2D in item_positions:
		var item_resource: ItemsResource = data.get_random_store_item()
		var store_item_instance: StoreItem = Global.STORE_ITEM_BASE.instantiate()
		add_child(store_item_instance)
		store_item_instance.global_position = marker.global_position
		store_item_instance.setup(item_resource)


func setup_room_as_protal() -> void:
	var protal_instance: Protal = Global.PROTAL.instantiate()
	add_child(protal_instance)
	protal_instance.global_position = to_global(get_free_spawn_position())

func crete_props(level_resource: LevelResource) -> void:
	var random_props = randi_range(level_resource.min_props_per_room, level_resource.max_props_per_room)
	for i in random_props:
		var tile_coord: Vector2i = tiles.pick_random()
		var tile_position = tile_data.map_to_local(tile_coord)
		var prop_instance: Prop = level_resource.props.pick_random().instantiate() as Prop
		add_child(prop_instance)
		prop_instance.position = tile_position
	


func lock_room() -> void:
	for direction: Vector2i in room_doors:
		var wall = room_walls[direction]
		var door = room_doors[direction]
		if wall and not wall.enabled:
			door.enabled = true


func unlock_room() -> void:
	for direction: Vector2i in room_doors:
		room_doors[direction].enabled = false


func open_well(direction: Vector2i) -> void:
	if not room_walls.has(direction): return
	room_walls[direction].enabled = false


func close_all_walls() -> void:
	for wall_key: Vector2i in room_walls:
		room_walls[wall_key].enabled = true


func _on_player_detector_body_entered(_body: Node2D) -> void:
	EventBus.rooms.emit_on_player_room_entered(self)
		
