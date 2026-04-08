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
	var remembered_position_by_subject: Dictionary[StringName, Vector2i] = {}
	var remembered_is_ghost_by_subject: Dictionary[StringName, bool] = {}

	for entry: ChangeRecord in surviving_queue_entries:
		if entry == null:
			continue
		if not _is_replayable_position_affecting_entry(entry):
			continue
		var subject_id: StringName = entry.subject_id
		var remembered_state: Dictionary = _resolve_current_replay_state(
			defaults,
			remembered_position_by_subject,
			remembered_is_ghost_by_subject,
			subject_id
		)
		if not bool(remembered_state.get("exists", false)):
			continue
		if entry.type == ChangeRecord.ChangeType.POSITION:
			var path_steps: Array[Dictionary] = PositionPathHelper.expand_without_conflict(
				subject_id,
				remembered_state["position"],
				entry.target_position,
				true
			)
			for path_step: Dictionary in path_steps:
				steps.append(path_step)
			var terminal_position: Vector2i = _resolve_visual_terminal_for_steps(path_steps, entry.target_position)
			remembered_position_by_subject[subject_id] = terminal_position
			remembered_is_ghost_by_subject[subject_id] = false
		elif entry.type == ChangeRecord.ChangeType.GHOST:
			var ghost_path_steps: Array[Dictionary] = _build_auto_ghost_steps(
				subject_id,
				remembered_state["position"],
				true
			)
			for ghost_step: Dictionary in ghost_path_steps:
				steps.append(ghost_step)
			remembered_position_by_subject[subject_id] = remembered_state["position"]
			remembered_is_ghost_by_subject[subject_id] = true
	return steps


func _resolve_current_replay_state(
	defaults: WorldDefaults,
	remembered_position_by_subject: Dictionary[StringName, Vector2i],
	remembered_is_ghost_by_subject: Dictionary[StringName, bool],
	subject_id: StringName
) -> Dictionary:
	if remembered_position_by_subject.has(subject_id):
		return {
			"exists": true,
			"position": remembered_position_by_subject[subject_id],
			"is_ghost": bool(remembered_is_ghost_by_subject.get(subject_id, false)),
		}
	if defaults.default_entity_positions.has(subject_id):
		return {
			"exists": true,
			"position": defaults.default_entity_positions[subject_id],
			"is_ghost": false,
		}
	return {
		"exists": false,
		"position": Vector2i.ZERO,
		"is_ghost": false,
	}


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
