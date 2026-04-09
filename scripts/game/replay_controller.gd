class_name ReplayController
extends Node

@export var board_view_path: NodePath
@export var replay_layer_path: NodePath
@export var memory_beat_duration: float = 1.0
@export var beat_prepare_duration: float = 0.15
@export var beat_action_duration: float = 0.65
@export var beat_tail_duration: float = 0.2
@export var move_anticipation_ratio: float = 0.2
@export var move_travel_ratio: float = 0.62
@export var move_settle_ratio: float = 0.3
@export var ghost_expand_ratio: float = 0.32
@export var ghost_stamp_ratio: float = 0.28

var _board_view: BoardView
var _replay_layer: Node2D
var _replay_presenting_subjects: Dictionary[StringName, bool] = {}
var _replay_actors: Dictionary[StringName, BoxView] = {}
var _last_used_live_box_views: bool = false
var _last_phase_trace: Array[String] = []


func _ready() -> void:
	_board_view = get_node(board_view_path)
	_replay_layer = get_node(replay_layer_path)


func has_steps(steps: Array[Dictionary]) -> bool:
	return not steps.is_empty()


func play_steps(steps: Array[Dictionary]) -> void:
	_sync_replay_layer_transform()
	var replay_subjects: Array[StringName] = _collect_replay_subjects(steps)
	_last_used_live_box_views = false
	_last_phase_trace = []
	_replay_presenting_subjects.clear()
	_board_view.begin_replay_presentation(replay_subjects)
	_clear_replay_actors()
	for subject_id: StringName in replay_subjects:
		_replay_presenting_subjects[subject_id] = true
		_ensure_replay_actor(subject_id)
	if not steps.is_empty():
		_last_phase_trace.append("phase:rebuild")
	for step: Dictionary in steps:
		_sync_replay_layer_transform()
		await play_memory_step(step)
		_sync_replay_layer_transform()
	_restore_live_subjects(replay_subjects)
	_clear_replay_actors()
	_replay_presenting_subjects.clear()
	_board_view.end_replay_presentation()


func play_memory_step(step: Dictionary, beat_duration: float = memory_beat_duration) -> void:
	_sync_replay_layer_transform()
	var phase_timing: Dictionary = _resolve_phase_timing(beat_duration)
	var prepare_time: float = float(phase_timing.get("prepare", 0.0))
	var action_time: float = float(phase_timing.get("action", 0.0))
	var tail_time: float = float(phase_timing.get("tail", 0.0))
	if prepare_time > 0.0:
		await get_tree().create_timer(prepare_time).timeout
	var presentation_kind: StringName = StringName(step.get("presentation_kind", _resolve_presentation_kind(step)))
	match presentation_kind:
		ReplayPayloadBuilder.PRESENTATION_BEAT:
			_last_phase_trace.append("step:beat")
			await play_timing_beat(action_time)
		ReplayPayloadBuilder.PRESENTATION_GHOSTIFY:
			_last_phase_trace.append("step:ghostify")
			await play_board_replay(step, action_time)
		_:
			_last_phase_trace.append("step:move")
			await play_board_replay(step, action_time)
	if tail_time > 0.0:
		await get_tree().create_timer(tail_time).timeout


func play_board_replay(step: Dictionary, action_duration: float) -> void:
	var presentation_kind: StringName = StringName(step.get("presentation_kind", _resolve_presentation_kind(step)))
	match presentation_kind:
		ReplayPayloadBuilder.PRESENTATION_GHOSTIFY:
			await _play_ghostify_step(step, action_duration)
		ReplayPayloadBuilder.PRESENTATION_MOVE:
			await _play_move_step(step, action_duration)


func _play_move_step(step: Dictionary, action_duration: float) -> void:
	var node: BoxView = _prepare_step_actor(step)
	if node == null:
		if action_duration > 0.0:
			await get_tree().create_timer(action_duration).timeout
		return
	var from_pos: Vector2i = step.get("from", Vector2i.ZERO)
	var to_pos: Vector2i = step.get("to", from_pos)
	node.set_board_position(from_pos, _board_view.cell_size)
	node.scale = Vector2.ONE
	node.modulate = Color.WHITE
	node.set_is_ghost(false)
	node.set_is_conflict(false)
	var anticipate: Tween = create_tween()
	anticipate.tween_property(node, "scale", Vector2(0.92, 1.06), action_duration * move_anticipation_ratio)
	await anticipate.finished

	var travel: Tween = create_tween()
	travel.set_parallel(true)
	travel.tween_property(node, "position", _board_view.board_to_pixel_center(to_pos), action_duration * move_travel_ratio)
	travel.tween_property(node, "scale", Vector2(1.06, 0.94), action_duration * move_travel_ratio)
	await travel.finished

	var settle: Tween = create_tween()
	settle.tween_property(node, "scale", Vector2.ONE, action_duration * move_settle_ratio)
	await settle.finished
	if bool(step.get("ends_as_ghost", false)):
		node.set_is_ghost(true)
	node.set_is_conflict(bool(step.get("is_conflict", false)))


