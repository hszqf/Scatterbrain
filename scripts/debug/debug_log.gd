class_name DebugLog
extends RefCounted

const EDITOR_SAVE: StringName = &"EDITOR_SAVE"
const LEVEL_LOAD: StringName = &"LEVEL_LOAD"
const ANIMATION: StringName = &"ANIMATION"

static var _enabled_by_category: Dictionary = {
	EDITOR_SAVE: true,
	LEVEL_LOAD: true,
	ANIMATION: false,
}


static func is_enabled(category: StringName) -> bool:
	return bool(_enabled_by_category.get(category, false))


static func log(category: StringName, message: String) -> void:
	if not is_enabled(category):
		return
	print("[%s] %s" % [String(category), message])
