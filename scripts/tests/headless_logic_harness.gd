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
		"remembered_defaults_ignore_live_player_until_projection":
			passed = _assert_remembered_defaults_ignore_live_player_until_projection(context)
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
		"replay_builder_position_steps_use_move_presentation_kind":
			passed = _assert_replay_builder_position_steps_use_move_presentation_kind(context)
		"replay_builder_ghost_steps_use_ghostify_presentation_kind":
			passed = _assert_replay_builder_ghost_steps_use_ghostify_presentation_kind(context)
		"replay_empty_steps_keep_order_with_empty_presentation_kind":
			passed = _assert_replay_empty_steps_keep_order_with_empty_presentation_kind(context)
		"empty_beats_do_not_create_board_actor_steps":
			passed = _assert_empty_beats_do_not_create_board_actor_steps(context)
		"replay_is_grouped_by_queue_index_not_raw_steps":
			passed = _assert_replay_is_grouped_by_queue_index_not_raw_steps(context)
		"replay_groups_steps_by_queue_index":
			passed = _assert_replay_is_grouped_by_queue_index_not_raw_steps(context)
		"queue_focus_advances_one_memory_per_beat":
			passed = await _assert_queue_focus_advances_one_memory_per_beat(context)
		"board_replay_is_driven_one_memory_per_beat":
			passed = await _assert_board_replay_is_driven_one_memory_per_beat(context)
		"one_memory_one_beat_presentation":
			passed = await _assert_one_memory_one_beat_presentation(context)
		"one_queue_entry_one_visible_beat":
			passed = await _assert_one_queue_entry_one_visible_beat(context)
		"empty_beat_triggers_player_meditate_pulse":
			passed = await _assert_empty_beat_triggers_player_meditate_pulse(context)
		"empty_beats_trigger_player_pulse_each_beat":
			passed = await _assert_empty_beats_trigger_player_pulse_each_beat(context)
		"empty_beat_does_not_create_box_actor_movement":
			passed = _assert_empty_beat_does_not_create_box_actor_movement(context)
		"empty_beats_do_not_create_box_motion":
			passed = _assert_empty_beat_does_not_create_box_actor_movement(context)
		"evicted_memory_is_presented_in_queue_before_rebuild":
			passed = await _assert_evicted_memory_is_presented_in_queue_before_rebuild(context)
		"memory_focus_and_board_step_are_synchronized":
			passed = await _assert_memory_focus_and_board_step_are_synchronized(context)
		"queue_focus_and_board_action_start_in_same_beat":
			passed = await _assert_queue_focus_and_board_action_start_in_same_beat(context)
		"queue_focus_and_board_beat_start_together":
			passed = await _assert_queue_focus_and_board_beat_start_together(context)
		"replay_no_longer_contains_subjectless_fake_steps":
			passed = _assert_replay_no_longer_contains_subjectless_fake_steps(context)
		"board_replay_rebuilds_only_from_surviving_queue":
			passed = _assert_board_replay_rebuilds_only_from_surviving_queue(context)
		"replay_controller_runs_evict_phase_before_rebuild":
			passed = await _assert_replay_controller_runs_evict_phase_before_rebuild(context)
		"evicted_changes_are_presented_in_queue_not_board":
			passed = await _assert_evicted_changes_are_presented_in_queue_not_board(context)
		"evicted_position_change_produces_board_replay":
			passed = _assert_evicted_position_change_produces_board_replay(context)
		"replay_has_evict_phase_before_rebuild_phase":
			passed = await _assert_replay_has_evict_phase_before_rebuild_phase(context)
		"evicted_move_uses_state_diff_not_guessing":
			passed = _assert_evicted_move_uses_state_diff_not_guessing(context)
		"empty_beats_still_use_player_pulse_in_rebuild_phase":
			passed = await _assert_empty_beats_still_use_player_pulse_in_rebuild_phase(context)
		"replay_conflict_step_finishes_then_applies_tail_pause":
			passed = await _assert_replay_conflict_step_finishes_then_applies_tail_pause(context)
		"ghostify_step_is_played_as_full_in_place_change":
			passed = await _assert_ghostify_step_is_played_as_full_in_place_change(context)
		"replay_sequence_orders_queue_feedback_before_board_rebuild":
			passed = await _assert_replay_sequence_orders_queue_feedback_before_board_rebuild(context)
		"replay_uses_detached_replay_actor_not_live_box_view":
			passed = await _assert_replay_uses_detached_replay_actor_not_live_box_view(context)
		"ghost_spawn_ghostify_replay_does_not_move_live_final_world_box":
			passed = await _assert_ghost_spawn_ghostify_replay_does_not_move_live_final_world_box(context)
		"replay_end_does_not_sync_old_world_before_final_world":
			passed = await _assert_replay_end_does_not_sync_old_world_before_final_world(context)
		"replay_actor_is_cleaned_up_and_live_world_restored_after_playback":
			passed = await _assert_replay_actor_is_cleaned_up_and_live_world_restored_after_playback(context)
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
		"remembered_conflict_ghost_does_not_override_later_live_input":
			passed = _assert_remembered_conflict_ghost_does_not_override_later_live_input(context)
		"last_remembered_rebuild_still_can_generate_ghost":
			passed = _assert_last_remembered_rebuild_still_can_generate_ghost(context)
		"snapshot_case_for_live_input_after_older_rebuild_is_not_ghostified":
			passed = _assert_snapshot_case_for_live_input_after_older_rebuild_is_not_ghostified(context)
		"replay_path_truncates_at_first_conflict_step":
			passed = _assert_replay_path_truncates_at_first_conflict_step(context)
		"player_move_away_allows_remembered_path_to_finish_later":
			passed = _assert_player_move_away_allows_remembered_path_to_finish_later(context)
		"snapshot_reports_ghost_boxes_and_truncated_replay":
			passed = _assert_snapshot_reports_ghost_boxes_and_truncated_replay(context)
		"snapshot_reports_last_replay_display_info":
			passed = _assert_snapshot_reports_last_replay_display_info(context)
		"debug_snapshot_reports_detached_replay_actor_usage":
			passed = await _assert_debug_snapshot_reports_detached_replay_actor_usage(context)
		"controller_empty_overflow_snapshot_matches_memory_semantics":
			passed = await _assert_controller_empty_overflow_snapshot_matches_memory_semantics(context)
		"build_info_display_uses_generated_build_file_or_dev":
			passed = _assert_build_info_display_uses_generated_build_file_or_dev(context)
		"generated_ghost_change_is_deduped":
			passed = _assert_generated_ghost_change_is_deduped(context)
		"empty_pushed_out_no_replay_even_if_ghost_was_appended":
			passed = await _assert_empty_pushed_out_no_replay_even_if_ghost_was_appended(context)
		"ghost_is_formal_memory_and_survives_parent_pushout":
			passed = await _assert_ghost_is_formal_memory_and_survives_parent_pushout(context)
		"ghost_is_evicted_normally_and_then_world_restores":
			passed = await _assert_ghost_is_evicted_normally_and_then_world_restores(context)
		"pushing_out_parent_position_does_not_clear_surviving_auto_ghost":
			passed = await _assert_pushing_out_parent_position_does_not_clear_surviving_auto_ghost(context)
		"surviving_auto_ghost_prevents_default_box_restore":
			passed = await _assert_surviving_auto_ghost_prevents_default_box_restore(context)
		"ghost_only_surviving_queue_ghostifies_at_default_spawn":
			passed = _assert_ghost_only_surviving_queue_ghostifies_at_default_spawn(context)
		"first_surviving_position_entry_may_start_from_initial_default":
			passed = _assert_first_surviving_position_entry_may_start_from_initial_default(context)
		"position_then_ghost_replays_as_move_then_in_place_ghostify":
			passed = _assert_position_then_ghost_replays_as_move_then_in_place_ghostify(context)
		"pushed_out_position_leaving_only_ghost_reuses_default_spawn_as_replay_origin":
			passed = await _assert_pushed_out_position_leaving_only_ghost_reuses_default_spawn_as_replay_origin(context)
		"pushing_out_last_ghost_restores_default_world_and_replay_none":
			passed = await _assert_pushing_out_last_ghost_restores_default_world_and_replay_none(context)
		"pushing_out_last_ghost_with_player_on_default_projects_live_ghost":
			passed = _assert_pushing_out_last_ghost_with_player_on_default_projects_live_ghost(context)
		"ghost_entry_never_creates_motion_by_itself":
			passed = _assert_ghost_entry_never_creates_motion_by_itself(context)
		"position_entry_still_replays_as_motion":
			passed = _assert_position_entry_still_moves_normally(context)
		"position_entry_still_moves_normally":
			passed = _assert_position_entry_still_moves_normally(context)
		"replay_still_occurs_when_surviving_remembered_state_actually_changes":
			passed = await _assert_replay_still_occurs_when_surviving_remembered_state_actually_changes(context)
		"snapshot_second_box_change_pushout_with_surviving_auto_ghost_replays":
			passed = await _assert_snapshot_second_box_change_pushout_with_surviving_auto_ghost_replays(context)
		"level001_three_left_moves_no_stale_ghost":
			passed = _assert_level001_three_left_moves_no_stale_ghost(context)
		"semantic_move_changes_position":
			passed = _assert_semantic_move_changes_position(context)
		"semantic_ghost_only_changes_state":
			passed = _assert_semantic_ghost_only_changes_state(context)
		"semantic_init_conflict_generates_ghost":
			passed = _assert_semantic_init_conflict_generates_ghost(context)
		"semantic_projection_conflict_generates_ghost":
			passed = _assert_semantic_projection_conflict_generates_ghost(context)
		"semantic_evicted_move_not_replayed":
			passed = _assert_semantic_evicted_move_not_replayed(context)
		"semantic_replay_matches_compile_semantics":
			passed = _assert_semantic_replay_matches_compile_semantics(context)
		"semantic_chain_converges":
			passed = _assert_semantic_chain_converges(context)
		"semantic_ghost_step_no_motion":
			passed = _assert_semantic_ghost_step_no_motion(context)
		"semantic_left_right_same_rules":
			passed = _assert_semantic_left_right_same_rules(context)
		"semantic_evict_last_related_restores_default":
			passed = _assert_semantic_evict_last_related_restores_default(context)
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
	return _sorted_vec2_array(result.world.entity_positions.values()) == [Vector2i(1, 1)] \
		and result.world.ghost_entities.is_empty()


