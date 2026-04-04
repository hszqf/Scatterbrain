class_name GameController
extends Node

## Orchestrates level runtime, input handling, change queue updates, and recompiles.
@export var level_resource: LevelDefinition
@export var board_view_path: NodePath
@export var queue_view_path: NodePath
@export var status_label_path: NodePath

var _board_view: BoardView
var _queue_view: MemoryQueueView
var _status_label: Label

var _defaults: WorldDefaults
var _compiler: WorldCompiler = WorldCompiler.new()
var _queue: ChangeQueue = ChangeQueue.new()
var _world: CompiledWorld
var _input_router: InputRouter = InputRouter.new()
var _input_locked: bool = false
var _is_complete: bool = false


func _ready() -> void:
	_board_view = get_node(board_view_path)
	_queue_view = get_node(queue_view_path)
	_status_label = get_node(status_label_path)
	_reset_level()


func _process(_delta: float) -> void:
	if _input_locked:
		return
	var intent: InputRouter.Intent = _input_router.poll_intent()
	if intent == InputRouter.Intent.NONE:
		return
	if intent == InputRouter.Intent.RESTART:
		_reset_level()
		return
	if _is_complete:
		return
	if intent == InputRouter.Intent.EMPTY_CHANGE:
		append_change(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "meditate"))
		return
	var direction: Vector2i = _input_router.intent_to_direction(intent)
	if direction != Vector2i.ZERO:
		_handle_move(direction)


func _handle_move(direction: Vector2i) -> void:
	var target: Vector2i = _world.player_position + direction
	if not _world.is_inside(target):
		return

	var box_id: StringName = _find_solid_box_at(target)
	if box_id == &"":
		_world.player_position = target
		_post_player_move()
		return

	var push_target: Vector2i = target + direction
	if not _world.is_inside(push_target):
		return
	if _world.is_solid_at(push_target):
		return

	_world.player_position = target
	append_change(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, box_id, push_target, false, "push"))
	_post_player_move()


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
		_status_label.text = "过关！按 R 重开"


func _recompile_world(reason: String) -> void:
	_input_locked = true
	print("[Recompile] begin reason=%s" % reason)
	var result: CompileResult = _compiler.compile(_defaults, _queue)
	_world = result.world

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
	_status_label.text = "方向键/WASD:移动  Space:沉思  R:重开"


func _find_solid_box_at(pos: Vector2i) -> StringName:
	for entity_id: StringName in _world.entity_positions.keys():
		if _world.entity_positions[entity_id] == pos:
			return entity_id
	return &""


func _reset_level() -> void:
	_is_complete = false
	_queue.clear()
	_defaults = WorldDefaults.from_level(level_resource)
	_world = CompiledWorld.new()
	_world.board_size = _defaults.board_size
	_world.player_position = _defaults.player_start
	_world.exit_position = _defaults.exit_position
	_world.entity_positions = _defaults.default_entity_positions.duplicate()
	_board_view.set_board_size(_defaults.board_size)
	_board_view.sync_world(_world)
	_queue_view.render_queue(_queue.entries(), _defaults.memory_capacity, _defaults.obsession_capacity)
	_update_status()
