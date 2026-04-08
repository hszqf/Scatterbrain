class_name ChangeRecord
extends RefCounted

## Immutable record for one remembered world change.
enum ChangeType {
	POSITION,
	EMPTY,
	GHOST,
}

enum SourceKind {
	LIVE_INPUT,
	REMEMBERED_REBUILD,
	AUTO_GHOST,
}

var type: ChangeType
var subject_id: StringName
var target_position: Vector2i
var move_delta: Vector2i
var pinned: bool
var debug_label: String
var source_kind: SourceKind

func _init(
	p_type: ChangeType,
	p_subject_id: StringName = &"",
	p_target_position: Vector2i = Vector2i.ZERO,
	p_pinned: bool = false,
	p_debug_label: String = "",
	p_source_kind: SourceKind = SourceKind.REMEMBERED_REBUILD,
	p_move_delta: Vector2i = Vector2i.ZERO
) -> void:
	type = p_type
	subject_id = p_subject_id
	target_position = p_target_position
	move_delta = p_move_delta
	pinned = p_pinned
	debug_label = p_debug_label
	source_kind = p_source_kind


func summary() -> String:
	var source_tag: String = _source_kind_label(source_kind)
	match type:
		ChangeType.POSITION:
			return "Position[%s](%s Δ%s; target=%s)" % [source_tag, subject_id, move_delta, target_position]
		ChangeType.EMPTY:
			return "Empty[%s]" % source_tag
		ChangeType.GHOST:
			return "Ghost[%s](%s ghostify_at_current; source_target=%s)" % [source_tag, subject_id, target_position]
		_:
			return "Unknown"


func with_source_kind(p_source_kind: SourceKind) -> ChangeRecord:
	return ChangeRecord.new(type, subject_id, target_position, pinned, debug_label, p_source_kind, move_delta)


func with_move_delta(p_move_delta: Vector2i) -> ChangeRecord:
	return ChangeRecord.new(type, subject_id, target_position, pinned, debug_label, source_kind, p_move_delta)


func _source_kind_label(kind: SourceKind) -> String:
	match kind:
		SourceKind.LIVE_INPUT:
			return "LIVE_INPUT"
		SourceKind.REMEMBERED_REBUILD:
			return "REMEMBERED_REBUILD"
		SourceKind.AUTO_GHOST:
			return "AUTO_GHOST"
		_:
			return "UNKNOWN"
