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
			request_restart()
		InputRouter.Intent.EMPTY_CHANGE:
			request_empty_change()
		_:
			request_move(_input_router.intent_to_direction(intent))


func request_move(direction: Vector2i) -> void:
	if _input_locked or _is_complete or direction == Vector2i.ZERO:
		return
	_handle_move(direction)


func request_empty_change() -> void:
	if _input_locked or _is_complete:
		return
	append_change(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "meditate"))


func request_restart() -> void:
	if _input_locked:
		return
	_reset_level()


func on_move_left_pressed() -> void:
	request_move(Vector2i.LEFT)


func on_move_right_pressed() -> void:
	request_move(Vector2i.RIGHT)


func on_move_up_pressed() -> void:
	request_move(Vector2i.UP)


func on_move_down_pressed() -> void:
	request_move(Vector2i.DOWN)


func on_meditate_pressed() -> void:
	request_empty_change()


func on_restart_pressed() -> void:
	request_restart()


func on_copy_log_pressed() -> void:
	copy_debug_log()


func copy_debug_log() -> void:
	var text: String = _debug_log_formatter.build_snapshot(_world, _queue.entries(), _last_recompile_reason, _last_replay_steps, BuildInfo.display_text())
	DisplayServer.clipboard_set(text)
	if DisplayServer.clipboard_get() == text:
		_debug_feedback_label.text = "LOG copied"
	else:
		print(text)
		_debug_feedback_label.text = "Copy failed; printed log"
	_feedback_clear_at_msec = Time.get_ticks_msec() + 1400


func _handle_move(direction: Vector2i) -> void:
	var resolution: Dictionary = _move_resolver.resolve_move(_world, direction)
	if not resolution["player_moved"]:
		return

	var change: ChangeRecord = resolution["change"]
	if change == null:
		_post_player_move()
		return
	append_change(change)


func append_change(change: ChangeRecord) -> void:
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
	print("[Recompile] begin reason=%s" % reason)
	var current_player_position: Vector2i = _world.player_position
	var result: CompileResult = _compiler.compile(_defaults, _queue, current_player_position)
	var world_after_compile: CompiledWorld = result.world
	var replay_steps: Array[Dictionary] = []
	if not result.pushed_out_changes.is_empty():
		replay_steps = _replay_payload_builder.build_steps(_defaults, result.queue_entries, current_player_position)
	_last_replay_steps = replay_steps

	if _replay_controller.has_steps(replay_steps):
		await _replay_controller.play_steps(replay_steps)

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
	_last_recompile_reason = "reset"
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
