class_name DebugLogFormatter
extends RefCounted


func build_animation_coordinate_snapshot(
	replay_steps: Array[Dictionary],
	last_replay_display_steps: Array[Dictionary],
	presentation_trace: Array[String] = [],
	queue_animation_plan: Array[String] = [],
	queue_geometry_points: Array[String] = [],
	pre_recompile_queue_trace: Array[String] = [],
	replay_queue_trace: Array[String] = [],
	board_trace: Array[String] = [],
	geometry_capture_stage: String = "none"
) -> String:
	var lines: Array[String] = []
	lines.append("[AnimationSegments]")
	lines.append("formatter_version=2026-04-animation-flow-by-phase")
	lines.append("coord_system=board_grid_vector2i")
	var source_steps: Array[Dictionary] = last_replay_display_steps if not last_replay_display_steps.is_empty() else replay_steps
	var segment_index: int = 0
	for step: Dictionary in source_steps:
		if int(step.get("type", -1)) == ChangeRecord.ChangeType.EMPTY:
			continue
		var subject: StringName = step.get("subject", &"")
		var from_pos: Vector2i = step.get("from", Vector2i.ZERO)
		var to_pos: Vector2i = step.get("to", Vector2i.ZERO)
		lines.append("segment_%d=%s:%s->%s" % [segment_index, String(subject), str(from_pos), str(to_pos)])
		segment_index += 1
	if segment_index == 0:
		lines.append("segments=none")
	lines.append("[AnimationFlow]")
	if presentation_trace.is_empty():
		lines.append("flow=none")
	else:
		for index: int in range(presentation_trace.size()):
			lines.append("flow_%d=%s" % [index, presentation_trace[index]])
	lines.append("[AnimationFlowByPhase]")
	_append_flow_phase(lines, "pre_recompile_queue_trace", pre_recompile_queue_trace)
	_append_flow_phase(lines, "replay_queue_trace", replay_queue_trace)
	_append_flow_phase(lines, "board_trace", board_trace)
	lines.append("[QueueAnimationPlan]")
	if queue_animation_plan.is_empty():
		lines.append("plan=none")
	else:
		for index: int in range(queue_animation_plan.size()):
			lines.append("plan_%d=%s" % [index, queue_animation_plan[index]])
	lines.append("[QueueGeometryPoints]")
	if queue_geometry_points.is_empty():
		var has_queue_transaction: bool = _contains_queue_transaction(pre_recompile_queue_trace) or _contains_queue_transaction(replay_queue_trace)
		if has_queue_transaction:
			lines.append("geometry_missing_for_transaction=true")
			lines.append("geometry_capture_failed=true")
			lines.append("geometry_capture_stage=%s" % geometry_capture_stage)
		else:
			lines.append("geometry=none")
	else:
		for index: int in range(queue_geometry_points.size()):
			lines.append("geo_%d=%s" % [index, queue_geometry_points[index]])
	return "\n".join(lines)


func _append_flow_phase(lines: Array[String], phase_name: String, phase_trace: Array[String]) -> void:
	if phase_trace.is_empty():
		lines.append("%s=none" % phase_name)
		return
	for index: int in range(phase_trace.size()):
		lines.append("%s_%d=%s" % [phase_name, index, phase_trace[index]])


func _contains_queue_transaction(phase_trace: Array[String]) -> bool:
	for line: String in phase_trace:
		if line.find("queue:append") >= 0 or line.find("queue:evict") >= 0 or line.find("queue:update") >= 0:
			return true
	return false


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
		if int(step.get("type", -1)) == ChangeRecord.ChangeType.EMPTY:
			labels.append("beat")
			continue
		labels.append("%s:%s->%s" % [step.get("subject", &""), step.get("from", Vector2i.ZERO), step.get("to", Vector2i.ZERO)])
	return str(labels)


func _replay_display_summary(steps: Array[Dictionary]) -> String:
	if steps.is_empty():
		return "[]"
	var labels: Array[String] = []
	for step: Dictionary in steps:
		if int(step.get("type", -1)) == ChangeRecord.ChangeType.EMPTY:
			labels.append("beat")
			continue
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