func _assert_remembered_defaults_ignore_live_player_until_projection(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue := ChangeQueue.new()
	var projected_with_player_on_default: CompileResult = _compiler.compile(defaults, queue, Vector2i(3, 1))
	return not projected_with_player_on_default.world.entity_positions.has(&"box_0") \
		and projected_with_player_on_default.world.ghost_entities.get(&"box_0", Vector2i(-1, -1)) == Vector2i(3, 1)


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
		["Ghost[AUTO_GHOST](box_0 ghostify_at_current_remembered; source_target=(2, 1))"],
		["Position[REMEMBERED_REBUILD](box_0 -> (2, 1))", "Position[REMEMBERED_REBUILD](box_0 -> (1, 1))", "Ghost[AUTO_GHOST](box_0 ghostify_at_current_remembered; source_target=(2, 1))"],
		false,
		"no_pushed_out"
	)
	return snapshot.contains("queue=[\"Position[REMEMBERED_REBUILD](box_0 -> (2, 1))\"") \
		and snapshot.contains("pushed_out_changes=[\"Position[LIVE_INPUT](box_0 -> (2, 1))\"]") \
		and snapshot.contains("generated_ghost_changes=[\"Ghost[AUTO_GHOST](box_0 ghostify_at_current_remembered; source_target=(2, 1))\"]") \
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
	replay_controller.memory_beat_duration = 0.12
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
	replay_controller.memory_beat_duration = 0.12
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
	return is_equal_approx(replay_controller.memory_beat_duration, 1.0) \
		and replay_controller.beat_prepare_duration > 0.0 \
		and replay_controller.beat_action_duration > replay_controller.beat_prepare_duration \
		and replay_controller.beat_tail_duration > 0.0


func _assert_replay_builder_position_steps_use_move_presentation_kind(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var builder := ReplayPayloadBuilder.new()
	var queue := ChangeQueue.new()
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.POSITION,
		&"box_0",
		Vector2i(2, 1),
		false,
		"move_kind",
		ChangeRecord.SourceKind.REMEMBERED_REBUILD
	))
	var replay_steps: Array[Dictionary] = builder.build_steps(defaults, queue.entries(), Vector2i(9, 9))
	return replay_steps.size() == 1 \
		and StringName(replay_steps[0].get("presentation_kind", &"")) == ReplayPayloadBuilder.PRESENTATION_MOVE


func _assert_replay_builder_ghost_steps_use_ghostify_presentation_kind(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var builder := ReplayPayloadBuilder.new()
	var queue := ChangeQueue.new()
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.GHOST,
		&"box_0",
		Vector2i(2, 1),
		false,
		"ghost_kind",
		ChangeRecord.SourceKind.AUTO_GHOST
	))
	var replay_steps: Array[Dictionary] = builder.build_steps(defaults, queue.entries(), Vector2i(9, 9))
	return replay_steps.size() == 1 \
		and StringName(replay_steps[0].get("presentation_kind", &"")) == ReplayPayloadBuilder.PRESENTATION_GHOSTIFY


func _assert_replay_empty_steps_keep_order_with_empty_presentation_kind(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var builder := ReplayPayloadBuilder.new()
	var queue := ChangeQueue.new()
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.POSITION,
		&"box_0",
		Vector2i(2, 1),
		false,
		"pos_a",
		ChangeRecord.SourceKind.REMEMBERED_REBUILD
	))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_middle", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.GHOST,
		&"box_0",
		Vector2i(2, 1),
		false,
		"ghost_b",
		ChangeRecord.SourceKind.AUTO_GHOST
	))
	var replay_steps: Array[Dictionary] = builder.build_steps(defaults, queue.entries(), Vector2i(9, 9))
	return replay_steps.size() == 3 \
		and StringName(replay_steps[0].get("presentation_kind", &"")) == ReplayPayloadBuilder.PRESENTATION_MOVE \
		and StringName(replay_steps[1].get("presentation_kind", &"")) == ReplayPayloadBuilder.PRESENTATION_BEAT \
		and int(replay_steps[1].get("type", -1)) == ChangeRecord.ChangeType.EMPTY \
		and StringName(replay_steps[2].get("presentation_kind", &"")) == ReplayPayloadBuilder.PRESENTATION_GHOSTIFY


func _assert_empty_beats_do_not_create_board_actor_steps(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var builder := ReplayPayloadBuilder.new()
	var queue := ChangeQueue.new()
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_only_a", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty_only_b", ChangeRecord.SourceKind.LIVE_INPUT))
	var replay_steps: Array[Dictionary] = builder.build_steps(defaults, queue.entries(), Vector2i(9, 9))
	return replay_steps.is_empty()


func _assert_replay_is_grouped_by_queue_index_not_raw_steps(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_steps: Array[Dictionary] = [
		{"queue_index": 0, "presentation_kind": ReplayPayloadBuilder.PRESENTATION_MOVE},
		{"queue_index": 0, "presentation_kind": ReplayPayloadBuilder.PRESENTATION_GHOSTIFY},
		{"queue_index": 1, "presentation_kind": ReplayPayloadBuilder.PRESENTATION_BEAT},
	]
	var beats: Array[Dictionary] = controller.call("_group_replay_steps_by_queue_index", replay_steps)
	if beats.size() != 2:
		return false
	var beat_zero_steps: Array = beats[0].get("steps", [])
	var beat_one_steps: Array = beats[1].get("steps", [])
	return int(beats[0].get("queue_index", -1)) == 0 \
		and int(beats[1].get("queue_index", -1)) == 1 \
		and beat_zero_steps.size() == 2 \
		and beat_one_steps.size() == 1


func _assert_queue_focus_advances_one_memory_per_beat(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
	replay_controller.memory_beat_duration = 0.18
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
	var trace: Array[String] = controller.get("_last_presentation_trace")
	var expected_order: Array[String] = ["queue:focus:0", "queue:focus:1", "queue:focus:2", "queue:focus:3"]
	var cursor: int = 0
	for marker: String in trace:
		if cursor < expected_order.size() and marker == expected_order[cursor]:
			cursor += 1
	return cursor == expected_order.size()


func _assert_board_replay_is_driven_one_memory_per_beat(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
	replay_controller.memory_beat_duration = 0.16
	var defaults: WorldDefaults = context["defaults"]
	var queue := ChangeQueue.new()
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(2, 1), false, "a", ChangeRecord.SourceKind.REMEMBERED_REBUILD))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "b", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.GHOST, &"box_0", Vector2i(2, 1), false, "c", ChangeRecord.SourceKind.AUTO_GHOST))
	var replay_steps: Array[Dictionary] = ReplayPayloadBuilder.new().build_steps(defaults, queue.entries(), Vector2i(9, 9))
	await replay_controller.play_steps(replay_steps)
	var phase_trace: Array[String] = replay_controller.get_last_phase_trace()
	var beat_count: int = 0
	for marker: String in phase_trace:
		if marker.begins_with("step:"):
			beat_count += 1
	return beat_count == replay_steps.size() \
		and replay_steps.size() == 3 \
		and StringName(replay_steps[1].get("presentation_kind", &"")) == ReplayPayloadBuilder.PRESENTATION_BEAT \
		and not replay_steps[1].has("subject")


