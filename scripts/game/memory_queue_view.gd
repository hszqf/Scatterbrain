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
		slot.custom_minimum_size = Vector2(28, 28)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var has_entry: bool = i < entries.size()
		slot.modulate = _slot_color(entries[i]) if has_entry else Color("3a4452")
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 12)
		label.text = _slot_symbol(entries[i]) if has_entry else "·"
		slot.add_child(label)
		var marker: ColorRect = ColorRect.new()
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.custom_minimum_size = Vector2(7, 7)
		marker.anchor_right = 0.0
		marker.anchor_bottom = 0.0
		marker.offset_left = 2.0
		marker.offset_top = 2.0
		marker.offset_right = 9.0
		marker.offset_bottom = 9.0
		marker.color = _slot_marker_color(entries[i]) if has_entry else Color("4f5a6a")
		slot.add_child(marker)
		_slots_container.add_child(slot)
	_obsession_label.text = "PIN %d" % obsession_capacity


func _slot_symbol(entry: ChangeRecord) -> String:
	match entry.type:
		ChangeRecord.ChangeType.POSITION:
			return "↔"
		ChangeRecord.ChangeType.EMPTY:
			return "○"
		ChangeRecord.ChangeType.GHOST:
			return "◌"
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


func _slot_marker_color(entry: ChangeRecord) -> Color:
	match entry.type:
		ChangeRecord.ChangeType.POSITION:
			return Color("4b3a00")
		ChangeRecord.ChangeType.EMPTY:
			return Color("12375b")
		ChangeRecord.ChangeType.GHOST:
			return Color("321a4f")
		_:
			return Color("3b4555")
