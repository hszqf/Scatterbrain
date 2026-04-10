class_name WorldCompiler
extends RefCounted

const MAX_ITERATIONS: int = 4

var _interpreter: ChangeInterpreter = ChangeInterpreter.new()


func compile(defaults: WorldDefaults, queue: ChangeQueue, player_position: Vector2i) -> CompileResult:
	var result := CompileResult.new()
	var normalized_queue: Array[ChangeRecord] = _normalize_queue_for_rebuild_context(queue.entries())
	var queue_entries: Array[ChangeRecord] = normalized_queue.duplicate()
	var context := CompileContext.new()
	var iteration: int = 0
	var replay_trace: Array[Dictionary] = []

	while iteration < MAX_ITERATIONS:
		iteration += 1
		var temp_queue := ChangeQueue.new()
		for entry: ChangeRecord in queue_entries:
			temp_queue.append(entry)
		var removed: Array[ChangeRecord] = temp_queue.normalize_to_capacity(defaults.memory_capacity)
		if iteration == 1:
			result.pushed_out_changes.append_array(removed)
		queue_entries = temp_queue.entries()

		var pass_index: int = iteration - 1
		replay_trace.append({
			"kind": "pass_begin",
			"pass_index": pass_index,
			"queue_entries": queue_entries.duplicate(),
		})

		context.clear_generated()
		var state := SimulationState.new()
		state.setup_from_defaults(defaults, player_position)
		var generated_this_pass: Array[ChangeRecord] = []
		var pass_interrupted: bool = false
		for queue_index: int in range(queue_entries.size()):
			var entry: ChangeRecord = queue_entries[queue_index]
			if entry == null:
				continue
			replay_trace.append({
				"kind": "queue_focus",
				"pass_index": pass_index,
				"queue_index": queue_index,
				"entry": entry,
			})
			if entry.type == ChangeRecord.ChangeType.EMPTY:
				replay_trace.append({
					"kind": "beat_empty",
					"pass_index": pass_index,
					"queue_index": queue_index,
				})
				continue
			var events: Array[Dictionary] = []
			_interpreter.interpret([entry], state, context, events)
			for event: Dictionary in events:
				var change: ChangeRecord = event.get("change")
				if change == null:
					continue
				if change.type == ChangeRecord.ChangeType.POSITION:
					replay_trace.append({
						"kind": "move",
						"pass_index": pass_index,
						"queue_index": queue_index,
						"subject": change.subject_id,
						"from": event.get("from", Vector2i.ZERO),
						"to": event.get("to", Vector2i.ZERO),
						"is_conflict": bool(event.get("is_conflict", false)),
						"ends_as_ghost": bool(event.get("ends_as_ghost", false)),
					})
				elif change.type == ChangeRecord.ChangeType.GHOST:
					replay_trace.append({
						"kind": "ghostify",
						"pass_index": pass_index,
						"queue_index": queue_index,
						"subject": change.subject_id,
						"at": event.get("from", Vector2i.ZERO),
						"is_conflict": true,
					})

			var generated_after_entry: Array[ChangeRecord] = _detect_generated_changes_after_entry(state, queue_entries, context, queue_index)
			if generated_after_entry.is_empty():
				continue

			for generated: ChangeRecord in generated_after_entry:
				if _has_same_change(queue_entries, generated):
					continue
				generated_this_pass.append(generated)
				queue_entries.append(generated)
				replay_trace.append({
					"kind": "generated_change",
					"pass_index": pass_index,
					"source_queue_index": queue_index,
					"change": generated,
				})
				if generated.type == ChangeRecord.ChangeType.GHOST and not _has_same_change(result.generated_ghost_changes, generated):
					result.generated_ghost_changes.append(generated)

			if generated_this_pass.is_empty():
				continue
			var before_normalize_queue_entries: Array[ChangeRecord] = queue_entries.duplicate()
			var normalize_queue := ChangeQueue.new()
			for q_entry: ChangeRecord in queue_entries:
				normalize_queue.append(q_entry)
			var evicted_changes: Array[ChangeRecord] = normalize_queue.normalize_to_capacity(defaults.memory_capacity)
			var after_normalize_queue_entries: Array[ChangeRecord] = normalize_queue.entries()
			queue_entries = after_normalize_queue_entries.duplicate()
			replay_trace.append({
				"kind": "queue_update",
				"pass_index": pass_index,
				"generated_changes": generated_this_pass.duplicate(),
				"evicted_changes": evicted_changes.duplicate(),
				"before_queue_entries": before_normalize_queue_entries,
				"after_queue_entries": after_normalize_queue_entries,
			})
			replay_trace.append({
				"kind": "queue_restart",
				"pass_index": pass_index,
				"next_pass_index": pass_index + 1,
				"next_queue_entries": queue_entries.duplicate(),
			})
			pass_interrupted = true
			break

		if not pass_interrupted:
			result.world = _build_projected_world(state)
			break

	result.iterations = iteration
	if result.world == null:
		var fallback_state := SimulationState.new()
		fallback_state.setup_from_defaults(defaults, player_position)
		_interpreter.interpret(queue_entries, fallback_state, CompileContext.new())
		result.world = _build_projected_world(fallback_state)
	if iteration >= MAX_ITERATIONS and not context.generated_changes.is_empty():
		result.reached_safety_limit = true
	var final_queue := ChangeQueue.new()
	for entry: ChangeRecord in queue_entries:
		final_queue.append(entry)
	final_queue.normalize_to_capacity(defaults.memory_capacity)
	result.queue_entries = final_queue.entries()
	result.replay_trace = replay_trace
	return result


