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
	# Replay uses two tracks:
	# - visual_* : where a subject is currently shown during replay animation.
	# - semantic_* : remembered queue semantics after applying surviving entries.
	# Ghost[AUTO_GHOST] only changes state (solid -> ghost) and never creates motion.
	var visual_position_by_subject: Dictionary[StringName, Vector2i] = {}
	var semantic_position_by_subject: Dictionary[StringName, Vector2i] = {}
	var semantic_is_ghost_by_subject: Dictionary[StringName, bool] = {}
	var replayable_subject_seen: Dictionary[StringName, bool] = {}
	for entry: ChangeRecord in surviving_queue_entries:
		if entry == null:
			continue
		if not _is_replayable_position_affecting_entry(entry):
			continue
		var subject_id: StringName = entry.subject_id
		var is_first_surviving_replayable_entry: bool = not replayable_subject_seen.has(subject_id)
		if entry.type == ChangeRecord.ChangeType.POSITION:
			var from_data: Dictionary = _resolve_current_replay_state(
				defaults,
				visual_position_by_subject,
				semantic_position_by_subject,
				semantic_is_ghost_by_subject,
				subject_id,
				is_first_surviving_replayable_entry
			)
			var path_steps: Array[Dictionary] = _build_remembered_position_steps(
				subject_id,
				from_data["from_pos"],
				entry.target_position,
				from_data["from_exists"],
				live_player_position
			)
			for path_step: Dictionary in path_steps:
				steps.append(path_step)
			var terminal_position: Vector2i = _resolve_visual_terminal_for_steps(
				path_steps,
				entry.target_position
			)
			visual_position_by_subject[subject_id] = terminal_position
			semantic_position_by_subject[subject_id] = terminal_position
			semantic_is_ghost_by_subject[subject_id] = false
		elif entry.type == ChangeRecord.ChangeType.GHOST:
			var ghost_display_data: Dictionary = _resolve_current_replay_state(
				defaults,
				visual_position_by_subject,
				semantic_position_by_subject,
				semantic_is_ghost_by_subject,
				subject_id,
				is_first_surviving_replayable_entry
			)
			var ghost_path_steps: Array[Dictionary] = _build_auto_ghost_steps(
				subject_id,
				ghost_display_data["display_pos"],
				ghost_display_data["from_exists"]
			)
			for ghost_step: Dictionary in ghost_path_steps:
				steps.append(ghost_step)
			visual_position_by_subject[subject_id] = ghost_display_data["display_pos"]
			semantic_position_by_subject[subject_id] = ghost_display_data["display_pos"]
			semantic_is_ghost_by_subject[subject_id] = true
		replayable_subject_seen[subject_id] = true
	return steps


func _resolve_current_replay_state(
	defaults: WorldDefaults,
	visual_position_by_subject: Dictionary[StringName, Vector2i],
	semantic_position_by_subject: Dictionary[StringName, Vector2i],
	semantic_is_ghost_by_subject: Dictionary[StringName, bool],
	subject_id: StringName,
	is_first_surviving_replayable_entry: bool
) -> Dictionary:
	if semantic_position_by_subject.has(subject_id):
		return {
			"display_pos": semantic_position_by_subject[subject_id],
			"from_pos": semantic_position_by_subject[subject_id],
			"from_exists": true,
			"is_ghost": bool(semantic_is_ghost_by_subject.get(subject_id, false)),
		}
	if visual_position_by_subject.has(subject_id):
		return {
			"display_pos": visual_position_by_subject[subject_id],
			"from_pos": visual_position_by_subject[subject_id],
			"from_exists": true,
			"is_ghost": false,
		}
	if is_first_surviving_replayable_entry and defaults.default_entity_positions.has(subject_id):
		return {
			"display_pos": defaults.default_entity_positions[subject_id],
			"from_pos": defaults.default_entity_positions[subject_id],
			"from_exists": true,
			"is_ghost": false,
		}
	return {
		"display_pos": Vector2i.ZERO,
		"from_pos": Vector2i.ZERO,
		"from_exists": false,
		"is_ghost": false,
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


func _resolve_visual_terminal_for_steps(path_steps: Array[Dictionary], fallback: Vector2i) -> Vector2i:
	if path_steps.is_empty():
		return fallback
	var terminal_step: Dictionary = path_steps[path_steps.size() - 1]
	return terminal_step.get("to", fallback)


func _build_auto_ghost_steps(
	subject_id: StringName,
	display_pos: Vector2i,
	from_exists: bool
) -> Array[Dictionary]:
	# Hard rule: Ghost[AUTO_GHOST] never creates motion in replay.
	# It only ghostifies at the current display position (from == to).
	return [{
		"type": ChangeRecord.ChangeType.POSITION,
		"from": display_pos,
		"to": display_pos,
		"subject": subject_id,
		"from_exists": from_exists,
		"to_exists": true,
		"appears": not from_exists,
		"is_conflict": true,
		"ends_as_ghost": true,
	}]


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
