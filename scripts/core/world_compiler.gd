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

	while iteration < MAX_ITERATIONS:
		iteration += 1
		var temp_queue := ChangeQueue.new()
		for entry: ChangeRecord in queue_entries:
			temp_queue.append(entry)
		var removed: Array[ChangeRecord] = temp_queue.normalize_to_capacity(defaults.memory_capacity)
		if iteration == 1:
			result.pushed_out_changes.append_array(removed)
		queue_entries = temp_queue.entries()

		context.clear_generated()
		var state := SimulationState.new()
		state.setup_from_defaults(defaults, player_position)
		_interpreter.interpret(queue_entries, state, context)
		_collect_conflict_generated_changes(state, queue_entries, context)

		if context.generated_changes.is_empty():
			result.world = _build_projected_world(state)
			break
		for generated: ChangeRecord in context.generated_changes:
			if _has_same_change(queue_entries, generated):
				continue
			queue_entries.append(generated)
			if generated.type == ChangeRecord.ChangeType.GHOST and not _has_same_change(result.generated_ghost_changes, generated):
				result.generated_ghost_changes.append(generated)

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


func _collect_conflict_generated_changes(
	state: SimulationState,
	queue_entries: Array[ChangeRecord],
	context: CompileContext
) -> void:
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
