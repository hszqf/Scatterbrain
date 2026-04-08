class_name SimulationState
extends RefCounted

var defaults: WorldDefaults
var player_position: Vector2i
var exists_by_subject: Dictionary[StringName, bool] = {}
var position_by_subject: Dictionary[StringName, Vector2i] = {}
var is_ghost_by_subject: Dictionary[StringName, bool] = {}


func setup_from_defaults(p_defaults: WorldDefaults, p_player_position: Vector2i) -> void:
	defaults = p_defaults
	player_position = p_player_position
	exists_by_subject.clear()
	position_by_subject.clear()
	is_ghost_by_subject.clear()
	for subject_id: StringName in defaults.default_entity_positions.keys():
		exists_by_subject[subject_id] = true
		position_by_subject[subject_id] = defaults.default_entity_positions[subject_id]
		is_ghost_by_subject[subject_id] = false


func ensure_subject(subject_id: StringName) -> void:
	if exists_by_subject.has(subject_id):
		return
	if defaults != null and defaults.default_entity_positions.has(subject_id):
		exists_by_subject[subject_id] = true
		position_by_subject[subject_id] = defaults.default_entity_positions[subject_id]
		is_ghost_by_subject[subject_id] = false


func subject_exists(subject_id: StringName) -> bool:
	return bool(exists_by_subject.get(subject_id, false))


func subject_position(subject_id: StringName) -> Vector2i:
	return position_by_subject.get(subject_id, Vector2i.ZERO)


func set_subject_position(subject_id: StringName, position: Vector2i) -> void:
	exists_by_subject[subject_id] = true
	position_by_subject[subject_id] = position


func set_subject_ghost(subject_id: StringName, is_ghost: bool) -> void:
	if not subject_exists(subject_id):
		return
	is_ghost_by_subject[subject_id] = is_ghost


func build_world() -> CompiledWorld:
	var world := CompiledWorld.new()
	world.board_size = defaults.board_size
	world.player_position = player_position
	world.exit_position = defaults.exit_position
	for floor_pos: Vector2i in defaults.floor_cells:
		world.floor_cells[floor_pos] = true
	for wall_pos: Vector2i in defaults.wall_positions:
		world.wall_positions[wall_pos] = true

	var ordered_subjects: Array[StringName] = []
	for subject_id_variant: Variant in position_by_subject.keys():
		ordered_subjects.append(subject_id_variant)
	ordered_subjects.sort()
	for subject_id: StringName in ordered_subjects:
		if not bool(exists_by_subject.get(subject_id, false)):
			continue
		var pos: Vector2i = position_by_subject[subject_id]
		if bool(is_ghost_by_subject.get(subject_id, false)):
			world.ghost_entities[subject_id] = pos
		else:
			world.entity_positions[subject_id] = pos
	return world
