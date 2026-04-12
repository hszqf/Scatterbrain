class_name App
extends Node

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/menu/MainMenu.tscn")
const GAME_SCENE: PackedScene = preload("res://scenes/game/GameRoot.tscn")
const LEVEL_EDITOR_SCENE: PackedScene = preload("res://scenes/level_editor/LevelEditorScene.tscn")

var _current_screen: Node


func _ready() -> void:
	_open_main_menu()


func _open_main_menu() -> void:
	_clear_current_screen()
	var menu: MainMenu = MAIN_MENU_SCENE.instantiate()
	menu.play_pressed.connect(_open_game)
	menu.level_editor_pressed.connect(_open_level_editor)
	add_child(menu)
	_current_screen = menu


func _open_game() -> void:
	_replace_with_scene(GAME_SCENE)


func _open_level_editor() -> void:
	_replace_with_scene(LEVEL_EDITOR_SCENE)


func _replace_with_scene(scene: PackedScene) -> void:
	_clear_current_screen()
	_current_screen = scene.instantiate()
	add_child(_current_screen)


func _clear_current_screen() -> void:
	if _current_screen != null:
		_current_screen.queue_free()
		_current_screen = null
