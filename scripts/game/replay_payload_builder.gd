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
		var path_result: Dictionary = PositionPathHelper.expand_with_player_conflict(
			entry.subject_id,
			from_pos,
			to_pos,
			from_exists,
			live_player_position
		)
		var path_steps: Array[Dictionary] = path_result.get("steps", [])
		for path_step: Dictionary in path_steps:
			steps.append(path_step)
		remembered_positions[entry.subject_id] = to_pos
	return steps
