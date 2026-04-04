class_name BuildInfo
extends RefCounted

const BUILD_INFO_PATH: String = "res://config/build_info.cfg"
const SECTION: String = "build"
const DEFAULT_VERSION: String = "0.1.0"
const DEFAULT_COMMIT: String = "dev"


static func display_text() -> String:
	var config := ConfigFile.new()
	var has_config: bool = config.load(BUILD_INFO_PATH) == OK
	var version: String = _read_value(config, has_config, "version", DEFAULT_VERSION)
	var commit: String = _read_value(config, has_config, "commit", DEFAULT_COMMIT)
	var build_date: String = _read_value(config, has_config, "build_date", "")
	var text: String = "v%s · %s" % [version, commit]
	if build_date != "":
		text += " · %s" % build_date
	return text


static func _read_value(config: ConfigFile, has_config: bool, key: String, fallback: String) -> String:
	if not has_config:
		return fallback
	var value: Variant = config.get_value(SECTION, key, fallback)
	return str(value)
