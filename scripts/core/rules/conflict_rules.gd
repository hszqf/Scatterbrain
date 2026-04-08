class_name ConflictRules
extends RefCounted


static func ghostify_change(subject_id: StringName, source_position: Vector2i, label: String = "auto_ghost") -> ChangeRecord:
	return ChangeRecord.new(
		ChangeRecord.ChangeType.GHOST,
		subject_id,
		source_position,
		false,
		label,
		ChangeRecord.SourceKind.AUTO_GHOST
	)
