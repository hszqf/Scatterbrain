class_name GameController
extends Node

## Orchestrates level runtime, input handling, change queue updates, and recompiles.
@export var level_scene: PackedScene
@export var board_view_path: NodePath
@export var replay_controller_path: NodePath
@export var queue_view_path: NodePath
@export var status_label_path: NodePath
@export var level_label_path: NodePath
@export var debug_feedback_label_path: NodePath
@export var board_center_anchor_path: NodePath
@export var build_info_label_path: NodePath
@export var level_scenes: Array[PackedScene] = []
@export var player_memory_slots: int = 1

var _board_view: BoardView
var _replay_controller: ReplayController
var _queue_view: MemoryQueueView
var _status_label: Label
var _level_label: Label
var _debug_feedback_label: Label
var _board_center_anchor: Control
var _build_info_label: Label

var _defaults: WorldDefaults
var _compiler: WorldCompiler = WorldCompiler.new()
var _queue: ChangeQueue = ChangeQueue.new()
var _world: CompiledWorld
var _input_router: InputRouter = InputRouter.new()
var _move_resolver: PlayerMoveResolver = PlayerMoveResolver.new()
var _debug_log_formatter: DebugLogFormatter = DebugLogFormatter.new()
var _input_locked: bool = false
var _is_complete: bool = false
var _last_recompile_reason: String = "init"
var _last_replay_steps: Array[Dictionary] = []
var _last_replay_display_steps: Array[Dictionary] = []
var _last_replay_presenting_subjects: Array[StringName] = []
var _last_replay_used_live_box_views: bool = false
var _last_replay_completed: bool = false
var _last_replay_stop_reason: String = "none"
var _last_input_source: String = "none"
var _last_input_intent: String = "none"
var _last_input_direction: Vector2i = Vector2i.ZERO
var _last_move_player_moved: bool = false
var _last_move_generated_change: String = "none"
var _last_appended_change_summary: String = "none"
var _last_pushed_out_summaries: Array[String] = []
var _last_generated_ghost_summaries: Array[String] = []
var _last_queue_after_compile_summaries: Array[String] = []
var _last_replay_gate_allowed: bool = false
var _last_replay_gate_reason: String = "none"
var _last_presentation_trace: Array[String] = []
var _feedback_clear_at_msec: int = 0
var _current_level_index: int = 0


func _ready() -> void:
	_board_view = get_node(board_view_path)
	_replay_controller = get_node(replay_controller_path)
	_queue_view = get_node(queue_view_path)
	_status_label = get_node(status_label_path)
	_level_label = get_node(level_label_path)
	_debug_feedback_label = get_node(debug_feedback_label_path)
	_board_center_anchor = get_node(board_center_anchor_path)
	_build_info_label = get_node(build_info_label_path)
	_build_info_label.text = BuildInfo.display_text()
	_resolve_initial_level_index()
	_reset_level()


func _process(_delta: float) -> void:
	_layout_board()
	if _feedback_clear_at_msec > 0 and Time.get_ticks_msec() >= _feedback_clear_at_msec:
		_debug_feedback_label.text = ""
		_feedback_clear_at_msec = 0
	if _input_locked:
		return
	var intent: InputRouter.Intent = _input_router.poll_intent()
	if intent == InputRouter.Intent.NONE:
		return
	match intent:
		InputRouter.Intent.RESTART:
			_set_last_input_debug("keyboard", "restart", Vector2i.ZERO)
			request_restart()
		InputRouter.Intent.EMPTY_CHANGE:
			_set_last_input_debug("keyboard", "empty", Vector2i.ZERO)
			request_empty_change()
		_:
			var direction: Vector2i = _input_router.intent_to_direction(intent)
			_set_last_input_debug("keyboard", _intent_to_debug_name(intent), direction)
			request_move(direction)


func request_move(direction: Vector2i) -> void:
	if _input_locked or _is_complete or direction == Vector2i.ZERO:
		return
	_handle_move(direction)


