class_name WorldCompiler
extends RefCounted

const MAX_ITERATIONS: int = 4

## Applies memory queue changes onto default world and resolves ghost collisions.
func compile(defaults: WorldDefaults, queue: ChangeQueue, player_position: Vector2i) -> CompileResult:
	var result := CompileResult.new()
	var working_queue: ChangeQueue = queue
	var current_world: CompiledWorld = _build_base_world(defaults, player_position)
	var iteration: int = 0
	var stabilized: bool = false

	while iteration < MAX_ITERATIONS:
		iteration += 1
		var removed: Array[ChangeRecord] = working_queue.normalize_to_capacity(defaults.memory_capacity)
		result.pushed_out_changes.append_array(removed)

		current_world = _build_base_world(defaults, player_position)
		var queue_entries: Array[ChangeRecord] = working_queue.entries()
		var generated: Array[ChangeRecord] = _apply_changes(defaults, queue_entries, current_world)

		if generated.is_empty():
			stabilized = true
			break

		for ghost_change: ChangeRecord in generated:
			var removed_for_generated: ChangeRecord = _remove_oldest_unpinned_empty(working_queue)
			if removed_for_generated != null:
				result.pushed_out_changes.append(removed_for_generated)
			elif working_queue.size() >= defaults.memory_capacity:
				var removed_oldest: ChangeRecord = working_queue.remove_oldest_unpinned()
				if removed_oldest != null:
					result.pushed_out_changes.append(removed_oldest)
			working_queue.append(ghost_change)
		result.generated_ghost_changes.append_array(generated)

		if working_queue.size() <= defaults.memory_capacity:
			continue

	if not stabilized and iteration >= MAX_ITERATIONS:
		result.reached_safety_limit = true
		push_error("WorldCompiler safety limit reached (%d)." % MAX_ITERATIONS)

	result.iterations = iteration
	result.world = current_world
	result.queue_entries = _normalize_queue_for_rebuild_context(working_queue.entries())
	return result




func _remove_oldest_unpinned_empty(queue: ChangeQueue) -> ChangeRecord:
	var entries: Array[ChangeRecord] = queue.entries()
	for i: int in range(entries.size()):
		var entry: ChangeRecord = entries[i]
		if entry == null:
			continue
		if entry.pinned:
			continue
		if entry.type != ChangeRecord.ChangeType.EMPTY:
			continue
		var removed: ChangeRecord = entry
		queue.clear()
		for j: int in range(entries.size()):
			if j == i:
				continue
			queue.append(entries[j])
		return removed
	return null
func _build_base_world(defaults: WorldDefaults, player_position: Vector2i) -> CompiledWorld:
	var world := CompiledWorld.new()
	world.board_size = defaults.board_size
	world.player_position = player_position
	world.exit_position = defaults.exit_position
	for floor_pos: Vector2i in defaults.floor_cells:
		world.floor_cells[floor_pos] = true
	for wall_pos: Vector2i in defaults.wall_positions:
		world.wall_positions[wall_pos] = true
	for entity_id: StringName in defaults.default_entity_positions.keys():
		var entity_pos: Vector2i = defaults.default_entity_positions[entity_id]
		if _can_place_box(world, entity_pos, entity_id):
			world.entity_positions[entity_id] = entity_pos
	return world


func _apply_changes(
	_defaults: WorldDefaults,
	entries: Array[ChangeRecord],
	world: CompiledWorld
) -> Array[ChangeRecord]:
	var generated_ghost_changes: Array[ChangeRecord] = []
	var last_position_affecting_index_by_subject: Dictionary = _build_last_position_affecting_index_by_subject(entries)
	for index: int in range(entries.size()):
		var change: ChangeRecord = entries[index]
		match change.type:
			ChangeRecord.ChangeType.POSITION:
				var generated_ghost: ChangeRecord = _apply_position_change(
					change,
					world,
					last_position_affecting_index_by_subject,
					index
				)
				if generated_ghost != null and not _contains_equivalent_ghost_change(entries, generated_ghost_changes, generated_ghost):
					generated_ghost_changes.append(generated_ghost)
			ChangeRecord.ChangeType.GHOST:
				_apply_ghost_change(change, world)
			ChangeRecord.ChangeType.EMPTY:
				continue
			_:
				push_warning("Unknown change type: %s" % [change.type])
	return generated_ghost_changes


func _build_last_position_affecting_index_by_subject(entries: Array[ChangeRecord]) -> Dictionary:
	var result: Dictionary = {}
	for index: int in range(entries.size()):
		var entry: ChangeRecord = entries[index]
		if entry == null:
			continue
		if entry.subject_id == &"":
			continue
		if entry.type != ChangeRecord.ChangeType.POSITION and entry.type != ChangeRecord.ChangeType.GHOST:
			continue
		result[entry.subject_id] = index
	return result


