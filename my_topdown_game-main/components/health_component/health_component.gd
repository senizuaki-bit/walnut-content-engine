@icon("res://assets/icon/heart-icon.svg")
class_name HealthComponent
extends Node2D

signal on_unit_damaged(amount: float) ## 攻击信号
signal on_unit_healed(amount: float) ## 健康变化信号
signal on_unit_dead ## 单位死亡信号

var max_health: float ## 最大血量
var current_health: float ## 当前血量


## 初始化血量
func init_health(value: float) -> void:
	max_health = value
	current_health = value

## 受击函数
func take_damage(value: float) -> void:
	if current_health >= 0.0: # 建议类型统一
		current_health -= value
		on_unit_damaged.emit(value)
		if current_health <= 0.0:
			die()

## 死亡
func die() -> void:
	current_health = 0.0
	on_unit_dead.emit()


## 健康
func heal(value: float) -> void:
	if current_health >= max_health: return
	current_health = min(max_health, current_health + value)
	on_unit_healed.emit(value)
