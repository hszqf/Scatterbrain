class_name ReplayPayloadBuilder
extends RefCounted


func build_steps(defaults: WorldDefaults, queue_before_compile: Array[ChangeRecord], pushed_out: Array[ChangeRecord]) -> Array[Dictionary]:
	if pushed_out.is_empty():
		return []
	var tracked: Dictionary = defaults.default_entity_positions.duplicate()
	var steps: Array[Dictionary] = []
	for entry: ChangeRecord in queue_before_compile:
		if _contains_change(pushed_out, entry):
			var replay_step: Dictionary = _build_step(tracked, entry)
			if not replay_step.is_empty():
				steps.append(replay_step)
		_apply_change_to_tracking(tracked, entry)
	return steps


func _contains_change(changes: Array[ChangeRecord], target: ChangeRecord) -> bool:
	for item: ChangeRecord in changes:
		if item == target:
			return true
	return false


func _build_step(tracked: Dictionary, change: ChangeRecord) -> Dictionary:
	if not _is_replayable_pushed_out_change(tracked, change):
		return {}
	var from_pos: Vector2i = tracked[change.subject_id]
	var to_pos: Vector2i = change.target_position
	if from_pos == to_pos:
		return {}
	return {
		"type": change.type,
		"from": from_pos,
		"to": to_pos,
		"subject": change.subject_id,
	}


func _apply_change_to_tracking(tracked: Dictionary, change: ChangeRecord) -> void:
	if change.type == ChangeRecord.ChangeType.EMPTY:
		return
	if String(change.subject_id) == "":
		return
	tracked[change.subject_id] = change.target_position


func _is_replayable_pushed_out_change(tracked: Dictionary, change: ChangeRecord) -> bool:
	if change.type == ChangeRecord.ChangeType.EMPTY:
		return false
	if String(change.subject_id) == "":
		return false
	if not tracked.has(change.subject_id):
		return false
	return true
