class_name App
extends Node

## Application entry, opens the game root immediately for v1.
func _ready() -> void:
	var game_scene: PackedScene = preload("res://scenes/game/GameRoot.tscn")
	var game: Node = game_scene.instantiate()
	add_child(game)