func _play_ghostify_step(step: Dictionary, action_duration: float) -> void:
	var node: BoxView = _prepare_step_actor(step)
	if node == null:
		if action_duration > 0.0:
			await get_tree().create_timer(action_duration).timeout
		return
	var from_pos: Vector2i = step.get("from", Vector2i.ZERO)
	node.set_board_position(from_pos, _board_view.cell_size)
	node.set_is_ghost(false)
	node.set_is_conflict(false)
	node.modulate = Color.WHITE
	node.scale = Vector2.ONE

	var expand: Tween = create_tween()
	expand.tween_property(node, "scale", Vector2(1.18, 1.18), action_duration * ghost_expand_ratio)
	await expand.finished

	node.set_is_ghost(true)
	node.set_is_conflict(bool(step.get("is_conflict", false)))
	var stamp: Tween = create_tween()
	stamp.tween_property(node, "scale", Vector2(0.94, 0.94), action_duration * ghost_stamp_ratio)
	await stamp.finished

	var settle: Tween = create_tween()
	settle.tween_property(node, "scale", Vector2.ONE, action_duration * 0.2)
	await settle.finished


func play_timing_beat(action_duration: float) -> void:
	await get_tree().create_timer(action_duration).timeout


func _prepare_step_actor(step: Dictionary) -> BoxView:
	var subject_id: StringName = step.get("subject", &"")
	if subject_id == &"" or not _replay_presenting_subjects.has(subject_id):
		return null
	var node: BoxView = _ensure_replay_actor(subject_id)
	node.visible = true
	node.modulate = Color.WHITE
	node.scale = Vector2.ONE
	return node


func _resolve_presentation_kind(step: Dictionary) -> StringName:
	if int(step.get("type", -1)) == ChangeRecord.ChangeType.EMPTY:
		return ReplayPayloadBuilder.PRESENTATION_BEAT
	if bool(step.get("ends_as_ghost", false)):
		return ReplayPayloadBuilder.PRESENTATION_GHOSTIFY
	return ReplayPayloadBuilder.PRESENTATION_MOVE


func _sync_replay_layer_transform() -> void:
	if _board_view == null or _replay_layer == null:
		return
	_replay_layer.position = _board_view.position
	_replay_layer.scale = _board_view.scale


func _resolve_phase_timing(beat_duration: float) -> Dictionary:
	var clamped_duration: float = maxf(beat_duration, 0.01)
	var configured_total: float = beat_prepare_duration + beat_action_duration + beat_tail_duration
	if configured_total <= 0.001:
		return {
			"prepare": 0.0,
			"action": clamped_duration,
			"tail": 0.0,
		}
	var scale_factor: float = clamped_duration / configured_total
	return {
		"prepare": beat_prepare_duration * scale_factor,
		"action": beat_action_duration * scale_factor,
		"tail": beat_tail_duration * scale_factor,
	}


func get_replay_actor_subjects() -> Array[StringName]:
	var subjects: Array[StringName] = []
	for subject_id: StringName in _replay_presenting_subjects.keys():
		subjects.append(subject_id)
	subjects.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	return subjects


func get_replay_hidden_subjects() -> Array[StringName]:
	return get_replay_actor_subjects()


func used_live_box_views() -> bool:
	return _last_used_live_box_views


func get_replay_actor_count() -> int:
	return _replay_actors.size()


func get_replay_actor(subject_id: StringName) -> BoxView:
	if _replay_actors.has(subject_id):
		return _replay_actors[subject_id]
	return null


func get_last_phase_trace() -> Array[String]:
	return _last_phase_trace.duplicate()


func _collect_replay_subjects(steps: Array[Dictionary]) -> Array[StringName]:
	var seen: Dictionary[StringName, bool] = {}
	for step: Dictionary in steps:
		if int(step.get("type", -1)) == ChangeRecord.ChangeType.EMPTY:
			continue
		var subject_id: StringName = step.get("subject", &"")
		if subject_id == &"":
			continue
		seen[subject_id] = true
	var subjects: Array[StringName] = []
	for subject_id: StringName in seen.keys():
		subjects.append(subject_id)
	subjects.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	return subjects


func _restore_live_subjects(subject_ids: Array[StringName]) -> void:
	for subject_id: StringName in subject_ids:
		var box_view: BoxView = _board_view.get_box_view(subject_id)
		box_view.visible = true


func _ensure_replay_actor(subject_id: StringName) -> BoxView:
	if _replay_actors.has(subject_id):
		return _replay_actors[subject_id]
	var live_box: BoxView = _board_view.get_box_view(subject_id)
	var replay_actor: BoxView = preload("res://scenes/entities/BoxView.tscn").instantiate()
	replay_actor.name = "ReplayActor_%s" % String(subject_id)
	replay_actor.visible = true
	replay_actor.set_is_ghost(live_box.is_ghost())
	replay_actor.set_is_conflict(false)
	replay_actor.position = live_box.position
	_replay_layer.add_child(replay_actor)
	_replay_actors[subject_id] = replay_actor
	return replay_actor


func _clear_replay_actors() -> void:
	for actor: BoxView in _replay_actors.values():
		if actor != null:
			actor.queue_free()
	_replay_actors.clear()
