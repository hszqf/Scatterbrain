class_name LevelValidationResult
extends RefCounted

var is_valid: bool = true
var errors: Array[String] = []


func add_error(message: String) -> void:
	is_valid = false
	errors.append(message)