func _apply_position_change(
	change: ChangeRecord,
	world: CompiledWorld,
	last_position_affecting_index_by_subject: Dictionary,
	change_index: int
) -> ChangeRecord:
	if change.subject_id == &"":
		return null

	if change.source_kind == ChangeRecord.SourceKind.LIVE_INPUT:
		return _apply_live_input_position_change(change, world)
	return _apply_remembered_rebuild_position_change(
		change,
		world,
		last_position_affecting_index_by_subject,
		change_index
	)


func _apply_live_input_position_change(change: ChangeRecord, world: CompiledWorld) -> ChangeRecord:
	var final_position: Vector2i = change.target_position
	if not world.is_inside(final_position) or not world.has_floor_at(final_position) or world.has_wall_at(final_position):
		world.entity_positions.erase(change.subject_id)
		world.ghost_entities.erase(change.subject_id)
		return null
	if _can_place_box(world, final_position, change.subject_id):
		world.ghost_entities.erase(change.subject_id)
		world.entity_positions[change.subject_id] = final_position
		return null
	world.entity_positions.erase(change.subject_id)
	world.ghost_entities[change.subject_id] = final_position
	return null


func _apply_remembered_rebuild_position_change(
	change: ChangeRecord,
	world: CompiledWorld,
	last_position_affecting_index_by_subject: Dictionary,
	change_index: int
) -> ChangeRecord:
	var from_exists: bool = world.entity_positions.has(change.subject_id)
	var from_pos: Vector2i = world.entity_positions.get(change.subject_id, change.target_position)
	var path_result: Dictionary = PositionPathHelper.expand_with_player_conflict(
		change.subject_id,
		from_pos,
		change.target_position,
		from_exists,
		world.player_position
	)
	var final_position: Vector2i = path_result.get("final_position", change.target_position)
	if bool(path_result.get("truncated_by_player_conflict", false)):
		world.entity_positions.erase(change.subject_id)
		world.ghost_entities[change.subject_id] = final_position
		if world.ghost_entities.get(change.subject_id, Vector2i(-1, -1)) == final_position \
			and not _has_later_position_affecting_change(last_position_affecting_index_by_subject, change.subject_id, change_index):
			return ChangeRecord.new(
				ChangeRecord.ChangeType.GHOST,
				change.subject_id,
				final_position,
				change.pinned,
				"generated_from_player_conflict",
				ChangeRecord.SourceKind.AUTO_GHOST
			)
		return null

	if not world.is_inside(final_position) or not world.has_floor_at(final_position) or world.has_wall_at(final_position):
		world.entity_positions.erase(change.subject_id)
		world.ghost_entities.erase(change.subject_id)
		return null

	if _can_place_box(world, final_position, change.subject_id):
		world.ghost_entities.erase(change.subject_id)
		world.entity_positions[change.subject_id] = final_position
		return null

	world.entity_positions.erase(change.subject_id)
	world.ghost_entities[change.subject_id] = final_position
	return null


func _has_later_position_affecting_change(
	last_position_affecting_index_by_subject: Dictionary,
	subject_id: StringName,
	change_index: int
) -> bool:
	if not last_position_affecting_index_by_subject.has(subject_id):
		return false
	return int(last_position_affecting_index_by_subject[subject_id]) > change_index


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


func _contains_equivalent_ghost_change(
	entries: Array[ChangeRecord],
	generated_ghost_changes: Array[ChangeRecord],
	candidate: ChangeRecord
) -> bool:
	for entry: ChangeRecord in entries:
		if _is_equivalent_ghost_change(entry, candidate):
			return true
	for generated: ChangeRecord in generated_ghost_changes:
		if _is_equivalent_ghost_change(generated, candidate):
			return true
	return false


func _is_equivalent_ghost_change(entry: ChangeRecord, candidate: ChangeRecord) -> bool:
	if entry == null or candidate == null:
		return false
	return entry.type == ChangeRecord.ChangeType.GHOST \
		and entry.subject_id == candidate.subject_id \
		and entry.target_position == candidate.target_position


func _apply_ghost_change(change: ChangeRecord, world: CompiledWorld) -> void:
	if change.subject_id == &"":
		return
	var target: Vector2i = change.target_position
	if not world.is_inside(target) or not world.has_floor_at(target) or world.has_wall_at(target):
		world.entity_positions.erase(change.subject_id)
		world.ghost_entities.erase(change.subject_id)
		return
	world.entity_positions.erase(change.subject_id)
	world.ghost_entities[change.subject_id] = target


func _can_place_box(world: CompiledWorld, target: Vector2i, ignore_entity_id: StringName = &"") -> bool:
	if not world.is_inside(target):
		return false
	if not world.has_floor_at(target):
		return false
	if world.has_wall_at(target):
		return false
	if target == world.player_position:
		return false
	for entity_id: StringName in world.entity_positions.keys():
		if entity_id == ignore_entity_id:
			continue
		if world.entity_positions[entity_id] == target:
			return false
	return true
