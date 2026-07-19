class_name RoomsSignal
extends Node

signal on_player_room_entered(room: LevelRoom)

func emit_on_player_room_entered(room: LevelRoom) -> void:
	on_player_room_entered.emit(room)


signal on_room_cleared

func emit_on_room_cleared() -> void:
	on_room_cleared.emit()


signal on_portal_reached

func emit_on_portal_reached() -> void:
	on_portal_reached.emit()
