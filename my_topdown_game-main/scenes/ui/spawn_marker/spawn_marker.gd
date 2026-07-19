class_name SpawnMarker
extends Sprite2D

@export var spawn_sound: AudioStream
@onready var animation_player: AnimationPlayer = %AnimationPlayer


func _ready() -> void:
	SFXPlayer.play(spawn_sound)
