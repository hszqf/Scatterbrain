class_name PlayerView
extends Node2D

## Visual player block.
var board_size_hint: Vector2i = Vector2i.ZERO


func set_board_position(pos: Vector2i, cell_size: int) -> void:
	position = Vector2((pos.x + 0.5) * cell_size, (pos.y + 0.5) * cell_size)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2(-28, -28), Vector2(56, 56)), Color.WHITE, true)
