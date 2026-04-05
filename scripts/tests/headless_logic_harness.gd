extends SceneTree

const EXIT_OK: int = 0
const EXIT_FAIL: int = 1
const LEVEL_ROOT_SCENE: PackedScene = preload("res://scenes/levels/LevelRoot.tscn")
const LEVEL001_SCENE: PackedScene = preload("res://scenes/levels/Level001.tscn")
const GAME_ROOT_SCENE: PackedScene = preload("res://scenes/game/GameRoot.tscn")

var _compiler: WorldCompiler = WorldCompiler.new()
var _resolver: PlayerMoveResolver = PlayerMoveResolver.new()
var _formatter: DebugLogFormatter = DebugLogFormatter.new()


func _init() -> void:
	var cases: Array[Dictionary] = _build_cases()
	var failed: int = 0
	for case_data: Dictionary in cases:
		if not await _run_case(case_data):
			failed += 1

	print("==== LOGIC HARNESS SUMMARY ====")
	print("total=%d pass=%d fail=%d" % [cases.size(), cases.size() - failed, failed])
	quit(EXIT_OK if failed == 0 else EXIT_FAIL)


func _run_case(case_data: Dictionary) -> bool:
	var case_id: String = String(case_data["id"])
	var context_mode: String = String(case_data.get("context_mode", "blueprint"))
	if context_mode == "blueprint" and case_id.begins_with("controller_"):
		context_mode = "controller_blueprint"
	var context: Dictionary = {}
	var is_controller_case: bool = false
	match context_mode:
		"controller_blueprint":
			context = await _build_controller_context(case_data["blueprint"])
			is_controller_case = true
		"controller_level001":
			context = await _build_controller_context_from_level_scene(LEVEL001_SCENE)
			is_controller_case = true
		"level001":
			context = _build_level_context(LEVEL001_SCENE)
		_:
			context = _build_context(case_data["blueprint"])
	print("=== CASE: %s ===" % case_data["name"])
	print("initial state: %s" % _format_state(context["world"], context["queue"], context["runtime_data"], context["defaults"]))
	print("action: %s" % case_data["action"])

	var passed: bool = false
	match case_id:
		"chain_levelroot_runtime_data":
			passed = _assert_runtime_data_output(context)
		"chain_world_defaults_mapping":
			passed = _assert_world_defaults_output(context)
		"chain_no_resolver_shortcut":
			passed = _assert_full_chain_output(context)
		"world_floor_wall_queries":
			passed = _assert_floor_wall_queries(context)
		"world_player_walkable_queries":
			passed = _assert_player_walkable_queries(context)
		"world_box_landing_queries":
			passed = _assert_box_landing_queries(context)
		"gameplay_walk_success":
			passed = _assert_gameplay_walk_success(context)
		"gameplay_walk_block_wall":
			passed = _assert_gameplay_wall_block(context)
		"gameplay_walk_block_no_floor":
			passed = _assert_gameplay_void_block(context)
		"gameplay_push_box_to_floor":
			passed = _assert_gameplay_push_to_floor(context)
		"gameplay_push_box_to_void":
			passed = _assert_gameplay_push_to_void(context)
		"gameplay_recompile_keeps_player_position":
			passed = _assert_recompile_keeps_player(context)
		"controller_walk_success":
			passed = _assert_controller_walk_success(context)
		"controller_walk_block_wall":
			passed = _assert_controller_walk_block_wall(context)
		"controller_walk_block_no_floor":
			passed = _assert_controller_walk_block_no_floor(context)
		"controller_push_box_to_floor":
			passed = _assert_controller_push_box_to_floor(context)
		"controller_push_box_to_void":
			passed = _assert_controller_push_box_to_void(context)
		"compile_pushes_out_oldest_unpinned":
			passed = _assert_compile_pushes_out_oldest_unpinned(context)
		"controller_replay_locks_input_then_unlocks":
			passed = await _assert_controller_replay_locks_input_then_unlocks(context)
		"replay_layer_transform_matches_board_view":
			passed = await _assert_replay_layer_transform_matches_board_view(context)
		"replay_micro_steps_have_slower_cadence_config":
			passed = _assert_replay_micro_steps_have_slower_cadence_config(context)
		"replay_uses_live_box_view_and_restores_state":
			passed = await _assert_replay_uses_live_box_view_and_restores_state(context)
		"board_view_sync_does_not_override_replay_presenting_subjects":
			passed = await _assert_board_view_sync_does_not_override_replay_presenting_subjects(context)
		"level001_layout_matches_expected":
			passed = _assert_level001_layout_matches_expected(context)
		"level001_two_left_moves_state_is_stable":
			passed = _assert_level001_two_left_moves_state_is_stable(context)
		"debug_snapshot_has_real_values_not_placeholders":
			passed = _assert_debug_snapshot_has_real_values_not_placeholders(context)
		"snapshot_includes_build_info":
			passed = _assert_snapshot_includes_build_info(context)
		"overflow_with_only_empty_memory_has_no_replay":
			passed = _assert_overflow_with_only_empty_memory_has_no_replay(context)
		"overflow_with_remaining_position_memory_replays_retained_steps":
			passed = _assert_overflow_with_remaining_position_memory_replays_retained_steps(context)
		"retained_position_replay_expands_to_micro_steps":
			passed = _assert_retained_position_replay_expands_to_micro_steps(context)
		"replay_marks_player_conflict_on_intermediate_step":
			passed = _assert_replay_marks_player_conflict_on_intermediate_step(context)
		"snapshot_reports_last_replay_display_info":
			passed = _assert_snapshot_reports_last_replay_display_info(context)
		"controller_empty_overflow_snapshot_matches_memory_semantics":
			passed = await _assert_controller_empty_overflow_snapshot_matches_memory_semantics(context)
		"build_info_display_uses_generated_build_file_or_dev":
			passed = _assert_build_info_display_uses_generated_build_file_or_dev(context)
		"compiler_does_not_duplicate_same_ghost_repeatedly":
			passed = _assert_compiler_does_not_duplicate_same_ghost_repeatedly(context)
		"level001_three_left_moves_no_stale_ghost":
			passed = _assert_level001_three_left_moves_no_stale_ghost(context)
		"memory_queue_symbols_are_ascii_safe":
			passed = _assert_memory_queue_symbols_are_ascii_safe(context)
		_:
			push_error("Unknown case id: %s" % case_id)
			passed = false

	print("final state: %s" % _format_state(context["world"], context["queue"], context["runtime_data"], context["defaults"]))
	print("queue state: %s" % _format_queue(context["queue"].entries()))
	print("result: %s" % ("PASS" if passed else "FAIL"))
	print("")
	if is_controller_case:
		var controller: GameController = context["controller"]
		get_root().remove_child(controller)
		controller.queue_free()
	return passed


func _build_context(blueprint: Dictionary) -> Dictionary:
	var level_root: LevelRoot = _instantiate_level_root_from_blueprint(blueprint)
	get_root().add_child(level_root)

	var runtime_data: LevelRuntimeData = level_root.build_runtime_data()
	var defaults: WorldDefaults = WorldDefaults.from_runtime_data(runtime_data)
	var queue: ChangeQueue = ChangeQueue.new()
	var compiled: CompileResult = _compiler.compile(defaults, queue, defaults.player_start)
	var world: CompiledWorld = compiled.world

	queue.clear()
	for entry: ChangeRecord in compiled.queue_entries:
		queue.append(entry)

	level_root.queue_free()
	return {
		"runtime_data": runtime_data,
		"defaults": defaults,
		"queue": queue,
		"world": world,
	}


