class_name ReplayPayloadBuilder
extends RefCounted


func build_steps(world_before_compile: CompiledWorld, world_after_compile: CompiledWorld) -> Array[Dictionary]:
	if world_before_compile == null or world_after_compile == null:
		return []
	var steps: Array[Dictionary] = []
	var subjects: Dictionary = {}
	for subject_id: StringName in world_before_compile.entity_positions.keys():
		subjects[subject_id] = true
	for subject_id: StringName in world_after_compile.entity_positions.keys():
		subjects[subject_id] = true
	for subject_id: StringName in subjects.keys():
		var before_exists: bool = world_before_compile.entity_positions.has(subject_id)
		var after_exists: bool = world_after_compile.entity_positions.has(subject_id)
		var before_pos: Vector2i = world_before_compile.entity_positions.get(subject_id, Vector2i.ZERO)
		var after_pos: Vector2i = world_after_compile.entity_positions.get(subject_id, Vector2i.ZERO)
		if before_exists == after_exists and before_pos == after_pos:
			continue
		steps.append({
			"type": ChangeRecord.ChangeType.POSITION,
			"from": before_pos,
			"to": after_pos,
			"subject": subject_id,
			"from_exists": before_exists,
			"to_exists": after_exists,
		})
	return steps
