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
		var existing_ghost_keys: Dictionary[String, bool] = _collect_existing_ghost_keys(queue_entries)
		var generated: Array[ChangeRecord] = _apply_changes(defaults, queue_entries, current_world, existing_ghost_keys)

		if generated.is_empty():
			stabilized = true
			break

		for ghost_change: ChangeRecord in generated:
			working_queue.append(ghost_change)
		result.generated_ghost_changes.append_array(generated)

		if working_queue.size() <= defaults.memory_capacity:
			continue

	if not stabilized and iteration >= MAX_ITERATIONS:
		result.reached_safety_limit = true
		push_error("WorldCompiler safety limit reached (%d)." % MAX_ITERATIONS)

	result.iterations = iteration
	result.world = current_world
	result.queue_entries = working_queue.entries()
	return result


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
	world: CompiledWorld,
	existing_ghost_keys: Dictionary[String, bool]
) -> Array[ChangeRecord]:
	var generated_ghost_changes: Array[ChangeRecord] = []
	var generated_ghost_keys: Dictionary[String, bool] = {}
	var last_position_like_index_by_subject: Dictionary[StringName, int] = {}
	for i: int in range(entries.size()):
		var position_like_entry: ChangeRecord = entries[i]
		if position_like_entry.type != ChangeRecord.ChangeType.POSITION and position_like_entry.type != ChangeRecord.ChangeType.GHOST:
			continue
		if position_like_entry.subject_id == &"":
			continue
		last_position_like_index_by_subject[position_like_entry.subject_id] = i

	for i: int in range(entries.size()):
		var change: ChangeRecord = entries[i]
		match change.type:
			ChangeRecord.ChangeType.POSITION:
				_apply_position_like_change(
					change,
					i,
					last_position_like_index_by_subject,
					world,
					generated_ghost_changes,
					true,
					existing_ghost_keys,
					generated_ghost_keys
				)
			ChangeRecord.ChangeType.GHOST:
				_apply_position_like_change(
					change,
					i,
					last_position_like_index_by_subject,
					world,
					generated_ghost_changes,
					false,
					existing_ghost_keys,
					generated_ghost_keys
				)
			ChangeRecord.ChangeType.EMPTY:
				continue
			_:
				push_warning("Unknown change type: %s" % [change.type])
	return generated_ghost_changes


func _apply_position_like_change(
	change: ChangeRecord,
	index: int,
	last_position_like_index_by_subject: Dictionary[StringName, int],
	world: CompiledWorld,
	generated_ghost_changes: Array[ChangeRecord],
	allow_generate_ghost: bool,
	existing_ghost_keys: Dictionary[String, bool],
	generated_ghost_keys: Dictionary[String, bool]
) -> void:
	if change.subject_id == &"":
		return

	var target: Vector2i = change.target_position
	if not world.is_inside(target) or not world.has_floor_at(target) or world.has_wall_at(target):
		world.entity_positions.erase(change.subject_id)
		world.ghost_entities.erase(change.subject_id)
		return

	if _can_place_box(world, target, change.subject_id):
		world.ghost_entities.erase(change.subject_id)
		world.entity_positions[change.subject_id] = target
		return

	world.entity_positions.erase(change.subject_id)
	world.ghost_entities[change.subject_id] = target
	if allow_generate_ghost:
		var last_position_like_index: int = last_position_like_index_by_subject.get(change.subject_id, index)
		if index != last_position_like_index:
			return
		var key: String = _ghost_key(change.subject_id, target)
		if existing_ghost_keys.has(key) or generated_ghost_keys.has(key):
			return
		generated_ghost_keys[key] = true
		generated_ghost_changes.append(
			ChangeRecord.new(
				ChangeRecord.ChangeType.GHOST,
				change.subject_id,
				target,
				false,
				"auto-generated ghost"
			)
		)


func _collect_existing_ghost_keys(entries: Array[ChangeRecord]) -> Dictionary[String, bool]:
	var keys: Dictionary[String, bool] = {}
	for entry: ChangeRecord in entries:
		if entry.type != ChangeRecord.ChangeType.GHOST:
			continue
		keys[_ghost_key(entry.subject_id, entry.target_position)] = true
	return keys


func _ghost_key(subject_id: StringName, target: Vector2i) -> String:
	return "%s|%d|%d" % [subject_id, target.x, target.y]


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
