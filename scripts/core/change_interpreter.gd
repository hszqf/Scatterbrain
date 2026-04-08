class_name ChangeInterpreter
extends RefCounted

var _move_handler: MoveChangeHandler = MoveChangeHandler.new()
var _ghost_handler: GhostifyChangeHandler = GhostifyChangeHandler.new()


func interpret(
	changes: Array[ChangeRecord],
	state: SimulationState,
	context: CompileContext,
	event_collector: Array[Dictionary] = []
) -> void:
	for change: ChangeRecord in changes:
		if change == null:
			continue
		var before_position: Vector2i = state.subject_position(change.subject_id)
		match change.type:
			ChangeRecord.ChangeType.POSITION:
				_move_handler.apply(change, state, context)
			ChangeRecord.ChangeType.GHOST:
				_ghost_handler.apply(change, state, context)
			_:
				continue
		if event_collector != null and change.subject_id != &"":
			event_collector.append({
				"change": change,
				"from": before_position,
				"to": state.subject_position(change.subject_id),
				"ends_as_ghost": bool(state.is_ghost_by_subject.get(change.subject_id, false)),
			})
