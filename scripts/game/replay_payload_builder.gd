class_name ReplayPayloadBuilder
extends RefCounted


func build_steps(defaults: WorldDefaults, queue_before_compile: Array[ChangeRecord], pushed_out: Array[ChangeRecord]) -> Array[Dictionary]:
	if pushed_out.is_empty():
		return []
	var tracked: Dictionary = defaults.default_entity_positions.duplicate()
	var steps: Array[Dictionary] = []
	for entry: ChangeRecord in queue_before_compile:
		if _contains_change(pushed_out, entry):
			steps.append(_build_step(tracked, entry))
		_apply_change_to_tracking(tracked, entry)
	return steps


func _contains_change(changes: Array[ChangeRecord], target: ChangeRecord) -> bool:
	for item: ChangeRecord in changes:
		if item == target:
			return true
	return false


func _build_step(tracked: Dictionary, change: ChangeRecord) -> Dictionary:
	if change.type == ChangeRecord.ChangeType.EMPTY:
		return {
			"type": change.type,
			"from": Vector2i.ZERO,
			"to": Vector2i.ZERO,
			"subject": change.subject_id,
		}
	var from_pos: Vector2i = tracked.get(change.subject_id, change.target_position)
	return {
		"type": change.type,
		"from": from_pos,
		"to": change.target_position,
		"subject": change.subject_id,
	}


func _apply_change_to_tracking(tracked: Dictionary, change: ChangeRecord) -> void:
	if change.type == ChangeRecord.ChangeType.EMPTY:
		return
	tracked[change.subject_id] = change.target_position
