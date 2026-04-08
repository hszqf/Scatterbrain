class_name CompileContext
extends RefCounted

var generated_changes: Array[ChangeRecord] = []
var generated_ghost_changes: Array[ChangeRecord] = []


func add_generated_change(change: ChangeRecord) -> void:
	if change == null:
		return
	if _contains_change(generated_changes, change):
		return
	generated_changes.append(change)
	if change.type == ChangeRecord.ChangeType.GHOST:
		generated_ghost_changes.append(change)


func clear_generated() -> void:
	generated_changes.clear()
	generated_ghost_changes.clear()


func _contains_change(changes: Array[ChangeRecord], candidate: ChangeRecord) -> bool:
	for entry: ChangeRecord in changes:
		if entry.type == candidate.type and entry.subject_id == candidate.subject_id and entry.target_position == candidate.target_position and entry.move_delta == candidate.move_delta and entry.source_kind == candidate.source_kind:
			return true
	return false
