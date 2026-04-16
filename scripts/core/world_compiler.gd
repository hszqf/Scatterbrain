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
		var pass_index: int = iteration - 1
		print("[Recompile][Diag] pass_index=%d queue_entries_before_normalize=%s" % [pass_index, _describe_changes(queue_entries)])
		var temp_queue := ChangeQueue.new()
		for entry: ChangeRecord in queue_entries:
			temp_queue.append(entry)
		var removed: Array[ChangeRecord] = temp_queue.normalize_to_capacity(defaults.memory_capacity)
		print("[Recompile][Diag] pass_index=%d removed_by_normalize=%s" % [pass_index, _describe_changes(removed)])
		if iteration == 1:
			result.pushed_out_changes.append_array(removed)
		queue_entries = temp_queue.entries()
		print("[Recompile][Diag] pass_index=%d queue_entries_after_normalize=%s" % [pass_index, _describe_changes(queue_entries)])

		replay_trace.append({
			"kind": "pass_begin",
			"pass_index": pass_index,
			"queue_entries": queue_entries.duplicate(),
		})

		context.clear_generated()
		var replay_player_start: Vector2i = _derive_replay_player_start(player_position, queue_entries)
		print("[Recompile][Diag] pass_index=%d replay_player_start=%s" % [pass_index, replay_player_start])
		var state := SimulationState.new()
		state.setup_from_defaults(defaults, replay_player_start)
		print("[Recompile][Diag] pass_index=%d pass_begin_player_position=%s" % [pass_index, state.player_position])
		print("[Recompile][Diag] pass_index=%d pass_begin_position_by_subject=%s" % [pass_index, state.position_by_subject])
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
					"player_at": state.player_position,
				})
			else:
				var events: Array[Dictionary] = []
				_interpreter.interpret([entry], state, context, events)
				var player_before_entry: Vector2i = state.player_position
				if entry.type == ChangeRecord.ChangeType.POSITION:
					state.player_position += entry.move_delta
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
							"player_from": player_before_entry,
							"player_to": state.player_position,
						})
					elif change.type == ChangeRecord.ChangeType.GHOST:
						replay_trace.append({
							"kind": "ghostify",
							"pass_index": pass_index,
							"queue_index": queue_index,
							"subject": change.subject_id,
							"at": event.get("from", Vector2i.ZERO),
							"is_conflict": true,
							"player_at": state.player_position,
						})

			var generated_after_entry: Array[ChangeRecord] = _detect_generated_changes_after_entry(state, queue_entries, context, pass_index, queue_index)
			print(
				"[Recompile][Diag] pass_index=%d queue_index=%d generated_after_entry=%s" %
				[pass_index, queue_index, _describe_changes(generated_after_entry)]
			)
			if generated_after_entry.is_empty():
				continue

			var before_queue_update_entries: Array[ChangeRecord] = queue_entries.duplicate()
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
				"before_queue_entries": before_queue_update_entries,
				"before_normalize_queue_entries": before_normalize_queue_entries,
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
			result.world = _build_projected_world(state, player_position)
			break

	result.iterations = iteration
	if result.world == null:
		var fallback_state := SimulationState.new()
		fallback_state.setup_from_defaults(defaults, player_position)
		_interpreter.interpret(queue_entries, fallback_state, CompileContext.new())
		result.world = _build_projected_world(fallback_state, player_position)
	if iteration >= MAX_ITERATIONS and not context.generated_changes.is_empty():
		result.reached_safety_limit = true
	var final_queue := ChangeQueue.new()
	for entry: ChangeRecord in queue_entries:
		final_queue.append(entry)
	final_queue.normalize_to_capacity(defaults.memory_capacity)
	result.queue_entries = final_queue.entries()
	result.replay_trace = replay_trace
	print("[Recompile][Diag] result_generated_ghost_changes=%s" % [_describe_changes(result.generated_ghost_changes)])
	print("[Recompile][Diag] replay_trace_kinds_summary=%s" % [_summarize_trace_kinds(replay_trace)])
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
	pass_index: int,
	source_queue_index: int
) -> Array[ChangeRecord]:
	context.clear_generated()
	for subject_id: StringName in state.position_by_subject.keys():
		if not state.subject_exists(subject_id):
			continue
		if bool(state.is_ghost_by_subject.get(subject_id, false)):
			continue
		var position: Vector2i = state.subject_position(subject_id)
		var can_land_solid: bool = PlacementRules.can_land_solid(state, subject_id, position)
		var ghost_change: ChangeRecord = ConflictRules.ghostify_change(subject_id, position, "placement_conflict")
		var filtered_by_same_change: bool = _has_same_change(queue_entries, ghost_change)
		print(
			"[Recompile][Diag] pass_index=%d queue_index=%d detect subject_id=%s position=%s player_position=%s can_land_solid=%s filtered_by_has_same_change=%s ghost_change=%s" %
			[
				pass_index,
				source_queue_index,
				subject_id,
				position,
				state.player_position,
				can_land_solid,
				filtered_by_same_change,
				_describe_change(ghost_change),
			]
		)
		if can_land_solid:
			continue
		if filtered_by_same_change:
			continue
		context.add_generated_change(ghost_change)
	return context.generated_changes.duplicate()


func _derive_replay_player_start(live_player_position: Vector2i, queue_entries: Array[ChangeRecord]) -> Vector2i:
	var replay_player_position: Vector2i = live_player_position
	for index: int in range(queue_entries.size() - 1, -1, -1):
		var entry: ChangeRecord = queue_entries[index]
		if entry == null:
			continue
		if entry.type != ChangeRecord.ChangeType.POSITION:
			continue
		replay_player_position -= entry.move_delta
	return replay_player_position


func _build_projected_world(state: SimulationState, live_player_position: Vector2i) -> CompiledWorld:
	var world: CompiledWorld = state.build_world()
	world.player_position = live_player_position
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


func _describe_changes(changes: Array[ChangeRecord]) -> Array[Dictionary]:
	var described: Array[Dictionary] = []
	for entry: ChangeRecord in changes:
		described.append(_describe_change(entry))
	return described


func _describe_change(entry: ChangeRecord) -> Dictionary:
	if entry == null:
		return {"null": true}
	return {
		"type": entry.type,
		"subject_id": entry.subject_id,
		"target_position": entry.target_position,
		"move_delta": entry.move_delta,
		"source_kind": entry.source_kind,
		"debug_label": entry.debug_label,
	}


func _summarize_trace_kinds(trace: Array[Dictionary]) -> Dictionary:
	var summary: Dictionary = {}
	for item: Dictionary in trace:
		var kind: String = String(item.get("kind", "unknown"))
		summary[kind] = int(summary.get(kind, 0)) + 1
	return summary
