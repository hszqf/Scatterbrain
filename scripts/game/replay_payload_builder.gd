class_name ReplayPayloadBuilder
extends RefCounted


const REPLAYABLE_POSITION_SOURCE: ChangeRecord.SourceKind = ChangeRecord.SourceKind.REMEMBERED_REBUILD
const REPLAYABLE_GHOST_SOURCE: ChangeRecord.SourceKind = ChangeRecord.SourceKind.AUTO_GHOST


## Replay canonical state is not a raw queue playback.
## We reduce surviving queue to the last position-affecting remembered entry per subject,
## then replay how that canonical remembered state is rebuilt from defaults.
static func build_canonical_replay_state(surviving_queue_entries: Array[ChangeRecord]) -> Array[ChangeRecord]:
	var canonical_by_subject: Dictionary[StringName, ChangeRecord] = {}
	for entry: ChangeRecord in surviving_queue_entries:
		if not _is_replayable_position_affecting_entry(entry):
			continue
		canonical_by_subject[entry.subject_id] = entry
	var subjects: Array[StringName] = canonical_by_subject.keys()
	subjects.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	var canonical_entries: Array[ChangeRecord] = []
	for subject_id: StringName in subjects:
		canonical_entries.append(canonical_by_subject[subject_id])
	return canonical_entries


static func build_canonical_state_signature(surviving_queue_entries: Array[ChangeRecord]) -> Array[String]:
	var canonical_entries: Array[ChangeRecord] = build_canonical_replay_state(surviving_queue_entries)
	var signature: Array[String] = []
	for entry: ChangeRecord in canonical_entries:
		var memory_kind: String = "REMEMBERED_POSITION" if entry.type == ChangeRecord.ChangeType.POSITION else "AUTO_GHOST"
		signature.append("%s:%s:(%d,%d)" % [
			String(entry.subject_id),
			memory_kind,
			entry.target_position.x,
			entry.target_position.y,
		])
	return signature


func build_steps(
	defaults: WorldDefaults,
	surviving_queue_entries: Array[ChangeRecord],
	live_player_position: Vector2i = Vector2i(999999, 999999)
) -> Array[Dictionary]:
	if defaults == null:
		return []
	var canonical_entries: Array[ChangeRecord] = build_canonical_replay_state(surviving_queue_entries)
	var steps: Array[Dictionary] = []
	for entry: ChangeRecord in canonical_entries:
		var from_exists: bool = defaults.default_entity_positions.has(entry.subject_id)
		var from_pos: Vector2i = defaults.default_entity_positions.get(entry.subject_id, Vector2i.ZERO)
		var path_steps: Array[Dictionary] = _build_canonical_entry_steps(entry, from_pos, from_exists, live_player_position)
		for path_step: Dictionary in path_steps:
			steps.append(path_step)
	return steps


func _build_remembered_position_steps(
	subject_id: StringName,
	from_pos: Vector2i,
	to_pos: Vector2i,
	from_exists: bool,
	live_player_position: Vector2i
) -> Array[Dictionary]:
	var path_result: Dictionary = PositionPathHelper.expand_with_player_conflict(
		subject_id,
		from_pos,
		to_pos,
		from_exists,
		live_player_position
	)
	return path_result.get("steps", [])


func _build_auto_ghost_steps(
	subject_id: StringName,
	from_pos: Vector2i,
	to_pos: Vector2i,
	from_exists: bool
) -> Array[Dictionary]:
	var path_result: Dictionary = PositionPathHelper.expand_with_player_conflict(
		subject_id,
		from_pos,
		to_pos,
		from_exists,
		Vector2i(999999, 999999)
	)
	var steps: Array[Dictionary] = path_result.get("steps", [])
	if steps.is_empty():
		return steps
	var last_index: int = steps.size() - 1
	for index: int in range(steps.size()):
		var step: Dictionary = steps[index]
		step["ends_as_ghost"] = index == last_index
		step["is_conflict"] = index == last_index
		steps[index] = step
	return steps


func _build_canonical_entry_steps(
	entry: ChangeRecord,
	from_pos: Vector2i,
	from_exists: bool,
	live_player_position: Vector2i
) -> Array[Dictionary]:
	if entry.type == ChangeRecord.ChangeType.POSITION:
		return _build_remembered_position_steps(
			entry.subject_id,
			from_pos,
			entry.target_position,
			from_exists,
			live_player_position
		)
	return _build_auto_ghost_steps(
		entry.subject_id,
		from_pos,
		entry.target_position,
		from_exists
	)


static func _is_replayable_position_affecting_entry(entry: ChangeRecord) -> bool:
	if entry == null:
		return false
	if entry.subject_id == &"":
		return false
	var is_replayable_position: bool = entry.type == ChangeRecord.ChangeType.POSITION \
		and entry.source_kind == REPLAYABLE_POSITION_SOURCE
	var is_replayable_ghost: bool = entry.type == ChangeRecord.ChangeType.GHOST \
		and entry.source_kind == REPLAYABLE_GHOST_SOURCE
	return is_replayable_position or is_replayable_ghost
