class_name ReplayPayloadBuilder
extends RefCounted


const REPLAYABLE_POSITION_SOURCE: ChangeRecord.SourceKind = ChangeRecord.SourceKind.REMEMBERED_REBUILD
const REPLAYABLE_GHOST_SOURCE: ChangeRecord.SourceKind = ChangeRecord.SourceKind.AUTO_GHOST


func build_steps(
	defaults: WorldDefaults,
	surviving_queue_entries: Array[ChangeRecord],
	live_player_position: Vector2i = Vector2i(999999, 999999)
) -> Array[Dictionary]:
	if defaults == null:
		return []
	var steps: Array[Dictionary] = []
	var replay_entity_positions_by_subject: Dictionary[StringName, Vector2i] = defaults.default_entity_positions.duplicate()
	var replay_ghost_positions_by_subject: Dictionary[StringName, Vector2i] = {}
	for entry: ChangeRecord in surviving_queue_entries:
		if entry == null:
			continue
		if not _is_replayable_position_affecting_entry(entry):
			continue
		var subject_id: StringName = entry.subject_id
		if entry.type == ChangeRecord.ChangeType.POSITION:
			var from_data: Dictionary = _resolve_from_for_position(defaults, replay_entity_positions_by_subject, replay_ghost_positions_by_subject, subject_id)
			var path_steps: Array[Dictionary] = _build_remembered_position_steps(
				subject_id,
				from_data["from_pos"],
				entry.target_position,
				from_data["from_exists"],
				live_player_position
			)
			for path_step: Dictionary in path_steps:
				steps.append(path_step)
			replay_entity_positions_by_subject[subject_id] = entry.target_position
			replay_ghost_positions_by_subject.erase(subject_id)
		elif entry.type == ChangeRecord.ChangeType.GHOST:
			var ghost_from_data: Dictionary = _resolve_from_for_ghost(defaults, replay_entity_positions_by_subject, replay_ghost_positions_by_subject, subject_id)
			var ghost_path_steps: Array[Dictionary] = _build_auto_ghost_steps(
				subject_id,
				ghost_from_data["from_pos"],
				entry.target_position,
				ghost_from_data["from_exists"]
			)
			for ghost_step: Dictionary in ghost_path_steps:
				steps.append(ghost_step)
			replay_entity_positions_by_subject.erase(subject_id)
			replay_ghost_positions_by_subject[subject_id] = entry.target_position
	return steps


func _resolve_from_for_position(
	defaults: WorldDefaults,
	replay_entity_positions_by_subject: Dictionary[StringName, Vector2i],
	replay_ghost_positions_by_subject: Dictionary[StringName, Vector2i],
	subject_id: StringName
) -> Dictionary:
	if replay_entity_positions_by_subject.has(subject_id):
		return {
			"from_pos": replay_entity_positions_by_subject[subject_id],
			"from_exists": true,
		}
	if replay_ghost_positions_by_subject.has(subject_id):
		return {
			"from_pos": replay_ghost_positions_by_subject[subject_id],
			"from_exists": true,
		}
	if defaults.default_entity_positions.has(subject_id):
		return {
			"from_pos": defaults.default_entity_positions[subject_id],
			"from_exists": true,
		}
	return {
		"from_pos": Vector2i.ZERO,
		"from_exists": false,
	}


func _resolve_from_for_ghost(
	defaults: WorldDefaults,
	replay_entity_positions_by_subject: Dictionary[StringName, Vector2i],
	replay_ghost_positions_by_subject: Dictionary[StringName, Vector2i],
	subject_id: StringName
) -> Dictionary:
	if replay_entity_positions_by_subject.has(subject_id):
		return {
			"from_pos": replay_entity_positions_by_subject[subject_id],
			"from_exists": true,
		}
	if replay_ghost_positions_by_subject.has(subject_id):
		return {
			"from_pos": replay_ghost_positions_by_subject[subject_id],
			"from_exists": true,
		}
	if defaults.default_entity_positions.has(subject_id):
		return {
			"from_pos": defaults.default_entity_positions[subject_id],
			"from_exists": true,
		}
	return {
		"from_pos": Vector2i.ZERO,
		"from_exists": false,
	}


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
	var path_result: Dictionary = PositionPathHelper.expand_with_player_conflict(
		subject_id,
		from_pos,
		to_pos,
		from_exists,
		Vector2i(999999, 999999)
	)
	var steps: Array[Dictionary] = path_result.get("steps", [])
	if steps.is_empty():
		return steps
	var last_index: int = steps.size() - 1
	for index: int in range(steps.size()):
		var step: Dictionary = steps[index]
		step["ends_as_ghost"] = index == last_index
		step["is_conflict"] = index == last_index
		steps[index] = step
	return steps


static func _is_replayable_position_affecting_entry(entry: ChangeRecord) -> bool:
	if entry == null:
		return false
	if entry.subject_id == &"":
		return false
	var is_replayable_position: bool = entry.type == ChangeRecord.ChangeType.POSITION \
		and entry.source_kind == REPLAYABLE_POSITION_SOURCE
	var is_replayable_ghost: bool = entry.type == ChangeRecord.ChangeType.GHOST \
		and entry.source_kind == REPLAYABLE_GHOST_SOURCE
	return is_replayable_position or is_replayable_ghost
