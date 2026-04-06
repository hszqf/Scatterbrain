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
	var subjects_with_remembered_position: Dictionary[StringName, bool] = {}
	for queued_entry: ChangeRecord in surviving_queue_entries:
		if queued_entry == null:
			continue
		if queued_entry.type == ChangeRecord.ChangeType.POSITION \
			and queued_entry.source_kind == ChangeRecord.SourceKind.REMEMBERED_REBUILD \
			and queued_entry.subject_id != &"":
			subjects_with_remembered_position[queued_entry.subject_id] = true
	var steps: Array[Dictionary] = []
	for entry: ChangeRecord in surviving_queue_entries:
		if entry == null:
			continue
		if entry.type != ChangeRecord.ChangeType.POSITION and entry.type != ChangeRecord.ChangeType.GHOST:
			continue
		if entry.subject_id == &"":
			continue
		var from_exists: bool = remembered_positions.has(entry.subject_id)
		var from_pos: Vector2i = remembered_positions.get(entry.subject_id, Vector2i.ZERO)
		var to_pos: Vector2i = entry.target_position
		if from_exists and from_pos == to_pos:
			continue
		var path_steps: Array[Dictionary] = []
		if entry.type == ChangeRecord.ChangeType.POSITION and entry.source_kind == ChangeRecord.SourceKind.REMEMBERED_REBUILD:
			path_steps = _build_remembered_position_steps(
				entry.subject_id,
				from_pos,
				to_pos,
				from_exists,
				live_player_position
			)
		elif entry.type == ChangeRecord.ChangeType.GHOST and entry.source_kind == ChangeRecord.SourceKind.AUTO_GHOST:
			if subjects_with_remembered_position.has(entry.subject_id):
				continue
			path_steps = _build_auto_ghost_steps(
				entry.subject_id,
				from_pos,
				to_pos,
				from_exists
			)
		else:
			continue
		for path_step: Dictionary in path_steps:
			steps.append(path_step)
		remembered_positions[entry.subject_id] = to_pos
	return steps


func _build_remembered_position_steps(
	subject_id: StringName,
	from_pos: Vector2i,
	to_pos: Vector2i,
	from_exists: bool,
	live_player_position: Vector2i
) -> Array[Dictionary]:
	var path_result: Dictionary = PositionPathHelper.expand_with_player_conflict(
		subject_id,
		from_pos,
		to_pos,
		from_exists,
		live_player_position
	)
	return path_result.get("steps", [])


func _build_auto_ghost_steps(
	subject_id: StringName,
	from_pos: Vector2i,
	to_pos: Vector2i,
	from_exists: bool
) -> Array[Dictionary]:
	var no_player_conflict: Vector2i = Vector2i(999999, 999999)
	var path_result: Dictionary = PositionPathHelper.expand_with_player_conflict(
		subject_id,
		from_pos,
		to_pos,
		from_exists,
		no_player_conflict
	)
	var steps: Array[Dictionary] = path_result.get("steps", [])
	if steps.is_empty():
		return steps
	var last_index: int = steps.size() - 1
	var terminal_step: Dictionary = steps[last_index].duplicate()
	terminal_step["is_conflict"] = true
	steps[last_index] = terminal_step
	return steps
