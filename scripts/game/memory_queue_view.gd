class_name MemoryQueueView
extends Control

## Displays remembered changes in fixed-size slots.
@export var queue_label_path: NodePath
@export var obsession_label_path: NodePath

var _queue_label: Label
var _obsession_label: Label


func _ready() -> void:
	_queue_label = get_node(queue_label_path)
	_obsession_label = get_node(obsession_label_path)


func render_queue(entries: Array[ChangeRecord], capacity: int, obsession_capacity: int) -> void:
	var lines: Array[String] = []
	for i: int in range(capacity):
		if i < entries.size():
			lines.append("[%d] %s" % [i, entries[i].summary()])
		else:
			lines.append("[%d] --" % i)
	_queue_label.text = "记忆队列\n" + "\n".join(lines)
	_obsession_label.text = "执念: %d (未解锁)" % obsession_capacity
