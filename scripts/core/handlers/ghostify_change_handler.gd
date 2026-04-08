class_name GhostifyChangeHandler
extends RefCounted


func apply(change: ChangeRecord, state: SimulationState, _context: CompileContext) -> void:
	if change == null or change.subject_id == &"":
		return
	if not state.subject_exists(change.subject_id):
		return
	state.set_subject_ghost(change.subject_id, true)
