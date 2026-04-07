class_name GameController
extends Node

## Orchestrates level runtime, input handling, change queue updates, and recompiles.
@export var level_scene: PackedScene
@export var board_view_path: NodePath
@export var replay_controller_path: NodePath
@export var queue_view_path: NodePath
@export var status_label_path: NodePath
@export var debug_feedback_label_path: NodePath
@export var board_center_anchor_path: NodePath
@export var build_info_label_path: NodePath

var _board_view: BoardView
var _replay_controller: ReplayController
var _queue_view: MemoryQueueView
var _status_label: Label
var _debug_feedback_label: Label
var _board_center_anchor: Control
var _build_info_label: Label

var _defaults: WorldDefaults
var _compiler: WorldCompiler = WorldCompiler.new()
var _queue: ChangeQueue = ChangeQueue.new()
var _world: CompiledWorld
var _input_router: InputRouter = InputRouter.new()
var _move_resolver: PlayerMoveResolver = PlayerMoveResolver.new()
var _replay_payload_builder: ReplayPayloadBuilder = ReplayPayloadBuilder.new()
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
var _feedback_clear_at_msec: int = 0


func _ready() -> void:
	_board_view = get_node(board_view_path)
	_replay_controller = get_node(replay_controller_path)
	_queue_view = get_node(queue_view_path)
	_status_label = get_node(status_label_path)
	_debug_feedback_label = get_node(debug_feedback_label_path)
	_board_center_anchor = get_node(board_center_anchor_path)
	_build_info_label = get_node(build_info_label_path)
	_build_info_label.text = BuildInfo.display_text()
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
	append_change(change)


func append_change(change: ChangeRecord) -> void:
	_last_appended_change_summary = _change_summary_or_none(change)
	_queue.append(change)
	_recompile_world("append: %s" % change.summary())


func _post_player_move() -> void:
	_board_view.sync_world(_world)
	_update_status()
	_check_win()


func _check_win() -> void:
	if _world.player_position == _world.exit_position:
		_is_complete = true
		_status_label.text = "CLEAR • R/RST"


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
	print("[Recompile] begin reason=%s" % reason)
	var current_player_position: Vector2i = _world.player_position
	var result: CompileResult = _compiler.compile(_defaults, _queue, current_player_position)
	var world_after_compile: CompiledWorld = result.world
	var replay_steps: Array[Dictionary] = []
	_last_pushed_out_summaries = _change_summaries(result.pushed_out_changes)
	_last_generated_ghost_summaries = _change_summaries(result.generated_ghost_changes)
	_last_queue_after_compile_summaries = _change_summaries(result.queue_entries)
	var has_replayable_pushed_out: bool = _has_replayable_pushed_out_changes(result.pushed_out_changes)
	var has_surviving_replayable_memory: bool = _has_surviving_replayable_memory(result.queue_entries)
	var can_build_replay_steps: bool = false
	if has_replayable_pushed_out and has_surviving_replayable_memory:
		replay_steps = _replay_payload_builder.build_steps(_defaults, result.queue_entries, current_player_position)
		can_build_replay_steps = not replay_steps.is_empty()
	var replay_gate_allowed: bool = has_replayable_pushed_out and has_surviving_replayable_memory and can_build_replay_steps
	_last_replay_gate_allowed = replay_gate_allowed
	_last_replay_gate_reason = _resolve_replay_gate_reason(
		result.pushed_out_changes,
		has_replayable_pushed_out,
		has_surviving_replayable_memory,
		can_build_replay_steps
	)
	if replay_gate_allowed:
		_last_replay_steps = replay_steps
		_last_replay_display_steps = _duplicate_replay_steps(replay_steps)
		_last_replay_presenting_subjects = _collect_replay_subjects(replay_steps)
		if not replay_steps.is_empty():
			var has_player_conflict_step: bool = false
			for replay_step: Dictionary in replay_steps:
				if bool(replay_step.get("is_conflict", false)):
					has_player_conflict_step = true
					break
			_last_replay_stop_reason = "player_conflict" if has_player_conflict_step else "completed"

		if _replay_controller.has_steps(replay_steps):
			await _replay_controller.play_steps(replay_steps)
			_last_replay_used_live_box_views = _replay_controller.used_live_box_views()
			_last_replay_completed = true
		elif not replay_steps.is_empty():
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
	_queue_view.render_queue(_queue.entries(), _defaults.memory_capacity, _defaults.obsession_capacity)
	_update_status()
	_check_win()

	if result.reached_safety_limit:
		push_error("compile reached safety limit")
	print("[Recompile] end iterations=%d queue=%d" % [result.iterations, _queue.size()])
	_input_locked = false


