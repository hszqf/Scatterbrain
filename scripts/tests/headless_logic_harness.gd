extends SceneTree

const EXIT_OK: int = 0
const EXIT_FAIL: int = 1

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
	var defaults: WorldDefaults = _build_defaults(case_data)
	var queue: ChangeQueue = ChangeQueue.new()
	var world: CompiledWorld = _build_world(defaults, case_data["player_start"])

	print("=== CASE: %s ===" % case_data["name"])
	print("initial state: %s" % _format_state(world, queue))
	print("action: move %s" % case_data["action"])

	var resolution: Dictionary = _resolver.resolve_move(world, case_data["action"])
	var change: ChangeRecord = resolution["change"]
	if change != null:
		queue.append(change)
		var compiled: CompileResult = _compiler.compile(defaults, queue, world.player_position)
		world = compiled.world
		queue.clear()
		for entry: ChangeRecord in compiled.queue_entries:
			queue.append(entry)

	print("final state: %s" % _format_state(world, queue))
	var passed: bool = _matches_expected(world, case_data["expect"])
	print("result: %s" % ("PASS" if passed else "FAIL"))
	if not passed:
		print("expected: %s" % case_data["expect"])
	print("")
	return passed


func _build_defaults(case_data: Dictionary) -> WorldDefaults:
	var defaults := WorldDefaults.new()
	defaults.board_size = case_data["board_size"]
	defaults.player_start = case_data["player_start"]
	defaults.exit_position = Vector2i(0, 0)
	defaults.memory_capacity = 8
	defaults.obsession_capacity = 0
	for floor_pos: Vector2i in case_data["floors"]:
		defaults.floor_cells.append(floor_pos)
	for wall_pos: Vector2i in case_data["walls"]:
		defaults.wall_positions.append(wall_pos)
	defaults.default_entity_positions = _build_box_dictionary(case_data["boxes"])
	return defaults


func _build_world(defaults: WorldDefaults, player_start: Vector2i) -> CompiledWorld:
	var world := CompiledWorld.new()
	world.board_size = defaults.board_size
	world.player_position = player_start
	world.exit_position = defaults.exit_position
	for floor_pos: Vector2i in defaults.floor_cells:
		world.floor_cells[floor_pos] = true
	for wall_pos: Vector2i in defaults.wall_positions:
		world.wall_positions[wall_pos] = true
	world.entity_positions = defaults.default_entity_positions.duplicate()
	return world


func _build_box_dictionary(box_positions: Array) -> Dictionary[StringName, Vector2i]:
	var boxes: Dictionary[StringName, Vector2i] = {}
	for i: int in range(box_positions.size()):
		boxes[StringName("box_%d" % i)] = box_positions[i]
	return boxes


func _matches_expected(world: CompiledWorld, expect: Dictionary) -> bool:
	if world.player_position != expect["player"]:
		return false
	var actual_boxes: Array[Vector2i] = _sorted_vec2_array(world.entity_positions.values())
	var expected_boxes: Array[Vector2i] = _sorted_vec2_array(expect["boxes"])
	return actual_boxes == expected_boxes


func _format_state(world: CompiledWorld, queue: ChangeQueue) -> String:
	return "player=%s boxes=%s walls=%s floors=%s queue=%s" % [
		world.player_position,
		_sorted_vec2_array(world.entity_positions.values()),
		_sorted_vec2_array(world.wall_positions.keys()),
		_sorted_vec2_array(world.floor_cells.keys()),
		_format_queue(queue.entries()),
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


func _build_cases() -> Array[Dictionary]:
	var floors_full: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	return [
		{
			"name": "move_to_empty_floor_success",
			"board_size": Vector2i(3, 1),
			"player_start": Vector2i(0, 0),
			"floors": floors_full,
			"walls": [],
			"boxes": [],
			"action": Vector2i.RIGHT,
			"expect": {"player": Vector2i(1, 0), "boxes": []},
		},
		{
			"name": "move_blocked_by_wall",
			"board_size": Vector2i(3, 1),
			"player_start": Vector2i(0, 0),
			"floors": floors_full,
			"walls": [Vector2i(1, 0)],
			"boxes": [],
			"action": Vector2i.RIGHT,
			"expect": {"player": Vector2i(0, 0), "boxes": []},
		},
		{
			"name": "move_blocked_by_no_floor",
			"board_size": Vector2i(3, 1),
			"player_start": Vector2i(0, 0),
			"floors": [Vector2i(0, 0), Vector2i(2, 0)],
			"walls": [],
			"boxes": [],
			"action": Vector2i.RIGHT,
			"expect": {"player": Vector2i(0, 0), "boxes": []},
		},
		{
			"name": "push_box_success",
			"board_size": Vector2i(3, 1),
			"player_start": Vector2i(0, 0),
			"floors": floors_full,
			"walls": [],
			"boxes": [Vector2i(1, 0)],
			"action": Vector2i.RIGHT,
			"expect": {"player": Vector2i(1, 0), "boxes": [Vector2i(2, 0)]},
		},
		{
			"name": "push_box_blocked_by_wall",
			"board_size": Vector2i(3, 1),
			"player_start": Vector2i(0, 0),
			"floors": floors_full,
			"walls": [Vector2i(2, 0)],
			"boxes": [Vector2i(1, 0)],
			"action": Vector2i.RIGHT,
			"expect": {"player": Vector2i(0, 0), "boxes": [Vector2i(1, 0)]},
		},
		{
			"name": "push_box_into_void_box_disappears",
			"board_size": Vector2i(3, 1),
			"player_start": Vector2i(0, 0),
			"floors": [Vector2i(0, 0), Vector2i(1, 0)],
			"walls": [],
			"boxes": [Vector2i(1, 0)],
			"action": Vector2i.RIGHT,
			"expect": {"player": Vector2i(1, 0), "boxes": []},
		},
	]
