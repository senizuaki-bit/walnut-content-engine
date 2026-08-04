class_name DamageText
extends Control

@onready var label: Label = %Label

var damgea :float :set = _set_damgae
var lifetime_remaining := 0.5

func _set_damgae(value: float) ->void:
	damgea = value
	label.text = str(damgea)
	lifetime_remaining = 0.5


func _process(delta: float) -> void:
	lifetime_remaining -= delta
	if lifetime_remaining > 0.0:
		return
	set_process(false)
	queue_free()
