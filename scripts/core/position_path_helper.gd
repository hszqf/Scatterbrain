class_name PositionPathHelper
extends RefCounted


static func expand_without_conflict(
	subject_id: StringName,
	from_pos: Vector2i,
	to_pos: Vector2i,
	from_exists: bool
) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	if not from_exists:
		steps.append({
			"type": ChangeRecord.ChangeType.POSITION,
			"from": from_pos,
			"to": to_pos,
			"subject": subject_id,
			"from_exists": false,
			"to_exists": true,
			"is_conflict": false,
		})
		return steps

	var current: Vector2i = from_pos
	while current.x != to_pos.x:
		var x_dir: int = 1 if to_pos.x > current.x else -1
		var next_x := Vector2i(current.x + x_dir, current.y)
		steps.append({
			"type": ChangeRecord.ChangeType.POSITION,
			"from": current,
			"to": next_x,
			"subject": subject_id,
			"from_exists": true,
			"to_exists": true,
			"is_conflict": false,
		})
		current = next_x

	while current.y != to_pos.y:
		var y_dir: int = 1 if to_pos.y > current.y else -1
		var next_y := Vector2i(current.x, current.y + y_dir)
		steps.append({
			"type": ChangeRecord.ChangeType.POSITION,
			"from": current,
			"to": next_y,
			"subject": subject_id,
			"from_exists": true,
			"to_exists": true,
			"is_conflict": false,
		})
		current = next_y

	return steps


static func expand_with_player_conflict(
	subject_id: StringName,
	from_pos: Vector2i,
	to_pos: Vector2i,
	from_exists: bool,
	live_player_position: Vector2i
) -> Dictionary:
	var steps: Array[Dictionary] = []
	if not from_exists:
		steps.append(_build_step(subject_id, from_pos, to_pos, from_exists, live_player_position))
		var spawn_conflict: bool = to_pos == live_player_position
		return {
			"steps": steps,
			"final_position": to_pos,
			"did_truncate": spawn_conflict,
			"truncated_by_player_conflict": spawn_conflict,
			"ends_as_ghost": spawn_conflict,
		}

	var current: Vector2i = from_pos
	while current.x != to_pos.x:
		var x_dir: int = 1 if to_pos.x > current.x else -1
		var next_x := Vector2i(current.x + x_dir, current.y)
		var x_step: Dictionary = _build_step(subject_id, current, next_x, from_exists, live_player_position)
		steps.append(x_step)
		current = next_x
		from_exists = true
		if bool(x_step.get("is_conflict", false)):
			return {
				"steps": steps,
				"final_position": current,
				"did_truncate": true,
				"truncated_by_player_conflict": true,
				"ends_as_ghost": true,
			}

	while current.y != to_pos.y:
		var y_dir: int = 1 if to_pos.y > current.y else -1
		var next_y := Vector2i(current.x, current.y + y_dir)
		var y_step: Dictionary = _build_step(subject_id, current, next_y, from_exists, live_player_position)
		steps.append(y_step)
		current = next_y
		from_exists = true
		if bool(y_step.get("is_conflict", false)):
			return {
				"steps": steps,
				"final_position": current,
				"did_truncate": true,
				"truncated_by_player_conflict": true,
				"ends_as_ghost": true,
			}

	return {
		"steps": steps,
		"final_position": current,
		"did_truncate": false,
		"truncated_by_player_conflict": false,
		"ends_as_ghost": false,
	}


static func _build_step(
	subject_id: StringName,
	from_pos: Vector2i,
	to_pos: Vector2i,
	from_exists: bool,
	live_player_position: Vector2i
) -> Dictionary:
	return {
		"type": ChangeRecord.ChangeType.POSITION,
		"from": from_pos,
		"to": to_pos,
		"subject": subject_id,
		"from_exists": from_exists,
		"to_exists": true,
		"is_conflict": to_pos == live_player_position,
	}
