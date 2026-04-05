class_name DebugLogFormatter
extends RefCounted


func build_snapshot(
	world: CompiledWorld,
	queue_entries: Array[ChangeRecord],
	recompile_reason: String,
	replay_steps: Array[Dictionary],
	last_replay_display_steps: Array[Dictionary],
	last_replay_presenting_subjects: Array[StringName],
	last_replay_used_live_box_views: bool,
	last_replay_completed: bool,
	build_text: String,
	board_view_transform: String = "n/a",
	replay_layer_transform: String = "n/a",
	last_replay_stop_reason: String = "none",
	input_source: String = "none",
	input_intent: String = "none",
	input_direction: Vector2i = Vector2i.ZERO,
	move_player_moved: bool = false,
	move_generated_change: String = "none",
	appended_change: String = "none",
	pushed_out_changes: Array[String] = [],
	generated_ghost_changes: Array[String] = [],
	queue_after_compile: Array[String] = [],
	replay_gate_allowed: bool = false,
	replay_gate_reason: String = "none"
) -> String:
	var lines: Array[String] = []
	lines.append("[DebugSnapshot]")
	lines.append("build=%s" % build_text)
	lines.append("player=%s" % world.player_position)
	lines.append("boxes=%s" % str(_sorted_vec2(world.entity_positions.values())))
	lines.append("ghost_boxes=%s" % str(_sorted_vec2(world.ghost_entities.values())))
	lines.append("queue=%s" % str(_queue_summary(queue_entries)))
	lines.append("input_source=%s" % _safe_or_default(input_source, "none"))
	lines.append("input_intent=%s" % _safe_or_default(input_intent, "none"))
	lines.append("input_direction=%s" % str(input_direction))
	lines.append("move_player_moved=%s" % str(move_player_moved))
	lines.append("move_generated_change=%s" % _safe_or_default(move_generated_change, "none"))
	lines.append("appended_change=%s" % _safe_or_default(appended_change, "none"))
	lines.append("pushed_out_changes=%s" % str(_copy_string_array(pushed_out_changes)))
	lines.append("generated_ghost_changes=%s" % str(_copy_string_array(generated_ghost_changes)))
	lines.append("queue_after_compile=%s" % str(_copy_string_array(queue_after_compile)))
	lines.append("replay_gate_allowed=%s" % str(replay_gate_allowed))
	lines.append("replay_gate_reason=%s" % _safe_or_default(replay_gate_reason, "none"))
	lines.append("board_size=%s" % world.board_size)
	lines.append("floors=%d sample=%s" % [world.floor_cells.size(), str(_sample_positions(world.floor_cells.keys()))])
	lines.append("walls=%d sample=%s" % [world.wall_positions.size(), str(_sample_positions(world.wall_positions.keys()))])
	lines.append("recompile_reason=%s" % recompile_reason)
	lines.append("replay=%s" % str(_replay_summary(replay_steps)))
	lines.append("last_replay_display_steps=%s" % str(_replay_display_summary(last_replay_display_steps)))
	lines.append("last_replay_presenting_subjects=%s" % str(last_replay_presenting_subjects))
	lines.append("last_replay_used_live_box_views=%s" % str(last_replay_used_live_box_views))
	lines.append("last_replay_completed=%s" % str(last_replay_completed))
	lines.append("last_replay_stop_reason=%s" % last_replay_stop_reason)
	lines.append("board_view_transform=%s" % board_view_transform)
	lines.append("replay_layer_transform=%s" % replay_layer_transform)
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


func _replay_display_summary(steps: Array[Dictionary]) -> String:
	if steps.is_empty():
		return "[]"
	var labels: Array[String] = []
	for step: Dictionary in steps:
		labels.append("%s:%s->%s conflict=%s" % [
			step.get("subject", &""),
			step.get("from", Vector2i.ZERO),
			step.get("to", Vector2i.ZERO),
			str(step.get("is_conflict", false)),
		])
	return str(labels)


func _safe_or_default(value: String, fallback: String) -> String:
	return value if not value.is_empty() else fallback


func _copy_string_array(values: Array[String]) -> Array[String]:
	var copied: Array[String] = []
	for value: String in values:
		copied.append(_safe_or_default(value, "none"))
	return copied
