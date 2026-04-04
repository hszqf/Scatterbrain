class_name WorldCompiler
extends RefCounted

const MAX_ITERATIONS: int = 4

## Applies memory queue changes onto default world and resolves ghost collisions.
func compile(defaults: WorldDefaults, queue: ChangeQueue) -> CompileResult:
	var result := CompileResult.new()
	var working_queue: ChangeQueue = queue
	var current_world: CompiledWorld = _build_base_world(defaults)
	var iteration: int = 0
	var stabilized: bool = false

	while iteration < MAX_ITERATIONS:
		iteration += 1
		var removed: Array[ChangeRecord] = working_queue.normalize_to_capacity(defaults.memory_capacity)
		result.pushed_out_changes.append_array(removed)

		current_world = _build_base_world(defaults)
		var generated: Array[ChangeRecord] = _apply_changes(defaults, working_queue.entries(), current_world)

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


func _build_base_world(defaults: WorldDefaults) -> CompiledWorld:
	var world := CompiledWorld.new()
	world.board_size = defaults.board_size
	world.player_position = defaults.player_start
	world.exit_position = defaults.exit_position
	for entity_id: StringName in defaults.default_entity_positions.keys():
		world.entity_positions[entity_id] = defaults.default_entity_positions[entity_id]
	return world


func _apply_changes(defaults: WorldDefaults, entries: Array[ChangeRecord], world: CompiledWorld) -> Array[ChangeRecord]:
	var generated_ghost_changes: Array[ChangeRecord] = []
	for change: ChangeRecord in entries:
		match change.type:
			ChangeRecord.ChangeType.POSITION:
				_apply_position_like_change(change, world, generated_ghost_changes, true)
			ChangeRecord.ChangeType.GHOST:
				_apply_position_like_change(change, world, generated_ghost_changes, false)
			ChangeRecord.ChangeType.EMPTY:
				continue
			_:
				push_warning("Unknown change type: %s" % [change.type])
	return generated_ghost_changes


func _apply_position_like_change(
	change: ChangeRecord,
	world: CompiledWorld,
	generated_ghost_changes: Array[ChangeRecord],
	allow_generate_ghost: bool
) -> void:
	if change.subject_id == &"":
		return
	var target: Vector2i = change.target_position
	var blocked: bool = (target == world.player_position)
	if not blocked:
		for entity_id: StringName in world.entity_positions.keys():
			if entity_id != change.subject_id and world.entity_positions[entity_id] == target:
				blocked = true
				break

	if blocked:
		world.entity_positions.erase(change.subject_id)
		world.ghost_entities[change.subject_id] = target
		if allow_generate_ghost:
			generated_ghost_changes.append(
				ChangeRecord.new(
					ChangeRecord.ChangeType.GHOST,
					change.subject_id,
					target,
					false,
					"auto-generated ghost"
				)
			)
	else:
		world.ghost_entities.erase(change.subject_id)
		world.entity_positions[change.subject_id] = target
