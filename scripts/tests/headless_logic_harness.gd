extends SceneTree

const EXIT_OK: int = 0
const EXIT_FAIL: int = 1
const LEVEL_ROOT_SCENE: PackedScene = preload("res://scenes/levels/LevelRoot.tscn")

var _compiler: WorldCompiler = WorldCompiler.new()
var _resolver: PlayerMoveResolver = PlayerMoveResolver.new()


func _init() -> void:
	var cases: Array[Dictionary] = _build_cases()
	var failed: int = 0
	for case_data: Dictionary in cases:
		if not _run_case(case_data):
			failed += 1

	print("==== LOGIC HARNESS SUMMARY ====")
	print("total=%d pass=%d fail=%d" % [cases.size(), cases.size() - failed, failed])
	quit(EXIT_OK if failed == 0 else EXIT_FAIL)


func _run_case(case_data: Dictionary) -> bool:
	var context: Dictionary = _build_context(case_data["blueprint"])
	print("=== CASE: %s ===" % case_data["name"])
	print("initial state: %s" % _format_state(context["world"], context["queue"], context["runtime_data"], context["defaults"]))
	print("action: %s" % case_data["action"])

	var passed: bool = false
	match case_data["id"]:
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
		_:
			push_error("Unknown case id: %s" % case_data["id"])
			passed = false

	print("final state: %s" % _format_state(context["world"], context["queue"], context["runtime_data"], context["defaults"]))
	print("queue state: %s" % _format_queue(context["queue"].entries()))
	print("result: %s" % ("PASS" if passed else "FAIL"))
	print("")
	return passed


func _build_context(blueprint: Dictionary) -> Dictionary:
	var level_root: LevelRoot = LEVEL_ROOT_SCENE.instantiate()
	get_root().add_child(level_root)
	level_root.auto_rebuild_in_editor = false
	level_root.grid_size = Vector3i(blueprint["board_size"].x, blueprint["board_size"].y, 1)
	level_root.memory_capacity = 8

	var grid: Node = level_root.get_node("Grid")
	level_root.set("_grid", grid)
	var slice := Node2D.new()
	slice.name = "Slice_0"
	grid.add_child(slice)

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
	]
