class_name InputRouter
extends RefCounted

## Maps player input into game intents.
enum Intent {
	NONE,
	MOVE_LEFT,
	MOVE_RIGHT,
	MOVE_UP,
	MOVE_DOWN,
	EMPTY_CHANGE,
	RESTART,
}


func poll_intent() -> Intent:
	if Input.is_action_just_pressed("restart_level"):
		return Intent.RESTART
	if Input.is_action_just_pressed("empty_change"):
		return Intent.EMPTY_CHANGE
	if Input.is_action_just_pressed("move_left"):
		return Intent.MOVE_LEFT
	if Input.is_action_just_pressed("move_right"):
		return Intent.MOVE_RIGHT
	if Input.is_action_just_pressed("move_up"):
		return Intent.MOVE_UP
	if Input.is_action_just_pressed("move_down"):
		return Intent.MOVE_DOWN
	return Intent.NONE


func intent_to_direction(intent: Intent) -> Vector2i:
	match intent:
		Intent.MOVE_LEFT:
			return Vector2i.LEFT
		Intent.MOVE_RIGHT:
			return Vector2i.RIGHT
		Intent.MOVE_UP:
			return Vector2i.UP
		Intent.MOVE_DOWN:
			return Vector2i.DOWN
		_:
			return Vector2i.ZERO
