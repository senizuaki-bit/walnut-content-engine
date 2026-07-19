class_name WeaponCard
extends TextureButton

@export var hover_stream: AudioStream
@export var weapon_resource: WeaponResource: set = _set_weapon_resource

@onready var icon: TextureRect = %Icon
@onready var selector: TextureRect = %Selector
@onready var discription_panel: DiscriptionPanel = %DiscriptionPanel


func _set_weapon_resource(value: WeaponResource) -> void:
	if not is_node_ready(): 
		await ready
	weapon_resource = value
	icon.texture = weapon_resource.icon
	discription_panel.text = tr(weapon_resource.description)


func _on_mouse_entered() -> void:
	SFXPlayer.play(hover_stream)
	discription_panel.animate_show()
	DampedOscillator.animate(icon, "scale", randf_range(400, 450), randf_range(5, 10), randf_range(10, 15), 0.5)
	

func _on_mouse_exited() -> void:
	discription_panel.hide()