func _build_level_context(level_scene: PackedScene) -> Dictionary:
	var runtime_data: LevelRuntimeData = _build_runtime_data_from_level_scene(level_scene)
	var defaults: WorldDefaults = WorldDefaults.from_runtime_data(runtime_data)
	var queue: ChangeQueue = ChangeQueue.new()
	var world: CompiledWorld = _compiler.compile(defaults, queue, defaults.player_start).world
	return {
		"runtime_data": runtime_data,
		"defaults": defaults,
		"queue": queue,
		"world": world,
	}


func _build_controller_context(blueprint: Dictionary) -> Dictionary:
	var level_scene: PackedScene = _build_level_scene_from_blueprint(blueprint)
	return await _build_controller_context_from_level_scene(level_scene)


func _build_controller_context_from_level_scene(level_scene: PackedScene) -> Dictionary:
	var runtime_data: LevelRuntimeData = _build_runtime_data_from_level_scene(level_scene)
	var controller: GameController = GAME_ROOT_SCENE.instantiate()
	controller.level_scene = level_scene
	get_root().add_child(controller)
	await process_frame
	var defaults: WorldDefaults = controller.get("_defaults")
	var world: CompiledWorld = controller.get("_world")
	var queue: ChangeQueue = controller.get("_queue")
	return {
		"controller": controller,
		"runtime_data": runtime_data,
		"defaults": defaults,
		"queue": queue,
		"world": world,
	}


func _build_level_scene_from_blueprint(blueprint: Dictionary) -> PackedScene:
	var level_root: LevelRoot = _instantiate_level_root_from_blueprint(blueprint)
	_assign_child_owners(level_root, level_root)
	var packed_level: PackedScene = PackedScene.new()
	var pack_result: int = packed_level.pack(level_root)
	assert(pack_result == OK, "Failed to pack blueprint LevelRoot scene")
	level_root.queue_free()
	return packed_level


func _build_runtime_data_from_level_scene(level_scene: PackedScene) -> LevelRuntimeData:
	var level_root: LevelRoot = level_scene.instantiate()
	get_root().add_child(level_root)
	var runtime_data: LevelRuntimeData = level_root.build_runtime_data()
	get_root().remove_child(level_root)
	level_root.queue_free()
	return runtime_data


