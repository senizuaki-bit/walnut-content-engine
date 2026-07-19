class_name EnemySignal
extends Node


signal on_enemy_die

func emit_on_enemy_die() -> void:
	on_enemy_die.emit()