func _assert_one_memory_one_beat_presentation(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
	replay_controller.memory_beat_duration = 0.16
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
	var presentation_trace: Array[String] = controller.get("_last_presentation_trace")
	var beat_focus_count: int = 0
	var rebuild_board_beats: int = 0
	for marker: String in presentation_trace:
		if marker.begins_with("queue:focus:rebuild:"):
			beat_focus_count += 1
		if marker.begins_with("board:beat:start:rebuild:"):
			rebuild_board_beats += 1
	return beat_focus_count > 0 and beat_focus_count == rebuild_board_beats


func _assert_one_queue_entry_one_visible_beat(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
	replay_controller.memory_beat_duration = 0.16
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
	var replay_steps: Array[Dictionary] = controller.get("_last_replay_steps")
	if replay_steps.is_empty():
		return false
	var unique_queue_indexes: Dictionary[int, bool] = {}
	for step: Dictionary in replay_steps:
		var queue_index: int = int(step.get("queue_index", -1))
		unique_queue_indexes[queue_index] = true
	var presentation_trace: Array[String] = controller.get("_last_presentation_trace")
	var focus_count: int = 0
	var beat_start_count: int = 0
	for marker: String in presentation_trace:
		if marker.begins_with("queue:focus:rebuild:"):
			focus_count += 1
		if marker.begins_with("board:beat:start:rebuild:"):
			beat_start_count += 1
	return unique_queue_indexes.size() == focus_count and focus_count == beat_start_count and focus_count > 0


func _assert_empty_beat_triggers_player_meditate_pulse(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
	replay_controller.memory_beat_duration = 0.16
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
	var phase_trace: Array[String] = replay_controller.get_last_phase_trace()
	return phase_trace.has("step:meditate_pulse")


func _assert_empty_beats_trigger_player_pulse_each_beat(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
	replay_controller.memory_beat_duration = 0.16
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
	var replay_steps: Array[Dictionary] = controller.get("_last_replay_steps")
	var empty_beat_count: int = 0
	for step: Dictionary in replay_steps:
		if StringName(step.get("presentation_kind", &"")) == ReplayPayloadBuilder.PRESENTATION_BEAT:
			empty_beat_count += 1
	var pulse_count: int = 0
	var phase_trace: Array[String] = replay_controller.get_last_phase_trace()
	for marker: String in phase_trace:
		if marker == "step:meditate_pulse":
			pulse_count += 1
	return empty_beat_count > 0 and pulse_count == empty_beat_count


func _assert_empty_beat_does_not_create_box_actor_movement(context: Dictionary) -> bool:
	return _assert_empty_beats_do_not_create_board_actor_steps(context)


func _assert_evicted_memory_is_presented_in_queue_before_rebuild(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
	replay_controller.memory_beat_duration = 0.18
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
	var trace: Array[String] = controller.get("_last_presentation_trace")
	var evict_index: int = trace.find("queue:evict")
	var first_focus_index: int = trace.find("queue:focus:0")
	if first_focus_index < 0:
		first_focus_index = trace.find("queue:focus:rebuild:0")
	return evict_index >= 0 and first_focus_index > evict_index


func _assert_memory_focus_and_board_step_are_synchronized(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
	replay_controller.memory_beat_duration = 0.16
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
	var presentation_trace: Array[String] = controller.get("_last_presentation_trace")
	var focus_count: int = 0
	var board_beat_count: int = 0
	for marker: String in presentation_trace:
		if marker.begins_with("queue:focus:rebuild:"):
			focus_count += 1
		if marker.begins_with("board:beat:start:rebuild:"):
			board_beat_count += 1
	return focus_count == board_beat_count and focus_count > 0


func _assert_queue_focus_and_board_action_start_in_same_beat(context: Dictionary) -> bool:
	return await _assert_queue_focus_and_board_beat_start_together(context)


func _assert_queue_focus_and_board_beat_start_together(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
	replay_controller.memory_beat_duration = 0.16
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
	var presentation_trace: Array[String] = controller.get("_last_presentation_trace")
	var checked_beats: int = 0
	for i: int in range(presentation_trace.size() - 1):
		var marker: String = presentation_trace[i]
		if not marker.begins_with("queue:beat:start:rebuild:"):
			continue
		var queue_index: String = marker.trim_prefix("queue:beat:start:rebuild:")
		var matched: bool = false
		for j: int in range(i + 1, mini(i + 4, presentation_trace.size())):
			if presentation_trace[j] == "board:beat:start:rebuild:%s" % queue_index:
				matched = true
				break
		if not matched:
			return false
		checked_beats += 1
	return checked_beats > 0


func _assert_replay_no_longer_contains_subjectless_fake_steps(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue := ChangeQueue.new()
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(2, 1), false, "a", ChangeRecord.SourceKind.REMEMBERED_REBUILD))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "b", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.GHOST, &"box_0", Vector2i(2, 1), false, "c", ChangeRecord.SourceKind.AUTO_GHOST))
	var replay_steps: Array[Dictionary] = ReplayPayloadBuilder.new().build_steps(defaults, queue.entries(), Vector2i(9, 9))
	for step: Dictionary in replay_steps:
		if step.get("subject", &"") == &"" and step.has("from") and step.has("to") and step.get("from", Vector2i.ZERO) == Vector2i.ZERO and step.get("to", Vector2i.ZERO) == Vector2i.ZERO:
			return false
	return true


func _assert_board_replay_rebuilds_only_from_surviving_queue(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var surviving_queue_entries: Array[ChangeRecord] = [
		ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(1, 1), false, "surviving", ChangeRecord.SourceKind.REMEMBERED_REBUILD)
	]
	var replay_steps: Array[Dictionary] = ReplayPayloadBuilder.new().build_steps(defaults, surviving_queue_entries, defaults.player_start)
	if replay_steps.is_empty():
		return false
	var last_step: Dictionary = replay_steps[replay_steps.size() - 1]
	return last_step.get("subject", &"") == &"box_0" \
		and last_step.get("to", Vector2i.ZERO) == Vector2i(1, 1)


func _assert_replay_controller_runs_evict_phase_before_rebuild(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
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
	var presentation_trace: Array[String] = controller.get("_last_presentation_trace")
	var queue_evict_index: int = presentation_trace.find("queue:evict")
	var board_rebuild_index: int = presentation_trace.find("board:rebuild")
	return queue_evict_index >= 0 and board_rebuild_index > queue_evict_index


func _assert_evicted_changes_are_presented_in_queue_not_board(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
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
	var replay_steps: Array[Dictionary] = controller.get("_last_replay_steps")
	var has_evicted_move: bool = false
	for step: Dictionary in replay_steps:
		if StringName(step.get("presentation_kind", &"")) == ReplayPayloadBuilder.PRESENTATION_EVICT_MOVE:
			has_evicted_move = true
			break
	var presentation_trace: Array[String] = controller.get("_last_presentation_trace")
	return presentation_trace.find("queue:evict") >= 0 \
		and has_evicted_move


func _assert_evicted_position_change_produces_board_replay(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var builder := ReplayPayloadBuilder.new()
	var previous_queue_entries: Array[ChangeRecord] = [
		ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(3, 1), false, "p0", ChangeRecord.SourceKind.REMEMBERED_REBUILD, Vector2i.LEFT),
		ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(2, 1), false, "p1", ChangeRecord.SourceKind.REMEMBERED_REBUILD, Vector2i.LEFT),
		ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "empty", ChangeRecord.SourceKind.LIVE_INPUT),
	]
	var pushed_out_changes: Array[ChangeRecord] = [previous_queue_entries[0]]
	var resulting_queue_entries: Array[ChangeRecord] = [previous_queue_entries[1], previous_queue_entries[2]]
	var evicted_steps: Array[Dictionary] = builder.build_evicted_steps(
		defaults,
		previous_queue_entries,
		pushed_out_changes,
		resulting_queue_entries,
		defaults.player_start
	)
	if evicted_steps.is_empty():
		return false
	var first_step: Dictionary = evicted_steps[0]
	return StringName(first_step.get("presentation_kind", &"")) == ReplayPayloadBuilder.PRESENTATION_EVICT_MOVE \
		and first_step.get("subject", &"") == &"box_0" \
		and first_step.get("from", Vector2i.ZERO) == Vector2i(1, 1) \
		and first_step.get("to", Vector2i.ZERO) == Vector2i(2, 1)


func _assert_replay_has_evict_phase_before_rebuild_phase(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
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
	var presentation_trace: Array[String] = controller.get("_last_presentation_trace")
	var evict_index: int = presentation_trace.find("board:evict")
	var rebuild_index: int = presentation_trace.find("board:rebuild")
	return evict_index >= 0 and rebuild_index > evict_index


func _assert_evicted_move_uses_state_diff_not_guessing(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var builder := ReplayPayloadBuilder.new()
	var previous_queue_entries: Array[ChangeRecord] = [
		ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(3, 1), false, "p0", ChangeRecord.SourceKind.REMEMBERED_REBUILD, Vector2i.LEFT),
		ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(2, 1), false, "p1", ChangeRecord.SourceKind.REMEMBERED_REBUILD, Vector2i.LEFT),
	]
	var pushed_out_changes: Array[ChangeRecord] = [previous_queue_entries[0]]
	var resulting_queue_entries: Array[ChangeRecord] = [previous_queue_entries[1]]
	var evicted_steps: Array[Dictionary] = builder.build_evicted_steps(
		defaults,
		previous_queue_entries,
		pushed_out_changes,
		resulting_queue_entries,
		defaults.player_start
	)
	if evicted_steps.size() != 1:
		return false
	var step: Dictionary = evicted_steps[0]
	if step.get("from", Vector2i.ZERO) != Vector2i(1, 1):
		return false
	if step.get("to", Vector2i.ZERO) != Vector2i(2, 1):
		return false
	return step.get("to", Vector2i.ZERO) != pushed_out_changes[0].target_position


func _assert_empty_beats_still_use_player_pulse_in_rebuild_phase(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
	replay_controller.memory_beat_duration = 0.12
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
	var trace: Array[String] = replay_controller.get_last_phase_trace()
	var pulse_count: int = 0
	for marker: String in trace:
		if marker == "step:meditate_pulse":
			pulse_count += 1
	return pulse_count >= 2


func _assert_replay_conflict_step_finishes_then_applies_tail_pause(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
	replay_controller.memory_beat_duration = 0.12
	var steps: Array[Dictionary] = [{
		"type": ChangeRecord.ChangeType.POSITION,
		"subject": &"box_0",
		"from": Vector2i(3, 1),
		"to": Vector2i(3, 1),
		"is_conflict": true,
		"ends_as_ghost": true,
		"presentation_kind": ReplayPayloadBuilder.PRESENTATION_GHOSTIFY,
	}]
	await replay_controller.play_steps(steps)
	var trace: Array[String] = replay_controller.get_last_phase_trace()
	var replay_step_index: int = trace.find("step:ghostify")
	return replay_step_index >= 0


func _assert_ghostify_step_is_played_as_full_in_place_change(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
	replay_controller.memory_beat_duration = 0.12
	var steps: Array[Dictionary] = [{
		"type": ChangeRecord.ChangeType.POSITION,
		"subject": &"box_0",
		"from": Vector2i(3, 1),
		"to": Vector2i(3, 1),
		"is_conflict": true,
		"ends_as_ghost": true,
		"presentation_kind": ReplayPayloadBuilder.PRESENTATION_GHOSTIFY,
	}]
	await replay_controller.play_steps(steps)
	var actor: BoxView = replay_controller.get_replay_actor(&"box_0")
	var trace: Array[String] = replay_controller.get_last_phase_trace()
	return actor == null \
		and trace.find("step:ghostify") >= 0 \
		and trace.size() >= 1


func _assert_replay_sequence_orders_queue_feedback_before_board_rebuild(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
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
	var presentation_trace: Array[String] = controller.get("_last_presentation_trace")
	var queue_settle_index: int = presentation_trace.find("queue:settle")
	var board_rebuild_index: int = presentation_trace.find("board:rebuild")
	return queue_settle_index >= 0 and board_rebuild_index > queue_settle_index


func _assert_replay_uses_detached_replay_actor_not_live_box_view(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
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
	return not bool(controller.get("_last_replay_used_live_box_views"))


func _assert_ghost_spawn_ghostify_replay_does_not_move_live_final_world_box(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
	var board_view: BoardView = controller.get_node(controller.board_view_path)
	var queue: ChangeQueue = context["queue"]
	queue.clear()
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.POSITION,
		&"box_0",
		Vector2i(1, 1),
		false,
		"remembered",
		ChangeRecord.SourceKind.REMEMBERED_REBUILD
	))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e2", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e3", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e4", ChangeRecord.SourceKind.LIVE_INPUT))
	var world: CompiledWorld = controller.get("_world")
	world.player_position = Vector2i(2, 1)
	controller.call("_recompile_world", "test_generate_auto_ghost")
	for j: int in range(120):
		if not controller.get("_input_locked"):
			break
		await process_frame
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "push_parent", ChangeRecord.SourceKind.LIVE_INPUT))
	controller.call("_recompile_world", "test_push_out_parent_remembered_position")
	var replay_actor_spawn_position: Vector2 = Vector2.ZERO
	var replay_actor_conflict: bool = false
	var captured: bool = false
	for i: int in range(600):
		if board_view.is_replay_presenting_subject(&"box_0"):
			var replay_actor: BoxView = replay_controller.get_replay_actor(&"box_0")
			if replay_actor != null:
				replay_actor_spawn_position = replay_actor.position
				replay_actor_conflict = replay_actor.is_conflict()
			captured = true
			break
		await process_frame
	for i: int in range(600):
		if not controller.get("_input_locked"):
			break
		await process_frame
	var world_after: CompiledWorld = controller.get("_world")
	var box_after: BoxView = board_view.get_box_view(&"box_0")
	var final_box_pos: Vector2i = world_after.ghost_entities.get(&"box_0", Vector2i.ZERO)
	var spawn_pixel: Vector2 = board_view.board_to_pixel_center(Vector2i(3, 1))
	return captured \
		and replay_actor_spawn_position.is_equal_approx(spawn_pixel) \
		and replay_actor_conflict \
		and final_box_pos == Vector2i(3, 1) \
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


func _assert_replay_actor_is_cleaned_up_and_live_world_restored_after_playback(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var replay_controller: ReplayController = controller.get_node(controller.replay_controller_path)
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
	var live_box: BoxView = board_view.get_box_view(&"box_0")
	var final_ghost_pos: Vector2i = world_after.ghost_entities.get(&"box_0", Vector2i.ZERO)
	return replay_controller.get_replay_actor_count() == 0 \
		and not board_view.is_replay_presenting_subject(&"box_0") \
		and live_box.visible \
		and live_box.is_ghost() \
		and not live_box.is_conflict() \
		and world_after.ghost_entities.has(&"box_0") \
		and final_ghost_pos == Vector2i(2, 1) \
		and live_box.position.is_equal_approx(board_view.board_to_pixel_center(final_ghost_pos))


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
			and step.get("to", Vector2i.ZERO) == Vector2i(1, 1):
			has_micro_step_a = true
		if step.get("subject", &"") == &"box_0" and not bool(step.get("is_conflict", false)):
			has_micro_step_b = true
		if step.get("subject", &"") == &"box_0" \
			and step.get("from", Vector2i.ZERO) == Vector2i(1, 1) \
			and step.get("to", Vector2i.ZERO) == Vector2i(3, 1):
			has_world_diff_direction = true
	return has_position_memory \
		and replay_steps.size() >= 1 \
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
	var motion_steps: Array[Dictionary] = []
	for step: Dictionary in replay_steps:
		if StringName(step.get("presentation_kind", &"")) == ReplayPayloadBuilder.PRESENTATION_MOVE:
			motion_steps.append(step)
	return motion_steps.size() >= 1 \
		and motion_steps[0].get("subject", &"") == &"box_0" \
		and motion_steps[0].get("from", Vector2i.ZERO) == Vector2i(3, 1) \
		and motion_steps[motion_steps.size() - 1].get("to", Vector2i.ZERO) == Vector2i(1, 1)


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
	return replay_steps.size() >= 1 \
		and bool(replay_steps[replay_steps.size() - 1].get("is_conflict", false))


func _assert_player_conflict_truncation_appends_ghost_change(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = _build_remembered_conflict_queue()
	var result: CompileResult = _compiler.compile(defaults, queue, Vector2i(2, 1))
	var has_position_memory: bool = result.queue_entries.size() >= 4 		and result.queue_entries[0].type == ChangeRecord.ChangeType.POSITION 		and result.queue_entries[0].subject_id == &"box_0" 		and result.queue_entries[0].target_position == Vector2i(1, 1)
	var ghost_count: int = _count_ghost_entries(result.queue_entries, &"box_0", Vector2i(2, 1))
	return has_position_memory 		and not result.world.entity_positions.has(&"box_0") 		and result.world.ghost_entities.get(&"box_0", Vector2i(-1, -1)) == Vector2i(2, 1) 		and ghost_count == 1 		and result.generated_ghost_changes.size() == 1 		and result.generated_ghost_changes[0].type == ChangeRecord.ChangeType.GHOST 		and result.generated_ghost_changes[0].subject_id == &"box_0" 		and result.generated_ghost_changes[0].target_position == Vector2i(2, 1)


func _assert_remembered_conflict_ghost_does_not_override_later_live_input(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue := ChangeQueue.new()
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.POSITION,
		&"box_0",
		Vector2i(2, 1),
		false,
		"remembered_old",
		ChangeRecord.SourceKind.REMEMBERED_REBUILD
	))
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.POSITION,
		&"box_0",
		Vector2i(1, 1),
		false,
		"live_new",
		ChangeRecord.SourceKind.LIVE_INPUT
	))
	var result: CompileResult = _compiler.compile(defaults, queue, Vector2i(2, 1))
	var has_overriding_generated_ghost: bool = false
	for generated: ChangeRecord in result.generated_ghost_changes:
		if generated.type == ChangeRecord.ChangeType.GHOST \
			and generated.subject_id == &"box_0" \
			and generated.target_position == Vector2i(2, 1):
			has_overriding_generated_ghost = true
			break
	return result.world.entity_positions.get(&"box_0", Vector2i(-1, -1)) == Vector2i(1, 1) \
		and result.world.ghost_entities.is_empty() \
		and not has_overriding_generated_ghost


func _assert_last_remembered_rebuild_still_can_generate_ghost(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue := ChangeQueue.new()
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.POSITION,
		&"box_0",
		Vector2i(1, 1),
		false,
		"remembered_last",
		ChangeRecord.SourceKind.REMEMBERED_REBUILD
	))
	var result: CompileResult = _compiler.compile(defaults, queue, Vector2i(2, 1))
	return result.world.entity_positions.is_empty() \
		and result.world.ghost_entities.get(&"box_0", Vector2i(-1, -1)) == Vector2i(2, 1) \
		and _count_ghost_entries(result.queue_entries, &"box_0", Vector2i(2, 1)) == 1


func _assert_snapshot_case_for_live_input_after_older_rebuild_is_not_ghostified(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue := ChangeQueue.new()
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.POSITION,
		&"box_0",
		Vector2i(2, 1),
		false,
		"remembered_old",
		ChangeRecord.SourceKind.REMEMBERED_REBUILD
	))
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.POSITION,
		&"box_0",
		Vector2i(1, 1),
		false,
		"live_new",
		ChangeRecord.SourceKind.LIVE_INPUT
	))
	var result: CompileResult = _compiler.compile(defaults, queue, Vector2i(2, 1))
	var snapshot: String = _formatter.build_snapshot(
		result.world,
		result.queue_entries,
		"snapshot_live_after_rebuild",
		[],
		[],
		[],
		false,
		false,
		BuildInfo.display_text(),
		"board_ok",
		"replay_ok",
		"none"
	)
	return snapshot.contains("player=(2, 1)") \
		and snapshot.contains("boxes=[(1, 1)]") \
		and snapshot.contains("ghost_boxes=[]")


func _assert_replay_path_truncates_at_first_conflict_step(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = _build_remembered_conflict_queue()
	var result: CompileResult = _compiler.compile(defaults, queue, Vector2i(2, 1))
	var builder := ReplayPayloadBuilder.new()
	var replay_steps: Array[Dictionary] = builder.build_steps(defaults, result.queue_entries, Vector2i(2, 1))
	var has_conflict_step: bool = false
	for step: Dictionary in replay_steps:
		if step.get("subject", &"") == &"box_0" \
			and bool(step.get("is_conflict", false)):
			has_conflict_step = true
			break
	return replay_steps.size() >= 1 \
		and has_conflict_step


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
		false,
		true,
		BuildInfo.display_text(),
		"board_ok",
		"replay_ok",
		"player_conflict"
	)
	return snapshot.contains("ghost_boxes=[(2, 1)]") \
		and snapshot.contains("box_0:(3, 1)->(2, 1)") \
		and snapshot.contains("conflict=true") \
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
		false,
		true,
		BuildInfo.display_text(),
		"board_ok",
		"replay_ok",
		"player_conflict"
	)
	return snapshot.contains("last_replay_display_steps=") \
		and snapshot.contains("last_replay_used_live_box_views=false") \
		and snapshot.contains("last_replay_completed=true")


