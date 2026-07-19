class_name MapController
extends Control

const MAP_CELL_SCENE = preload("uid://btq6hbq1jeawa")

var cell_size: Vector2i
var player_coord := Vector2i.MAX
var minimap_cells: Dictionary[Vector2i, MapCell] = {}


func update_on_room_entered(new_room_coord: Vector2i) -> void:
	var new_call: MapCell
	if new_room_coord == player_coord: return
	if minimap_cells.has(player_coord):
		minimap_cells[player_coord].player_action = false
	if minimap_cells.has(new_room_coord):
		new_call = minimap_cells[new_room_coord]
	else :
		new_call = create_map_cell(new_room_coord)
	player_coord = new_room_coord
	new_call.player_action = true


func create_map_cell(coord: Vector2i) -> MapCell:
	var call_instance: MapCell = MAP_CELL_SCENE.instantiate() as MapCell
	add_child(call_instance)
	minimap_cells[coord] = call_instance
	if cell_size == Vector2i.ZERO:
		cell_size = call_instance.size
	var relative_postion = Vector2(coord * cell_size)
	call_instance.position = (size / 2.0) + relative_postion - (cell_size / 2.0)
	return call_instance


func reset() -> void:
	for cell: MapCell in minimap_cells.values():
		cell.queue_free()
	minimap_cells.clear()
	player_coord = Vector2i.MAX
	cell_size = Vector2.ZERO
