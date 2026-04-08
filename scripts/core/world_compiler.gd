class_name WorldCompiler
extends RefCounted

const MAX_ITERATIONS: int = 4


## Applies memory queue changes onto default world in two layers:
## 1) remembered world interpreter (default + surviving queue only)
## 2) projected live world (remembered world + current player projection)
func compile(defaults: WorldDefaults, queue: ChangeQueue, player_position: Vector2i) -> CompileResult:
	var result := CompileResult.new()
	var removed: Array[ChangeRecord] = queue.normalize_to_capacity(defaults.memory_capacity)
	result.pushed_out_changes.append_array(removed)
	result.iterations = 1
	result.queue_entries = _normalize_queue_for_rebuild_context(queue.entries())
	var remembered_state: Dictionary = _build_remembered_world(defaults, result.queue_entries)
	result.world = _project_live_world(defaults, remembered_state, player_position)
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


func _build_remembered_world(defaults: WorldDefaults, entries: Array[ChangeRecord]) -> Dictionary:
	var exists_by_subject: Dictionary[StringName, bool] = {}
	var position_by_subject: Dictionary[StringName, Vector2i] = {}
	var is_ghost_by_subject: Dictionary[StringName, bool] = {}

	for subject_id: StringName in defaults.default_entity_positions.keys():
		exists_by_subject[subject_id] = true
		position_by_subject[subject_id] = defaults.default_entity_positions[subject_id]
		is_ghost_by_subject[subject_id] = false

	for entry: ChangeRecord in entries:
		if entry == null:
			continue
		if entry.subject_id == &"":
			continue
		match entry.type:
			ChangeRecord.ChangeType.POSITION:
				exists_by_subject[entry.subject_id] = true
				position_by_subject[entry.subject_id] = entry.target_position
				is_ghost_by_subject[entry.subject_id] = false
			ChangeRecord.ChangeType.GHOST:
				if not bool(exists_by_subject.get(entry.subject_id, false)):
					continue
				is_ghost_by_subject[entry.subject_id] = true
			_:
				continue

	return {
		"exists_by_subject": exists_by_subject,
		"position_by_subject": position_by_subject,
		"is_ghost_by_subject": is_ghost_by_subject,
	}


func _project_live_world(
	defaults: WorldDefaults,
	remembered_state: Dictionary,
	player_position: Vector2i
) -> CompiledWorld:
	var world := CompiledWorld.new()
	world.board_size = defaults.board_size
	world.player_position = player_position
	world.exit_position = defaults.exit_position
	for floor_pos: Vector2i in defaults.floor_cells:
		world.floor_cells[floor_pos] = true
	for wall_pos: Vector2i in defaults.wall_positions:
		world.wall_positions[wall_pos] = true

	var exists_by_subject: Dictionary = remembered_state.get("exists_by_subject", {})
	var position_by_subject: Dictionary = remembered_state.get("position_by_subject", {})
	var is_ghost_by_subject: Dictionary = remembered_state.get("is_ghost_by_subject", {})
	var ordered_subjects: Array[StringName] = []
	for subject_id_variant: Variant in position_by_subject.keys():
		ordered_subjects.append(subject_id_variant)
	ordered_subjects.sort()

	for subject_id: StringName in ordered_subjects:
		if not bool(exists_by_subject.get(subject_id, false)):
			continue
		if not position_by_subject.has(subject_id):
			continue
		var remembered_position: Vector2i = position_by_subject[subject_id]
		if not world.is_inside(remembered_position):
			continue
		if not world.has_floor_at(remembered_position):
			continue
		if world.has_wall_at(remembered_position):
			continue
		if bool(is_ghost_by_subject.get(subject_id, false)):
			world.ghost_entities[subject_id] = remembered_position
			continue
		if _can_project_solid_box(world, remembered_position, subject_id):
			world.entity_positions[subject_id] = remembered_position
			continue
		world.ghost_entities[subject_id] = remembered_position

	return world


func _can_project_solid_box(world: CompiledWorld, target: Vector2i, ignore_entity_id: StringName = &"") -> bool:
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