func request_empty_change() -> void:
	if _input_locked or _is_complete:
		return
	append_change(ChangeRecord.new(
		ChangeRecord.ChangeType.EMPTY,
		&"",
		Vector2i.ZERO,
		false,
		"meditate",
		ChangeRecord.SourceKind.LIVE_INPUT
	))


func request_restart() -> void:
	if _input_locked:
		return
	_reset_level()


func on_move_left_pressed() -> void:
	_set_last_input_debug("button_left", "move_left", Vector2i.LEFT)
	request_move(Vector2i.LEFT)


func on_move_right_pressed() -> void:
	_set_last_input_debug("button_right", "move_right", Vector2i.RIGHT)
	request_move(Vector2i.RIGHT)


func on_move_up_pressed() -> void:
	_set_last_input_debug("button_up", "move_up", Vector2i.UP)
	request_move(Vector2i.UP)


func on_move_down_pressed() -> void:
	_set_last_input_debug("button_down", "move_down", Vector2i.DOWN)
	request_move(Vector2i.DOWN)


func on_meditate_pressed() -> void:
	_set_last_input_debug("button_rest", "empty", Vector2i.ZERO)
	request_empty_change()


func on_restart_pressed() -> void:
	_set_last_input_debug("button_restart", "restart", Vector2i.ZERO)
	request_restart()


func on_copy_log_pressed() -> void:
	copy_debug_log()


func copy_debug_log() -> void:
	var replay_layer_transform: String = _snapshot_replay_layer_transform()
	var text: String = _debug_log_formatter.build_snapshot(
		_world,
		_queue.entries(),
		_last_recompile_reason,
		_last_replay_steps,
		_last_replay_display_steps,
		_last_replay_presenting_subjects,
		_last_replay_used_live_box_views,
		_last_replay_completed,
		BuildInfo.display_text(),
		_format_node2d_transform(_board_view),
		replay_layer_transform,
		_last_replay_stop_reason,
		_last_input_source,
		_last_input_intent,
		_last_input_direction,
		_last_move_player_moved,
		_last_move_generated_change,
		_last_appended_change_summary,
		_last_pushed_out_summaries,
		_last_generated_ghost_summaries,
		_last_queue_after_compile_summaries,
		_last_replay_gate_allowed,
		_last_replay_gate_reason
	)
	DisplayServer.clipboard_set(text)
	if DisplayServer.clipboard_get() == text:
		_debug_feedback_label.text = "LOG copied"
	else:
		print(text)
		_debug_feedback_label.text = "Copy failed; printed log"
	_feedback_clear_at_msec = Time.get_ticks_msec() + 1400


func _format_node2d_transform(node: Node2D) -> String:
	if node == null:
		return "n/a"
	return "pos(%s), scale(%s)" % [str(node.position), str(node.scale)]


func _snapshot_replay_layer_transform() -> String:
	if not _last_replay_completed:
		return "inactive"
	var replay_layer: Node2D = _replay_controller.get_node(_replay_controller.replay_layer_path) as Node2D
	return _format_node2d_transform(replay_layer)


func _handle_move(direction: Vector2i) -> void:
	var resolution: Dictionary = _move_resolver.resolve_move(_world, direction)
	_last_move_player_moved = bool(resolution.get("player_moved", false))
	var change: ChangeRecord = resolution.get("change")
	_last_move_generated_change = _change_summary_or_none(change)
	if not _last_move_player_moved:
		return

	if change == null:
		_post_player_move()
		return

	# 先把本次玩家位移完整呈现（仅刷新棋盘），再进入记忆入队/重编译表现。
	_present_live_player_move()
	append_change(change)


func append_change(change: ChangeRecord) -> void:
	if change == null:
		return
	var queue_before_append: Array[ChangeRecord] = _queue.entries()
	var source_global_pos: Vector2 = _board_view.get_change_source_global_position(change)
	_board_view.play_change_source_highlight(change)
	if DisplayServer.get_name() == "headless":
		_queue_view.play_incoming_change_fx(
			change,
			source_global_pos,
			queue_before_append,
			_memory_capacity(),
			_defaults.obsession_capacity
		)
	else:
		await _queue_view.play_incoming_change_fx(
			change,
			source_global_pos,
			queue_before_append,
			_memory_capacity(),
			_defaults.obsession_capacity
		)
	_last_appended_change_summary = _change_summary_or_none(change)
	_queue.append(change)
	_recompile_world("append: %s" % change.summary())


