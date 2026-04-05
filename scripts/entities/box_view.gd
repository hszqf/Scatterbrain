class_name BoxView
extends Node2D

## Visual box block, supports ghost appearance.
var _is_ghost: bool = false
var _is_conflict: bool = false


func set_board_position(pos: Vector2i, cell_size: int) -> void:
	position = Vector2((pos.x + 0.5) * cell_size, (pos.y + 0.5) * cell_size)
	queue_redraw()


func set_is_ghost(value: bool) -> void:
	_is_ghost = value
	queue_redraw()


func set_is_conflict(value: bool) -> void:
	_is_conflict = value
	queue_redraw()


func is_ghost() -> bool:
	return _is_ghost


func is_conflict() -> bool:
	return _is_conflict


func _draw() -> void:
	var color: Color = Color("e6c547")
	if _is_ghost:
		color.a = 0.45
	if _is_conflict:
		color = Color("ff4a5f")
		color.a = 0.72
	draw_rect(Rect2(Vector2(-26, -26), Vector2(52, 52)), color, true)
