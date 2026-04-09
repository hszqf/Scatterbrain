class_name ReplayPayloadBuilder
extends RefCounted

const PRESENTATION_MOVE: StringName = &"move"
const PRESENTATION_GHOSTIFY: StringName = &"ghostify"
const PRESENTATION_BEAT: StringName = &"beat"

var _interpreter: ChangeInterpreter = ChangeInterpreter.new()


func build_steps(
	defaults: WorldDefaults,
	surviving_queue_entries: Array[ChangeRecord],
	live_player_position: Vector2i = Vector2i(999999, 999999)
) -> Array[Dictionary]:
	if defaults == null:
		return []
	var steps: Array[Dictionary] = []
	var state := SimulationState.new()
	state.setup_from_defaults(defaults, live_player_position)
	for entry: ChangeRecord in surviving_queue_entries:
		if entry == null:
			continue
		if entry.type == ChangeRecord.ChangeType.EMPTY:
			steps.append({
				"type": ChangeRecord.ChangeType.EMPTY,
				"presentation_kind": PRESENTATION_BEAT,
			})
			continue
		if not _is_replayable_position_affecting_entry(entry):
			continue
		var context := CompileContext.new()
		var events: Array[Dictionary] = []
		_interpreter.interpret([entry], state, context, events)
		for event: Dictionary in events:
			var change: ChangeRecord = event.get("change")
			if change == null:
				continue
			var from_pos: Vector2i = event.get("from", Vector2i.ZERO)
			var to_pos: Vector2i = event.get("to", from_pos)
			if change.type == ChangeRecord.ChangeType.POSITION:
				for step: Dictionary in PositionPathHelper.expand_without_conflict(change.subject_id, from_pos, to_pos, true):
					step["presentation_kind"] = PRESENTATION_MOVE
					steps.append(step)
			elif change.type == ChangeRecord.ChangeType.GHOST:
				steps.append({
					"type": ChangeRecord.ChangeType.POSITION,
					"from": from_pos,
					"to": from_pos,
					"subject": change.subject_id,
					"from_exists": true,
					"to_exists": true,
					"appears": false,
					"is_conflict": true,
					"ends_as_ghost": true,
					"presentation_kind": PRESENTATION_GHOSTIFY,
				})
	if steps.is_empty():
		return []
	var has_replayable_visual_step: bool = false
	for step: Dictionary in steps:
		if StringName(step.get("presentation_kind", PRESENTATION_BEAT)) != PRESENTATION_BEAT:
			has_replayable_visual_step = true
			break
	if not has_replayable_visual_step:
		return []
	return steps


static func _is_replayable_position_affecting_entry(entry: ChangeRecord) -> bool:
	if entry == null:
		return false
	if entry.subject_id == &"":
		return false
	var is_replayable_position: bool = (
		entry.type == ChangeRecord.ChangeType.POSITION
		and entry.source_kind == ChangeRecord.SourceKind.REMEMBERED_REBUILD
	)
	var is_replayable_ghost: bool = (
		entry.type == ChangeRecord.ChangeType.GHOST
		and entry.source_kind == ChangeRecord.SourceKind.AUTO_GHOST
	)
	return is_replayable_position or is_replayable_ghost