func _normalize_queue_for_rebuild_context(entries: Array[ChangeRecord]) -> Array[ChangeRecord]:
	var normalized: Array[ChangeRecord] = []
	for entry: ChangeRecord in entries:
		if entry == null:
			continue
		if entry.type == ChangeRecord.ChangeType.POSITION and entry.source_kind == ChangeRecord.SourceKind.LIVE_INPUT:
			normalized.append(entry.with_source_kind(ChangeRecord.SourceKind.REMEMBERED_REBUILD))
			continue
		normalized.append(entry)
	return normalized


func _detect_generated_changes_after_entry(
	state: SimulationState,
	queue_entries: Array[ChangeRecord],
	context: CompileContext,
	_source_queue_index: int
) -> Array[ChangeRecord]:
	context.clear_generated()
	for subject_id: StringName in state.position_by_subject.keys():
		if not state.subject_exists(subject_id):
			continue
		if bool(state.is_ghost_by_subject.get(subject_id, false)):
			continue
		var position: Vector2i = state.subject_position(subject_id)
		if PlacementRules.can_land_solid(state, subject_id, position):
			continue
		var ghost_change: ChangeRecord = ConflictRules.ghostify_change(subject_id, position, "placement_conflict")
		if _has_same_change(queue_entries, ghost_change):
			continue
		context.add_generated_change(ghost_change)
	return context.generated_changes.duplicate()


func _build_projected_world(state: SimulationState) -> CompiledWorld:
	var world: CompiledWorld = state.build_world()
	var to_ghostify: Array[StringName] = []
	for subject_id: StringName in world.entity_positions.keys():
		var position: Vector2i = world.entity_positions[subject_id]
		if position == world.player_position:
			to_ghostify.append(subject_id)
	for subject_id: StringName in to_ghostify:
		var position: Vector2i = world.entity_positions[subject_id]
		world.entity_positions.erase(subject_id)
		world.ghost_entities[subject_id] = position
	return world


func _has_same_change(changes: Array[ChangeRecord], candidate: ChangeRecord) -> bool:
	for entry: ChangeRecord in changes:
		if entry.type == candidate.type and entry.subject_id == candidate.subject_id and entry.target_position == candidate.target_position and entry.source_kind == candidate.source_kind:
			return true
	return false