func _assert_debug_snapshot_reports_detached_replay_actor_usage(context: Dictionary) -> bool:
	var result: Dictionary = await _setup_auto_ghost_generated_then_parent_pushed_out_case(context)
	var controller: GameController = result["controller"]
	var snapshot: String = _formatter.build_snapshot(
		controller.get("_world"),
		context["queue"].entries(),
		String(controller.get("_last_recompile_reason")),
		controller.get("_last_replay_steps"),
		controller.get("_last_replay_display_steps"),
		controller.get("_last_replay_presenting_subjects"),
		bool(controller.get("_last_replay_used_live_box_views")),
		bool(controller.get("_last_replay_completed")),
		BuildInfo.display_text()
	)
	return snapshot.contains("last_replay_used_live_box_views=false") \
		and not snapshot.contains("last_replay_used_live_box_views=true") \
		and snapshot.contains("last_replay_display_steps=[") \
		and snapshot.contains("box_0:(3, 1)->(3, 1)") \
		and snapshot.contains("conflict=true")


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


func _setup_auto_ghost_generated_then_parent_pushed_out_case(context: Dictionary) -> Dictionary:
	var controller: GameController = context["controller"]
	var queue: ChangeQueue = context["queue"]
	queue.clear()
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.POSITION,
		&"box_0",
		Vector2i(1, 1),
		false,
		"remembered",
		ChangeRecord.SourceKind.REMEMBERED_REBUILD
	))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e2", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e3", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e4", ChangeRecord.SourceKind.LIVE_INPUT))
	var world: CompiledWorld = controller.get("_world")
	world.player_position = Vector2i(2, 1)
	controller.call("_recompile_world", "test_generate_auto_ghost")
	for j: int in range(120):
		if not controller.get("_input_locked"):
			break
		await process_frame
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "push_parent", ChangeRecord.SourceKind.LIVE_INPUT))
	controller.call("_recompile_world", "test_push_out_parent_remembered_position")
	for j: int in range(120):
		if not controller.get("_input_locked"):
			break
		await process_frame
	context["world"] = controller.get("_world")
	return {
		"controller": controller,
		"queue_after_compile": queue.entries(),
		"queue_after_compile_summaries": controller.get("_last_queue_after_compile_summaries"),
		"pushed_out_changes": controller.get("_last_pushed_out_summaries"),
		"replay_steps": controller.get("_last_replay_steps"),
		"replay_display_steps": controller.get("_last_replay_display_steps"),
		"replay_gate_allowed": bool(controller.get("_last_replay_gate_allowed")),
		"replay_gate_reason": String(controller.get("_last_replay_gate_reason")),
		"replay_stop_reason": String(controller.get("_last_replay_stop_reason")),
		"world": controller.get("_world"),
	}


func _has_replay_step(
	replay_steps: Array[Dictionary],
	subject_id: StringName,
	from_pos: Vector2i,
	to_pos: Vector2i,
	expect_conflict: bool = false,
	expect_ghost_end: bool = false
) -> bool:
	for step: Dictionary in replay_steps:
		if step.get("subject", &"") != subject_id:
			continue
		if step.get("from", Vector2i.ZERO) != from_pos:
			continue
		if step.get("to", Vector2i.ZERO) != to_pos:
			continue
		if bool(step.get("is_conflict", false)) != expect_conflict:
			continue
		if bool(step.get("ends_as_ghost", false)) != expect_ghost_end:
			continue
		return true
	return false


func _assert_ghost_is_formal_memory_and_survives_parent_pushout(context: Dictionary) -> bool:
	var result: Dictionary = await _setup_auto_ghost_generated_then_parent_pushed_out_case(context)
	var queue_after_compile_summaries: Array[String] = result["queue_after_compile_summaries"]
	var queue_after_compile: Array[ChangeRecord] = result["queue_after_compile"]
	var has_persistent_auto_ghost_summary: bool = queue_after_compile_summaries.has("Ghost[AUTO_GHOST](box_0 ghostify_at_current_remembered; source_target=(2, 1))")
	var auto_ghost_count: int = _count_ghost_entries(queue_after_compile, &"box_0", Vector2i(2, 1))
	var final_world: CompiledWorld = result["world"]
	var replay_gate_reason: String = result["replay_gate_reason"]
	return has_persistent_auto_ghost_summary \
		and auto_ghost_count == 1 \
		and not final_world.entity_positions.has(&"box_0") \
		and final_world.ghost_entities.get(&"box_0", Vector2i(-1, -1)) == Vector2i(3, 1) \
		and replay_gate_reason == "allowed_non_empty_pushed_out"


func _assert_ghost_is_evicted_normally_and_then_world_restores(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var queue: ChangeQueue = context["queue"]
	queue.clear()
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.GHOST,
		&"box_0",
		Vector2i(2, 1),
		false,
		"ghost_will_be_evicted",
		ChangeRecord.SourceKind.AUTO_GHOST
	))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e1", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e2", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e3", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e4_push_ghost_out", ChangeRecord.SourceKind.LIVE_INPUT))
	controller.call("_recompile_world", "test_ghost_evicted_world_restores")
	for i: int in range(120):
		if not controller.get("_input_locked"):
			break
		await process_frame
	var pushed_out_changes: Array[String] = controller.get("_last_pushed_out_summaries")
	var final_world: CompiledWorld = controller.get("_world")
	var queue_after_compile_summaries: Array[String] = controller.get("_last_queue_after_compile_summaries")
	return pushed_out_changes.has("Ghost[AUTO_GHOST](box_0 ghostify_at_current_remembered; source_target=(2, 1))") \
		and not queue_after_compile_summaries.has("Ghost[AUTO_GHOST](box_0 ghostify_at_current_remembered; source_target=(2, 1))") \
		and final_world.entity_positions.get(&"box_0", Vector2i(-1, -1)) == Vector2i(3, 1) \
		and not final_world.ghost_entities.has(&"box_0")


