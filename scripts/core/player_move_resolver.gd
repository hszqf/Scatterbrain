class_name PlayerMoveResolver
extends RefCounted

## Resolves one player movement intent against current compiled world.
func resolve_move(world: CompiledWorld, direction: Vector2i) -> Dictionary:
	var result: Dictionary = {
		"player_moved": false,
		"change": null,
		"reason": "blocked",
	}

	if direction == Vector2i.ZERO:
		result["reason"] = "no_direction"
		return result

	var target: Vector2i = world.player_position + direction
	if not world.is_inside(target):
		result["reason"] = "target_outside"
		return result
	if not world.has_floor_at(target):
		result["reason"] = "target_no_floor"
		return result
	if world.has_wall_at(target):
		result["reason"] = "target_wall"
		return result

	var box_id: StringName = _find_solid_box_at(world, target)
	if box_id == &"":
		world.player_position = target
		result["player_moved"] = true
		result["reason"] = "walk"
		return result

	var push_target: Vector2i = target + direction
	if not world.is_inside(push_target):
		result["reason"] = "push_outside"
		return result
	if world.has_wall_at(push_target):
		result["reason"] = "push_wall"
		return result
	if _find_solid_box_at(world, push_target) != &"":
		result["reason"] = "push_box"
		return result

	world.player_position = target
	result["player_moved"] = true
	if world.has_floor_at(push_target):
		world.entity_positions[box_id] = push_target
		result["change"] = ChangeRecord.new(
			ChangeRecord.ChangeType.POSITION,
			box_id,
			push_target,
			false,
			"push",
			ChangeRecord.SourceKind.LIVE_INPUT,
			direction
		)
		result["reason"] = "push_success"
		return result

	world.entity_positions.erase(box_id)
	result["change"] = ChangeRecord.new(
		ChangeRecord.ChangeType.POSITION,
		box_id,
		push_target,
		false,
		"push_fall",
		ChangeRecord.SourceKind.LIVE_INPUT,
		direction
	)
	result["reason"] = "push_fall"
	return result


func _find_solid_box_at(world: CompiledWorld, pos: Vector2i) -> StringName:
	for entity_id: StringName in world.entity_positions.keys():
		if world.entity_positions[entity_id] == pos:
			return entity_id
	return &""
