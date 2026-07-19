class_name Prop
extends Area2D

@onready var icon: Sprite2D = %Icon

func _on_body_entered(_body: Node2D) -> void:
	var range_number = randi_range(0, 1)
	DampedOscillator.animate(icon, "scale", 250, 10, 17, 0.5 * range_number)
