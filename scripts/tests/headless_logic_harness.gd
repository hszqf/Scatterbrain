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
		"live_input_push_does_not_ghostify":
			passed = _assert_live_input_push_does_not_ghostify(context)
		"remembered_rebuild_position_truncates_to_ghost_on_player_conflict":
			passed = _assert_remembered_rebuild_position_truncates_to_ghost_on_player_conflict(context)
		"input_and_rebuild_semantics_are_distinct_in_snapshot":
			passed = _assert_input_and_rebuild_semantics_are_distinct_in_snapshot(context)
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
		"replay_end_does_not_sync_old_world_before_final_world":
			passed = await _assert_replay_end_does_not_sync_old_world_before_final_world(context)
		"restore_live_subjects_does_not_override_final_position":
			passed = await _assert_restore_live_subjects_does_not_override_final_position(context)
		"level001_layout_matches_expected":
			passed = _assert_level001_layout_matches_expected(context)
		"level001_two_left_moves_state_is_stable":
			passed = _assert_level001_two_left_moves_state_is_stable(context)
		"debug_snapshot_has_real_values_not_placeholders":
			passed = _assert_debug_snapshot_has_real_values_not_placeholders(context)
		"snapshot_includes_build_info":
			passed = _assert_snapshot_includes_build_info(context)
		"snapshot_includes_input_chain_fields":
			passed = _assert_snapshot_includes_input_chain_fields(context)
		"move_input_populates_input_chain_debug_fields":
			passed = _assert_move_input_populates_input_chain_debug_fields(context)
		"empty_input_populates_input_chain_debug_fields":
			passed = await _assert_empty_input_populates_input_chain_debug_fields(context)
		"pushed_out_only_empty_skips_replay":
			passed = await _assert_pushed_out_only_empty_skips_replay(context)
		"no_pushed_out_replay_debug_state_resets":
			passed = await _assert_no_pushed_out_replay_debug_state_resets(context)
		"overflow_with_remaining_position_memory_replays_retained_steps":
			passed = _assert_overflow_with_remaining_position_memory_replays_retained_steps(context)
		"retained_position_replay_expands_to_micro_steps":
			passed = _assert_retained_position_replay_expands_to_micro_steps(context)
		"replay_marks_player_conflict_on_intermediate_step":
			passed = _assert_replay_marks_player_conflict_on_intermediate_step(context)
		"player_conflict_truncation_appends_ghost_change":
			passed = _assert_player_conflict_truncation_appends_ghost_change(context)
		"replay_path_truncates_at_first_conflict_step":
			passed = _assert_replay_path_truncates_at_first_conflict_step(context)
		"player_move_away_allows_remembered_path_to_finish_later":
			passed = _assert_player_move_away_allows_remembered_path_to_finish_later(context)
		"snapshot_reports_ghost_boxes_and_truncated_replay":
			passed = _assert_snapshot_reports_ghost_boxes_and_truncated_replay(context)
		"snapshot_reports_last_replay_display_info":
			passed = _assert_snapshot_reports_last_replay_display_info(context)
		"controller_empty_overflow_snapshot_matches_memory_semantics":
			passed = await _assert_controller_empty_overflow_snapshot_matches_memory_semantics(context)
		"build_info_display_uses_generated_build_file_or_dev":
			passed = _assert_build_info_display_uses_generated_build_file_or_dev(context)
		"generated_ghost_change_is_deduped":
			passed = _assert_generated_ghost_change_is_deduped(context)
		"empty_pushed_out_no_replay_even_if_ghost_was_appended":
			passed = await _assert_empty_pushed_out_no_replay_even_if_ghost_was_appended(context)
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
		and (resolution["change"] as ChangeRecord).source_kind == ChangeRecord.SourceKind.LIVE_INPUT \
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
		and (resolution["change"] as ChangeRecord).source_kind == ChangeRecord.SourceKind.LIVE_INPUT \
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


