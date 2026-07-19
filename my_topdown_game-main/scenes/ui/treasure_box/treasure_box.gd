class_name TreasureBox
extends StaticBody2D

const COIN_SCENE = preload("uid://jq1wxnd3f37t")

@export var coin_amount := 5
@export var chest_sound: AudioStream

@onready var chest_close: Sprite2D = %ChestClose
@onready var chest_open: Sprite2D = %ChestOpen
@onready var drop_position: Marker2D = %DropPosition

var collected: bool = false

func _on_area_2d_body_entered(body: Node2D) -> void:
	if collected: return
	if not body is Player: return
	chest_close.visible = false
	chest_open.visible = true
	SFXPlayer.play(chest_sound)
	for i in coin_amount:
		var coin_instance = COIN_SCENE.instantiate() as Coin
		get_tree().root.call_deferred("add_child", coin_instance)
		var coin_position: Vector2 = drop_position.global_position + Vector2(randf_range(-50, 50), 0)
		coin_instance.global_position = coin_position
	collected = true