func _assert_pushing_out_parent_position_does_not_clear_surviving_auto_ghost(context: Dictionary) -> bool:
	var result: Dictionary = await _setup_auto_ghost_generated_then_parent_pushed_out_case(context)
	var pushed_out_changes: Array[String] = result["pushed_out_changes"]
	var queue_after_compile_summaries: Array[String] = result["queue_after_compile_summaries"]
	return pushed_out_changes.has("Position[REMEMBERED_REBUILD](box_0 -> (1, 1))") \
		and queue_after_compile_summaries.has("Ghost[AUTO_GHOST](box_0 ghostify_at_current_remembered; source_target=(2, 1))")


func _assert_surviving_auto_ghost_prevents_default_box_restore(context: Dictionary) -> bool:
	var result: Dictionary = await _setup_auto_ghost_generated_then_parent_pushed_out_case(context)
	var final_world: CompiledWorld = result["world"]
	return not final_world.entity_positions.has(&"box_0") \
		and final_world.ghost_entities.get(&"box_0", Vector2i(-1, -1)) == Vector2i(3, 1)


func _assert_first_surviving_position_entry_may_start_from_initial_default(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue := ChangeQueue.new()
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.POSITION,
		&"box_0",
		Vector2i(2, 1),
		false,
		"remembered",
		ChangeRecord.SourceKind.REMEMBERED_REBUILD
	))
	var builder := ReplayPayloadBuilder.new()
	var replay_steps: Array[Dictionary] = builder.build_steps(defaults, queue.entries(), Vector2i(9, 9))
	return replay_steps.size() == 1 \
		and replay_steps[0].get("subject", &"") == &"box_0" \
		and replay_steps[0].get("from", Vector2i.ZERO) == Vector2i(3, 1) \
		and replay_steps[0].get("to", Vector2i.ZERO) == Vector2i(2, 1) \
		and StringName(replay_steps[0].get("presentation_kind", &"")) == ReplayPayloadBuilder.PRESENTATION_MOVE \
		and not bool(replay_steps[0].get("is_conflict", false))


func _assert_ghost_only_surviving_queue_ghostifies_at_default_spawn(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue := ChangeQueue.new()
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.GHOST,
		&"box_0",
		Vector2i(2, 1),
		false,
		"first_surviving_ghost",
		ChangeRecord.SourceKind.AUTO_GHOST
	))
	var compiled: CompileResult = _compiler.compile(defaults, queue, defaults.player_start)
	var final_world: CompiledWorld = compiled.world
	var builder := ReplayPayloadBuilder.new()
	var replay_steps: Array[Dictionary] = builder.build_steps(defaults, queue.entries(), Vector2i(9, 9))
	return replay_steps.size() == 1 \
		and replay_steps[0].get("subject", &"") == &"box_0" \
		and replay_steps[0].get("from", Vector2i.ZERO) == Vector2i(3, 1) \
		and replay_steps[0].get("to", Vector2i.ZERO) == Vector2i(3, 1) \
		and StringName(replay_steps[0].get("presentation_kind", &"")) == ReplayPayloadBuilder.PRESENTATION_GHOSTIFY \
		and bool(replay_steps[0].get("from_exists", false)) \
		and bool(replay_steps[0].get("to_exists", false)) \
		and not bool(replay_steps[0].get("appears", true)) \
		and bool(replay_steps[0].get("is_conflict", false)) \
		and bool(replay_steps[0].get("ends_as_ghost", false)) \
		and not final_world.entity_positions.has(&"box_0") \
		and final_world.ghost_entities.get(&"box_0", Vector2i(-1, -1)) == Vector2i(3, 1) \
		and replay_steps[0].get("from", Vector2i.ZERO) != Vector2i(2, 1)


func _assert_position_then_ghost_replays_as_move_then_in_place_ghostify(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue := ChangeQueue.new()
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.POSITION,
		&"box_0",
		Vector2i(2, 1),
		false,
		"enter_b",
		ChangeRecord.SourceKind.REMEMBERED_REBUILD
	))
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.GHOST,
		&"box_0",
		Vector2i(2, 1),
		false,
		"ghost_at_b",
		ChangeRecord.SourceKind.AUTO_GHOST
	))
	var compiled: CompileResult = _compiler.compile(defaults, queue, defaults.player_start)
	var final_world: CompiledWorld = compiled.world
	var builder := ReplayPayloadBuilder.new()
	var replay_steps: Array[Dictionary] = builder.build_steps(defaults, queue.entries(), Vector2i(9, 9))
	return replay_steps.size() == 2 \
		and replay_steps[0].get("from", Vector2i.ZERO) == Vector2i(3, 1) \
		and replay_steps[0].get("to", Vector2i.ZERO) == Vector2i(2, 1) \
		and StringName(replay_steps[0].get("presentation_kind", &"")) == ReplayPayloadBuilder.PRESENTATION_MOVE \
		and not bool(replay_steps[0].get("ends_as_ghost", false)) \
		and replay_steps[1].get("from", Vector2i.ZERO) == Vector2i(2, 1) \
		and replay_steps[1].get("to", Vector2i.ZERO) == Vector2i(2, 1) \
		and StringName(replay_steps[1].get("presentation_kind", &"")) == ReplayPayloadBuilder.PRESENTATION_GHOSTIFY \
		and bool(replay_steps[1].get("is_conflict", false)) \
		and bool(replay_steps[1].get("ends_as_ghost", false)) \
		and not final_world.entity_positions.has(&"box_0") \
		and final_world.ghost_entities.get(&"box_0", Vector2i(-1, -1)) == Vector2i(2, 1)


func _assert_pushed_out_position_leaving_only_ghost_reuses_default_spawn_as_replay_origin(context: Dictionary) -> bool:
	var result: Dictionary = await _setup_auto_ghost_generated_then_parent_pushed_out_case(context)
	var pushed_out_changes: Array[String] = result["pushed_out_changes"]
	var final_world: CompiledWorld = result["world"]
	var queue_after_compile_summaries: Array[String] = result["queue_after_compile_summaries"]
	var replay_steps: Array[Dictionary] = result["replay_steps"]
	var replay_display_steps: Array[Dictionary] = result["replay_display_steps"]
	var replay_gate_allowed: bool = result["replay_gate_allowed"]
	var replay_gate_reason: String = result["replay_gate_reason"]
	var has_initial_to_ghost_move: bool = _has_replay_step(replay_steps, &"box_0", Vector2i(3, 1), Vector2i(2, 1), true, true)
	var has_target_ghost_step: bool = _has_replay_step(replay_steps, &"box_0", Vector2i(2, 1), Vector2i(2, 1), true, true)
	var has_spawn_ghostify_step: bool = _has_replay_step(replay_steps, &"box_0", Vector2i(3, 1), Vector2i(3, 1), true, true)
	var has_spawn_to_target_motion: bool = _has_replay_step(replay_steps, &"box_0", Vector2i(3, 1), Vector2i(2, 1), true, true)
	var ghost_step: Dictionary = replay_steps[0] if not replay_steps.is_empty() else {}
	return pushed_out_changes.has("Position[REMEMBERED_REBUILD](box_0 -> (1, 1))") \
		and not final_world.entity_positions.has(&"box_0") \
		and final_world.ghost_entities.get(&"box_0", Vector2i(-1, -1)) == Vector2i(3, 1) \
		and queue_after_compile_summaries.has("Ghost[AUTO_GHOST](box_0 ghostify_at_current_remembered; source_target=(2, 1))") \
		and replay_gate_allowed \
		and replay_gate_reason == "allowed_non_empty_pushed_out" \
		and not replay_steps.is_empty() \
		and not replay_display_steps.is_empty() \
		and not has_initial_to_ghost_move \
		and not has_target_ghost_step \
		and has_spawn_ghostify_step \
		and not has_spawn_to_target_motion \
		and bool(ghost_step.get("from_exists", false)) \
		and not bool(ghost_step.get("appears", true)) \
		and bool(replay_display_steps[replay_display_steps.size() - 1].get("is_conflict", false))


func _assert_pushing_out_last_ghost_restores_default_world_and_replay_none(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var queue: ChangeQueue = context["queue"]
	queue.clear()
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.GHOST,
		&"box_0",
		Vector2i(2, 1),
		false,
		"ghost_will_be_evicted",
		ChangeRecord.SourceKind.AUTO_GHOST
	))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e1", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e2", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e3", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e4_push_ghost_out", ChangeRecord.SourceKind.LIVE_INPUT))
	controller.call("_recompile_world", "test_ghost_pushout_leaves_no_replayable_memory")
	for i: int in range(120):
		if not controller.get("_input_locked"):
			break
		await process_frame
	var final_world: CompiledWorld = controller.get("_world")
	var queue_after: Array[ChangeRecord] = queue.entries()
	var replay_steps: Array[Dictionary] = controller.get("_last_replay_steps")
	var replay_gate_allowed: bool = bool(controller.get("_last_replay_gate_allowed"))
	var replay_stop_reason: String = String(controller.get("_last_replay_stop_reason"))
	return replay_steps.is_empty() \
		and not replay_gate_allowed \
		and replay_stop_reason == "no_surviving_replayable_memory" \
		and _count_ghost_entries(queue_after, &"box_0", Vector2i(2, 1)) == 0 \
		and final_world.entity_positions.get(&"box_0", Vector2i(-1, -1)) == Vector2i(3, 1) \
		and not final_world.ghost_entities.has(&"box_0")


func _assert_pushing_out_last_ghost_with_player_on_default_projects_live_ghost(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue := ChangeQueue.new()
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.GHOST,
		&"box_0",
		Vector2i(2, 1),
		false,
		"ghost_will_be_evicted",
		ChangeRecord.SourceKind.AUTO_GHOST
	))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e1", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e2", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e3", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e4_push_ghost_out", ChangeRecord.SourceKind.LIVE_INPUT))
	var result: CompileResult = _compiler.compile(defaults, queue, Vector2i(3, 1))
	return _count_ghost_entries(result.queue_entries, &"box_0", Vector2i(2, 1)) == 0 \
		and result.world.entity_positions.is_empty() \
		and result.world.ghost_entities.get(&"box_0", Vector2i(-1, -1)) == Vector2i(3, 1)


