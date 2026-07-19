class_name Protal
extends Area2D


func _on_body_entered(_body: Node2D) -> void:
	EventBus.rooms.emit_on_portal_reached()
