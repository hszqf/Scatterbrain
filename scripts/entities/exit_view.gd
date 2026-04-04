class_name ExitView
extends Node2D

## Visual exit marker.

func set_board_position(pos: Vector2i, cell_size: int) -> void:
	position = Vector2((pos.x + 0.5) * cell_size, (pos.y + 0.5) * cell_size)
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 22.0, Color("48d7d7"))
