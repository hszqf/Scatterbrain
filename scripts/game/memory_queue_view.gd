class_name MemoryQueueView
extends Control

## Displays remembered changes in fixed-size slots.
@export var slots_container_path: NodePath
@export var obsession_label_path: NodePath
@export var evict_drop_pixels: float = 14.0
@export var evict_scale: float = 1.16
@export var evict_duration: float = 0.12
@export var append_pop_scale: float = 1.12
@export var append_duration: float = 0.1
@export var settle_duration: float = 0.05

var _slots_container: HBoxContainer
var _obsession_label: Label
var _slot_nodes: Array[Panel] = []
var _last_animation_trace: Array[String] = []


func _ready() -> void:
	_slots_container = get_node(slots_container_path)
	_obsession_label = get_node(obsession_label_path)


func render_queue(entries: Array[ChangeRecord], capacity: int, obsession_capacity: int) -> void:
	_rebuild_slots(entries, capacity)
	_obsession_label.text = "PIN %d" % obsession_capacity


func play_queue_transition(
	previous_entries: Array[ChangeRecord],
	new_entries: Array[ChangeRecord],
	capacity: int,
	obsession_capacity: int,
	evicted_changes: Array[ChangeRecord]
) -> void:
	_last_animation_trace = []
	render_queue(previous_entries, capacity, obsession_capacity)
	if not evicted_changes.is_empty():
		_last_animation_trace.append("queue:evict")
		await animate_evicted_changes(evicted_changes)
	render_queue(new_entries, capacity, obsession_capacity)
	var appended_changes: Array[ChangeRecord] = _compute_appended_changes(previous_entries, new_entries, evicted_changes.size())
	if not appended_changes.is_empty():
		_last_animation_trace.append("queue:append")
		await animate_appended_changes(appended_changes)
	_last_animation_trace.append("queue:settle")
	await animate_queue_settle()


func animate_evicted_changes(evicted_changes: Array[ChangeRecord]) -> void:
	var evict_count: int = mini(evicted_changes.size(), _slot_nodes.size())
	if evict_count == 0:
		return
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	for i: int in range(evict_count):
		var slot: Panel = _slot_nodes[i]
		if slot == null:
			continue
		slot.pivot_offset = slot.size * 0.5
		tween.tween_property(slot, "position:y", slot.position.y + evict_drop_pixels, evict_duration)
		tween.tween_property(slot, "scale", Vector2(evict_scale, evict_scale), evict_duration)
		tween.tween_property(slot, "modulate:a", 0.0, evict_duration)
	await tween.finished


func animate_appended_changes(appended_changes: Array[ChangeRecord]) -> void:
	if appended_changes.is_empty() or _slot_nodes.is_empty():
		return
	var start_index: int = maxi(0, _slot_nodes.size() - appended_changes.size())
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	for i: int in range(start_index, _slot_nodes.size()):
		var slot: Panel = _slot_nodes[i]
		if slot == null:
			continue
		slot.pivot_offset = slot.size * 0.5
		slot.modulate.a = 0.0
		slot.scale = Vector2(0.86, 0.86)
		tween.tween_property(slot, "modulate:a", 1.0, append_duration)
		tween.tween_property(slot, "scale", Vector2(append_pop_scale, append_pop_scale), append_duration)
	await tween.finished


func animate_queue_settle() -> void:
	if _slot_nodes.is_empty():
		return
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	for slot: Panel in _slot_nodes:
		if slot == null:
			continue
		slot.pivot_offset = slot.size * 0.5
		tween.tween_property(slot, "scale", Vector2.ONE, settle_duration)
	await tween.finished


func get_last_animation_trace() -> Array[String]:
	return _last_animation_trace.duplicate()


func _rebuild_slots(entries: Array[ChangeRecord], capacity: int) -> void:
	for child: Node in _slots_container.get_children():
		child.queue_free()
	_slot_nodes.clear()
	for i: int in range(capacity):
		var has_entry: bool = i < entries.size()
		var slot: Panel = _build_slot(entries[i] if has_entry else null)
		_slots_container.add_child(slot)
		_slot_nodes.append(slot)


func _build_slot(entry: ChangeRecord) -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(28, 28)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var has_entry: bool = entry != null
	slot.modulate = _slot_color(entry) if has_entry else Color("3a4452")
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 12)
	label.text = _slot_symbol(entry) if has_entry else "-"
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
	marker.color = _slot_marker_color(entry) if has_entry else Color("4f5a6a")
	slot.add_child(marker)
	return slot


func _compute_appended_changes(
	previous_entries: Array[ChangeRecord],
	new_entries: Array[ChangeRecord],
	evicted_count: int
) -> Array[ChangeRecord]:
	var surviving_previous: Array[ChangeRecord] = []
	for i: int in range(evicted_count, previous_entries.size()):
		surviving_previous.append(previous_entries[i])
	var mismatch_index: int = mini(surviving_previous.size(), new_entries.size())
	for i: int in range(mismatch_index):
		if surviving_previous[i].summary() != new_entries[i].summary():
			mismatch_index = i
			break
	var appended: Array[ChangeRecord] = []
	for i: int in range(mismatch_index, new_entries.size()):
		appended.append(new_entries[i])
	return appended


func _slot_symbol(entry: ChangeRecord) -> String:
	if entry == null:
		return "-"
	match entry.type:
		ChangeRecord.ChangeType.POSITION:
			return "POS"
		ChangeRecord.ChangeType.EMPTY:
			return "EMP"
		ChangeRecord.ChangeType.GHOST:
			return "GST"
		_:
			return "?"


func _slot_color(entry: ChangeRecord) -> Color:
	if entry == null:
		return Color("586273")
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
	if entry == null:
		return Color("3b4555")
	match entry.type:
		ChangeRecord.ChangeType.POSITION:
			return Color("4b3a00")
		ChangeRecord.ChangeType.EMPTY:
			return Color("12375b")
		ChangeRecord.ChangeType.GHOST:
			return Color("321a4f")
		_:
			return Color("3b4555")
