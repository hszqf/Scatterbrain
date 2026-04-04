class_name ChangeRecord
extends RefCounted

## Immutable record for one remembered world change.
enum ChangeType {
	POSITION,
	EMPTY,
	GHOST,
}

var type: ChangeType
var subject_id: StringName
var target_position: Vector2i
var pinned: bool
var debug_label: String

func _init(
	p_type: ChangeType,
	p_subject_id: StringName = &"",
	p_target_position: Vector2i = Vector2i.ZERO,
	p_pinned: bool = false,
	p_debug_label: String = ""
) -> void:
	type = p_type
	subject_id = p_subject_id
	target_position = p_target_position
	pinned = p_pinned
	debug_label = p_debug_label


func summary() -> String:
	match type:
		ChangeType.POSITION:
			return "Position(%s -> %s)" % [subject_id, target_position]
		ChangeType.EMPTY:
			return "Empty"
		ChangeType.GHOST:
			return "Ghost(%s -> %s)" % [subject_id, target_position]
		_:
			return "Unknown"
