class_name MemoryQueueView
extends Control

## Displays remembered changes in fixed-size slots.
@export var slots_container_path: NodePath
@export var obsession_label_path: NodePath
@export var evict_drop_pixels: float = 14.0
@export var evict_scale: float = 1.24
@export var evict_duration: float = 0.34
@export var evict_hold_duration: float = 0.5
@export var append_pop_scale: float = 1.2
@export var append_duration: float = 0.3
@export var incoming_fx_duration: float = 0.5
@export var incoming_fx_size: float = 14.0
@export var incoming_fx_end_scale: float = 0.72
@export var incoming_pop_height: float = 34.0
@export var incoming_pop_duration: float = 0.18
@export var incoming_hold_before_launch: float = 0.5
@export var incoming_hold_at_lane: float = 0.5
@export var lane_left_padding: float = 34.0
@export var lane_right_padding: float = 34.0
@export var settle_duration: float = 0.16
@export var push_shift_duration: float = 0.28
@export var focus_scale: float = 1.3
@export var focus_in_duration: float = 0.15
@export var focus_out_duration: float = 0.2
@export var focus_modulate: Color = Color(1.42, 1.35, 1.05, 1.0)

var _slots_container: HBoxContainer
var _obsession_label: Label
var _slot_nodes: Array[Panel] = []
var _slot_base_modulates: Array[Color] = []
var _last_animation_trace: Array[String] = []
var _slot_focus_tweens: Dictionary[int, Tween] = {}
var _displayed_entries: Array[ChangeRecord] = []
var _displayed_capacity: int = 0
var _displayed_obsession_capacity: int = 0
var _incoming_fx_nodes: Array[Control] = []
var _pending_incoming_overlay: Control


func _ready() -> void:
	_slots_container = get_node(slots_container_path)
	_obsession_label = get_node(obsession_label_path)


func render_queue(entries: Array[ChangeRecord], capacity: int, obsession_capacity: int) -> void:
	_displayed_entries = entries.duplicate()
	_displayed_capacity = capacity
	_displayed_obsession_capacity = obsession_capacity
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
	var appended_changes: Array[ChangeRecord] = _compute_appended_changes(previous_entries, new_entries, evicted_changes.size())
	if appended_changes.is_empty():
		_clear_pending_incoming_overlay()
	if not evicted_changes.is_empty():
		_last_animation_trace.append("queue:evict")
	if not appended_changes.is_empty():
		_last_animation_trace.append("queue:append")
	await _animate_push_right_then_evict(previous_entries, appended_changes, evicted_changes.size())
	render_queue(new_entries, capacity, obsession_capacity)
	_last_animation_trace.append("queue:settle")
	await animate_queue_settle()


func animate_evicted_changes(evicted_changes: Array[ChangeRecord]) -> void:
	var evict_count: int = mini(evicted_changes.size(), _slot_nodes.size())
	if evict_count == 0:
		return
	if evict_hold_duration > 0.0:
		await get_tree().create_timer(evict_hold_duration).timeout
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	var right_lane: Vector2 = _incoming_lane_right_point()
	for i: int in range(evict_count):
		var slot_index: int = _slot_nodes.size() - 1 - i
		var slot: Panel = _slot_nodes[slot_index]
		if slot == null:
			continue
		slot.pivot_offset = slot.size * 0.5
		var lane_target_x: float = right_lane.x - slot.size.x * 0.5 + float(i) * 4.0
		tween.tween_property(slot, "position:x", lane_target_x + evict_drop_pixels, evict_duration)
		tween.tween_property(slot, "scale", Vector2(evict_scale, evict_scale), evict_duration)
		tween.tween_property(slot, "modulate:a", 0.0, evict_duration)
	await tween.finished


func animate_appended_changes(appended_changes: Array[ChangeRecord]) -> void:
	if appended_changes.is_empty() or _slot_nodes.is_empty():
		return
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	_append_slots_to_tween(appended_changes, tween)
	await tween.finished


