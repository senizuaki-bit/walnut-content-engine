class_name MapCell
extends Control

@onready var player_icon: TextureRect = %PlayerIcon

var player_action: bool = false : set = _set_player_action

func _set_player_action(value: bool) -> void:
	player_action = value
	player_icon.visible = player_action
