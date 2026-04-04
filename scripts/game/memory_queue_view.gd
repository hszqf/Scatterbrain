class_name MemoryQueueView
extends Control

## Displays remembered changes in fixed-size slots.
@export var slots_container_path: NodePath
@export var obsession_label_path: NodePath

var _slots_container: HBoxContainer
var _obsession_label: Label


func _ready() -> void:
	_slots_container = get_node(slots_container_path)
	_obsession_label = get_node(obsession_label_path)


func render_queue(entries: Array[ChangeRecord], capacity: int, obsession_capacity: int) -> void:
	for child: Node in _slots_container.get_children():
		child.queue_free()
	for i: int in range(capacity):
		var slot: Panel = Panel.new()
		slot.custom_minimum_size = Vector2(44, 44)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.modulate = _slot_color(entries[i]) if i < entries.size() else Color("3a4452")
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		label.text = _slot_symbol(entries[i]) if i < entries.size() else "-"
		slot.add_child(label)
		_slots_container.add_child(slot)
	_obsession_label.text = "执念: %d" % obsession_capacity


func _slot_symbol(entry: ChangeRecord) -> String:
	match entry.type:
		ChangeRecord.ChangeType.POSITION:
			return "推"
		ChangeRecord.ChangeType.EMPTY:
			return "空"
		ChangeRecord.ChangeType.GHOST:
			return "幽"
		_:
			return "?"


func _slot_color(entry: ChangeRecord) -> Color:
	match entry.type:
		ChangeRecord.ChangeType.POSITION:
			return Color("e6c547")
		ChangeRecord.ChangeType.EMPTY:
			return Color("85a7d6")
		ChangeRecord.ChangeType.GHOST:
			return Color("a57bd7")
		_:
			return Color("586273")
