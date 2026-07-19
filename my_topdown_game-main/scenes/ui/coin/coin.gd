class_name Coin
extends Area2D


func _on_body_entered(body: Node2D) -> void:
	if not body is Player: return
	Global.conis += 1
	EventBus.shop.emit_on_coin_picked()
	queue_free()
