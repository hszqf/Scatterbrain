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
		generated_ghost_changes.append(
			ChangeRecord.new(
				ChangeRecord.ChangeType.GHOST,
				change.subject_id,
				target,
				false,
				"auto-generated ghost"
			)
		)


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