func _assert_live_input_push_does_not_ghostify(context: Dictionary) -> bool:
	_controller_handle_move(context, Vector2i.LEFT)
	var second_move: Dictionary = _controller_handle_move(context, Vector2i.LEFT)
	var world: CompiledWorld = context["world"]
	var queue_entries: Array[ChangeRecord] = context["queue"].entries()
	return second_move["player_moved"] \
		and world.player_position == Vector2i(3, 1) \
		and _sorted_vec2_array(world.entity_positions.values()) == [Vector2i(2, 1)] \
		and world.ghost_entities.is_empty() \
		and queue_entries.size() == 1 \
		and queue_entries[0].type == ChangeRecord.ChangeType.POSITION \
		and queue_entries[0].source_kind == ChangeRecord.SourceKind.REMEMBERED_REBUILD


func _assert_remembered_rebuild_position_truncates_to_ghost_on_player_conflict(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = ChangeQueue.new()
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.POSITION,
		&"box_0",
		Vector2i(1, 1),
		false,
		"remembered_conflict",
		ChangeRecord.SourceKind.REMEMBERED_REBUILD
	))
	var result: CompileResult = _compiler.compile(defaults, queue, Vector2i(2, 1))
	return _sorted_vec2_array(result.world.entity_positions.values()).is_empty() \
		and _sorted_vec2_array(result.world.ghost_entities.values()) == [Vector2i(2, 1)]


func _assert_input_and_rebuild_semantics_are_distinct_in_snapshot(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = ChangeQueue.new()
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.POSITION,
		&"box_0",
		Vector2i(2, 1),
		false,
		"live_source",
		ChangeRecord.SourceKind.LIVE_INPUT
	))
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.POSITION,
		&"box_0",
		Vector2i(1, 1),
		false,
		"remembered_source",
		ChangeRecord.SourceKind.REMEMBERED_REBUILD
	))
	var result: CompileResult = _compiler.compile(defaults, queue, Vector2i(2, 1))
	var snapshot: String = _formatter.build_snapshot(
		result.world,
		result.queue_entries,
		"semantic_snapshot",
		[],
		[],
		[],
		false,
		false,
		BuildInfo.display_text(),
		"board_ok",
		"replay_ok",
		"player_conflict",
		"test_source",
		"test_intent",
		Vector2i.ZERO,
		true,
		"Position[LIVE_INPUT](box_0 -> (2, 1))",
		"Position[LIVE_INPUT](box_0 -> (2, 1))",
		["Position[LIVE_INPUT](box_0 -> (2, 1))"],
		["Ghost[AUTO_GHOST](box_0 -> (2, 1))"],
		["Position[REMEMBERED_REBUILD](box_0 -> (2, 1))", "Position[REMEMBERED_REBUILD](box_0 -> (1, 1))", "Ghost[AUTO_GHOST](box_0 -> (2, 1))"],
		false,
		"no_pushed_out"
	)
	return snapshot.contains("queue=[\"Position[REMEMBERED_REBUILD](box_0 -> (2, 1))\"") \
		and snapshot.contains("pushed_out_changes=[\"Position[LIVE_INPUT](box_0 -> (2, 1))\"]") \
		and snapshot.contains("generated_ghost_changes=[\"Ghost[AUTO_GHOST](box_0 -> (2, 1))\"]") \
		and snapshot.contains("queue_after_compile=[\"Position[REMEMBERED_REBUILD](box_0 -> (2, 1))\"")


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
	var final_box_pos: Vector2i = world_after.get_entity_position(&"box_0")
	return saw_live_presenting \
		and box_during_playback == box_after \
		and replay_controller.used_live_box_views() \
		and box_after.is_ghost() \
		and not box_after.is_conflict() \
		and box_after.visible \
		and final_box_pos == Vector2i(2, 1) \
		and world_after.ghost_entities.has(&"box_0") \
		and box_after.position.is_equal_approx(board_view.board_to_pixel_center(final_box_pos))


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
	var final_box_pos: Vector2i = world_after.get_entity_position(&"box_0")
	return captured \
		and position_before_forced_sync.is_equal_approx(position_after_forced_sync) \
		and not board_view.is_replay_presenting_subject(&"box_0") \
		and final_box_pos == Vector2i(2, 1) \
		and world_after.ghost_entities.has(&"box_0") \
		and box_after.position.is_equal_approx(board_view.board_to_pixel_center(final_box_pos))


