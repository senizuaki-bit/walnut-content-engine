class_name DiscriptionPanel
extends Control

@onready var discription_label: Label = %DiscriptionLabel

var text: String: set = _set_text


func _set_text(value: String) -> void:
	text = value
	discription_label.text = text


func animate_show() -> void:
	DampedOscillator.animate(self, "scale", randf_range(400, 450), randf_range(5, 10), randf_range(10, 15), 0.5)
	DampedOscillator.animate(self, "rotation_dogrees", 300, 7.5, 15, 0.5 * randf_range(-20, 20))
	show()
