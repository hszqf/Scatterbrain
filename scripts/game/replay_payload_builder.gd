class_name ReplayPayloadBuilder
extends RefCounted

const PRESENTATION_MOVE: StringName = &"move"
const PRESENTATION_EVICT_MOVE: StringName = &"evict_move"
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
	for queue_index: int in range(surviving_queue_entries.size()):
		var entry: ChangeRecord = surviving_queue_entries[queue_index]
		if entry == null:
			continue
		if entry.type == ChangeRecord.ChangeType.EMPTY:
			steps.append({
				"type": ChangeRecord.ChangeType.EMPTY,
				"presentation_kind": PRESENTATION_BEAT,
				"queue_index": queue_index,
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
				steps.append({
					"type": ChangeRecord.ChangeType.POSITION,
					"from": from_pos,
					"to": to_pos,
					"subject": change.subject_id,
					"from_exists": true,
					"to_exists": true,
					"appears": false,
					"is_conflict": bool(event.get("is_conflict", false)),
					"ends_as_ghost": bool(event.get("ends_as_ghost", false)),
					"presentation_kind": PRESENTATION_MOVE,
					"queue_index": queue_index,
				})
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
					"queue_index": queue_index,
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


func build_evicted_steps(
	defaults: WorldDefaults,
	previous_queue_entries: Array[ChangeRecord],
	pushed_out_changes: Array[ChangeRecord],
	resulting_queue_entries: Array[ChangeRecord],
	live_player_position: Vector2i = Vector2i(999999, 999999)
) -> Array[Dictionary]:
	if defaults == null:
		return []
	if previous_queue_entries.is_empty() or pushed_out_changes.is_empty():
		return []
	var steps: Array[Dictionary] = []
	var rolling_entries: Array[ChangeRecord] = previous_queue_entries.duplicate()
	var before_state: SimulationState = _simulate_queue(defaults, rolling_entries, live_player_position)
	for evict_index: int in range(pushed_out_changes.size()):
		var pushed_out: ChangeRecord = pushed_out_changes[evict_index]
		if pushed_out == null:
			continue
		_remove_first_matching_change(rolling_entries, pushed_out)
		if evict_index == pushed_out_changes.size() - 1 and not _queue_summaries_equal(rolling_entries, resulting_queue_entries):
			rolling_entries = resulting_queue_entries.duplicate()
		var after_state: SimulationState = _simulate_queue(defaults, rolling_entries, live_player_position)
		if pushed_out.type == ChangeRecord.ChangeType.POSITION:
			var moved_subjects: Array[StringName] = _collect_position_changed_subjects(before_state, after_state)
			for subject_id: StringName in moved_subjects:
				steps.append({
					"type": ChangeRecord.ChangeType.POSITION,
					"from": before_state.subject_position(subject_id),
					"to": after_state.subject_position(subject_id),
					"subject": subject_id,
					"from_exists": before_state.subject_exists(subject_id),
					"to_exists": after_state.subject_exists(subject_id),
					"appears": false,
					"is_conflict": false,
					"ends_as_ghost": bool(after_state.is_ghost_by_subject.get(subject_id, false)),
					"presentation_kind": PRESENTATION_EVICT_MOVE,
					"queue_index": evict_index,
					"phase": &"evict",
				})
		before_state = after_state
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


func _simulate_queue(
	defaults: WorldDefaults,
	queue_entries: Array[ChangeRecord],
	live_player_position: Vector2i
) -> SimulationState:
	var state := SimulationState.new()
	state.setup_from_defaults(defaults, live_player_position)
	if queue_entries.is_empty():
		return state
	var context := CompileContext.new()
	_interpreter.interpret(queue_entries, state, context)
	return state


func _collect_position_changed_subjects(before_state: SimulationState, after_state: SimulationState) -> Array[StringName]:
	var changed: Array[StringName] = []
	var subject_keys: Dictionary[StringName, bool] = {}
	for subject_id: StringName in before_state.position_by_subject.keys():
		subject_keys[subject_id] = true
	for subject_id: StringName in after_state.position_by_subject.keys():
		subject_keys[subject_id] = true
	for subject_id: StringName in subject_keys.keys():
		var before_exists: bool = before_state.subject_exists(subject_id)
		var after_exists: bool = after_state.subject_exists(subject_id)
		if not before_exists or not after_exists:
			continue
		if before_state.subject_position(subject_id) == after_state.subject_position(subject_id):
			continue
		changed.append(subject_id)
	changed.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	return changed


func _remove_first_matching_change(entries: Array[ChangeRecord], target: ChangeRecord) -> void:
	for i: int in range(entries.size()):
		var candidate: ChangeRecord = entries[i]
		if candidate == target or _change_records_match(candidate, target):
			entries.remove_at(i)
			return


func _change_records_match(a: ChangeRecord, b: ChangeRecord) -> bool:
	if a == null or b == null:
		return false
	return a.type == b.type \
		and a.subject_id == b.subject_id \
		and a.target_position == b.target_position \
		and a.move_delta == b.move_delta \
		and a.pinned == b.pinned \
		and a.source_kind == b.source_kind \
		and a.debug_label == b.debug_label


func _queue_summaries_equal(a_entries: Array[ChangeRecord], b_entries: Array[ChangeRecord]) -> bool:
	if a_entries.size() != b_entries.size():
		return false
	for i: int in range(a_entries.size()):
		var a_entry: ChangeRecord = a_entries[i]
		var b_entry: ChangeRecord = b_entries[i]
		if not _change_records_match(a_entry, b_entry):
			return false
	return true
