class_name ReplayPayloadBuilder
extends RefCounted


func build_steps(
	defaults: WorldDefaults,
	surviving_queue_entries: Array[ChangeRecord],
	live_player_position: Vector2i = Vector2i(999999, 999999)
) -> Array[Dictionary]:
	if defaults == null:
		return []
	var remembered_positions: Dictionary[StringName, Vector2i] = defaults.default_entity_positions.duplicate()
	var steps: Array[Dictionary] = []
	for entry: ChangeRecord in surviving_queue_entries:
		if entry == null:
			continue
		if entry.type != ChangeRecord.ChangeType.POSITION:
			continue
		if entry.subject_id == &"":
			continue
		var from_exists: bool = remembered_positions.has(entry.subject_id)
		var from_pos: Vector2i = remembered_positions.get(entry.subject_id, Vector2i.ZERO)
		var to_pos: Vector2i = entry.target_position
		if from_exists and from_pos == to_pos:
			continue
		var path_steps: Array[Dictionary] = _expand_position_micro_steps(entry.subject_id, from_pos, to_pos, from_exists, live_player_position)
		for path_step: Dictionary in path_steps:
			steps.append(path_step)
		remembered_positions[entry.subject_id] = to_pos
	return steps


func _expand_position_micro_steps(
	subject: StringName,
	from_pos: Vector2i,
	to_pos: Vector2i,
	from_exists: bool,
	live_player_position: Vector2i
) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	var current: Vector2i = from_pos
	if not from_exists:
		steps.append(_build_step(subject, from_pos, to_pos, from_exists, live_player_position))
		return steps
	while current.x != to_pos.x:
		var x_dir: int = 1 if to_pos.x > current.x else -1
		var next_x := Vector2i(current.x + x_dir, current.y)
		steps.append(_build_step(subject, current, next_x, from_exists, live_player_position))
		current = next_x
		from_exists = true
	while current.y != to_pos.y:
		var y_dir: int = 1 if to_pos.y > current.y else -1
		var next_y := Vector2i(current.x, current.y + y_dir)
		steps.append(_build_step(subject, current, next_y, from_exists, live_player_position))
		current = next_y
		from_exists = true
	return steps


func _build_step(
	subject: StringName,
	from_pos: Vector2i,
	to_pos: Vector2i,
	from_exists: bool,
	live_player_position: Vector2i
) -> Dictionary:
	return {
		"type": ChangeRecord.ChangeType.POSITION,
		"from": from_pos,
		"to": to_pos,
		"subject": subject,
		"from_exists": from_exists,
		"to_exists": true,
		"is_conflict": to_pos == live_player_position,
	}