func _assert_replay_end_does_not_sync_old_world_before_final_world(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var board_view: BoardView = controller.get_node(controller.board_view_path)
	controller.request_move(Vector2i.LEFT)
	controller.request_move(Vector2i.LEFT)
	controller.request_move(Vector2i.LEFT)
	controller.request_empty_change()
	controller.request_empty_change()
	controller.request_empty_change()
	for i: int in range(600):
		if not controller.get("_input_locked"):
			break
		await process_frame
	var world_after: CompiledWorld = controller.get("_world")
	var box_after: BoxView = board_view.get_box_view(&"box_0")
	var final_box_pos: Vector2i = world_after.get_entity_position(&"box_0")
	var script_text: String = FileAccess.get_file_as_string("res://scripts/game/board_view.gd")
	var has_old_world_sync_in_end: bool = script_text.contains("func end_replay_presentation() -> void:\n\t_replay_presenting_subjects.clear()\n\tif _world != null:\n\t\tsync_world(_world)")
	return not has_old_world_sync_in_end \
		and not board_view.is_replay_presenting_subject(&"box_0") \
		and world_after.ghost_entities.has(&"box_0") \
		and final_box_pos == Vector2i(2, 1) \
		and box_after.position.is_equal_approx(board_view.board_to_pixel_center(final_box_pos))


func _assert_restore_live_subjects_does_not_override_final_position(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
	var board_view: BoardView = controller.get_node(controller.board_view_path)
	var box_view: BoxView = board_view.get_box_view(&"box_0")
	var expected_position: Vector2 = board_view.board_to_pixel_center(Vector2i(1, 1))
	box_view.set_board_position(Vector2i(1, 1), board_view.cell_size)
	box_view.set_is_ghost(true)
	box_view.set_is_conflict(true)
	box_view.visible = false
	var subject_ids: Array[StringName] = [&"box_0"]
	replay_controller.call("_restore_live_subjects", subject_ids)
	return box_view.position.is_equal_approx(expected_position) \
		and not box_view.is_ghost() \
		and not box_view.is_conflict() \
		and box_view.visible


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
		and snapshot.contains("Position[REMEMBERED_REBUILD](box_0 -> (2, 1))")


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


func _assert_snapshot_includes_input_chain_fields(context: Dictionary) -> bool:
	var snapshot: String = _formatter.build_snapshot(
		context["world"],
		context["queue"].entries(),
		"input_chain_probe",
		[],
		[],
		[],
		false,
		false,
		BuildInfo.display_text()
	)
	return snapshot.contains("input_source=") \
		and snapshot.contains("input_intent=") \
		and snapshot.contains("input_direction=") \
		and snapshot.contains("move_player_moved=") \
		and snapshot.contains("move_generated_change=") \
		and snapshot.contains("appended_change=") \
		and snapshot.contains("pushed_out_changes=") \
		and snapshot.contains("generated_ghost_changes=") \
		and snapshot.contains("queue_after_compile=") \
		and snapshot.contains("replay_gate_allowed=") \
		and snapshot.contains("replay_gate_reason=")


func _assert_move_input_populates_input_chain_debug_fields(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	controller.on_move_left_pressed()
	controller.on_move_left_pressed()
	context["world"] = controller.get("_world")
	var input_source: String = String(controller.get("_last_input_source"))
	var input_intent: String = String(controller.get("_last_input_intent"))
	var input_direction: Vector2i = controller.get("_last_input_direction")
	var move_player_moved: bool = bool(controller.get("_last_move_player_moved"))
	var move_generated_change: String = String(controller.get("_last_move_generated_change"))
	return input_source == "button_left" \
		and input_intent == "move_left" \
		and input_direction == Vector2i.LEFT \
		and move_player_moved \
		and move_generated_change.begins_with("Position[LIVE_INPUT](")


func _assert_empty_input_populates_input_chain_debug_fields(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	controller.on_meditate_pressed()
	for i: int in range(60):
		if not controller.get("_input_locked"):
			break
		await process_frame
	context["world"] = controller.get("_world")
	var input_intent: String = String(controller.get("_last_input_intent"))
	var appended_change: String = String(controller.get("_last_appended_change_summary"))
	var queue_after_compile: Array[String] = controller.get("_last_queue_after_compile_summaries")
	var has_empty_queue_entry: bool = queue_after_compile.size() > 0 and queue_after_compile[queue_after_compile.size() - 1] == "Empty[LIVE_INPUT]"
	return input_intent == "empty" \
		and appended_change == "Empty[LIVE_INPUT]" \
		and has_empty_queue_entry \
		and bool(controller.get("_last_replay_gate_allowed")) == false


func _assert_pushed_out_only_empty_skips_replay(context: Dictionary) -> bool:
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
	var replay_steps: Array[Dictionary] = controller.get("_last_replay_steps")
	var stop_reason: String = String(controller.get("_last_replay_stop_reason"))
	var snapshot: String = _formatter.build_snapshot(
		controller.get("_world"),
		context["queue"].entries(),
		String(controller.get("_last_recompile_reason")),
		replay_steps,
		controller.get("_last_replay_display_steps"),
		controller.get("_last_replay_presenting_subjects"),
		bool(controller.get("_last_replay_used_live_box_views")),
		bool(controller.get("_last_replay_completed")),
		BuildInfo.display_text(),
		"board_ok",
		"replay_ok",
		stop_reason
	)
	return replay_steps.is_empty() \
		and bool(controller.get("_last_replay_completed")) == false \
		and stop_reason == "pushed_out_only_empty" \
		and snapshot.contains("replay=none") \
		and snapshot.contains("last_replay_stop_reason=pushed_out_only_empty")


func _assert_no_pushed_out_replay_debug_state_resets(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	controller.on_move_left_pressed()
	controller.on_move_left_pressed()
	for i: int in range(120):
		if not controller.get("_input_locked"):
			break
		await process_frame
	context["world"] = controller.get("_world")

	var pushed_out: Array[String] = controller.get("_last_pushed_out_summaries")
	var replay_gate_allowed: bool = bool(controller.get("_last_replay_gate_allowed"))
	var replay_gate_reason: String = String(controller.get("_last_replay_gate_reason"))
	var replay_steps: Array[Dictionary] = controller.get("_last_replay_steps")
	var replay_display_steps: Array[Dictionary] = controller.get("_last_replay_display_steps")
	var replay_subjects: Array[StringName] = controller.get("_last_replay_presenting_subjects")
	var replay_used_live: bool = bool(controller.get("_last_replay_used_live_box_views"))
	var replay_completed: bool = bool(controller.get("_last_replay_completed"))
	var stop_reason: String = String(controller.get("_last_replay_stop_reason"))
	var replay_layer_transform: String = String(controller.call("_snapshot_replay_layer_transform"))
	var snapshot: String = _formatter.build_snapshot(
		context["world"],
		context["queue"].entries(),
		String(controller.get("_last_recompile_reason")),
		replay_steps,
		replay_display_steps,
		replay_subjects,
		replay_used_live,
		replay_completed,
		BuildInfo.display_text(),
		"board_ok",
		replay_layer_transform,
		stop_reason,
		String(controller.get("_last_input_source")),
		String(controller.get("_last_input_intent")),
		controller.get("_last_input_direction"),
		bool(controller.get("_last_move_player_moved")),
		String(controller.get("_last_move_generated_change")),
		String(controller.get("_last_appended_change_summary")),
		pushed_out,
		controller.get("_last_generated_ghost_summaries"),
		controller.get("_last_queue_after_compile_summaries"),
		replay_gate_allowed,
		replay_gate_reason
	)
	return pushed_out.is_empty() \
		and not replay_gate_allowed \
		and replay_gate_reason == "no_pushed_out" \
		and replay_steps.is_empty() \
		and replay_display_steps.is_empty() \
		and replay_subjects.is_empty() \
		and replay_used_live == false \
		and replay_completed == false \
		and stop_reason == "no_pushed_out" \
		and snapshot.contains("replay=none") \
		and snapshot.contains("last_replay_display_steps=[]") \
		and snapshot.contains("last_replay_completed=false") \
		and snapshot.contains("last_replay_stop_reason=no_pushed_out") \
		and snapshot.contains("replay_layer_transform=inactive")


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


func _build_remembered_conflict_queue() -> ChangeQueue:
	var queue: ChangeQueue = ChangeQueue.new()
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(1, 1), false, "remembered"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_a"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_b"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_c"))
	return queue


func _assert_replay_marks_player_conflict_on_intermediate_step(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = _build_remembered_conflict_queue()
	var result: CompileResult = _compiler.compile(defaults, queue, Vector2i(2, 1))
	var builder := ReplayPayloadBuilder.new()
	var replay_steps: Array[Dictionary] = builder.build_steps(defaults, result.queue_entries, Vector2i(2, 1))
	return replay_steps.size() == 1 		and bool(replay_steps[0].get("is_conflict", false))


func _assert_player_conflict_truncation_appends_ghost_change(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = _build_remembered_conflict_queue()
	var result: CompileResult = _compiler.compile(defaults, queue, Vector2i(2, 1))
	var has_position_memory: bool = result.queue_entries.size() >= 4 		and result.queue_entries[0].type == ChangeRecord.ChangeType.POSITION 		and result.queue_entries[0].subject_id == &"box_0" 		and result.queue_entries[0].target_position == Vector2i(1, 1)
	var ghost_count: int = _count_ghost_entries(result.queue_entries, &"box_0", Vector2i(2, 1))
	return has_position_memory 		and not result.world.entity_positions.has(&"box_0") 		and result.world.ghost_entities.get(&"box_0", Vector2i(-1, -1)) == Vector2i(2, 1) 		and ghost_count == 1 		and result.generated_ghost_changes.size() == 1 		and result.generated_ghost_changes[0].type == ChangeRecord.ChangeType.GHOST 		and result.generated_ghost_changes[0].subject_id == &"box_0" 		and result.generated_ghost_changes[0].target_position == Vector2i(2, 1)


func _assert_replay_path_truncates_at_first_conflict_step(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = _build_remembered_conflict_queue()
	var result: CompileResult = _compiler.compile(defaults, queue, Vector2i(2, 1))
	var builder := ReplayPayloadBuilder.new()
	var replay_steps: Array[Dictionary] = builder.build_steps(defaults, result.queue_entries, Vector2i(2, 1))
	return replay_steps.size() == 1 		and replay_steps[0].get("subject", &"") == &"box_0" 		and replay_steps[0].get("from", Vector2i.ZERO) == Vector2i(3, 1) 		and replay_steps[0].get("to", Vector2i.ZERO) == Vector2i(2, 1) 		and bool(replay_steps[0].get("is_conflict", false))


func _assert_player_move_away_allows_remembered_path_to_finish_later(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = _build_remembered_conflict_queue()
	var blocked_result: CompileResult = _compiler.compile(defaults, queue, Vector2i(2, 1))
	var queue_after_blocked: ChangeQueue = ChangeQueue.new()
	for entry: ChangeRecord in blocked_result.queue_entries:
		queue_after_blocked.append(entry)
	var unblocked_result: CompileResult = _compiler.compile(defaults, queue_after_blocked, Vector2i(5, 1))
	var unblocked_ghost_count: int = _count_ghost_entries(unblocked_result.queue_entries, &"box_0", Vector2i(2, 1))
	return not blocked_result.reached_safety_limit 		and not unblocked_result.reached_safety_limit 		and blocked_result.world.ghost_entities.get(&"box_0", Vector2i(-1, -1)) == Vector2i(2, 1) 		and unblocked_result.queue_entries[0].type == ChangeRecord.ChangeType.POSITION 		and unblocked_result.queue_entries[0].target_position == Vector2i(1, 1) 		and unblocked_ghost_count <= 1


func _assert_snapshot_reports_ghost_boxes_and_truncated_replay(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = _build_remembered_conflict_queue()
	var result: CompileResult = _compiler.compile(defaults, queue, Vector2i(2, 1))
	var builder := ReplayPayloadBuilder.new()
	var replay_steps: Array[Dictionary] = builder.build_steps(defaults, result.queue_entries, Vector2i(2, 1))
	var snapshot: String = _formatter.build_snapshot(
		result.world,
		result.queue_entries,
		"snapshot_ghost_boxes",
		replay_steps,
		replay_steps,
		[&"box_0"],
		true,
		true,
		BuildInfo.display_text(),
		"board_ok",
		"replay_ok",
		"player_conflict"
	)
	return snapshot.contains("boxes=[]") \
		and snapshot.contains("ghost_boxes=[(2, 1)]") \
		and snapshot.contains("replay=[\"box_0:(3, 1)->(2, 1)\"]") \
		and snapshot.contains("last_replay_display_steps=[\"box_0:(3, 1)->(2, 1) conflict=true\"]") \
		and snapshot.contains("last_replay_stop_reason=player_conflict")


func _assert_snapshot_reports_last_replay_display_info(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = _build_remembered_conflict_queue()
	var result: CompileResult = _compiler.compile(defaults, queue, Vector2i(2, 1))
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
		BuildInfo.display_text(),
		"board_ok",
		"replay_ok",
		"player_conflict"
	)
	return snapshot.contains("last_replay_display_steps=") \
		and snapshot.contains("box_0:(3, 1)->(2, 1) conflict=true") \
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




func _assert_empty_pushed_out_no_replay_even_if_ghost_was_appended(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var queue: ChangeQueue = context["queue"]
	queue.clear()
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e1"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e2"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e3"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(1, 1), false, "remembered"))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "trigger"))
	var world: CompiledWorld = controller.get("_world")
	world.player_position = Vector2i(2, 1)
	controller.call("_recompile_world", "test_empty_pushout_ghost")
	for i: int in range(120):
		if not controller.get("_input_locked"):
			break
		await process_frame
	var replay_steps: Array[Dictionary] = controller.get("_last_replay_steps")
	var replay_display_steps: Array[Dictionary] = controller.get("_last_replay_display_steps")
	var stop_reason: String = String(controller.get("_last_replay_stop_reason"))
	var final_world: CompiledWorld = controller.get("_world")
	var final_queue_entries: Array[ChangeRecord] = queue.entries()
	var snapshot: String = _formatter.build_snapshot(
		final_world,
		final_queue_entries,
		String(controller.get("_last_recompile_reason")),
		replay_steps,
		replay_display_steps,
		controller.get("_last_replay_presenting_subjects"),
		bool(controller.get("_last_replay_used_live_box_views")),
		bool(controller.get("_last_replay_completed")),
		BuildInfo.display_text(),
		"board_ok",
		"replay_ok",
		stop_reason
	)
	return replay_steps.is_empty() \
		and snapshot.contains("replay=none") \
		and _count_ghost_entries(final_queue_entries, &"box_0", Vector2i(2, 1)) == 1


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


func _assert_generated_ghost_change_is_deduped(_context: Dictionary) -> bool:
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

	var first_result: CompileResult = _compiler.compile(defaults, queue, defaults.player_start)
	var queue_after_first: ChangeQueue = ChangeQueue.new()
	for entry: ChangeRecord in first_result.queue_entries:
		queue_after_first.append(entry)
	var second_result: CompileResult = _compiler.compile(defaults, queue_after_first, defaults.player_start)
	var first_ghost_count: int = _count_ghost_entries(first_result.queue_entries, &"box_0", Vector2i(1, 0))
	var second_ghost_count: int = _count_ghost_entries(second_result.queue_entries, &"box_0", Vector2i(1, 0))
	return not first_result.reached_safety_limit \
		and not second_result.reached_safety_limit \
		and first_result.generated_ghost_changes.size() == 1 \
		and second_result.generated_ghost_changes.is_empty() \
		and first_ghost_count == 1 \
		and second_ghost_count == 1 \
		and second_result.world.ghost_entities.get(&"box_0", Vector2i(-1, -1)) == Vector2i(1, 0)


func _assert_level001_three_left_moves_no_stale_ghost(context: Dictionary) -> bool:
	_controller_handle_move(context, Vector2i.LEFT)
	_controller_handle_move(context, Vector2i.LEFT)
	var third_move: Dictionary = _controller_handle_move(context, Vector2i.LEFT)
	var world: CompiledWorld = context["world"]
	var queue_entries: Array[ChangeRecord] = context["queue"].entries()
	var replay_steps: Array[Dictionary] = context["controller"].get("_last_replay_steps")
	var ghost_to_two_one_count: int = _count_ghost_entries(queue_entries, &"box_0", Vector2i(2, 1))
	var position_count: int = 0
	for entry: ChangeRecord in queue_entries:
		if entry.type == ChangeRecord.ChangeType.POSITION:
			position_count += 1
	return third_move["player_moved"] \
		and world.player_position == Vector2i(2, 1) \
		and world.ghost_entities.get(&"box_0", Vector2i(-1, -1)) == Vector2i(2, 1) \
		and not world.entity_positions.has(&"box_0") \
		and queue_entries.size() == 3 \
		and position_count == 2 \
		and ghost_to_two_one_count == 1 \
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
			"id": "live_input_push_does_not_ghostify",
			"name": "live_input_push_does_not_ghostify",
			"action": "Level001 left push from live input keeps solid box and no ghost",
			"context_mode": "controller_level001",
		},
		{
			"id": "remembered_rebuild_position_truncates_to_ghost_on_player_conflict",
			"name": "remembered_rebuild_position_truncates_to_ghost_on_player_conflict",
			"action": "remembered Position rebuild truncates to ghost when path hits player",
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
			"id": "input_and_rebuild_semantics_are_distinct_in_snapshot",
			"name": "input_and_rebuild_semantics_are_distinct_in_snapshot",
			"action": "snapshot distinguishes LIVE_INPUT, REMEMBERED_REBUILD and AUTO_GHOST summaries",
			"blueprint": {
				"board_size": Vector2i(6, 3),
				"player_start": Vector2i(5, 1),
				"exit_position": Vector2i(1, 1),
				"memory_capacity": 6,
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
			"id": "replay_end_does_not_sync_old_world_before_final_world",
			"name": "replay_end_does_not_sync_old_world_before_final_world",
			"action": "replay end clears presenting state without syncing stale BoardView world, then final world remains authoritative",
			"context_mode": "controller_level001",
		},
		{
			"id": "restore_live_subjects_does_not_override_final_position",
			"name": "restore_live_subjects_does_not_override_final_position",
			"action": "restore_live_subjects only resets style and visibility without overriding BoxView position",
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
			"id": "snapshot_includes_input_chain_fields",
			"name": "snapshot_includes_input_chain_fields",
			"action": "DebugSnapshot includes input->append->compile chain fields with stable keys",
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
			"id": "move_input_populates_input_chain_debug_fields",
			"name": "move_input_populates_input_chain_debug_fields",
			"action": "button move input populates source/intent/direction + move resolver debug fields",
			"context_mode": "controller_level001",
		},
		{
			"id": "empty_input_populates_input_chain_debug_fields",
			"name": "empty_input_populates_input_chain_debug_fields",
			"action": "button meditate input records empty intent and appended Empty change",
			"context_mode": "controller_level001",
		},
		{
			"id": "pushed_out_only_empty_skips_replay",
			"name": "pushed_out_only_empty_skips_replay",
			"action": "controller overflow with only Empty pushed_out must keep replay=none",
			"context_mode": "controller_level001",
		},
		{
			"id": "no_pushed_out_replay_debug_state_resets",
			"name": "no_pushed_out_replay_debug_state_resets",
			"action": "no pushed_out compile resets replay debug latches and snapshots replay layer as inactive",
			"context_mode": "controller_level001",
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
			"id": "player_conflict_truncation_appends_ghost_change",
			"name": "player_conflict_truncation_appends_ghost_change",
			"action": "compile Position memory from default and truncate to ghost at first player conflict",
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
			"id": "replay_path_truncates_at_first_conflict_step",
			"name": "replay_path_truncates_at_first_conflict_step",
			"action": "replay path stops at first step that conflicts with live player",
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
			"id": "player_move_away_allows_remembered_path_to_finish_later",
			"name": "player_move_away_allows_remembered_path_to_finish_later",
			"action": "same Position memory recompile finishes later after player leaves conflict tile",
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
			"id": "snapshot_reports_ghost_boxes_and_truncated_replay",
			"name": "snapshot_reports_ghost_boxes_and_truncated_replay",
			"action": "DebugSnapshot includes ghost_boxes and one-step truncated replay details",
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
			"id": "generated_ghost_change_is_deduped",
			"name": "generated_ghost_change_is_deduped",
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
			"id": "empty_pushed_out_no_replay_even_if_ghost_was_appended",
			"name": "empty_pushed_out_no_replay_even_if_ghost_was_appended",
			"action": "controller replay gate stays none when pushed_out is Empty even if compile appends Ghost",
			"context_mode": "controller_blueprint",
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
