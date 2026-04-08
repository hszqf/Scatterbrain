class_name MoveChangeHandler
extends RefCounted


func apply(change: ChangeRecord, state: SimulationState, context: CompileContext) -> void:
	if change == null or change.subject_id == &"":
		return
	state.ensure_subject(change.subject_id)
	if not state.subject_exists(change.subject_id):
		return
	var current_position: Vector2i = state.subject_position(change.subject_id)
	var delta: Vector2i = change.move_delta
	if delta == Vector2i.ZERO and change.target_position != Vector2i.ZERO:
		delta = change.target_position - current_position
	var next_position: Vector2i = current_position + delta
	state.set_subject_position(change.subject_id, next_position)
	state.set_subject_ghost(change.subject_id, false)