func _present_live_player_move() -> void:
	_board_view.sync_world(_world)


func _post_player_move() -> void:
	_board_view.sync_world(_world)
	_update_status()
	_check_win()


func _check_win() -> void:
	if _world.player_position == _world.exit_position:
		_is_complete = true
		_status_label.text = "CLEAR"
		_begin_level_complete_transition()


func _begin_level_complete_transition() -> void:
	if _input_locked:
		return
	_input_locked = true
	await _fade_board_to(0.0, 0.38)
	_advance_level_index()
	_reset_level()
	_board_view.modulate.a = 0.0
	await _fade_board_to(1.0, 0.34)
	_input_locked = false


func _fade_board_to(target_alpha: float, duration: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_board_view, "modulate:a", target_alpha, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


func _recompile_world(reason: String) -> void:
	if _input_locked:
		return
	_input_locked = true
	_last_recompile_reason = reason
	_last_replay_steps = []
	_last_replay_display_steps = []
	_last_replay_presenting_subjects = []
	_last_replay_used_live_box_views = false
	_last_replay_completed = false
	_last_replay_stop_reason = "none"
	_last_presentation_trace = []
	print("[Recompile] begin reason=%s" % reason)
	var current_player_position: Vector2i = _world.player_position
	var previous_queue_entries: Array[ChangeRecord] = _queue.entries()
	var result: CompileResult = _compiler.compile(_defaults, _queue, current_player_position)
	var world_after_compile: CompiledWorld = result.world
	var replay_trace: Array[Dictionary] = result.replay_trace
	var first_pass_queue_entries: Array[ChangeRecord] = _queue_entries_for_first_pass(replay_trace, result.queue_entries)
	_last_pushed_out_summaries = _change_summaries(result.pushed_out_changes)
	_last_generated_ghost_summaries = _change_summaries(result.generated_ghost_changes)
	_last_queue_after_compile_summaries = _change_summaries(result.queue_entries)
	var has_replayable_pushed_out: bool = not result.pushed_out_changes.is_empty()
	var can_play_trace: bool = _replay_controller.has_trace_items(replay_trace)
	var has_queue_update_trace: bool = _trace_contains_kind(replay_trace, "queue_update")
	var replay_gate_allowed: bool = can_play_trace and (has_replayable_pushed_out or has_queue_update_trace)
	_last_replay_gate_allowed = replay_gate_allowed
	_last_replay_gate_reason = _resolve_replay_gate_reason(
		result.pushed_out_changes,
		has_replayable_pushed_out,
		has_queue_update_trace,
		can_play_trace
	)
	if replay_gate_allowed:
		await _queue_view.play_queue_transition(
			previous_queue_entries,
			first_pass_queue_entries,
			_memory_capacity(),
			_defaults.obsession_capacity,
			result.pushed_out_changes
		)
		_last_presentation_trace = _queue_view.get_last_animation_trace()
	else:
		_queue_view.render_queue(result.queue_entries, _memory_capacity(), _defaults.obsession_capacity)
	if replay_gate_allowed:
		_last_replay_steps = _duplicate_replay_steps(replay_trace)
		_last_replay_display_steps = _trace_to_display_steps(replay_trace)
		_last_replay_presenting_subjects = _collect_trace_subjects(replay_trace)
		_last_replay_stop_reason = "completed"
		if _replay_controller.has_trace_items(replay_trace):
			_last_presentation_trace.append("board:rebuild")
			await _play_compile_trace(replay_trace)
			_last_replay_used_live_box_views = _replay_controller.used_live_box_views()
			_last_replay_completed = true
		elif not replay_trace.is_empty():
			_last_replay_stop_reason = "none"
	else:
		_last_replay_steps = []
		_last_replay_display_steps = []
		_last_replay_presenting_subjects = []
		_last_replay_completed = false
		_last_replay_stop_reason = _last_replay_gate_reason

	_world = world_after_compile
	_queue.clear()
	for entry: ChangeRecord in result.queue_entries:
		_queue.append(entry)

	_board_view.sync_world(_world)
	_queue_view.render_queue(_queue.entries(), _memory_capacity(), _defaults.obsession_capacity)
	_update_status()
	_check_win()

	if result.reached_safety_limit:
		push_error("compile reached safety limit")
	print("[Recompile] end iterations=%d queue=%d" % [result.iterations, _queue.size()])
	_input_locked = false


func _play_compile_trace(trace: Array[Dictionary]) -> void:
	if trace.is_empty():
		return
	_replay_controller.begin_trace_playback(trace, _defaults)
	var focused_queue_index: int = -1
	for trace_index: int in range(trace.size()):
		var item: Dictionary = trace[trace_index]
		var kind: String = String(item.get("kind", ""))
		if kind == "queue_focus":
			if focused_queue_index >= 0:
				_queue_view.end_focus_on_slot(focused_queue_index)
			focused_queue_index = int(item.get("queue_index", -1))
			if focused_queue_index >= 0:
				_last_presentation_trace.append("queue:focus:%d" % focused_queue_index)
				_queue_view.begin_focus_on_slot(focused_queue_index)
			continue
		if kind == "queue_update":
			var before_entries: Array[ChangeRecord] = item.get("before_queue_entries", [])
			var after_entries: Array[ChangeRecord] = item.get("after_queue_entries", [])
			var evicted_changes: Array[ChangeRecord] = item.get("evicted_changes", [])
			var generated_changes: Array[ChangeRecord] = item.get("generated_changes", [])
			var incoming_change: ChangeRecord = null
			var incoming_source_pos: Vector2 = Vector2.ZERO
			for generated_change: ChangeRecord in generated_changes:
				if generated_change == null:
					continue
				incoming_change = generated_change
				incoming_source_pos = _replay_controller.get_subject_global_position(generated_change.subject_id)
			_replay_controller.reset_subjects_for_next_pass(trace, trace_index + 1)
			_last_presentation_trace.append("queue:update")
			await _queue_view.play_queue_update(
				before_entries,
				after_entries,
				_memory_capacity(),
				_defaults.obsession_capacity,
				evicted_changes,
				generated_changes,
				incoming_change,
				incoming_source_pos
			)
			continue
		if kind == "queue_restart":
			if focused_queue_index >= 0:
				_queue_view.end_focus_on_slot(focused_queue_index)
				focused_queue_index = -1
			_last_presentation_trace.append("queue:restart")
		if kind == "move" or kind == "ghostify" or kind == "beat_empty" or kind == "queue_restart":
			_last_presentation_trace.append("board:trace:%s" % kind)
			await _replay_controller.play_trace_item(item, _replay_controller.memory_beat_duration)
			if (kind == "move" or kind == "ghostify" or kind == "beat_empty") and focused_queue_index >= 0:
				_queue_view.end_focus_on_slot(focused_queue_index)
				focused_queue_index = -1
	if focused_queue_index >= 0:
		_queue_view.end_focus_on_slot(focused_queue_index)
	_replay_controller.end_trace_playback()


func _update_status() -> void:
	if _is_complete:
		return
	_status_label.text = "MOVE WASD/ARROWS - REST SPACE"
	_level_label.text = _format_level_label()


func _layout_board() -> void:
	if _board_center_anchor == null:
		return
	var area_pos: Vector2 = _board_center_anchor.global_position
	var area_size: Vector2 = _board_center_anchor.size
	var board_size: Vector2 = _board_view.board_pixel_size()
	if board_size == Vector2.ZERO:
		return
	var scale_fit_x: float = area_size.x / board_size.x
	var scale_fit_y: float = area_size.y / board_size.y
	var base_scale: float = min(scale_fit_x, scale_fit_y)
	var is_portrait: bool = area_size.y > area_size.x
	var target_scale: float = min(base_scale, 1.0)
	if is_portrait:
		target_scale = min(base_scale * 0.98, 1.05)
	var clamped_scale: float = clamp(target_scale, 0.65, 1.2)
	_board_view.scale = Vector2.ONE * clamped_scale
	var drawn_size: Vector2 = board_size * clamped_scale
	var top_bias: float = area_size.y * (0.12 if is_portrait else 0.18)
	var max_top: float = max(area_size.y - drawn_size.y, 0.0)
	var top_offset: float = clamp(top_bias, 0.0, max_top)
	var centered_x: float = (area_size.x - drawn_size.x) * 0.5
	_board_view.position = area_pos + Vector2(centered_x, top_offset)


func _reset_level() -> void:
	_is_complete = false
	_queue.clear()
	_last_replay_steps = []
	_last_replay_display_steps = []
	_last_replay_presenting_subjects = []
	_last_replay_used_live_box_views = false
	_last_replay_completed = false
	_last_replay_stop_reason = "none"
	_last_recompile_reason = "reset"
	_last_input_source = "none"
	_last_input_intent = "none"
	_last_input_direction = Vector2i.ZERO
	_last_move_player_moved = false
	_last_move_generated_change = "none"
	_last_appended_change_summary = "none"
	_last_pushed_out_summaries = []
	_last_generated_ghost_summaries = []
	_last_queue_after_compile_summaries = []
	_last_replay_gate_allowed = false
	_last_replay_gate_reason = "none"
	_last_presentation_trace = []
	_defaults = _build_defaults()
	_world = CompiledWorld.new()
	_world.board_size = _defaults.board_size
	_world.player_position = _defaults.player_start
	_world.exit_position = _defaults.exit_position
	for floor_pos: Vector2i in _defaults.floor_cells:
		_world.floor_cells[floor_pos] = true
	for wall_pos: Vector2i in _defaults.wall_positions:
		_world.wall_positions[wall_pos] = true
	_world.entity_positions = _defaults.default_entity_positions.duplicate()
	_board_view.set_board_size(_defaults.board_size)
	_board_view.sync_world(_world)
	_queue_view.render_queue(_queue.entries(), _memory_capacity(), _defaults.obsession_capacity)
	_debug_feedback_label.text = ""
	_level_label.text = _format_level_label()
	_update_status()
	_layout_board()


func _build_defaults() -> WorldDefaults:
	var active_scene: PackedScene = _get_active_level_scene()
	if active_scene == null:
		push_error("GameController.level_scene is required and cannot be null.")
		assert(false, "GameController requires level_scene")
		return null

	var root: Node = active_scene.instantiate()
	if root is not LevelRoot:
		root.queue_free()
		push_error("level_scene must instantiate LevelRoot")
		assert(false, "level_scene must instantiate LevelRoot")
		return null

	add_child(root)
	var runtime_data: LevelRuntimeData = (root as LevelRoot).build_runtime_data()
	remove_child(root)
	root.queue_free()
	var defaults: WorldDefaults = WorldDefaults.from_runtime_data(runtime_data)
	defaults.memory_capacity = _memory_capacity()
	return defaults


func _memory_capacity() -> int:
	return maxi(1, player_memory_slots)


func _get_active_level_scene() -> PackedScene:
	if not level_scenes.is_empty():
		var clamped_index: int = clampi(_current_level_index, 0, level_scenes.size() - 1)
		return level_scenes[clamped_index]
	return level_scene


func _resolve_initial_level_index() -> void:
	_current_level_index = 0
	if level_scenes.is_empty() or level_scene == null:
		return
	for idx: int in range(level_scenes.size()):
		if level_scenes[idx] == level_scene:
			_current_level_index = idx
			return


func _advance_level_index() -> void:
	if level_scenes.is_empty():
		return
	_current_level_index = (_current_level_index + 1) % level_scenes.size()


func _format_level_label() -> String:
	return "LEVEL %d" % (_current_level_index + 1)




func _duplicate_replay_steps(steps: Array[Dictionary]) -> Array[Dictionary]:
	var copied: Array[Dictionary] = []
	for step: Dictionary in steps:
		copied.append(step.duplicate(true))
	return copied


func _collect_trace_subjects(trace: Array[Dictionary]) -> Array[StringName]:
	var seen: Dictionary[StringName, bool] = {}
	for item: Dictionary in trace:
		var kind: String = String(item.get("kind", ""))
		if kind != "move" and kind != "ghostify":
			continue
		var subject_id: StringName = item.get("subject", &"")
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


func _trace_to_display_steps(trace: Array[Dictionary]) -> Array[Dictionary]:
	var display_steps: Array[Dictionary] = []
	for item: Dictionary in trace:
		var kind: String = String(item.get("kind", ""))
		match kind:
			"beat_empty":
				display_steps.append({
					"type": ChangeRecord.ChangeType.EMPTY,
					"queue_index": int(item.get("queue_index", -1)),
					"presentation_kind": ReplayController.PRESENTATION_BEAT,
				})
			"move":
				display_steps.append({
					"type": ChangeRecord.ChangeType.POSITION,
					"queue_index": int(item.get("queue_index", -1)),
					"subject": item.get("subject", &""),
					"from": item.get("from", Vector2i.ZERO),
					"to": item.get("to", Vector2i.ZERO),
					"presentation_kind": ReplayController.PRESENTATION_MOVE,
				})
			"ghostify":
				var at: Vector2i = item.get("at", Vector2i.ZERO)
				display_steps.append({
					"type": ChangeRecord.ChangeType.GHOST,
					"queue_index": int(item.get("queue_index", -1)),
					"subject": item.get("subject", &""),
					"from": at,
					"to": at,
					"presentation_kind": ReplayController.PRESENTATION_GHOSTIFY,
					"is_conflict": true,
					"ends_as_ghost": true,
				})
	return display_steps


func _set_last_input_debug(source: String, intent: String, direction: Vector2i) -> void:
	_last_input_source = source if not source.is_empty() else "unknown"
	_last_input_intent = intent if not intent.is_empty() else "unknown"
	_last_input_direction = direction


func _intent_to_debug_name(intent: InputRouter.Intent) -> String:
	match intent:
		InputRouter.Intent.MOVE_LEFT:
			return "move_left"
		InputRouter.Intent.MOVE_RIGHT:
			return "move_right"
		InputRouter.Intent.MOVE_UP:
			return "move_up"
		InputRouter.Intent.MOVE_DOWN:
			return "move_down"
		InputRouter.Intent.EMPTY_CHANGE:
			return "empty"
		InputRouter.Intent.RESTART:
			return "restart"
		_:
			return "unknown"


func _change_summary_or_none(change: ChangeRecord) -> String:
	if change == null:
		return "none"
	return change.summary()


func _change_summaries(changes: Array[ChangeRecord]) -> Array[String]:
	var summaries: Array[String] = []
	for change: ChangeRecord in changes:
		summaries.append(_change_summary_or_none(change))
	return summaries




func _trace_contains_kind(trace: Array[Dictionary], kind_name: String) -> bool:
	for item: Dictionary in trace:
		if String(item.get("kind", "")) == kind_name:
			return true
	return false


func _resolve_replay_gate_reason(
	pushed_out_changes: Array[ChangeRecord],
	has_replayable_pushed_out: bool,
	has_queue_update_trace: bool,
	can_play_trace: bool
) -> String:
	if can_play_trace and (has_replayable_pushed_out or has_queue_update_trace):
		return "allowed_trace_items"
	if not can_play_trace:
		return "no_trace_items"
	if not has_replayable_pushed_out and pushed_out_changes.is_empty():
		return "no_pushed_out"
	return "blocked"


func _queue_entries_for_first_pass(trace: Array[Dictionary], fallback_entries: Array[ChangeRecord]) -> Array[ChangeRecord]:
	for item: Dictionary in trace:
		if String(item.get("kind", "")) != "pass_begin":
			continue
		return item.get("queue_entries", fallback_entries)
	return fallback_entries
