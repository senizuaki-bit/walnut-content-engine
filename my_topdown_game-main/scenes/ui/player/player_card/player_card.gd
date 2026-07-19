class_name PlayerCard
extends TextureButton

@export var hover_stream: AudioStream
@export var player_resource: PlayerResource: set = _set_player_resource

@onready var icon: TextureRect = %Icon
@onready var selector: TextureRect = %Selector
@onready var discription_panel: DiscriptionPanel = %DiscriptionPanel



func _set_player_resource(value: PlayerResource) -> void:
	if not is_node_ready(): 
		await ready
	player_resource = value
	icon.texture = player_resource.icon
	set_discription()


func set_discription() -> void:
	# TODO 国际化缺失
	var message_value = [tr(player_resource.Player_name), player_resource.max_hp, player_resource.move_speed, player_resource.magic]
	var message := "玩家: %s\n 血量: %.0f\n 速度: %.0f\n 魔法: %.0f" % message_value
	discription_panel.text = message


func _on_mouse_entered() -> void:
	SFXPlayer.play(hover_stream)
	discription_panel.animate_show()
	DampedOscillator.animate(icon, "scale", randf_range(400, 450), randf_range(5, 10), randf_range(10, 15), 0.5)


func _on_mouse_exited() -> void:
	discription_panel.hide()
