class_name DebugLogFormatter
extends RefCounted


func build_snapshot(
	world: CompiledWorld,
	queue_entries: Array[ChangeRecord],
	recompile_reason: String,
	replay_steps: Array[Dictionary]
) -> String:
	var lines: Array[String] = []
	lines.append("[DebugSnapshot]")
	lines.append("player=%s" % world.player_position)
	lines.append("boxes=%s" % _sorted_vec2(world.entity_positions.values()))
	lines.append("queue=%s" % _queue_summary(queue_entries))
	lines.append("board_size=%s" % world.board_size)
	lines.append("floors=%d sample=%s" % [world.floor_cells.size(), _sample_positions(world.floor_cells.keys())])
	lines.append("walls=%d sample=%s" % [world.wall_positions.size(), _sample_positions(world.wall_positions.keys())])
	lines.append("recompile_reason=%s" % recompile_reason)
	lines.append("replay=%s" % _replay_summary(replay_steps))
	return "\n".join(lines)


func _queue_summary(entries: Array[ChangeRecord]) -> String:
	var labels: Array[String] = []
	for entry: ChangeRecord in entries:
		labels.append(entry.summary())
	return str(labels)


func _sample_positions(values: Array) -> Array[Vector2i]:
	var sorted: Array[Vector2i] = _sorted_vec2(values)
	return sorted.slice(0, mini(4, sorted.size()))


func _sorted_vec2(values: Array) -> Array[Vector2i]:
	var sorted: Array[Vector2i] = []
	for value in values:
		sorted.append(value)
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x == b.x:
			return a.y < b.y
		return a.x < b.x
	)
	return sorted


func _replay_summary(steps: Array[Dictionary]) -> String:
	if steps.is_empty():
		return "none"
	var labels: Array[String] = []
	for step: Dictionary in steps:
		labels.append("%s:%s->%s" % [step.get("subject", &""), step.get("from", Vector2i.ZERO), step.get("to", Vector2i.ZERO)])
	return str(labels)
