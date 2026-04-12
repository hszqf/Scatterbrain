class_name MainMenu
extends Control

signal play_pressed
signal level_editor_pressed


func _ready() -> void:
	$CenterContainer/VBox/PlayButton.pressed.connect(func() -> void: play_pressed.emit())
	$CenterContainer/VBox/LevelEditorButton.pressed.connect(func() -> void: level_editor_pressed.emit())