func animate_queue_swap(evicted_overlays: Array[Panel], appended_changes: Array[ChangeRecord]) -> void:
	if evicted_overlays.is_empty() and appended_changes.is_empty():
		return
	if (not evicted_overlays.is_empty()) and evict_hold_duration > 0.0:
		await get_tree().create_timer(evict_hold_duration).timeout
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	_append_slots_to_tween(appended_changes, tween)
	_evicted_overlays_to_tween(evicted_overlays, tween)
	await tween.finished
	for overlay: Panel in evicted_overlays:
		if is_instance_valid(overlay):
			overlay.queue_free()


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
		tween.tween_property(slot, "modulate", _base_modulate_for_slot(slot), settle_duration)
	await tween.finished


func play_generated_change_insert(change: ChangeRecord, new_queue_entries: Array[ChangeRecord]) -> void:
	_last_animation_trace.append("queue:generated_change")
	var previous_entries: Array[ChangeRecord] = _displayed_entries.duplicate()
	var capacity: int = _displayed_capacity if _displayed_capacity > 0 else max(new_queue_entries.size(), previous_entries.size())
	render_queue(new_queue_entries, capacity, _displayed_obsession_capacity)
	var appended_changes: Array[ChangeRecord] = _compute_appended_changes(previous_entries, new_queue_entries, 0)
	if appended_changes.is_empty() and change != null:
		appended_changes.append(change)
	if not appended_changes.is_empty():
		await animate_appended_changes(appended_changes)
	_last_animation_trace.append("queue:settle")
	await animate_queue_settle()


func play_queue_update(
	before_entries: Array[ChangeRecord],
	after_entries: Array[ChangeRecord],
	capacity: int,
	obsession_capacity: int,
	evicted_changes: Array[ChangeRecord],
	appended_changes: Array[ChangeRecord]
) -> void:
	_last_animation_trace.append("queue:update")
	render_queue(before_entries, capacity, obsession_capacity)
	var appended: Array[ChangeRecord] = appended_changes.duplicate()
	if appended.is_empty():
		appended = _compute_appended_changes(before_entries, after_entries, evicted_changes.size())
	if appended.is_empty():
		_clear_pending_incoming_overlay()
	if not appended.is_empty():
		_last_animation_trace.append("queue:append")
	if not evicted_changes.is_empty():
		_last_animation_trace.append("queue:evict")
	await _animate_push_right_then_evict(before_entries, appended, evicted_changes.size())
	render_queue(after_entries, capacity, obsession_capacity)
	_last_animation_trace.append("queue:settle")
	await animate_queue_settle()


func play_focus_on_slot(slot_index: int, beat_duration: float = 1.0) -> void:
	var slot: Panel = _slot_for_queue_index(slot_index)
	if slot == null:
		if beat_duration > 0.0:
			await get_tree().create_timer(beat_duration).timeout
		return
	begin_focus_on_slot(slot_index)
	var hold_duration: float = maxf(0.0, beat_duration - focus_out_duration)
	if hold_duration > 0.0:
		await get_tree().create_timer(hold_duration).timeout
	end_focus_on_slot(slot_index)
	if focus_out_duration > 0.0:
		await get_tree().create_timer(focus_out_duration).timeout


func begin_focus_on_slot(slot_index: int) -> void:
	var slot: Panel = _slot_for_queue_index(slot_index)
	if slot == null:
		return
	_last_animation_trace.append("queue:focus:%d:start" % slot_index)
	_slot_focus_tween_kill(slot_index)
	slot.pivot_offset = slot.size * 0.5
	var focus_in: Tween = create_tween()
	focus_in.set_parallel(true)
	focus_in.tween_property(slot, "scale", Vector2(focus_scale, focus_scale), focus_in_duration)
	focus_in.tween_property(slot, "modulate", _base_modulate_for_slot(slot) * focus_modulate, focus_in_duration)
	_slot_focus_tweens[slot_index] = focus_in


func end_focus_on_slot(slot_index: int) -> void:
	var slot: Panel = _slot_for_queue_index(slot_index)
	if slot == null:
		return
	_last_animation_trace.append("queue:focus:%d:end" % slot_index)
	_slot_focus_tween_kill(slot_index)
	var focus_out: Tween = create_tween()
	focus_out.set_parallel(true)
	focus_out.tween_property(slot, "scale", Vector2.ONE, focus_out_duration)
	focus_out.tween_property(slot, "modulate", _base_modulate_for_slot(slot), focus_out_duration)
	_slot_focus_tweens[slot_index] = focus_out