func _assign_child_owners(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner
		_assign_child_owners(child, owner)


func _instantiate_level_root_from_blueprint(blueprint: Dictionary) -> LevelRoot:
	var level_root: LevelRoot = LEVEL_ROOT_SCENE.instantiate()
	level_root.auto_rebuild_in_editor = false
	level_root.grid_size = Vector3i(blueprint["board_size"].x, blueprint["board_size"].y, 1)
	level_root.memory_capacity = int(blueprint.get("memory_capacity", 8))

	var grid: Node = level_root.get_node("Grid")
	grid.owner = level_root
	level_root.set("_grid", grid)
	var slice := Node2D.new()
	slice.name = "Slice_0"
	grid.add_child(slice)
	slice.owner = level_root

	for y: int in range(blueprint["board_size"].y):
		for x: int in range(blueprint["board_size"].x):
			var pos: Vector3i = Vector3i(x, y, 0)
			var cell := LevelCell.new()
			cell.name = "Cell_%d_%d_0" % [x, y]
			cell.coord = pos
			cell.has_floor = blueprint["floors"].has(pos)
			cell.content_type = LevelCell.CellContentType.EMPTY
			cell.is_player_spawn = false
			cell.is_exit = false
			slice.add_child(cell)
			cell.owner = level_root

	for wall_pos: Vector3i in blueprint["walls"]:
		var wall_cell: LevelCell = level_root.get_node("Grid/Slice_0/Cell_%d_%d_0" % [wall_pos.x, wall_pos.y])
		wall_cell.content_type = LevelCell.CellContentType.WALL
	for box_pos: Vector3i in blueprint["boxes"]:
		var box_cell: LevelCell = level_root.get_node("Grid/Slice_0/Cell_%d_%d_0" % [box_pos.x, box_pos.y])
		box_cell.content_type = LevelCell.CellContentType.BOX

	var spawn_cell: LevelCell = level_root.get_node("Grid/Slice_0/Cell_%d_%d_0" % [blueprint["player_start"].x, blueprint["player_start"].y])
	spawn_cell.is_player_spawn = true
	var exit_cell: LevelCell = level_root.get_node("Grid/Slice_0/Cell_%d_%d_0" % [blueprint["exit_position"].x, blueprint["exit_position"].y])
	exit_cell.is_exit = true
	return level_root


func _apply_official_move(context: Dictionary, direction: Vector2i) -> Dictionary:
	var world: CompiledWorld = context["world"]
	var queue: ChangeQueue = context["queue"]
	var defaults: WorldDefaults = context["defaults"]
	var resolution: Dictionary = _resolver.resolve_move(world, direction)
	if not resolution["player_moved"]:
		return resolution

	var change: ChangeRecord = resolution["change"]
	if change == null:
		return resolution

	queue.append(change)
	var result: CompileResult = _compiler.compile(defaults, queue, world.player_position)
	context["world"] = result.world
	queue.clear()
	for entry: ChangeRecord in result.queue_entries:
		queue.append(entry)
	return resolution


func _assert_runtime_data_output(context: Dictionary) -> bool:
	var runtime_data: LevelRuntimeData = context["runtime_data"]
	return runtime_data.player_start == Vector3i(0, 0, 0) \
		and runtime_data.exit_position == Vector3i(3, 0, 0) \
		and _sorted_vec3_array(runtime_data.floor_cells) == _sorted_vec3_array([Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(3, 0, 0)]) \
		and _sorted_vec3_array(runtime_data.walls) == [Vector3i(1, 0, 0)] \
		and _sorted_vec3_array(runtime_data.boxes) == [Vector3i(0, 0, 0)]


func _assert_world_defaults_output(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	return _sorted_vec2_array(defaults.floor_cells) == _sorted_vec2_array([Vector2i(0, 0), Vector2i(1, 0), Vector2i(3, 0)]) \
		and _sorted_vec2_array(defaults.wall_positions) == [Vector2i(1, 0)] \
		and _sorted_vec2_array(defaults.default_entity_positions.values()) == [Vector2i(0, 0)]


func _assert_full_chain_output(context: Dictionary) -> bool:
	var runtime_data: LevelRuntimeData = context["runtime_data"]
	var defaults: WorldDefaults = context["defaults"]
	var world: CompiledWorld = context["world"]
	return runtime_data.floor_cells.size() == defaults.floor_cells.size() \
		and runtime_data.walls.size() == defaults.wall_positions.size() \
		and runtime_data.boxes.size() == defaults.default_entity_positions.size() \
		and world.has_floor_at(Vector2i(3, 0)) \
		and world.has_wall_at(Vector2i(1, 0)) \
		and defaults.default_entity_positions.size() == 1 \
		and not world.has_box_at(Vector2i(0, 0))


func _assert_floor_wall_queries(context: Dictionary) -> bool:
	var world: CompiledWorld = context["world"]
	return world.has_floor_at(Vector2i(0, 0)) \
		and world.has_floor_at(Vector2i(2, 0)) \
		and not world.has_floor_at(Vector2i(1, 0)) \
		and world.has_wall_at(Vector2i(2, 0)) \
		and not world.has_wall_at(Vector2i(0, 0))


func _assert_player_walkable_queries(context: Dictionary) -> bool:
	var world: CompiledWorld = context["world"]
	return world.is_walkable_for_player(Vector2i(1, 0)) \
		and not world.is_walkable_for_player(Vector2i(2, 0)) \
		and not world.is_walkable_for_player(Vector2i(3, 0)) \
		and not world.is_walkable_for_player(Vector2i(4, 0))


func _assert_box_landing_queries(context: Dictionary) -> bool:
	var world: CompiledWorld = context["world"]
	return not world.is_blocked_for_box(Vector2i(1, 0)) \
		and world.is_blocked_for_box(Vector2i(2, 0)) \
		and world.is_blocked_for_box(Vector2i(3, 0)) \
		and world.is_blocked_for_box(Vector2i(0, 0)) \
		and world.is_blocked_for_box(Vector2i(5, 0))


func _assert_gameplay_walk_success(context: Dictionary) -> bool:
	var resolution: Dictionary = _apply_official_move(context, Vector2i.RIGHT)
	var world: CompiledWorld = context["world"]
	var queue: ChangeQueue = context["queue"]
	return resolution["player_moved"] \
		and resolution["change"] == null \
		and world.player_position == Vector2i(1, 0) \
		and queue.size() == 0


func _assert_gameplay_wall_block(context: Dictionary) -> bool:
	var resolution: Dictionary = _apply_official_move(context, Vector2i.RIGHT)
	var world: CompiledWorld = context["world"]
	var queue: ChangeQueue = context["queue"]
	return not resolution["player_moved"] \
		and world.player_position == Vector2i(0, 0) \
		and queue.size() == 0


func _assert_gameplay_void_block(context: Dictionary) -> bool:
	var resolution: Dictionary = _apply_official_move(context, Vector2i.RIGHT)
	var world: CompiledWorld = context["world"]
	var queue: ChangeQueue = context["queue"]
	return not resolution["player_moved"] \
		and world.player_position == Vector2i(0, 0) \
		and queue.size() == 0


func _assert_gameplay_push_to_floor(context: Dictionary) -> bool:
	var resolution: Dictionary = _apply_official_move(context, Vector2i.RIGHT)
	var world: CompiledWorld = context["world"]
	var queue_entries: Array[ChangeRecord] = context["queue"].entries()
	return resolution["player_moved"] \
		and resolution["change"] != null \
		and world.player_position == Vector2i(1, 0) \
		and world.has_box_at(Vector2i(2, 0)) \
		and queue_entries.size() == 1 \
		and queue_entries[0].type == ChangeRecord.ChangeType.POSITION \
		and queue_entries[0].target_position == Vector2i(2, 0)


func _assert_gameplay_push_to_void(context: Dictionary) -> bool:
	var resolution: Dictionary = _apply_official_move(context, Vector2i.RIGHT)
	var world: CompiledWorld = context["world"]
	var queue_entries: Array[ChangeRecord] = context["queue"].entries()
	return resolution["player_moved"] \
		and resolution["change"] != null \
		and world.player_position == Vector2i(1, 0) \
		and not world.has_box_at(Vector2i(2, 0)) \
		and world.entity_positions.size() == 0 \
		and queue_entries.size() == 1 \
		and queue_entries[0].type == ChangeRecord.ChangeType.POSITION


func _assert_recompile_keeps_player(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var _resolution: Dictionary = _apply_official_move(context, Vector2i.RIGHT)
	var world: CompiledWorld = context["world"]
	return world.player_position == Vector2i(1, 0) and world.player_position != defaults.player_start


func _controller_handle_move(context: Dictionary, direction: Vector2i) -> Dictionary:
	var controller: GameController = context["controller"]
	var queue: ChangeQueue = context["queue"]
	var before_position: Vector2i = (context["world"] as CompiledWorld).player_position
	var before_queue_size: int = queue.size()
	controller.call("_handle_move", direction)
	var world: CompiledWorld = controller.get("_world")
	context["world"] = world
	return {
		"before_position": before_position,
		"before_queue_size": before_queue_size,
		"after_queue_size": queue.size(),
		"player_moved": world.player_position != before_position,
	}


func _assert_controller_walk_success(context: Dictionary) -> bool:
	var move_result: Dictionary = _controller_handle_move(context, Vector2i.RIGHT)
	var world: CompiledWorld = context["world"]
	return move_result["player_moved"] \
		and world.player_position == Vector2i(1, 0) \
		and move_result["before_queue_size"] == move_result["after_queue_size"] \
		and move_result["after_queue_size"] == 0


func _assert_controller_walk_block_wall(context: Dictionary) -> bool:
	var move_result: Dictionary = _controller_handle_move(context, Vector2i.RIGHT)
	var world: CompiledWorld = context["world"]
	return not move_result["player_moved"] \
		and world.player_position == Vector2i(0, 0) \
		and move_result["before_queue_size"] == move_result["after_queue_size"] \
		and move_result["after_queue_size"] == 0


func _assert_controller_walk_block_no_floor(context: Dictionary) -> bool:
	var move_result: Dictionary = _controller_handle_move(context, Vector2i.RIGHT)
	var world: CompiledWorld = context["world"]
	return not move_result["player_moved"] \
		and world.player_position == Vector2i(0, 0) \
		and move_result["before_queue_size"] == move_result["after_queue_size"] \
		and move_result["after_queue_size"] == 0


func _assert_controller_push_box_to_floor(context: Dictionary) -> bool:
	var move_result: Dictionary = _controller_handle_move(context, Vector2i.RIGHT)
	var world: CompiledWorld = context["world"]
	var queue_entries: Array[ChangeRecord] = context["queue"].entries()
	return move_result["player_moved"] \
		and world.player_position == Vector2i(1, 0) \
		and world.has_box_at(Vector2i(2, 0)) \
		and queue_entries.size() == 1 \
		and queue_entries[0].type == ChangeRecord.ChangeType.POSITION \
		and queue_entries[0].target_position == Vector2i(2, 0) \
		and world.entity_positions.size() == 1


func _assert_controller_push_box_to_void(context: Dictionary) -> bool:
	var move_result: Dictionary = _controller_handle_move(context, Vector2i.RIGHT)
	var world: CompiledWorld = context["world"]
	var queue_entries: Array[ChangeRecord] = context["queue"].entries()
	return move_result["player_moved"] \
		and world.player_position == Vector2i(1, 0) \
		and not world.has_box_at(Vector2i(2, 0)) \
		and world.entity_positions.size() == 0 \
		and world.ghost_entities.size() == 0 \
		and queue_entries.size() == 1 \
		and queue_entries[0].type == ChangeRecord.ChangeType.POSITION


func _assert_compile_pushes_out_oldest_unpinned(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = context["queue"]
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "c1"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "c2"))
	var result: CompileResult = _compiler.compile(defaults, queue, defaults.player_start)
	return result.pushed_out_changes.size() == 1 \
		and result.pushed_out_changes[0].debug_label == "c1" \
		and result.queue_entries.size() == 1 \
		and result.queue_entries[0].debug_label == "c2"


func _assert_controller_replay_locks_input_then_unlocks(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
	replay_controller.step_duration = 0.05
	_controller_handle_move(context, Vector2i.RIGHT)
	controller.request_empty_change()
	for i: int in range(20):
		if not controller.get("_input_locked"):
			break
		await process_frame
	var unlocked_after: bool = not controller.get("_input_locked")
	var replay_steps: Array[Dictionary] = controller.get("_last_replay_steps")
	return unlocked_after \
		and replay_steps.is_empty()


func _assert_replay_layer_transform_matches_board_view(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
	replay_controller.step_duration = 0.08
	replay_controller.step_pause = 0.04
	controller.request_move(Vector2i.LEFT)
	controller.request_move(Vector2i.LEFT)
	controller.request_move(Vector2i.LEFT)
	controller.request_empty_change()
	controller.request_empty_change()
	controller.request_empty_change()
	for i: int in range(120):
		var replay_layer: Node2D = replay_controller.get_node(replay_controller.replay_layer_path)
		var board_view: BoardView = replay_controller.get_node(replay_controller.board_view_path)
		if board_view.is_replay_presenting_subject(&"box_0"):
			return replay_layer.position.is_equal_approx(board_view.position) \
				and replay_layer.scale.is_equal_approx(board_view.scale)
		await process_frame
	return false


func _assert_replay_micro_steps_have_slower_cadence_config(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
	return replay_controller.step_duration >= 0.6 \
		and replay_controller.step_pause >= 0.18


func _assert_replay_uses_live_box_view_and_restores_state(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
	var board_view: BoardView = controller.get_node(controller.board_view_path)
	controller.request_move(Vector2i.LEFT)
	controller.request_move(Vector2i.LEFT)
	controller.request_move(Vector2i.LEFT)
	controller.request_empty_change()
	controller.request_empty_change()
	controller.request_empty_change()
	var saw_live_presenting: bool = false
	var box_during_playback: BoxView = null
	for i: int in range(600):
		if board_view.is_replay_presenting_subject(&"box_0"):
			saw_live_presenting = true
			box_during_playback = board_view.get_box_view(&"box_0")
			break
		await process_frame
	for i: int in range(600):
		if not controller.get("_input_locked"):
			break
		await process_frame
	var world_after: CompiledWorld = controller.get("_world")
	var box_after: BoxView = board_view.get_box_view(&"box_0")
	return saw_live_presenting \
		and box_during_playback == box_after \
		and replay_controller.used_live_box_views() \
		and not box_after.is_ghost() \
		and not box_after.is_conflict() \
		and box_after.visible \
		and box_after.position.is_equal_approx(board_view.board_to_pixel_center(world_after.entity_positions[&"box_0"]))


func _assert_board_view_sync_does_not_override_replay_presenting_subjects(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var board_view: BoardView = controller.get_node(controller.board_view_path)
	controller.request_move(Vector2i.LEFT)
	controller.request_move(Vector2i.LEFT)
	controller.request_move(Vector2i.LEFT)
	controller.request_empty_change()
	controller.request_empty_change()
	controller.request_empty_change()
	var position_before_forced_sync: Vector2 = Vector2.ZERO
	var position_after_forced_sync: Vector2 = Vector2.ZERO
	var captured: bool = false
	for i: int in range(600):
		if board_view.is_replay_presenting_subject(&"box_0"):
			var box_view: BoxView = board_view.get_box_view(&"box_0")
			position_before_forced_sync = box_view.position
			board_view.sync_world(controller.get("_world"))
			position_after_forced_sync = box_view.position
			captured = true
			break
		await process_frame
	for i: int in range(600):
		if not controller.get("_input_locked"):
			break
		await process_frame
	var world_after: CompiledWorld = controller.get("_world")
	var box_after: BoxView = board_view.get_box_view(&"box_0")
	return captured \
		and position_before_forced_sync.is_equal_approx(position_after_forced_sync) \
		and not board_view.is_replay_presenting_subject(&"box_0") \
		and box_after.position.is_equal_approx(board_view.board_to_pixel_center(world_after.entity_positions[&"box_0"]))


func _assert_level001_layout_matches_expected(context: Dictionary) -> bool:
	var runtime_data: LevelRuntimeData = context["runtime_data"]
	var expected_walls: Array[Vector3i] = [
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0), Vector3i(4, 0, 0), Vector3i(5, 0, 0),
		Vector3i(0, 1, 0),
		Vector3i(0, 2, 0), Vector3i(1, 2, 0), Vector3i(2, 2, 0), Vector3i(3, 2, 0), Vector3i(4, 2, 0), Vector3i(5, 2, 0),
	]
	return runtime_data.grid_size == Vector3i(6, 3, 1) \
		and runtime_data.player_start == Vector3i(5, 1, 0) \
		and runtime_data.exit_position == Vector3i(1, 1, 0) \
		and _sorted_vec3_array(runtime_data.boxes) == [Vector3i(3, 1, 0)] \
		and _sorted_vec3_array(runtime_data.walls) == _sorted_vec3_array(expected_walls)


func _assert_level001_two_left_moves_state_is_stable(context: Dictionary) -> bool:
	var first_move: Dictionary = _controller_handle_move(context, Vector2i.LEFT)
	var first_player_position: Vector2i = (context["world"] as CompiledWorld).player_position
	var first_queue_size: int = context["queue"].size()
	var second_move: Dictionary = _controller_handle_move(context, Vector2i.LEFT)
	var world: CompiledWorld = context["world"]
	var queue_entries: Array[ChangeRecord] = context["queue"].entries()
	var replay_steps: Array[Dictionary] = context["controller"].get("_last_replay_steps")

	return first_move["player_moved"] \
		and first_player_position == Vector2i(4, 1) \
		and first_queue_size == 0 \
		and second_move["player_moved"] \
		and world.player_position == Vector2i(3, 1) \
		and _sorted_vec2_array(world.entity_positions.values()) == [Vector2i(2, 1)] \
		and queue_entries.size() == 1 \
		and queue_entries[0].type == ChangeRecord.ChangeType.POSITION \
		and queue_entries[0].subject_id == &"box_0" \
		and queue_entries[0].target_position == Vector2i(2, 1) \
		and _count_ghost_entries(queue_entries, &"box_0", Vector2i(2, 1)) == 0 \
		and replay_steps.is_empty()


func _assert_debug_snapshot_has_real_values_not_placeholders(context: Dictionary) -> bool:
	_controller_handle_move(context, Vector2i.LEFT)
	_controller_handle_move(context, Vector2i.LEFT)
	var controller: GameController = context["controller"]
	var world: CompiledWorld = context["world"]
	var snapshot: String = _formatter.build_snapshot(
		world,
		context["queue"].entries(),
		String(controller.get("_last_recompile_reason")),
		controller.get("_last_replay_steps"),
		[],
		[],
		false,
		false,
		BuildInfo.display_text()
	)
	return not snapshot.contains("boxes=%s") \
		and snapshot.contains("boxes=") \
		and snapshot.contains("board_size=(6, 3)") \
		and snapshot.contains("queue=[") \
		and not snapshot.contains("queue=%s") \
		and snapshot.contains("(2, 1)") \
		and snapshot.contains("Position(box_0 -> (2, 1))")


func _assert_snapshot_includes_build_info(context: Dictionary) -> bool:
	var build_info_path: String = BuildInfo.BUILD_INFO_PATH
	var build_info_absolute_path: String = ProjectSettings.globalize_path(build_info_path)
	var original_exists: bool = FileAccess.file_exists(build_info_path)
	var original_text: String = ""
	if original_exists:
		var original_file: FileAccess = FileAccess.open(build_info_path, FileAccess.READ)
		if original_file != null:
			original_text = original_file.get_as_text()
	DirAccess.remove_absolute(build_info_absolute_path)
	var snapshot: String = _formatter.build_snapshot(
		context["world"],
		context["queue"].entries(),
		"harness",
		[],
		[],
		[],
		false,
		false,
		BuildInfo.display_text()
	)
	if original_exists:
		_ensure_generated_dir_exists(build_info_absolute_path)
		var restore_file: FileAccess = FileAccess.open(build_info_path, FileAccess.WRITE)
		if restore_file != null:
			restore_file.store_string(original_text)
	return snapshot.contains("build=") \
		and snapshot.contains("build=dev")


func _assert_overflow_with_only_empty_memory_has_no_replay(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = context["queue"]
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(2, 1), false, "older"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(1, 1), false, "newer"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_a"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_b"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_c"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_trigger"))
	var result: CompileResult = _compiler.compile(defaults, queue, defaults.player_start)
	var builder := ReplayPayloadBuilder.new()
	var replay_steps: Array[Dictionary] = builder.build_steps(defaults, result.queue_entries)
	var final_entries: Array[ChangeRecord] = result.queue_entries
	var all_empty: bool = final_entries.size() == 4
	for entry: ChangeRecord in final_entries:
		all_empty = all_empty and entry.type == ChangeRecord.ChangeType.EMPTY
	var snapshot: String = _formatter.build_snapshot(
		result.world,
		final_entries,
		"overflow_only_empty",
		replay_steps,
		[],
		[],
		false,
		false,
		BuildInfo.display_text()
	)
	return all_empty \
		and replay_steps.is_empty() \
		and snapshot.contains("replay=none") \
		and not snapshot.contains("box_0:")


func _assert_overflow_with_remaining_position_memory_replays_retained_steps(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = context["queue"]
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(2, 1), false, "older"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(1, 1), false, "remembered"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_a"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_b"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_trigger"))
	var result: CompileResult = _compiler.compile(defaults, queue, defaults.player_start)
	var final_entries: Array[ChangeRecord] = result.queue_entries
	var builder := ReplayPayloadBuilder.new()
	var replay_steps: Array[Dictionary] = builder.build_steps(defaults, final_entries)
	var has_position_memory: bool = not final_entries.is_empty() \
		and final_entries[0].type == ChangeRecord.ChangeType.POSITION \
		and final_entries[0].subject_id == &"box_0" \
		and final_entries[0].target_position == Vector2i(1, 1)
	var has_micro_step_a: bool = false
	var has_micro_step_b: bool = false
	var has_world_diff_direction: bool = false
	for step: Dictionary in replay_steps:
		if step.get("subject", &"") == &"box_0" \
			and step.get("from", Vector2i.ZERO) == Vector2i(3, 1) \
			and step.get("to", Vector2i.ZERO) == Vector2i(2, 1):
			has_micro_step_a = true
		if step.get("subject", &"") == &"box_0" \
			and step.get("from", Vector2i.ZERO) == Vector2i(2, 1) \
			and step.get("to", Vector2i.ZERO) == Vector2i(1, 1):
			has_micro_step_b = true
		if step.get("subject", &"") == &"box_0" \
			and step.get("from", Vector2i.ZERO) == Vector2i(1, 1) \
			and step.get("to", Vector2i.ZERO) == Vector2i(3, 1):
			has_world_diff_direction = true
	return has_position_memory \
		and replay_steps.size() == 2 \
		and has_micro_step_a \
		and has_micro_step_b \
		and not has_world_diff_direction


func _assert_retained_position_replay_expands_to_micro_steps(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = context["queue"]
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(2, 1), false, "older"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(1, 1), false, "remembered"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_a"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_b"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_trigger"))
	var result: CompileResult = _compiler.compile(defaults, queue, defaults.player_start)
	var builder := ReplayPayloadBuilder.new()
	var replay_steps: Array[Dictionary] = builder.build_steps(defaults, result.queue_entries)
	return replay_steps.size() == 2 \
		and replay_steps[0].get("subject", &"") == &"box_0" \
		and replay_steps[0].get("from", Vector2i.ZERO) == Vector2i(3, 1) \
		and replay_steps[0].get("to", Vector2i.ZERO) == Vector2i(2, 1) \
		and replay_steps[1].get("subject", &"") == &"box_0" \
		and replay_steps[1].get("from", Vector2i.ZERO) == Vector2i(2, 1) \
		and replay_steps[1].get("to", Vector2i.ZERO) == Vector2i(1, 1)


func _assert_replay_marks_player_conflict_on_intermediate_step(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = context["queue"]
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(2, 1), false, "older"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(1, 1), false, "remembered"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_a"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_b"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_trigger"))
	var result: CompileResult = _compiler.compile(defaults, queue, defaults.player_start)
	var builder := ReplayPayloadBuilder.new()
	var replay_steps: Array[Dictionary] = builder.build_steps(defaults, result.queue_entries, Vector2i(2, 1))
	return replay_steps.size() == 2 \
		and bool(replay_steps[0].get("is_conflict", false)) \
		and not bool(replay_steps[1].get("is_conflict", true))


func _assert_snapshot_reports_last_replay_display_info(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = context["queue"]
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(2, 1), false, "older"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(1, 1), false, "remembered"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_a"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_b"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_trigger"))
	var result: CompileResult = _compiler.compile(defaults, queue, defaults.player_start)
	var builder := ReplayPayloadBuilder.new()
	var replay_steps: Array[Dictionary] = builder.build_steps(defaults, result.queue_entries, Vector2i(2, 1))
	var snapshot: String = _formatter.build_snapshot(
		result.world,
		result.queue_entries,
		"snapshot_replay_display",
		replay_steps,
		replay_steps,
		[&"box_0"],
		true,
		true,
		BuildInfo.display_text()
	)
	return snapshot.contains("last_replay_display_steps=") \
		and snapshot.contains("box_0:(3, 1)->(2, 1) conflict=true") \
		and snapshot.contains("box_0:(2, 1)->(1, 1) conflict=false") \
		and snapshot.contains("last_replay_presenting_subjects=[&\"box_0\"]") \
		and snapshot.contains("last_replay_used_live_box_views=true") \
		and snapshot.contains("last_replay_completed=true") \
		and snapshot.contains("board_view_transform=") \
		and snapshot.contains("replay_layer_transform=")


func _assert_controller_empty_overflow_snapshot_matches_memory_semantics(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	controller.request_empty_change()
	controller.request_empty_change()
	controller.request_empty_change()
	controller.request_empty_change()
	controller.request_empty_change()
	for i: int in range(120):
		if not controller.get("_input_locked"):
			break
		await process_frame
	context["world"] = controller.get("_world")
	var queue_entries: Array[ChangeRecord] = context["queue"].entries()
	var replay_steps: Array[Dictionary] = controller.get("_last_replay_steps")
	var all_empty: bool = queue_entries.size() == 4
	for entry: ChangeRecord in queue_entries:
		all_empty = all_empty and entry.type == ChangeRecord.ChangeType.EMPTY
	var snapshot: String = _formatter.build_snapshot(
		context["world"],
		queue_entries,
		String(controller.get("_last_recompile_reason")),
		replay_steps,
		[],
		[],
		false,
		true,
		BuildInfo.display_text()
	)
	return all_empty \
		and replay_steps.is_empty() \
		and snapshot.contains("replay=none") \
		and not snapshot.contains("box_0:(1, 1)->(3, 1)")


func _assert_build_info_display_uses_generated_build_file_or_dev(_context: Dictionary) -> bool:
	var build_info_path: String = BuildInfo.BUILD_INFO_PATH
	var build_info_absolute_path: String = ProjectSettings.globalize_path(build_info_path)
	var original_exists: bool = FileAccess.file_exists(build_info_path)
	var original_text: String = ""
	if original_exists:
		var original_file: FileAccess = FileAccess.open(build_info_path, FileAccess.READ)
		if original_file != null:
			original_text = original_file.get_as_text()
	_ensure_generated_dir_exists(build_info_absolute_path)

	var fallback_text: String = ""
	var generated_text: String = ""
	var passed: bool = false
	DirAccess.remove_absolute(build_info_absolute_path)
	fallback_text = BuildInfo.display_text()

	var writer: FileAccess = FileAccess.open(build_info_path, FileAccess.WRITE)
	if writer != null:
		writer.store_string("{\"version\":\"9.9.9\",\"short_sha\":\"abc1234\",\"build_date\":\"2026-04-04T00:00:00Z\"}")
		writer.flush()
		writer = null
		generated_text = BuildInfo.display_text()
	passed = fallback_text == "dev" and generated_text == "v9.9.9 · abc1234"

	if original_exists:
		var restore_file: FileAccess = FileAccess.open(build_info_path, FileAccess.WRITE)
		if restore_file != null:
			restore_file.store_string(original_text)
	else:
		DirAccess.remove_absolute(build_info_absolute_path)
	return passed


func _ensure_generated_dir_exists(build_info_absolute_path: String) -> void:
	var slash_index: int = build_info_absolute_path.rfind("/")
	if slash_index == -1:
		return
	var dir_path: String = build_info_absolute_path.substr(0, slash_index)
	if DirAccess.dir_exists_absolute(dir_path):
		return
	DirAccess.make_dir_recursive_absolute(dir_path)


func _assert_compiler_does_not_duplicate_same_ghost_repeatedly(_context: Dictionary) -> bool:
	var defaults := WorldDefaults.new()
	defaults.board_size = Vector2i(3, 1)
	defaults.player_start = Vector2i(1, 0)
	defaults.exit_position = Vector2i(2, 0)
	defaults.memory_capacity = 8
	defaults.floor_cells = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	defaults.wall_positions = []
	defaults.default_entity_positions = {&"box_0": Vector2i(0, 0)}

	var queue := ChangeQueue.new()
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(1, 0), false, "conflict_with_player"))

	var result: CompileResult = _compiler.compile(defaults, queue, defaults.player_start)
	var final_entries: Array[ChangeRecord] = result.queue_entries
	var duplicate_ghost_count: int = _count_ghost_entries(final_entries, &"box_0", Vector2i(1, 0))

	return not result.reached_safety_limit \
		and result.generated_ghost_changes.size() == 1 \
		and duplicate_ghost_count == 1 \
		and final_entries.size() == 2 \
		and final_entries[0].type == ChangeRecord.ChangeType.POSITION \
		and final_entries[1].type == ChangeRecord.ChangeType.GHOST


func _assert_level001_three_left_moves_no_stale_ghost(context: Dictionary) -> bool:
	_controller_handle_move(context, Vector2i.LEFT)
	_controller_handle_move(context, Vector2i.LEFT)
	var third_move: Dictionary = _controller_handle_move(context, Vector2i.LEFT)
	var world: CompiledWorld = context["world"]
	var queue_entries: Array[ChangeRecord] = context["queue"].entries()
	var replay_steps: Array[Dictionary] = context["controller"].get("_last_replay_steps")
	var has_ghost_to_two_one: bool = _count_ghost_entries(queue_entries, &"box_0", Vector2i(2, 1)) > 0
	var position_count: int = 0
	for entry: ChangeRecord in queue_entries:
		if entry.type == ChangeRecord.ChangeType.POSITION:
			position_count += 1
	return third_move["player_moved"] \
		and world.player_position == Vector2i(2, 1) \
		and _sorted_vec2_array(world.entity_positions.values()) == [Vector2i(1, 1)] \
		and queue_entries.size() == 2 \
		and position_count == 2 \
		and not has_ghost_to_two_one \
		and replay_steps.is_empty()


func _assert_memory_queue_symbols_are_ascii_safe(_context: Dictionary) -> bool:
	var view := MemoryQueueView.new()
	var position_symbol: String = view._slot_symbol(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(0, 0)))
	var empty_symbol: String = view._slot_symbol(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO))
	var ghost_symbol: String = view._slot_symbol(ChangeRecord.new(ChangeRecord.ChangeType.GHOST, &"box_0", Vector2i(0, 0)))
	return position_symbol == "POS" and empty_symbol == "EMP" and ghost_symbol == "GST"


func _count_ghost_entries(entries: Array[ChangeRecord], subject_id: StringName, target: Vector2i) -> int:
	var count: int = 0
	for entry: ChangeRecord in entries:
		if entry.type == ChangeRecord.ChangeType.GHOST and entry.subject_id == subject_id and entry.target_position == target:
			count += 1
	return count


func _format_state(world: CompiledWorld, queue: ChangeQueue, runtime_data: LevelRuntimeData, defaults: WorldDefaults) -> String:
	return "player=%s boxes=%s walls=%s floors=%s runtime[player=%s exit=%s floors=%s walls=%s boxes=%s] defaults[player=%s exit=%s floors=%s walls=%s boxes=%s]" % [
		world.player_position,
		_sorted_vec2_array(world.entity_positions.values()),
		_sorted_vec2_array(world.wall_positions.keys()),
		_sorted_vec2_array(world.floor_cells.keys()),
		runtime_data.player_start,
		runtime_data.exit_position,
		_sorted_vec3_array(runtime_data.floor_cells),
		_sorted_vec3_array(runtime_data.walls),
		_sorted_vec3_array(runtime_data.boxes),
		defaults.player_start,
		defaults.exit_position,
		_sorted_vec2_array(defaults.floor_cells),
		_sorted_vec2_array(defaults.wall_positions),
		_sorted_vec2_array(defaults.default_entity_positions.values()),
	]


func _format_queue(entries: Array[ChangeRecord]) -> String:
	var labels: Array[String] = []
	for entry: ChangeRecord in entries:
		labels.append(entry.summary())
	return str(labels)


func _sorted_vec2_array(values: Array) -> Array[Vector2i]:
	var sorted: Array[Vector2i] = []
	for value in values:
		sorted.append(value)
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x == b.x:
			return a.y < b.y
		return a.x < b.x
	)
	return sorted


func _sorted_vec3_array(values: Array) -> Array[Vector3i]:
	var sorted: Array[Vector3i] = []
	for value in values:
		sorted.append(value)
	sorted.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.x != b.x:
			return a.x < b.x
		if a.y != b.y:
			return a.y < b.y
		return a.z < b.z
	)
	return sorted


func _build_cases() -> Array[Dictionary]:
	return [
		{
			"id": "chain_levelroot_runtime_data",
			"name": "chain_levelroot_runtime_data",
			"action": "build_runtime_data",
			"blueprint": {
				"board_size": Vector2i(4, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(3, 0),
				"floors": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(3, 0, 0)],
				"walls": [Vector3i(1, 0, 0)],
				"boxes": [Vector3i(0, 0, 0)],
			},
		},
		{
			"id": "chain_world_defaults_mapping",
			"name": "chain_world_defaults_mapping",
			"action": "WorldDefaults.from_runtime_data",
			"blueprint": {
				"board_size": Vector2i(4, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(3, 0),
				"floors": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(3, 0, 0)],
				"walls": [Vector3i(1, 0, 0)],
				"boxes": [Vector3i(0, 0, 0)],
			},
		},
		{
			"id": "chain_no_resolver_shortcut",
			"name": "chain_no_resolver_shortcut",
			"action": "level->runtime_data->defaults->compile",
			"blueprint": {
				"board_size": Vector2i(4, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(3, 0),
				"floors": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(3, 0, 0)],
				"walls": [Vector3i(1, 0, 0)],
				"boxes": [Vector3i(0, 0, 0)],
			},
		},
		{
			"id": "world_floor_wall_queries",
			"name": "world_floor_wall_queries",
			"action": "compiled_world.has_floor_at/has_wall_at",
			"blueprint": {
				"board_size": Vector2i(4, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(0, 0),
				"floors": [Vector3i(0, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0)],
				"walls": [Vector3i(2, 0, 0)],
				"boxes": [],
			},
		},
		{
			"id": "world_player_walkable_queries",
			"name": "world_player_walkable_queries",
			"action": "compiled_world.is_walkable_for_player",
			"blueprint": {
				"board_size": Vector2i(5, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(0, 0),
				"floors": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0)],
				"walls": [Vector3i(2, 0, 0)],
				"boxes": [Vector3i(3, 0, 0)],
			},
		},
		{
			"id": "world_box_landing_queries",
			"name": "world_box_landing_queries",
			"action": "compiled_world.is_blocked_for_box",
			"blueprint": {
				"board_size": Vector2i(5, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(0, 0),
				"floors": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0), Vector3i(4, 0, 0)],
				"walls": [Vector3i(2, 0, 0)],
				"boxes": [Vector3i(3, 0, 0)],
			},
		},
		{
			"id": "gameplay_walk_success",
			"name": "gameplay_walk_success",
			"action": "move RIGHT",
			"blueprint": {
				"board_size": Vector2i(3, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(2, 0),
				"floors": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0)],
				"walls": [],
				"boxes": [],
			},
		},
		{
			"id": "gameplay_walk_block_wall",
			"name": "gameplay_walk_block_wall",
			"action": "move RIGHT",
			"blueprint": {
				"board_size": Vector2i(3, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(2, 0),
				"floors": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0)],
				"walls": [Vector3i(1, 0, 0)],
				"boxes": [],
			},
		},
		{
			"id": "gameplay_walk_block_no_floor",
			"name": "gameplay_walk_block_no_floor",
			"action": "move RIGHT",
			"blueprint": {
				"board_size": Vector2i(3, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(2, 0),
				"floors": [Vector3i(0, 0, 0), Vector3i(2, 0, 0)],
				"walls": [],
				"boxes": [],
			},
		},
		{
			"id": "gameplay_push_box_to_floor",
			"name": "gameplay_push_box_to_floor",
			"action": "push RIGHT",
			"blueprint": {
				"board_size": Vector2i(3, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(2, 0),
				"floors": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0)],
				"walls": [],
				"boxes": [Vector3i(1, 0, 0)],
			},
		},
		{
			"id": "gameplay_push_box_to_void",
			"name": "gameplay_push_box_to_void",
			"action": "push RIGHT to void",
			"blueprint": {
				"board_size": Vector2i(3, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(1, 0),
				"floors": [Vector3i(0, 0, 0), Vector3i(1, 0, 0)],
				"walls": [],
				"boxes": [Vector3i(1, 0, 0)],
			},
		},
		{
			"id": "gameplay_recompile_keeps_player_position",
			"name": "gameplay_recompile_keeps_player_position",
			"action": "push RIGHT and recompile",
			"blueprint": {
				"board_size": Vector2i(3, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(2, 0),
				"floors": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0)],
				"walls": [],
				"boxes": [Vector3i(1, 0, 0)],
			},
		},
		{
			"id": "controller_walk_success",
			"name": "controller_walk_success",
			"action": "GameController move RIGHT",
			"blueprint": {
				"board_size": Vector2i(3, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(2, 0),
				"floors": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0)],
				"walls": [],
				"boxes": [],
			},
		},
		{
			"id": "controller_walk_block_wall",
			"name": "controller_walk_block_wall",
			"action": "GameController move RIGHT",
			"blueprint": {
				"board_size": Vector2i(3, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(2, 0),
				"floors": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0)],
				"walls": [Vector3i(1, 0, 0)],
				"boxes": [],
			},
		},
		{
			"id": "controller_walk_block_no_floor",
			"name": "controller_walk_block_no_floor",
			"action": "GameController move RIGHT",
			"blueprint": {
				"board_size": Vector2i(3, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(2, 0),
				"floors": [Vector3i(0, 0, 0), Vector3i(2, 0, 0)],
				"walls": [],
				"boxes": [],
			},
		},
		{
			"id": "controller_push_box_to_floor",
			"name": "controller_push_box_to_floor",
			"action": "GameController push RIGHT",
			"blueprint": {
				"board_size": Vector2i(3, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(2, 0),
				"floors": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0)],
				"walls": [],
				"boxes": [Vector3i(1, 0, 0)],
			},
		},
		{
			"id": "controller_push_box_to_void",
			"name": "controller_push_box_to_void",
			"action": "GameController push RIGHT to void",
			"blueprint": {
				"board_size": Vector2i(3, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(1, 0),
				"floors": [Vector3i(0, 0, 0), Vector3i(1, 0, 0)],
				"walls": [],
				"boxes": [Vector3i(1, 0, 0)],
			},
		},
		{
			"id": "compile_pushes_out_oldest_unpinned",
			"name": "compile_pushes_out_oldest_unpinned",
			"action": "queue normalize pushes oldest non-pinned record",
			"blueprint": {
				"board_size": Vector2i(3, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(2, 0),
				"memory_capacity": 1,
				"floors": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0)],
				"walls": [],
				"boxes": [],
			},
		},
		{
			"id": "controller_replay_locks_input_then_unlocks",
			"name": "controller_replay_locks_input_then_unlocks",
			"action": "trigger queue overflow replay and verify input lock lifecycle",
			"blueprint": {
				"board_size": Vector2i(5, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(4, 0),
				"memory_capacity": 1,
				"floors": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0), Vector3i(4, 0, 0)],
				"walls": [],
				"boxes": [Vector3i(1, 0, 0)],
			},
		},
		{
			"id": "replay_layer_transform_matches_board_view",
			"name": "replay_layer_transform_matches_board_view",
			"action": "trigger replay and assert ReplayLayer transform matches BoardView during playback",
			"context_mode": "controller_level001",
		},
		{
			"id": "replay_micro_steps_have_slower_cadence_config",
			"name": "replay_micro_steps_have_slower_cadence_config",
			"action": "assert replay cadence config uses slower per-step tween and pause",
			"context_mode": "controller_level001",
		},
		{
			"id": "replay_uses_live_box_view_and_restores_state",
			"name": "replay_uses_live_box_view_and_restores_state",
			"action": "replay uses BoardView live BoxView and restores ghost/conflict/visible state afterwards",
			"context_mode": "controller_level001",
		},
		{
			"id": "board_view_sync_does_not_override_replay_presenting_subjects",
			"name": "board_view_sync_does_not_override_replay_presenting_subjects",
			"action": "while replay presenting, sync_world does not overwrite replaying subject transforms",
			"context_mode": "controller_level001",
		},
		{
			"id": "level001_layout_matches_expected",
			"name": "level001_layout_matches_expected",
			"context_mode": "level001",
			"action": "load scenes/levels/Level001.tscn and verify runtime mapping",
		},
		{
			"id": "level001_two_left_moves_state_is_stable",
			"name": "level001_two_left_moves_state_is_stable",
			"context_mode": "controller_level001",
			"action": "GameController on Level001 then LEFT, LEFT",
		},
		{
			"id": "debug_snapshot_has_real_values_not_placeholders",
			"name": "debug_snapshot_has_real_values_not_placeholders",
			"context_mode": "controller_level001",
			"action": "format DebugSnapshot after deterministic Level001 moves",
		},
		{
			"id": "snapshot_includes_build_info",
			"name": "snapshot_includes_build_info",
			"action": "DebugSnapshot includes build=dev fallback",
			"blueprint": {
				"board_size": Vector2i(1, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(0, 0),
				"floors": [Vector3i(0, 0, 0)],
				"walls": [],
				"boxes": [],
			},
		},
		{
			"id": "overflow_with_only_empty_memory_has_no_replay",
			"name": "overflow_with_only_empty_memory_has_no_replay",
			"action": "overflow leaves only Empty memory so replay must be none",
			"blueprint": {
				"board_size": Vector2i(6, 3),
				"player_start": Vector2i(5, 1),
				"exit_position": Vector2i(1, 1),
				"memory_capacity": 4,
				"floors": [
					Vector3i(1, 1, 0),
					Vector3i(2, 1, 0),
					Vector3i(3, 1, 0),
					Vector3i(4, 1, 0),
					Vector3i(5, 1, 0),
				],
				"walls": [],
				"boxes": [Vector3i(3, 1, 0)],
			},
		},
		{
			"id": "overflow_with_remaining_position_memory_replays_retained_steps",
			"name": "overflow_with_remaining_position_memory_replays_retained_steps",
			"action": "overflow retains Position memory so replay must build from default state",
			"blueprint": {
				"board_size": Vector2i(6, 3),
				"player_start": Vector2i(5, 1),
				"exit_position": Vector2i(1, 1),
				"memory_capacity": 4,
				"floors": [
					Vector3i(1, 1, 0),
					Vector3i(2, 1, 0),
					Vector3i(3, 1, 0),
					Vector3i(4, 1, 0),
					Vector3i(5, 1, 0),
				],
				"walls": [],
				"boxes": [Vector3i(3, 1, 0)],
			},
		},
		{
			"id": "retained_position_replay_expands_to_micro_steps",
			"name": "retained_position_replay_expands_to_micro_steps",
			"action": "retained Position replay expands from default to Manhattan micro-steps",
			"blueprint": {
				"board_size": Vector2i(6, 3),
				"player_start": Vector2i(5, 1),
				"exit_position": Vector2i(1, 1),
				"memory_capacity": 4,
				"floors": [
					Vector3i(1, 1, 0),
					Vector3i(2, 1, 0),
					Vector3i(3, 1, 0),
					Vector3i(4, 1, 0),
					Vector3i(5, 1, 0),
				],
				"walls": [],
				"boxes": [Vector3i(3, 1, 0)],
			},
		},
		{
			"id": "replay_marks_player_conflict_on_intermediate_step",
			"name": "replay_marks_player_conflict_on_intermediate_step",
			"action": "replay step marks conflict when micro-step enters live player tile",
			"blueprint": {
				"board_size": Vector2i(6, 3),
				"player_start": Vector2i(5, 1),
				"exit_position": Vector2i(1, 1),
				"memory_capacity": 4,
				"floors": [
					Vector3i(1, 1, 0),
					Vector3i(2, 1, 0),
					Vector3i(3, 1, 0),
					Vector3i(4, 1, 0),
					Vector3i(5, 1, 0),
				],
				"walls": [],
				"boxes": [Vector3i(3, 1, 0)],
			},
		},
		{
			"id": "snapshot_reports_last_replay_display_info",
			"name": "snapshot_reports_last_replay_display_info",
			"action": "DebugSnapshot contains last replay display details with presenting subjects and completion flags",
			"blueprint": {
				"board_size": Vector2i(6, 3),
				"player_start": Vector2i(5, 1),
				"exit_position": Vector2i(1, 1),
				"memory_capacity": 4,
				"floors": [
					Vector3i(1, 1, 0),
					Vector3i(2, 1, 0),
					Vector3i(3, 1, 0),
					Vector3i(4, 1, 0),
					Vector3i(5, 1, 0),
				],
				"walls": [],
				"boxes": [Vector3i(3, 1, 0)],
			},
		},
		{
			"id": "controller_empty_overflow_snapshot_matches_memory_semantics",
			"name": "controller_empty_overflow_snapshot_matches_memory_semantics",
			"action": "Level001 overflow with Empty memory only must snapshot replay=none",
			"context_mode": "controller_level001",
		},
		{
			"id": "build_info_display_uses_generated_build_file_or_dev",
			"name": "build_info_display_uses_generated_build_file_or_dev",
			"action": "BuildInfo falls back to dev and uses generated short_sha when present",
			"blueprint": {
				"board_size": Vector2i(1, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(0, 0),
				"floors": [Vector3i(0, 0, 0)],
				"walls": [],
				"boxes": [],
			},
		},
		{
			"id": "compiler_does_not_duplicate_same_ghost_repeatedly",
			"name": "compiler_does_not_duplicate_same_ghost_repeatedly",
			"action": "compile conflicting Position change and assert ghost dedupe",
			"blueprint": {
				"board_size": Vector2i(2, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(1, 0),
				"floors": [Vector3i(0, 0, 0), Vector3i(1, 0, 0)],
				"walls": [],
				"boxes": [],
			},
		},
		{
			"id": "level001_three_left_moves_no_stale_ghost",
			"name": "level001_three_left_moves_no_stale_ghost",
			"context_mode": "controller_level001",
			"action": "GameController on Level001 then LEFT, LEFT, LEFT and assert no stale ghost",
		},
		{
			"id": "memory_queue_symbols_are_ascii_safe",
			"name": "memory_queue_symbols_are_ascii_safe",
			"action": "assert queue slot symbols are POS/EMP/GST",
			"blueprint": {
				"board_size": Vector2i(1, 1),
				"player_start": Vector2i(0, 0),
				"exit_position": Vector2i(0, 0),
				"floors": [Vector3i(0, 0, 0)],
				"walls": [],
				"boxes": [],
			},
		},
	]
