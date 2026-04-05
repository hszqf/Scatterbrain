class_name ReplayController
extends Node

@export var board_view_path: NodePath
@export var replay_layer_path: NodePath
@export var step_duration: float = 0.6
@export var step_pause: float = 0.18

var _board_view: BoardView
var _replay_layer: Node2D
var _replay_presenting_subjects: Dictionary[StringName, bool] = {}
var _last_used_live_box_views: bool = false


func _ready() -> void:
	_board_view = get_node(board_view_path)
	_replay_layer = get_node(replay_layer_path)


func has_steps(steps: Array[Dictionary]) -> bool:
	return not steps.is_empty()


func play_steps(steps: Array[Dictionary]) -> void:
	_sync_replay_layer_transform()
	var replay_subjects: Array[StringName] = _collect_replay_subjects(steps)
	_last_used_live_box_views = not replay_subjects.is_empty()
	_replay_presenting_subjects.clear()
	_board_view.begin_replay_presentation(replay_subjects)
	for subject_id: StringName in replay_subjects:
		_replay_presenting_subjects[subject_id] = true
		var box_view: BoxView = _board_view.get_box_view(subject_id)
		box_view.visible = true
		box_view.set_is_ghost(true)
		box_view.set_is_conflict(false)
	for step: Dictionary in steps:
		_sync_replay_layer_transform()
		await _play_step(step)
		_sync_replay_layer_transform()
	_restore_live_subjects(replay_subjects)
	_replay_presenting_subjects.clear()
	_board_view.end_replay_presentation()


func _play_step(step: Dictionary) -> void:
	_sync_replay_layer_transform()
	if int(step.get("type", -1)) == ChangeRecord.ChangeType.EMPTY:
		await get_tree().create_timer(step_duration).timeout
		await get_tree().create_timer(step_pause).timeout
		return

	var subject_id: StringName = step.get("subject", &"")
	if not _replay_presenting_subjects.has(subject_id):
		return
	var node: BoxView = _board_view.get_box_view(subject_id)
	node.set_is_ghost(true)
	node.set_is_conflict(bool(step.get("is_conflict", false)))
	var from_pos: Vector2i = step.get("from", Vector2i.ZERO)
	var to_pos: Vector2i = step.get("to", from_pos)
	node.set_board_position(from_pos, _board_view.cell_size)

	var tween: Tween = create_tween()
	tween.tween_property(node, "position", _board_view.board_to_pixel_center(to_pos), step_duration)
	await tween.finished
	await get_tree().create_timer(step_pause).timeout


func _sync_replay_layer_transform() -> void:
	if _board_view == null or _replay_layer == null:
		return
	_replay_layer.position = _board_view.position
	_replay_layer.scale = _board_view.scale


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
		box_view.set_is_ghost(false)
		box_view.set_is_conflict(false)
		box_view.visible = true