func get_last_animation_trace() -> Array[String]:
	return _last_animation_trace.duplicate()


func play_incoming_change_fx(change: ChangeRecord, source_global_pos: Vector2, current_entries: Array[ChangeRecord], capacity: int, obsession_capacity: int) -> void:
	if change == null or capacity <= 0:
		return
	_last_animation_trace.append("queue:incoming_fx:start")
	_clear_pending_incoming_overlay()
	render_queue(current_entries, capacity, obsession_capacity)
	await get_tree().process_frame
	var target_index: int = resolve_incoming_slot_index(current_entries, capacity)
	var target_slot: Panel = _slot_at_display(target_index)
	if target_slot == null:
		_last_animation_trace.append("queue:incoming_fx:skip_no_target")
		return
	var target_slot_rect: Rect2 = target_slot.get_global_rect()
	var target_slot_center: Vector2 = _to_local_canvas(target_slot_rect.get_center())
	var lane_anchor: Vector2 = target_slot_center
	var particle: Control = _build_incoming_badge(change)
	particle.position = _to_local_canvas(source_global_pos) - particle.size * 0.5
	add_child(particle)
	_incoming_fx_nodes.append(particle)

	var source_local: Vector2 = _to_local_canvas(source_global_pos)
	var popped_local: Vector2 = source_local + Vector2(0.0, -maxf(incoming_pop_height, 0.0))
	var pop_time: float = maxf(incoming_pop_duration, 0.01)
	var pop_tween: Tween = create_tween()
	pop_tween.tween_property(particle, "position", popped_local - particle.size * 0.5, pop_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await pop_tween.finished
	if incoming_hold_before_launch > 0.0:
		await get_tree().create_timer(incoming_hold_before_launch).timeout

	var travel_time: float = maxf(incoming_fx_duration, 0.14)
	var lane_tween: Tween = create_tween()
	lane_tween.tween_property(particle, "position", lane_anchor - particle.size * 0.5, travel_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await lane_tween.finished
	if incoming_hold_at_lane > 0.0:
		await get_tree().create_timer(incoming_hold_at_lane).timeout

	var target_tween: Tween = create_tween()
	target_tween.set_parallel(true)
	var push_entry: Vector2 = _incoming_push_entry_point()
	target_tween.tween_property(particle, "position", push_entry - particle.size * 0.5, travel_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	target_tween.tween_property(particle, "scale", Vector2.ONE * incoming_fx_end_scale, travel_time)
	await target_tween.finished
	_last_animation_trace.append("queue:incoming_fx:landed")
	_pending_incoming_overlay = particle


func resolve_incoming_slot_index(current_entries: Array[ChangeRecord], capacity: int) -> int:
	if capacity <= 0:
		return -1
	return 0


func _rebuild_slots(entries: Array[ChangeRecord], capacity: int) -> void:
	for child: Node in _slots_container.get_children():
		child.queue_free()
	_slot_nodes.clear()
	_slot_base_modulates.clear()
	var display_entries: Array[ChangeRecord] = _to_display_entries(entries, capacity)
	for i: int in range(capacity):
		var slot: Panel = _build_slot(display_entries[i])
		_slots_container.add_child(slot)
		_slot_nodes.append(slot)
		_slot_base_modulates.append(slot.modulate)


func _build_slot(entry: ChangeRecord) -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(52, 52)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var has_entry: bool = entry != null
	slot.modulate = _slot_color(entry) if has_entry else Color("3a4452")
	var object_label := Label.new()
	object_label.anchor_right = 1.0
	object_label.anchor_bottom = 1.0
	object_label.offset_left = 0.0
	object_label.offset_top = 0.0
	object_label.offset_right = 0.0
	object_label.offset_bottom = 0.0
	object_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	object_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	object_label.add_theme_font_size_override("font_size", 30)
	object_label.text = _slot_object_symbol(entry) if has_entry else ""
	slot.add_child(object_label)

	var action_label := Label.new()
	action_label.anchor_right = 1.0
	action_label.anchor_bottom = 1.0
	action_label.offset_left = 0.0
	action_label.offset_top = 0.0
	action_label.offset_right = 0.0
	action_label.offset_bottom = -2.0
	action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	action_label.add_theme_font_size_override("font_size", 13)
	action_label.text = _slot_action_symbol(entry) if has_entry else ""
	slot.add_child(action_label)
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


func _slot_object_symbol(entry: ChangeRecord) -> String:
	if entry == null:
		return ""
	match entry.type:
		ChangeRecord.ChangeType.POSITION:
			return "BOX"
		ChangeRecord.ChangeType.EMPTY:
			return "..."
		ChangeRecord.ChangeType.GHOST:
			return "GHO"
		_:
			return "?"


func _slot_action_symbol(entry: ChangeRecord) -> String:
	if entry == null:
		return ""
	match entry.type:
		ChangeRecord.ChangeType.POSITION:
			return "PUSH %s" % _direction_arrow(entry.move_delta)
		ChangeRecord.ChangeType.EMPTY:
			return "THINK"
		ChangeRecord.ChangeType.GHOST:
			return "GHOST"
		_:
			return ""


func _direction_arrow(delta: Vector2i) -> String:
	if delta == Vector2i.UP:
		return "UP"
	if delta == Vector2i.DOWN:
		return "DN"
	if delta == Vector2i.LEFT:
		return "LT"
	if delta == Vector2i.RIGHT:
		return "RT"
	return "?"


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


func _slot_for_queue_index(queue_index: int) -> Panel:
	return _slot_at_display(_display_index_for_queue_index(queue_index))


func _slot_at_display(display_index: int) -> Panel:
	if display_index < 0 or display_index >= _slot_nodes.size():
		return null
	return _slot_nodes[display_index]


func _display_index_for_queue_index(queue_index: int) -> int:
	if queue_index < 0 or queue_index >= _displayed_entries.size():
		return -1
	return _displayed_entries.size() - 1 - queue_index


func _base_modulate_for_slot(slot: Panel) -> Color:
	var slot_index: int = _slot_nodes.find(slot)
	if slot_index < 0 or slot_index >= _slot_base_modulates.size():
		return Color.WHITE
	return _slot_base_modulates[slot_index]


func _slot_focus_tween_kill(slot_index: int) -> void:
	if not _slot_focus_tweens.has(slot_index):
		return
	var tween: Tween = _slot_focus_tweens[slot_index]
	if tween != null:
		tween.kill()
	_slot_focus_tweens.erase(slot_index)


func _incoming_lane_left_point() -> Vector2:
	if _slot_nodes.is_empty():
		return _to_local_canvas(global_position)
	var first_center: Vector2 = _to_local_canvas(_slot_nodes[0].get_global_rect().get_center())
	return first_center + Vector2(-maxf(lane_left_padding, 0.0), 0.0)


func _incoming_lane_right_point() -> Vector2:
	if _slot_nodes.is_empty():
		return _to_local_canvas(global_position)
	var last_center: Vector2 = _to_local_canvas(_slot_nodes[_slot_nodes.size() - 1].get_global_rect().get_center())
	return last_center + Vector2(maxf(lane_right_padding, 0.0), 0.0)


func _to_display_entries(entries: Array[ChangeRecord], capacity: int) -> Array[ChangeRecord]:
	var display_entries: Array[ChangeRecord] = []
	display_entries.resize(capacity)
	for i: int in range(capacity):
		display_entries[i] = null
	var occupied: int = mini(entries.size(), capacity)
	for i: int in range(occupied):
		display_entries[i] = entries[entries.size() - 1 - i]
	return display_entries


func _build_incoming_badge(change: ChangeRecord) -> Control:
	var badge: Panel = _build_slot(change)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.custom_minimum_size = Vector2(52, 52)
	badge.size = badge.custom_minimum_size
	badge.pivot_offset = badge.size * 0.5
	return badge


func _incoming_action_text(change: ChangeRecord) -> String:
	if change == null:
		return ""
	match change.type:
		ChangeRecord.ChangeType.POSITION:
			return "PUSH %s" % _direction_arrow(change.move_delta)
		ChangeRecord.ChangeType.EMPTY:
			return "THINK"
		ChangeRecord.ChangeType.GHOST:
			return "GHOSTIFY"
		_:
			return "CHANGE"


func _capture_evicted_slot_overlays(evicted_count: int) -> Array[Panel]:
	var overlays: Array[Panel] = []
	var count: int = mini(evicted_count, _slot_nodes.size())
	for i: int in range(count):
		var slot_index: int = _slot_nodes.size() - 1 - i
		var slot: Panel = _slot_nodes[slot_index]
		if slot == null:
			continue
		var overlay := Panel.new()
		overlay.custom_minimum_size = slot.size
		overlay.size = slot.size
		overlay.position = _to_local_canvas(slot.get_global_rect().position)
		overlay.modulate = slot.modulate
		overlay.pivot_offset = overlay.size * 0.5
		overlay.z_index = 64
		for child: Node in slot.get_children():
			overlay.add_child(child.duplicate())
		add_child(overlay)
		overlays.append(overlay)
	return overlays


func _capture_front_slot_overlays(entry_count: int) -> Array[Panel]:
	var overlays: Array[Panel] = []
	var count: int = mini(entry_count, _slot_nodes.size())
	for i: int in range(count):
		var slot: Panel = _slot_nodes[i]
		if slot == null:
			continue
		var overlay := Panel.new()
		overlay.custom_minimum_size = slot.size
		overlay.size = slot.size
		overlay.position = _to_local_canvas(slot.get_global_rect().position)
		overlay.modulate = slot.modulate
		overlay.pivot_offset = overlay.size * 0.5
		overlay.z_index = 64
		for child: Node in slot.get_children():
			overlay.add_child(child.duplicate())
		add_child(overlay)
		overlays.append(overlay)
	return overlays


func _build_append_overlay(change: ChangeRecord) -> Control:
	var overlay: Panel = _build_slot(change)
	overlay.custom_minimum_size = Vector2(52, 52)
	overlay.size = overlay.custom_minimum_size
	overlay.pivot_offset = overlay.size * 0.5
	overlay.z_index = 64
	add_child(overlay)
	return overlay


func _animate_push_right_then_evict(
	before_entries: Array[ChangeRecord],
	appended_changes: Array[ChangeRecord],
	evicted_count: int
) -> void:
	if _slot_nodes.is_empty() or appended_changes.is_empty():
		return
	var occupied_before: int = mini(before_entries.size(), _slot_nodes.size())
	var existing_overlays: Array[Panel] = _capture_front_slot_overlays(occupied_before)
	for i: int in range(occupied_before):
		if i < 0 or i >= _slot_nodes.size():
			continue
		if _slot_nodes[i] != null:
			_slot_nodes[i].visible = false
	var newest_slot: Panel = _slot_nodes[0]
	if newest_slot == null:
		for overlay: Panel in existing_overlays:
			if is_instance_valid(overlay):
				overlay.queue_free()
		return
	var shift_step: Vector2 = _slot_shift_vector()
	var had_pending_overlay: bool = _pending_incoming_overlay != null and is_instance_valid(_pending_incoming_overlay)
	var incoming_overlay: Control = _consume_pending_incoming_overlay(appended_changes[0])
	var newest_pos: Vector2 = _to_local_canvas(newest_slot.get_global_rect().position)
	if incoming_overlay == null:
		return
	incoming_overlay.pivot_offset = incoming_overlay.size * 0.5
	incoming_overlay.z_index = 64
	if not had_pending_overlay:
		incoming_overlay.position = newest_pos - shift_step
	var move_tween: Tween = create_tween()
	move_tween.set_parallel(true)
	var move_time: float = maxf(push_shift_duration, 0.05)
	move_tween.tween_property(incoming_overlay, "position", newest_pos, move_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for overlay: Panel in existing_overlays:
		if overlay == null:
			continue
		move_tween.tween_property(overlay, "position", overlay.position + shift_step, move_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await move_tween.finished
	var evict_overlays: Array[Panel] = []
	var evictable: int = mini(evicted_count, existing_overlays.size())
	for i: int in range(evictable):
		var overlay_index: int = existing_overlays.size() - 1 - i
		if overlay_index < 0:
			break
		evict_overlays.append(existing_overlays[overlay_index])
	if not evict_overlays.is_empty():
		var evict_tween: Tween = create_tween()
		evict_tween.set_parallel(true)
		for overlay: Panel in evict_overlays:
			if overlay == null:
				continue
			evict_tween.tween_property(overlay, "scale", Vector2(evict_scale, evict_scale), evict_duration)
			evict_tween.tween_property(overlay, "modulate:a", 0.0, evict_duration)
		await evict_tween.finished
	incoming_overlay.queue_free()
	_incoming_fx_nodes.erase(incoming_overlay)
	for overlay: Panel in existing_overlays:
		if is_instance_valid(overlay):
			overlay.queue_free()


func _consume_pending_incoming_overlay(fallback_change: ChangeRecord) -> Control:
	if _pending_incoming_overlay != null and is_instance_valid(_pending_incoming_overlay):
		var overlay: Control = _pending_incoming_overlay
		_pending_incoming_overlay = null
		return overlay
	return _build_append_overlay(fallback_change)


func _clear_pending_incoming_overlay() -> void:
	if _pending_incoming_overlay == null:
		return
	if is_instance_valid(_pending_incoming_overlay):
		_pending_incoming_overlay.queue_free()
	_incoming_fx_nodes.erase(_pending_incoming_overlay)
	_pending_incoming_overlay = null


func _incoming_push_entry_point() -> Vector2:
	if _slot_nodes.is_empty():
		return _incoming_lane_left_point()
	var newest_slot: Panel = _slot_nodes[0]
	var newest_pos: Vector2 = _to_local_canvas(newest_slot.get_global_rect().position)
	return newest_pos - _slot_shift_vector()


func _slot_shift_vector() -> Vector2:
	if _slot_nodes.is_empty() or _slot_nodes[0] == null:
		return Vector2(52.0, 0.0)
	var newest_pos: Vector2 = _to_local_canvas(_slot_nodes[0].get_global_rect().position)
	if _slot_nodes.size() > 1 and _slot_nodes[1] != null:
		var next_pos: Vector2 = _to_local_canvas(_slot_nodes[1].get_global_rect().position)
		return next_pos - newest_pos
	return Vector2(_slot_nodes[0].size.x, 0.0)


func _append_slots_to_tween(appended_changes: Array[ChangeRecord], tween: Tween) -> void:
	if tween == null or appended_changes.is_empty() or _slot_nodes.is_empty():
		return
	var end_index: int = mini(appended_changes.size(), _slot_nodes.size())
	for i: int in range(end_index):
		var slot: Panel = _slot_nodes[i]
		if slot == null:
			continue
		slot.pivot_offset = slot.size * 0.5
		slot.modulate.a = 0.0
		slot.scale = Vector2(0.86, 0.86)
		tween.tween_property(slot, "modulate:a", 1.0, append_duration)
		tween.tween_property(slot, "scale", Vector2(append_pop_scale, append_pop_scale), append_duration)


func _evicted_overlays_to_tween(evicted_overlays: Array[Panel], tween: Tween) -> void:
	if tween == null or evicted_overlays.is_empty():
		return
	var right_lane: Vector2 = _incoming_lane_right_point()
	for i: int in range(evicted_overlays.size()):
		var overlay: Panel = evicted_overlays[i]
		if overlay == null:
			continue
		overlay.pivot_offset = overlay.size * 0.5
		var lane_target_x: float = right_lane.x - overlay.size.x * 0.5 + float(i) * 4.0
		tween.tween_property(overlay, "position:x", lane_target_x + evict_drop_pixels, evict_duration)
		tween.tween_property(overlay, "scale", Vector2(evict_scale, evict_scale), evict_duration)
		tween.tween_property(overlay, "modulate:a", 0.0, evict_duration)


func _to_local_canvas(global_point: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * global_point