func _update_status() -> void:
	if _is_complete:
		return
	_status_label.text = "MOVE WASD/ARROWS • REST SPACE"


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
	_queue_view.render_queue(_queue.entries(), _defaults.memory_capacity, _defaults.obsession_capacity)
	_debug_feedback_label.text = ""
	_update_status()
	_layout_board()


func _build_defaults() -> WorldDefaults:
	if level_scene == null:
		push_error("GameController.level_scene is required and cannot be null.")
		assert(false, "GameController requires level_scene")
		return null

	var root: Node = level_scene.instantiate()
	if root is not LevelRoot:
		root.queue_free()
		push_error("level_scene must instantiate LevelRoot")
		assert(false, "level_scene must instantiate LevelRoot")
		return null

	add_child(root)
	var runtime_data: LevelRuntimeData = (root as LevelRoot).build_runtime_data()
	remove_child(root)
	root.queue_free()
	return WorldDefaults.from_runtime_data(runtime_data)




func _has_replayable_pushed_out_changes(pushed_out_changes: Array[ChangeRecord]) -> bool:
	for change: ChangeRecord in pushed_out_changes:
		if change == null:
			continue
		if change.type == ChangeRecord.ChangeType.EMPTY:
			continue
		if change.subject_id == &"":
			continue
		return true
	return false


func _has_surviving_replayable_memory(queue_entries: Array[ChangeRecord]) -> bool:
	for entry: ChangeRecord in queue_entries:
		if _is_replayable_memory_change(entry):
			return true
	return false


func _is_replayable_memory_change(entry: ChangeRecord) -> bool:
	if entry == null:
		return false
	if entry.subject_id == &"":
		return false
	var is_replayable_position: bool = entry.type == ChangeRecord.ChangeType.POSITION \
		and entry.source_kind == ChangeRecord.SourceKind.REMEMBERED_REBUILD
	var is_replayable_ghost: bool = entry.type == ChangeRecord.ChangeType.GHOST \
		and entry.source_kind == ChangeRecord.SourceKind.AUTO_GHOST
	return is_replayable_position or is_replayable_ghost


func _duplicate_replay_steps(steps: Array[Dictionary]) -> Array[Dictionary]:
	var copied: Array[Dictionary] = []
	for step: Dictionary in steps:
		copied.append(step.duplicate(true))
	return copied


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


func _resolve_replay_gate_reason(
	pushed_out_changes: Array[ChangeRecord],
	has_replayable_pushed_out: bool,
	has_surviving_replayable_memory: bool,
	can_build_replay_steps: bool
) -> String:
	if has_replayable_pushed_out and has_surviving_replayable_memory and can_build_replay_steps:
		return "allowed_non_empty_pushed_out"
	if not has_replayable_pushed_out and pushed_out_changes.is_empty():
		return "no_pushed_out"
	if has_replayable_pushed_out and not has_surviving_replayable_memory:
		return "no_surviving_replayable_memory"
	if has_replayable_pushed_out and has_surviving_replayable_memory and not can_build_replay_steps:
		return "no_replay_steps_from_surviving_memory"
	for change: ChangeRecord in pushed_out_changes:
		if change == null:
			continue
		if change.type != ChangeRecord.ChangeType.EMPTY and change.subject_id != &"":
			return "unknown"
	return "pushed_out_only_empty"
