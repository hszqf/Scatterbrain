class_name PlayerView
extends Node2D

## Visual player block.
var board_size_hint: Vector2i = Vector2i.ZERO
var _pulse_tween: Tween


func set_board_position(pos: Vector2i, cell_size: int) -> void:
	position = Vector2((pos.x + 0.5) * cell_size, (pos.y + 0.5) * cell_size)
	queue_redraw()


func play_meditate_pulse(action_duration: float, peak_scale: float = 1.14) -> void:
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
	var clamped_duration: float = maxf(0.01, action_duration)
	var in_duration: float = clamped_duration * 0.42
	var out_duration: float = clamped_duration - in_duration
	scale = Vector2.ONE
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "scale", Vector2(peak_scale, peak_scale), in_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(self, "scale", Vector2.ONE, out_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _pulse_tween.finished
	_pulse_tween = null


func _draw() -> void:
	draw_circle(Vector2.ZERO, 22.0, Color("48d7d7"))