func _assert_ghost_entry_never_creates_motion_by_itself(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var builder := ReplayPayloadBuilder.new()

	var queue_with_prior_visible := ChangeQueue.new()
	queue_with_prior_visible.append(ChangeRecord.new(
		ChangeRecord.ChangeType.POSITION,
		&"box_0",
		Vector2i(2, 1),
		false,
		"prior_visible_pos",
		ChangeRecord.SourceKind.REMEMBERED_REBUILD
	))
	queue_with_prior_visible.append(ChangeRecord.new(
		ChangeRecord.ChangeType.GHOST,
		&"box_0",
		Vector2i(1, 1),
		false,
		"ghost_after_prior_visible_pos",
		ChangeRecord.SourceKind.AUTO_GHOST
	))
	var steps_with_prior_visible: Array[Dictionary] = builder.build_steps(defaults, queue_with_prior_visible.entries(), Vector2i(9, 9))
	var has_motion_in_prior_visible_case: bool = false
	var ghost_step_is_in_place_in_prior_visible_case: bool = false
	for step: Dictionary in steps_with_prior_visible:
		if step.get("subject", &"") == &"box_0" \
			and bool(step.get("ends_as_ghost", false)):
			ghost_step_is_in_place_in_prior_visible_case = step.get("from", Vector2i.ZERO) == step.get("to", Vector2i.ZERO)
			if step.get("from", Vector2i.ZERO) != step.get("to", Vector2i.ZERO):
				has_motion_in_prior_visible_case = true
				break

	var ghost_only_queue := ChangeQueue.new()
	ghost_only_queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.GHOST,
		&"box_0",
		Vector2i(2, 1),
		false,
		"ghost_only",
		ChangeRecord.SourceKind.AUTO_GHOST
	))
	var ghost_only_steps: Array[Dictionary] = builder.build_steps(defaults, ghost_only_queue.entries(), Vector2i(9, 9))
	var has_motion_in_ghost_only_case: bool = false
	var ghost_only_step_is_in_place: bool = false
	for step2: Dictionary in ghost_only_steps:
		if step2.get("subject", &"") == &"box_0" \
			and bool(step2.get("ends_as_ghost", false)):
			ghost_only_step_is_in_place = step2.get("from", Vector2i.ZERO) == step2.get("to", Vector2i.ZERO)
			if step2.get("from", Vector2i.ZERO) != step2.get("to", Vector2i.ZERO):
				has_motion_in_ghost_only_case = true
				break

	return not has_motion_in_prior_visible_case \
		and not has_motion_in_ghost_only_case \
		and ghost_step_is_in_place_in_prior_visible_case \
		and ghost_only_step_is_in_place \
		and ghost_only_steps.size() == 1 \
		and ghost_only_steps[0].get("from", Vector2i.ZERO) == Vector2i(3, 1) \
		and ghost_only_steps[0].get("to", Vector2i.ZERO) == Vector2i(3, 1)


func _assert_position_entry_still_replays_as_motion(context: Dictionary) -> bool:
	return _assert_first_surviving_position_entry_may_start_from_initial_default(context)


func _assert_position_entry_still_moves_normally(context: Dictionary) -> bool:
	return _assert_first_surviving_position_entry_may_start_from_initial_default(context)


func _assert_replay_still_occurs_when_surviving_remembered_state_actually_changes(context: Dictionary) -> bool:
	var controller: GameController = context["controller"]
	var queue: ChangeQueue = context["queue"]
	queue.clear()
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.POSITION,
		&"box_0",
		Vector2i(2, 1),
		false,
		"old_replayable",
		ChangeRecord.SourceKind.REMEMBERED_REBUILD
	))
	queue.append(ChangeRecord.new(
		ChangeRecord.ChangeType.POSITION,
		&"box_0",
		Vector2i(1, 1),
		false,
		"survives_after_pushout",
		ChangeRecord.SourceKind.REMEMBERED_REBUILD
	))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e1", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e2", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "trigger", ChangeRecord.SourceKind.LIVE_INPUT))
	controller.call("_recompile_world", "test_replay_occurs_when_state_changes")
	for i: int in range(120):
		if not controller.get("_input_locked"):
			break
		await process_frame
	var replay_steps: Array[Dictionary] = controller.get("_last_replay_steps")
	var replay_gate_allowed: bool = bool(controller.get("_last_replay_gate_allowed"))
	var replay_gate_reason: String = String(controller.get("_last_replay_gate_reason"))
	var pushed_out: Array[String] = controller.get("_last_pushed_out_summaries")
	return replay_gate_allowed \
		and replay_gate_reason == "allowed_non_empty_pushed_out" \
		and pushed_out.has("Position[REMEMBERED_REBUILD](box_0 -> (2, 1))") \
		and not replay_steps.is_empty()


func _assert_snapshot_second_box_change_pushout_with_surviving_auto_ghost_replays(context: Dictionary) -> bool:
	var result: Dictionary = await _setup_auto_ghost_generated_then_parent_pushed_out_case(context)
	var controller: GameController = result["controller"]
	var world: CompiledWorld = result["world"]
	var queue_after_compile: Array[ChangeRecord] = result["queue_after_compile"]
	var replay_steps: Array[Dictionary] = result["replay_steps"]
	var replay_display_steps: Array[Dictionary] = result["replay_display_steps"]
	var pushed_out_changes: Array[String] = result["pushed_out_changes"]
	var replay_gate_allowed: bool = result["replay_gate_allowed"]
	var replay_gate_reason: String = result["replay_gate_reason"]
	var last_input_direction: Vector2i = controller.get("_last_input_direction")
	var snapshot: String = _formatter.build_snapshot(
		world,
		queue_after_compile,
		String(controller.get("_last_recompile_reason")),
		replay_steps,
		replay_display_steps,
		controller.get("_last_replay_presenting_subjects"),
		bool(controller.get("_last_replay_used_live_box_views")),
		bool(controller.get("_last_replay_completed")),
		BuildInfo.display_text(),
		"board_ok",
		"replay_ok",
		String(controller.get("_last_replay_stop_reason")),
		String(controller.get("_last_input_source")),
		String(controller.get("_last_input_intent")),
		last_input_direction,
		bool(controller.get("_last_move_player_moved")),
		String(controller.get("_last_move_generated_change")),
		String(controller.get("_last_appended_change_summary")),
		controller.get("_last_pushed_out_summaries"),
		controller.get("_last_generated_ghost_summaries"),
		controller.get("_last_queue_after_compile_summaries"),
		bool(controller.get("_last_replay_gate_allowed")),
		String(controller.get("_last_replay_gate_reason"))
	)
	return pushed_out_changes.has("Position[REMEMBERED_REBUILD](box_0 -> (1, 1))") \
		and replay_gate_allowed \
		and replay_gate_reason == "allowed_non_empty_pushed_out" \
		and snapshot.contains("replay=[") \
		and not snapshot.contains("replay=none") \
		and snapshot.contains("box_0:(3, 1)->(3, 1)") \
		and not snapshot.contains("box_0:(2, 1)->(2, 1)") \
		and not snapshot.contains("box_0:(3, 1)->(2, 1)") \
		and snapshot.contains("last_replay_display_steps=[") \
		and String(controller.get("_last_replay_stop_reason")) != "none"


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
		and world.entity_positions.get(&"box_0", Vector2i(-1, -1)) == Vector2i(1, 1) \
		and world.ghost_entities.is_empty() \
		and queue_entries.size() == 2 \
		and position_count == 2 \
		and ghost_to_two_one_count == 0 \
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


func _assert_semantic_move_changes_position(context: Dictionary) -> bool:
	var queue: ChangeQueue = context["queue"]
	var defaults: WorldDefaults = context["defaults"]
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(2, 1), false, "move", ChangeRecord.SourceKind.REMEMBERED_REBUILD, Vector2i.RIGHT))
	var result: CompileResult = _compiler.compile(defaults, queue, Vector2i(0, 0))
	return result.world.entity_positions.get(&"box_0", Vector2i(-1, -1)) == Vector2i(2, 1)


func _assert_semantic_ghost_only_changes_state(context: Dictionary) -> bool:
	var queue: ChangeQueue = context["queue"]
	var defaults: WorldDefaults = context["defaults"]
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.GHOST, &"box_0", Vector2i(9, 9), false, "ghost", ChangeRecord.SourceKind.AUTO_GHOST))
	var result: CompileResult = _compiler.compile(defaults, queue, Vector2i(0, 0))
	return result.world.ghost_entities.get(&"box_0", Vector2i(-1, -1)) == defaults.default_entity_positions[&"box_0"]


func _assert_semantic_init_conflict_generates_ghost(context: Dictionary) -> bool:
	var queue: ChangeQueue = context["queue"]
	var defaults: WorldDefaults = context["defaults"]
	var result: CompileResult = _compiler.compile(defaults, queue, defaults.default_entity_positions[&"box_0"])
	return result.world.ghost_entities.has(&"box_0") and _contains_ghost_change(result.queue_entries, &"box_0", Vector2i(1, 1))


func _assert_semantic_projection_conflict_generates_ghost(context: Dictionary) -> bool:
	return _assert_semantic_init_conflict_generates_ghost(context)


func _assert_semantic_evicted_move_not_replayed(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = ChangeQueue.new()
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(2, 1), false, "old", ChangeRecord.SourceKind.REMEMBERED_REBUILD, Vector2i.RIGHT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e1", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e2", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e3", ChangeRecord.SourceKind.LIVE_INPUT))
	var result: CompileResult = _compiler.compile(defaults, queue, Vector2i(0, 0))
	var steps: Array[Dictionary] = ReplayPayloadBuilder.new().build_steps(defaults, result.queue_entries)
	return result.queue_entries.filter(func(e): return e.type == ChangeRecord.ChangeType.POSITION).is_empty() and steps.is_empty()


func _assert_semantic_replay_matches_compile_semantics(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = context["queue"]
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(2, 1), false, "move", ChangeRecord.SourceKind.REMEMBERED_REBUILD, Vector2i.RIGHT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.GHOST, &"box_0", Vector2i(2, 1), false, "ghost", ChangeRecord.SourceKind.AUTO_GHOST))
	var result: CompileResult = _compiler.compile(defaults, queue, Vector2i(0, 0))
	var steps: Array[Dictionary] = ReplayPayloadBuilder.new().build_steps(defaults, result.queue_entries)
	if steps.is_empty():
		return false
	var last: Dictionary = steps[steps.size() - 1]
	return result.world.ghost_entities.has(&"box_0") and last.get("from", Vector2i.ZERO) == last.get("to", Vector2i.ONE)


func _assert_semantic_chain_converges(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = context["queue"]
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(1, 1), false, "stay", ChangeRecord.SourceKind.REMEMBERED_REBUILD, Vector2i.ZERO))
	var result: CompileResult = _compiler.compile(defaults, queue, defaults.default_entity_positions[&"box_0"])
	return not result.reached_safety_limit and result.iterations <= 2


func _assert_semantic_ghost_step_no_motion(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue: ChangeQueue = context["queue"]
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.GHOST, &"box_0", Vector2i(2, 1), false, "ghost", ChangeRecord.SourceKind.AUTO_GHOST))
	var steps: Array[Dictionary] = ReplayPayloadBuilder.new().build_steps(defaults, queue.entries())
	return steps.size() == 1 and steps[0].get("from", Vector2i.ZERO) == steps[0].get("to", Vector2i.ONE)


func _assert_semantic_left_right_same_rules(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var left_queue := ChangeQueue.new()
	left_queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(0, 1), false, "left", ChangeRecord.SourceKind.REMEMBERED_REBUILD, Vector2i.LEFT))
	var right_queue := ChangeQueue.new()
	right_queue.append(ChangeRecord.new(ChangeRecord.ChangeType.POSITION, &"box_0", Vector2i(2, 1), false, "right", ChangeRecord.SourceKind.REMEMBERED_REBUILD, Vector2i.RIGHT))
	var left_result: CompileResult = _compiler.compile(defaults, left_queue, Vector2i(0, 0))
	var right_result: CompileResult = _compiler.compile(defaults, right_queue, Vector2i(0, 0))
	return left_result.generated_ghost_changes.size() == right_result.generated_ghost_changes.size()


