class_name DamageText
extends Control

@onready var label: Label = %Label

var damgea :float :set = _set_damgae

func _set_damgae(value: float) ->void:
	damgea = value
	label.text = str(damgea)
	await get_tree().create_timer(0.5).timeout
	queue_free()
