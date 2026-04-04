class_name ReplayPayloadBuilder
extends RefCounted


func build_steps(defaults: WorldDefaults, surviving_queue_entries: Array[ChangeRecord]) -> Array[Dictionary]:
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
		steps.append({
			"type": ChangeRecord.ChangeType.POSITION,
			"from": from_pos,
			"to": to_pos,
			"subject": entry.subject_id,
			"from_exists": from_exists,
			"to_exists": true,
		})
		remembered_positions[entry.subject_id] = to_pos
	return steps