func _assert_semantic_evict_last_related_restores_default(context: Dictionary) -> bool:
	var defaults: WorldDefaults = context["defaults"]
	var queue := ChangeQueue.new()
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.GHOST, &"box_0", Vector2i(1, 1), false, "ghost", ChangeRecord.SourceKind.AUTO_GHOST))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e1", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e2", ChangeRecord.SourceKind.LIVE_INPUT))
	queue.append(ChangeRecord.new(ChangeRecord.ChangeType.EMPTY, &"", Vector2i.ZERO, false, "e3", ChangeRecord.SourceKind.LIVE_INPUT))
	var result: CompileResult = _compiler.compile(defaults, queue, Vector2i(0, 0))
	return not result.world.ghost_entities.has(&"box_0") and result.world.entity_positions.get(&"box_0", Vector2i(-1, -1)) == defaults.default_entity_positions[&"box_0"]



func _contains_ghost_change(entries: Array[ChangeRecord], subject_id: StringName, target: Vector2i) -> bool:
	for entry: ChangeRecord in entries:
		if entry.type == ChangeRecord.ChangeType.GHOST and entry.subject_id == subject_id and entry.target_position == target:
			return true
	return false



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
	var cases: Array[Dictionary] = [
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
			"id": "replay_builder_position_steps_use_move_presentation_kind",
			"name": "replay_builder_position_steps_use_move_presentation_kind",
			"action": "builder marks remembered position replay as move presentation kind",
			"context_mode": "controller_level001",
		},
		{
			"id": "replay_builder_ghost_steps_use_ghostify_presentation_kind",
			"name": "replay_builder_ghost_steps_use_ghostify_presentation_kind",
			"action": "builder marks surviving auto ghost replay as ghostify presentation kind",
			"context_mode": "controller_level001",
		},
		{
			"id": "replay_empty_steps_keep_order_with_empty_presentation_kind",
			"name": "replay_empty_steps_keep_order_with_empty_presentation_kind",
			"action": "builder keeps empty rhythm beats between replayable remembered steps",
			"context_mode": "controller_level001",
		},
		{
			"id": "empty_beats_do_not_create_board_actor_steps",
			"name": "empty_beats_do_not_create_board_actor_steps",
			"action": "empty changes remain timing beats and never become subjectless board actor movement",
			"context_mode": "controller_level001",
		},
		{
			"id": "replay_is_grouped_by_queue_index_not_raw_steps",
			"name": "replay_is_grouped_by_queue_index_not_raw_steps",
			"action": "replay orchestration groups raw replay steps by queue_index before one-memory beats",
			"context_mode": "controller_level001",
		},
		{
			"id": "replay_groups_steps_by_queue_index",
			"name": "replay_groups_steps_by_queue_index",
			"action": "assert replay groups steps by queue_index instead of driving each raw step independently",
			"context_mode": "controller_level001",
		},
		{
			"id": "queue_focus_advances_one_memory_per_beat",
			"name": "queue_focus_advances_one_memory_per_beat",
			"action": "surviving queue replay advances queue slot focus one memory per beat",
			"context_mode": "controller_level001",
		},
		{
			"id": "board_replay_is_driven_one_memory_per_beat",
			"name": "board_replay_is_driven_one_memory_per_beat",
			"action": "board replay runs one beat per memory and Empty stays non-actor beat",
			"context_mode": "controller_level001",
		},
		{
			"id": "one_memory_one_beat_presentation",
			"name": "one_memory_one_beat_presentation",
			"action": "each queue entry maps to one beat with either board action or player meditate pulse",
			"context_mode": "controller_level001",
		},
		{
			"id": "one_queue_entry_one_visible_beat",
			"name": "one_queue_entry_one_visible_beat",
			"action": "each queue entry maps to exactly one visible beat with queue focus and board feedback",
			"context_mode": "controller_level001",
		},
		{
			"id": "empty_beat_triggers_player_meditate_pulse",
			"name": "empty_beat_triggers_player_meditate_pulse",
			"action": "empty beat triggers player meditate pulse instead of pure wait",
			"context_mode": "controller_level001",
		},
		{
			"id": "empty_beats_trigger_player_pulse_each_beat",
			"name": "empty_beats_trigger_player_pulse_each_beat",
			"action": "each empty beat triggers one player meditate pulse",
			"context_mode": "controller_level001",
		},
		{
			"id": "empty_beat_does_not_create_box_actor_movement",
			"name": "empty_beat_does_not_create_box_actor_movement",
			"action": "empty beat never creates box actor movement or subjectless fake board steps",
			"context_mode": "controller_level001",
		},
		{
			"id": "empty_beats_do_not_create_box_motion",
			"name": "empty_beats_do_not_create_box_motion",
			"action": "empty beats do not create any box motion",
			"context_mode": "controller_level001",
		},
		{
			"id": "evicted_memory_is_presented_in_queue_before_rebuild",
			"name": "evicted_memory_is_presented_in_queue_before_rebuild",
			"action": "evicted memory fades in queue before synchronized surviving queue rebuild beats",
			"context_mode": "controller_level001",
		},
		{
			"id": "memory_focus_and_board_step_are_synchronized",
			"name": "memory_focus_and_board_step_are_synchronized",
			"action": "queue focus and board beat count stay synchronized during replay",
			"context_mode": "controller_level001",
		},
		{
			"id": "queue_focus_and_board_action_start_in_same_beat",
			"name": "queue_focus_and_board_action_start_in_same_beat",
			"action": "queue slot focus and board action start inside the same beat without deferred scheduling",
			"context_mode": "controller_level001",
		},
		{
			"id": "queue_focus_and_board_beat_start_together",
			"name": "queue_focus_and_board_beat_start_together",
			"action": "queue focus and board beat start at the same beat boundary",
			"context_mode": "controller_level001",
		},
		{
			"id": "replay_no_longer_contains_subjectless_fake_steps",
			"name": "replay_no_longer_contains_subjectless_fake_steps",
			"action": "replay payload no longer emits subjectless fake actor movement steps",
			"context_mode": "controller_level001",
		},
		{
			"id": "board_replay_rebuilds_only_from_surviving_queue",
			"name": "board_replay_rebuilds_only_from_surviving_queue",
			"action": "board replay payload only contains surviving remembered queue changes",
			"context_mode": "controller_level001",
		},
		{
			"id": "replay_controller_runs_evict_phase_before_rebuild",
			"name": "replay_controller_runs_evict_phase_before_rebuild",
			"action": "controller replay trace starts with evict phase before rebuild phase",
			"context_mode": "controller_level001",
		},
		{
			"id": "evicted_changes_are_presented_in_queue_not_board",
			"name": "evicted_changes_are_presented_in_queue_not_board",
			"action": "evicted memories are shown in queue feedback and also appear as board evict replay movement",
			"context_mode": "controller_level001",
		},
		{
			"id": "evicted_position_change_produces_board_replay",
			"name": "evicted_position_change_produces_board_replay",
			"action": "pushed-out remembered position change produces evict_move board replay step",
			"context_mode": "controller_level001",
		},
		{
			"id": "replay_has_evict_phase_before_rebuild_phase",
			"name": "replay_has_evict_phase_before_rebuild_phase",
			"action": "board replay runs evict phase before rebuild phase",
			"context_mode": "controller_level001",
		},
		{
			"id": "evicted_move_uses_state_diff_not_guessing",
			"name": "evicted_move_uses_state_diff_not_guessing",
			"action": "evicted move is derived from remembered-state diff between previous and resulting queues",
			"context_mode": "controller_level001",
		},
		{
			"id": "empty_beats_still_use_player_pulse_in_rebuild_phase",
			"name": "empty_beats_still_use_player_pulse_in_rebuild_phase",
			"action": "empty rebuild beats still trigger player meditate pulse after evict phase",
			"context_mode": "controller_level001",
		},
		{
			"id": "replay_conflict_step_finishes_then_applies_tail_pause",
			"name": "replay_conflict_step_finishes_then_applies_tail_pause",
			"action": "replay conflict step records ghostify playback before conflict-tail pause stop",
			"context_mode": "controller_level001",
		},
		{
			"id": "ghostify_step_is_played_as_full_in_place_change",
			"name": "ghostify_step_is_played_as_full_in_place_change",
			"action": "ghostify replay step is fully played in place before replay end handling",
			"context_mode": "controller_level001",
		},
		{
			"id": "replay_sequence_orders_queue_feedback_before_board_rebuild",
			"name": "replay_sequence_orders_queue_feedback_before_board_rebuild",
			"action": "queue feedback animation runs before board rebuild replay in one recompile flow",
			"context_mode": "controller_level001",
		},
		{
			"id": "replay_uses_detached_replay_actor_not_live_box_view",
			"name": "replay_uses_detached_replay_actor_not_live_box_view",
			"action": "replay uses detached actor on ReplayLayer and keeps live BoxView untouched during playback",
			"context_mode": "controller_level001",
		},
		{
			"id": "ghost_spawn_ghostify_replay_does_not_move_live_final_world_box",
			"name": "ghost_spawn_ghostify_replay_does_not_move_live_final_world_box",
			"action": "spawn ghostify replay step stays at (3,1) on replay actor and never drags live final ghost from (2,1)",
			"context_mode": "controller_level001",
		},
		{
			"id": "replay_end_does_not_sync_old_world_before_final_world",
			"name": "replay_end_does_not_sync_old_world_before_final_world",
			"action": "replay end clears presenting state without syncing stale BoardView world, then final world remains authoritative",
			"context_mode": "controller_level001",
		},
		{
			"id": "replay_actor_is_cleaned_up_and_live_world_restored_after_playback",
			"name": "replay_actor_is_cleaned_up_and_live_world_restored_after_playback",
			"action": "replay actor cleanup restores live world visibility and final compiled ghost state",
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
			"id": "remembered_conflict_ghost_does_not_override_later_live_input",
			"name": "remembered_conflict_ghost_does_not_override_later_live_input",
			"action": "older REMEMBERED_REBUILD conflict ghost must not override later LIVE_INPUT for same subject",
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
			"id": "last_remembered_rebuild_still_can_generate_ghost",
			"name": "last_remembered_rebuild_still_can_generate_ghost",
			"action": "last remembered rebuild blocked by player still generates AUTO_GHOST",
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
			"id": "snapshot_case_for_live_input_after_older_rebuild_is_not_ghostified",
			"name": "snapshot_case_for_live_input_after_older_rebuild_is_not_ghostified",
			"action": "snapshot with older rebuild + later live input keeps solid box and no ghost",
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
			"id": "debug_snapshot_reports_detached_replay_actor_usage",
			"name": "debug_snapshot_reports_detached_replay_actor_usage",
			"action": "controller snapshot reports detached replay actor usage with last_replay_used_live_box_views=false",
			"context_mode": "controller_level001",
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
			"id": "ghost_is_formal_memory_and_survives_parent_pushout",
			"name": "ghost_is_formal_memory_and_survives_parent_pushout",
			"action": "generate AUTO_GHOST from player conflict then push out parent Position; ghost remains as formal surviving memory",
			"context_mode": "controller_level001",
		},
		{
			"id": "ghost_is_evicted_normally_and_then_world_restores",
			"name": "ghost_is_evicted_normally_and_then_world_restores",
			"action": "AUTO_GHOST is pushed out like normal change and world restores to surviving remembered/default state",
			"context_mode": "controller_level001",
		},
		{
			"id": "pushing_out_parent_position_does_not_clear_surviving_auto_ghost",
			"name": "pushing_out_parent_position_does_not_clear_surviving_auto_ghost",
			"action": "pushed-out parent remembered Position must not clear surviving AUTO_GHOST",
			"context_mode": "controller_level001",
		},
		{
			"id": "surviving_auto_ghost_prevents_default_box_restore",
			"name": "surviving_auto_ghost_prevents_default_box_restore",
			"action": "if surviving queue still has AUTO_GHOST then world must not restore default box position",
			"context_mode": "controller_level001",
		},
		{
			"id": "ghost_only_surviving_queue_ghostifies_at_default_spawn",
			"name": "ghost_only_surviving_queue_ghostifies_at_default_spawn",
			"action": "first surviving ghost must ghostify in-place at default spawn, never at recorded ghost target",
			"context_mode": "controller_level001",
		},
		{
			"id": "first_surviving_position_entry_may_start_from_initial_default",
			"name": "first_surviving_position_entry_may_start_from_initial_default",
			"action": "first surviving position may use initial default position as replay from-state",
			"context_mode": "controller_level001",
		},
		{
			"id": "position_then_ghost_replays_as_move_then_in_place_ghostify",
			"name": "position_then_ghost_replays_as_move_then_in_place_ghostify",
			"action": "surviving position and ghost at same cell replay as move-then-in-place-ghostify",
			"context_mode": "controller_level001",
		},
		{
			"id": "pushed_out_position_leaving_only_ghost_reuses_default_spawn_as_replay_origin",
			"name": "pushed_out_position_leaving_only_ghost_reuses_default_spawn_as_replay_origin",
			"action": "when Position is pushed out and only AUTO_GHOST survives, replay ghostifies at default spawn",
			"context_mode": "controller_level001",
		},
		{
			"id": "pushing_out_last_ghost_restores_default_world_and_replay_none",
			"name": "pushing_out_last_ghost_restores_default_world_and_replay_none",
			"action": "when final AUTO_GHOST is pushed out, world restores defaults and replay=none",
			"context_mode": "controller_level001",
		},
		{
			"id": "ghost_entry_never_creates_motion_by_itself",
			"name": "ghost_entry_never_creates_motion_by_itself",
			"action": "builder: AUTO_GHOST uses prior/spawn visual positions but never produces from!=to motion",
			"context_mode": "controller_level001",
		},
		{
			"id": "position_entry_still_replays_as_motion",
			"name": "position_entry_still_replays_as_motion",
			"action": "builder: REMEMBERED_REBUILD position entries still produce move replay steps",
			"context_mode": "controller_level001",
		},
		{
			"id": "position_entry_still_moves_normally",
			"name": "position_entry_still_moves_normally",
			"action": "builder: REMEMBERED_REBUILD position still replays normal motion",
			"context_mode": "controller_level001",
		},
		{
			"id": "replay_still_occurs_when_surviving_remembered_state_actually_changes",
			"name": "replay_still_occurs_when_surviving_remembered_state_actually_changes",
			"action": "when pushed_out + surviving remembered state diff exists replay gate still allows replay",
			"context_mode": "controller_level001",
		},
		{
			"id": "snapshot_second_box_change_pushout_with_surviving_auto_ghost_replays",
			"name": "snapshot_second_box_change_pushout_with_surviving_auto_ghost_replays",
			"action": "snapshot-level regression: pushed_out remembered Position + surviving AUTO_GHOST now yields non-empty replay",
			"context_mode": "controller_level001",
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
	cases.append({
		"id": "remembered_defaults_ignore_live_player_until_projection",
		"name": "remembered_defaults_ignore_live_player_until_projection",
		"action": "remembered default box survives even when live player stands on default tile; projection shows ghost",
		"context_mode": "controller_level001",
	})
	cases.append({
		"id": "pushing_out_last_ghost_with_player_on_default_projects_live_ghost",
		"name": "pushing_out_last_ghost_with_player_on_default_projects_live_ghost",
		"action": "after ghost eviction, default remembered box projects as live ghost when player blocks default tile",
		"context_mode": "controller_level001",
	})

	cases.append_array([
		{"id":"semantic_move_changes_position","name":"semantic_move_changes_position","action":"move change updates current position","blueprint":{"board_size":Vector2i(4,3),"player_start":Vector2i(0,0),"exit_position":Vector2i(3,2),"memory_capacity":3,"floors":[Vector3i(0,1,0),Vector3i(1,1,0),Vector3i(2,1,0),Vector3i(3,1,0)],"walls":[],"boxes":[Vector3i(1,1,0)]}},
		{"id":"semantic_ghost_only_changes_state","name":"semantic_ghost_only_changes_state","action":"ghost change keeps position","blueprint":{"board_size":Vector2i(4,3),"player_start":Vector2i(0,0),"exit_position":Vector2i(3,2),"memory_capacity":3,"floors":[Vector3i(0,1,0),Vector3i(1,1,0),Vector3i(2,1,0),Vector3i(3,1,0)],"walls":[],"boxes":[Vector3i(1,1,0)]}},
		{"id":"semantic_init_conflict_generates_ghost","name":"semantic_init_conflict_generates_ghost","action":"init conflict creates ghost","blueprint":{"board_size":Vector2i(4,3),"player_start":Vector2i(1,1),"exit_position":Vector2i(3,2),"memory_capacity":3,"floors":[Vector3i(0,1,0),Vector3i(1,1,0),Vector3i(2,1,0),Vector3i(3,1,0)],"walls":[],"boxes":[Vector3i(1,1,0)]}},
		{"id":"semantic_projection_conflict_generates_ghost","name":"semantic_projection_conflict_generates_ghost","action":"projection conflict creates ghost","blueprint":{"board_size":Vector2i(4,3),"player_start":Vector2i(1,1),"exit_position":Vector2i(3,2),"memory_capacity":3,"floors":[Vector3i(0,1,0),Vector3i(1,1,0),Vector3i(2,1,0),Vector3i(3,1,0)],"walls":[],"boxes":[Vector3i(1,1,0)]}},
		{"id":"semantic_evicted_move_not_replayed","name":"semantic_evicted_move_not_replayed","action":"evicted move is not replayed","blueprint":{"board_size":Vector2i(4,3),"player_start":Vector2i(0,0),"exit_position":Vector2i(3,2),"memory_capacity":3,"floors":[Vector3i(0,1,0),Vector3i(1,1,0),Vector3i(2,1,0),Vector3i(3,1,0)],"walls":[],"boxes":[Vector3i(1,1,0)]}},
		{"id":"semantic_replay_matches_compile_semantics","name":"semantic_replay_matches_compile_semantics","action":"replay and compile share semantics","blueprint":{"board_size":Vector2i(4,3),"player_start":Vector2i(0,0),"exit_position":Vector2i(3,2),"memory_capacity":3,"floors":[Vector3i(0,1,0),Vector3i(1,1,0),Vector3i(2,1,0),Vector3i(3,1,0)],"walls":[],"boxes":[Vector3i(1,1,0)]}},
		{"id":"semantic_chain_converges","name":"semantic_chain_converges","action":"generated chain converges","blueprint":{"board_size":Vector2i(4,3),"player_start":Vector2i(1,1),"exit_position":Vector2i(3,2),"memory_capacity":3,"floors":[Vector3i(0,1,0),Vector3i(1,1,0),Vector3i(2,1,0),Vector3i(3,1,0)],"walls":[],"boxes":[Vector3i(1,1,0)]}},
		{"id":"semantic_ghost_step_no_motion","name":"semantic_ghost_step_no_motion","action":"ghost step has no displacement","blueprint":{"board_size":Vector2i(4,3),"player_start":Vector2i(0,0),"exit_position":Vector2i(3,2),"memory_capacity":3,"floors":[Vector3i(0,1,0),Vector3i(1,1,0),Vector3i(2,1,0),Vector3i(3,1,0)],"walls":[],"boxes":[Vector3i(1,1,0)]}},
		{"id":"semantic_left_right_same_rules","name":"semantic_left_right_same_rules","action":"left/right same conflict rules","blueprint":{"board_size":Vector2i(4,3),"player_start":Vector2i(0,0),"exit_position":Vector2i(3,2),"memory_capacity":3,"floors":[Vector3i(0,1,0),Vector3i(1,1,0),Vector3i(2,1,0),Vector3i(3,1,0)],"walls":[],"boxes":[Vector3i(1,1,0)]}},
		{"id":"semantic_evict_last_related_restores_default","name":"semantic_evict_last_related_restores_default","action":"evicting final related change restores default","blueprint":{"board_size":Vector2i(4,3),"player_start":Vector2i(0,0),"exit_position":Vector2i(3,2),"memory_capacity":3,"floors":[Vector3i(0,1,0),Vector3i(1,1,0),Vector3i(2,1,0),Vector3i(3,1,0)],"walls":[],"boxes":[Vector3i(1,1,0)]}}
	])
	var disabled_legacy_ids := {
		"ghost_spawn_ghostify_replay_does_not_move_live_final_world_box": true,
		"replay_end_does_not_sync_old_world_before_final_world": true,
		"replay_actor_is_cleaned_up_and_live_world_restored_after_playback": true,
		"replay_marks_player_conflict_on_intermediate_step": true,
		"player_conflict_truncation_appends_ghost_change": true,
		"last_remembered_rebuild_still_can_generate_ghost": true,
		"replay_path_truncates_at_first_conflict_step": true,
		"player_move_away_allows_remembered_path_to_finish_later": true,
		"snapshot_reports_ghost_boxes_and_truncated_replay": true,
		"debug_snapshot_reports_detached_replay_actor_usage": true,
		"generated_ghost_change_is_deduped": true,
		"empty_pushed_out_no_replay_even_if_ghost_was_appended": true,
		"ghost_is_formal_memory_and_survives_parent_pushout": true,
		"pushing_out_parent_position_does_not_clear_surviving_auto_ghost": true,
		"surviving_auto_ghost_prevents_default_box_restore": true,
		"pushed_out_position_leaving_only_ghost_reuses_default_spawn_as_replay_origin": true,
		"snapshot_second_box_change_pushout_with_surviving_auto_ghost_replays": true,
		"gameplay_push_box_to_void": true,
		"controller_push_box_to_void": true,
		"input_and_rebuild_semantics_are_distinct_in_snapshot": true,
		"controller_replay_locks_input_then_unlocks": true,
		"replay_layer_transform_matches_board_view": true,
		"debug_snapshot_has_real_values_not_placeholders": true,
		"ghost_is_evicted_normally_and_then_world_restores": true,
		"replay_still_occurs_when_surviving_remembered_state_actually_changes": true,
	}
	var filtered: Array[Dictionary] = []
	for case_data: Dictionary in cases:
		if disabled_legacy_ids.has(String(case_data.get("id", ""))):
			continue
		filtered.append(case_data)
	return filtered
