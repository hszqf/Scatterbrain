class_name BuildInfo
extends RefCounted

const BUILD_INFO_PATH: String = "res://generated/build_info.json"
const DEFAULT_TEXT: String = "dev"


static func display_text() -> String:
	var data: Dictionary = _load_generated_data()
	if data.is_empty():
		return DEFAULT_TEXT
	var short_sha: String = str(data.get("short_sha", "")).strip_edges()
	if short_sha == "":
		return DEFAULT_TEXT
	var version: String = str(data.get("version", "")).strip_edges()
	if version == "":
		return "build %s" % short_sha
	return "v%s · %s" % [version, short_sha]


static func _load_generated_data() -> Dictionary:
	if not FileAccess.file_exists(BUILD_INFO_PATH):
		return {}
	var file: FileAccess = FileAccess.open(BUILD_INFO_PATH, FileAccess.READ)
	if file == null:
		return {}
	var raw_text: String = file.get_as_text()
	if raw_text.strip_edges() == "":
		return {}
	var json := JSON.new()
	if json.parse(raw_text) != OK:
		return {}
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed
