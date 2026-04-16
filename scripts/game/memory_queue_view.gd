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
var _last_animation_plan_lines: Array[String] = []
var _last_geometry_points_lines: Array[String] = []
var _slot_focus_tweens: Dictionary[int, Tween] = {}
var _displayed_entries: Array[ChangeRecord] = []
var _displayed_capacity: int = 0
var _displayed_obsession_capacity: int = 0
var _incoming_fx_nodes: Array[Control] = []
var _pending_incoming_overlay: Control
var _pending_incoming_geometry_points: Dictionary = {}
var _last_geometry_capture_stage: String = "none"
var _stable_slot0_top_left: Vector2 = Vector2.INF
var _stable_slot0_center: Vector2 = Vector2.INF
var _stable_handoff_top_left: Vector2 = Vector2.INF
var _stable_handoff_center: Vector2 = Vector2.INF


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
	_last_animation_plan_lines = []
	_clear_geometry_points_buffer()
	render_queue(previous_entries, capacity, obsession_capacity)
	await get_tree().process_frame
	_capture_stable_queue_anchors()
	_append_geo_raw_line("queue_transition", "queue_layout_stabilized=true")
	_append_geo_line("queue_transition", "stable_slot0_before", _point_pair(_stable_slot0_top_left, _stable_slot0_center))
	var appended_changes: Array[ChangeRecord] = _compute_appended_changes(previous_entries, new_entries, evicted_changes.size())
	var has_pending_incoming_overlay: bool = _pending_incoming_overlay != null and is_instance_valid(_pending_incoming_overlay)
	var animated_appended_changes: Array[ChangeRecord] = appended_changes.duplicate()
	if animated_appended_changes.is_empty() and has_pending_incoming_overlay and not new_entries.is_empty():
		animated_appended_changes.append(new_entries[0])
	if animated_appended_changes.is_empty():
		_clear_pending_incoming_overlay()
	var diff_classification: String = _classify_queue_diff(
		previous_entries,
		new_entries,
		appended_changes,
		evicted_changes,
		has_pending_incoming_overlay
	)
	var animation_mode: String = _resolve_animation_mode(
		appended_changes.size(),
		evicted_changes.size(),
		mini(previous_entries.size(), capacity),
		has_pending_incoming_overlay
	)
	await _animate_push_right_then_evict(
		previous_entries,
		new_entries,
		animated_appended_changes,
		evicted_changes.size(),
		diff_classification,
		"queue_transition"
	)
	if animation_mode == "append_plus_evict" or animation_mode == "incoming_plus_evict":
		_last_animation_trace.append("queue:evict")
	elif animation_mode == "incoming_plus_shift" or animation_mode == "append_only":
		_last_animation_trace.append("queue:append")
	render_queue(new_entries, capacity, obsession_capacity)
	await get_tree().process_frame
	_capture_stable_queue_anchors()
	_append_geo_line("queue_transition", "stable_slot0_after", _point_pair(_stable_slot0_top_left, _stable_slot0_center))
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
	_last_animation_trace = []
	_last_animation_trace.append("queue:generated_change")
	_last_animation_plan_lines = []
	_clear_geometry_points_buffer()
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
	_last_animation_trace = []
	_last_animation_trace.append("queue:update")
	_last_animation_plan_lines = []
	_clear_geometry_points_buffer()
	render_queue(before_entries, capacity, obsession_capacity)
	await get_tree().process_frame
	_capture_stable_queue_anchors()
	_append_geo_raw_line("queue_update", "queue_layout_stabilized=true")
	_append_geo_line("queue_update", "stable_slot0_before", _point_pair(_stable_slot0_top_left, _stable_slot0_center))
	var appended: Array[ChangeRecord] = appended_changes.duplicate()
	if appended.is_empty():
		appended = _compute_appended_changes(before_entries, after_entries, evicted_changes.size())
	var diff_classification: String = _classify_queue_diff(before_entries, after_entries, appended, evicted_changes)
	if diff_classification == "normalize_in_place":
		_clear_pending_incoming_overlay_if_stale()
		await _animate_normalize_in_place_takeover()
		_last_animation_plan_lines = _build_queue_animation_plan(
			before_entries,
			after_entries,
			[],
			0,
			0,
			[],
			[],
			[],
			false,
			false,
			false,
			diff_classification
		)
		render_queue(after_entries, capacity, obsession_capacity)
		_last_animation_trace.append("queue:settle")
		await animate_queue_settle()
		return
	if appended.is_empty():
		_clear_pending_incoming_overlay()
	if not appended.is_empty():
		_last_animation_trace.append("queue:append")
	if not evicted_changes.is_empty():
		_last_animation_trace.append("queue:evict")
	await _animate_push_right_then_evict(
		before_entries,
		after_entries,
		appended,
		evicted_changes.size(),
		diff_classification,
		"queue_update"
	)
	render_queue(after_entries, capacity, obsession_capacity)
	await get_tree().process_frame
	_capture_stable_queue_anchors()
	_append_geo_line("queue_update", "stable_slot0_after", _point_pair(_stable_slot0_top_left, _stable_slot0_center))
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


func get_last_animation_plan_lines() -> Array[String]:
	return _last_animation_plan_lines.duplicate()


func get_last_geometry_points_lines() -> Array[String]:
	return _last_geometry_points_lines.duplicate()


func get_last_geometry_capture_stage() -> String:
	return _last_geometry_capture_stage


func play_incoming_change_fx(change: ChangeRecord, source_global_pos: Vector2, current_entries: Array[ChangeRecord], capacity: int, obsession_capacity: int) -> void:
	if change == null or capacity <= 0:
		return
	_last_animation_trace = []
	_last_animation_trace.append("queue:incoming_fx:start")
	_last_animation_plan_lines = []
	_clear_geometry_points_buffer()
	_clear_pending_incoming_overlay()
	render_queue(current_entries, capacity, obsession_capacity)
	await get_tree().process_frame
	var target_index: int = 0
	var target_slot: Panel = _slot_at_display(target_index)
	if target_slot == null:
		target_index = resolve_incoming_slot_index(current_entries, capacity)
		target_slot = _slot_at_display(target_index)
	if target_slot == null:
		_last_animation_trace.append("queue:incoming_fx:skip_no_target")
		return
	_capture_stable_queue_anchors()
	var target_slot_center: Vector2 = _stable_handoff_center
	var target_slot_top_left: Vector2 = _stable_handoff_top_left
	if target_slot_center == Vector2.INF or target_slot_top_left == Vector2.INF:
		var fallback_center: Vector2 = _slot_center_in_local(target_slot)
		var fallback_top_left: Vector2 = _slot_top_left_in_local(target_slot)
		var fallback_handoff: Dictionary = _left_handoff_geometry(fallback_center, fallback_top_left, _slot_shift_vector())
		target_slot_center = fallback_handoff["center"]
		target_slot_top_left = fallback_handoff["top_left"]
	var queue_entry_center: Vector2 = target_slot_center
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
	var target_tween: Tween = create_tween()
	target_tween.set_parallel(true)
	var push_entry: Vector2 = queue_entry_center
	_pending_incoming_geometry_points = {
		"source": _point_pair_from_center(source_local),
		"push_entry": _point_pair_from_center(push_entry),
		"incoming_fx_target_slot": _point_pair(target_slot_top_left, target_slot_center),
		"overlay_start": _point_pair_from_center(push_entry),
		"stable_slot0": _point_pair(_stable_slot0_top_left, _stable_slot0_center),
		"stable_handoff": _point_pair(_stable_handoff_top_left, _stable_handoff_center),
	}
	_append_geo_line("incoming_fx", "incoming.source", _pending_incoming_geometry_points["source"])
	_append_geo_line("incoming_fx", "incoming.push_entry", _pending_incoming_geometry_points["push_entry"])
	_append_geo_line("incoming_fx", "incoming_fx.target_slot(display_%d)" % target_index, _pending_incoming_geometry_points["incoming_fx_target_slot"])
	_append_geo_line("incoming_fx", "incoming.overlay_start", _pending_incoming_geometry_points["overlay_start"])
	target_tween.tween_property(particle, "position", push_entry - particle.size * 0.5, travel_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	target_tween.tween_property(particle, "scale", Vector2.ONE * incoming_fx_end_scale, travel_time)
	await target_tween.finished
	_pending_incoming_geometry_points["overlay_final"] = _point_pair_from_center(push_entry)
	_append_geo_line("incoming_fx", "incoming.overlay_final", _pending_incoming_geometry_points["overlay_final"])
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


func _capture_front_slot_overlays(entry_count: int, skip_indices: Array[int] = []) -> Array[Panel]:
	var overlays: Array[Panel] = []
	var count: int = mini(entry_count, _slot_nodes.size())
	for i: int in range(count):
		if skip_indices.has(i):
			continue
		var slot: Panel = _slot_nodes[i]
		if slot == null:
			continue
		var overlay := Panel.new()
		overlay.custom_minimum_size = slot.size
		overlay.size = slot.size
		overlay.position = _slot_top_left_in_local(slot)
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
	after_entries: Array[ChangeRecord],
	appended_changes: Array[ChangeRecord],
	evicted_count: int,
	diff_classification: String = "",
	geometry_stage_name: String = "queue_transition"
) -> void:
	if _slot_nodes.is_empty() or appended_changes.is_empty():
		_last_animation_plan_lines = _build_queue_animation_plan(
			before_entries,
			after_entries,
			appended_changes,
			evicted_count,
			0,
			[],
			[],
			[],
			false,
			false,
			false,
			diff_classification
		)
		return
	var occupied_before: int = mini(before_entries.size(), _slot_nodes.size())
	var had_pending_overlay: bool = _pending_incoming_overlay != null and is_instance_valid(_pending_incoming_overlay)
	var capture_skip_indices: Array[int] = []
	var must_capture_old_slot_zero_for_evict: bool = had_pending_overlay and evicted_count > 0 and (
		diff_classification == "append_plus_evict" or diff_classification == "pre_recompile_append_plus_evict"
	)
	if had_pending_overlay and not must_capture_old_slot_zero_for_evict:
		capture_skip_indices.append(0)
	var existing_overlays: Array[Panel] = _capture_front_slot_overlays(occupied_before, capture_skip_indices)
	var captured_slot_to_overlay: Array[String] = []
	var overlay_capture_idx: int = 0
	for slot_index: int in range(occupied_before):
		if capture_skip_indices.has(slot_index):
			continue
		captured_slot_to_overlay.append("slot_%d->overlay_%d" % [slot_index, overlay_capture_idx])
		overlay_capture_idx += 1
	var created_overlay_indices: Array[int] = []
	var hidden_slot_indices: Array[int] = []
	var removed_overlay_indices: Array[int] = []
	for i: int in range(occupied_before):
		if capture_skip_indices.has(i):
			continue
		created_overlay_indices.append(i)
	for i: int in range(occupied_before):
		if i < 0 or i >= _slot_nodes.size():
			continue
		if capture_skip_indices.has(i):
			continue
		if _slot_nodes[i] != null:
			_slot_nodes[i].visible = false
			hidden_slot_indices.append(i)
	var newest_slot: Panel = _slot_nodes[0]
	if newest_slot == null:
		for overlay: Panel in existing_overlays:
			if is_instance_valid(overlay):
				overlay.queue_free()
		removed_overlay_indices = created_overlay_indices.duplicate()
		_last_animation_plan_lines = _build_queue_animation_plan(
			before_entries,
			after_entries,
			appended_changes,
			evicted_count,
			0,
			hidden_slot_indices,
			created_overlay_indices,
			removed_overlay_indices,
			false,
			false,
			false,
			diff_classification
		)
		return
	var incoming_overlay: Control = _consume_pending_incoming_overlay()
	var created_incoming_overlay: bool = false
	if incoming_overlay == null:
		incoming_overlay = _build_append_overlay(appended_changes[0])
		created_incoming_overlay = true
	var newest_pos: Vector2 = _slot_top_left_in_local(newest_slot)
	var newest_center: Vector2 = _slot_center_in_local(newest_slot)
	if incoming_overlay == null:
		removed_overlay_indices = created_overlay_indices.duplicate()
		_last_animation_plan_lines = _build_queue_animation_plan(
			before_entries,
			after_entries,
			appended_changes,
			evicted_count,
			0,
			hidden_slot_indices,
			created_overlay_indices,
			removed_overlay_indices,
			false,
			had_pending_overlay,
			created_incoming_overlay,
			diff_classification
		)
		return
	if not created_overlay_indices.has(0):
		created_overlay_indices.append(0)
	incoming_overlay.pivot_offset = incoming_overlay.size * 0.5
	incoming_overlay.z_index = 64
	var incoming_from_center: Vector2 = incoming_overlay.position + incoming_overlay.size * 0.5
	var incoming_from_top_left: Vector2 = incoming_overlay.position
	var shift_step: Vector2 = _slot_shift_vector()
	var stable_slot0_geo: Dictionary = _pending_incoming_geometry_points.get("stable_slot0", {})
	var stable_handoff_geo: Dictionary = _pending_incoming_geometry_points.get("stable_handoff", {})
	if stable_slot0_geo.is_empty() or stable_handoff_geo.is_empty():
		stable_slot0_geo = _point_pair(_stable_slot0_top_left, _stable_slot0_center)
		stable_handoff_geo = _point_pair(_stable_handoff_top_left, _stable_handoff_center)
	var handoff_center: Vector2 = stable_handoff_geo.get("center", Vector2.INF)
	var handoff_top_left: Vector2 = stable_handoff_geo.get("top_left", Vector2.INF)
	var target_slot_center: Vector2 = stable_slot0_geo.get("center", Vector2.INF)
	var target_slot_top_left: Vector2 = stable_slot0_geo.get("top_left", Vector2.INF)
	if handoff_center == Vector2.INF or handoff_top_left == Vector2.INF or target_slot_center == Vector2.INF or target_slot_top_left == Vector2.INF:
		var handoff_geometry: Dictionary = _left_handoff_geometry(newest_center, newest_pos, shift_step)
		handoff_center = handoff_geometry["center"]
		handoff_top_left = handoff_geometry["top_left"]
		target_slot_center = newest_center
		target_slot_top_left = newest_pos
	if not had_pending_overlay:
		incoming_overlay.position = handoff_top_left
		incoming_from_center = incoming_overlay.position + incoming_overlay.size * 0.5
		incoming_from_top_left = incoming_overlay.position
	var incoming_to_center: Vector2 = target_slot_center
	var incoming_to_top_left: Vector2 = target_slot_top_left
	var lock_incoming_at_slot: bool = had_pending_overlay and (
		diff_classification == "append_plus_evict"
		or diff_classification == "pre_recompile_append_plus_evict"
		or diff_classification == "incoming_plus_evict"
	)
	var incoming_needs_handoff_to_slot: bool = incoming_from_top_left.distance_to(newest_pos) > 0.01
	var overlay_shift_starts: Array[Vector2] = []
	var overlay_shift_afters: Array[Vector2] = []
	for overlay: Panel in existing_overlays:
		if overlay == null:
			overlay_shift_starts.append(Vector2.INF)
			overlay_shift_afters.append(Vector2.INF)
			continue
		overlay_shift_starts.append(overlay.position)
		overlay_shift_afters.append(overlay.position + shift_step)
	var move_tween: Tween = create_tween()
	move_tween.set_parallel(true)
	var move_time: float = maxf(push_shift_duration, 0.05)
	if incoming_needs_handoff_to_slot:
		var incoming_move_time: float = move_time
		if lock_incoming_at_slot:
			incoming_move_time = minf(move_time, 0.12)
		move_tween.tween_property(incoming_overlay, "position", incoming_to_top_left, incoming_move_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for overlay_index: int in range(existing_overlays.size()):
		var overlay: Panel = existing_overlays[overlay_index]
		if overlay == null:
			continue
		move_tween.tween_property(overlay, "position", overlay_shift_afters[overlay_index], move_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await move_tween.finished
	var survivor_shift_plan: Array[String] = _existing_overlay_shift_plan(existing_overlays, overlay_shift_starts, overlay_shift_afters)
	var source_geo: Dictionary = _pending_incoming_geometry_points.get("source", {})
	if source_geo.is_empty():
		source_geo = _point_pair(incoming_from_top_left, incoming_from_center)
	var push_entry_geo: Dictionary = _pending_incoming_geometry_points.get("push_entry", {})
	if push_entry_geo.is_empty():
		push_entry_geo = _point_pair(handoff_top_left, handoff_center)
	var target_geo: Dictionary = _point_pair(incoming_to_top_left, incoming_to_center)
	var incoming_fx_target_geo: Dictionary = _pending_incoming_geometry_points.get("incoming_fx_target_slot", {})
	_append_geo_line(geometry_stage_name, "incoming.source", source_geo)
	_append_geo_line(geometry_stage_name, "incoming.push_entry", push_entry_geo)
	_append_geo_line(geometry_stage_name, "incoming.target_slot", target_geo)
	if not incoming_fx_target_geo.is_empty():
		_append_geo_line(geometry_stage_name, "incoming_fx.target_slot", incoming_fx_target_geo)
	_append_geo_line(geometry_stage_name, "incoming.overlay_start", _point_pair(incoming_from_top_left, incoming_from_center))
	_append_geo_line(geometry_stage_name, "incoming.overlay_final", _point_pair(incoming_to_top_left, incoming_to_center))
	for index: int in range(captured_slot_to_overlay.size()):
		_append_geo_raw_line(geometry_stage_name, "captured_slot_to_overlay_%d=%s" % [index, captured_slot_to_overlay[index]])
	for index: int in range(survivor_shift_plan.size()):
		_append_geo_raw_line(geometry_stage_name, "shift.overlay_%d=%s" % [index, survivor_shift_plan[index]])
	var evict_overlays: Array[Panel] = []
	var evict_target_positions: Array[Vector2] = []
	var evict_motion_plan: Array[String] = []
	var right_lane: Vector2 = _incoming_lane_right_point()
	var evictable: int = mini(evicted_count, existing_overlays.size())
	for i: int in range(evictable):
		var overlay_index: int = existing_overlays.size() - 1 - i
		if overlay_index < 0:
			break
		var evict_overlay: Panel = existing_overlays[overlay_index]
		evict_overlays.append(evict_overlay)
		evict_target_positions.append(Vector2.ZERO)
		if evict_overlay != null:
			var evict_start_top_left: Vector2 = evict_overlay.position
			if overlay_index >= 0 and overlay_index < overlay_shift_afters.size() and overlay_shift_afters[overlay_index] != Vector2.INF:
				evict_start_top_left = overlay_shift_afters[overlay_index]
			if evict_overlay.position.distance_to(evict_start_top_left) > 0.01:
				evict_overlay.position = evict_start_top_left
			var evict_start_center: Vector2 = evict_start_top_left + evict_overlay.size * 0.5
			var min_lane_center_x: float = evict_start_center.x + maxf(8.0, evict_drop_pixels * 0.5)
			var lane_center_x: float = maxf(right_lane.x + float(i) * 4.0, min_lane_center_x)
			var lane_target_x: float = lane_center_x - evict_overlay.size.x * 0.5
			var target_center_x: float = lane_center_x + maxf(evict_drop_pixels, 8.0)
			var evict_target_top_left: Vector2 = Vector2(target_center_x - evict_overlay.size.x * 0.5, evict_start_top_left.y)
			var evict_lane_center: Vector2 = Vector2(lane_target_x + evict_overlay.size.x * 0.5, evict_start_center.y)
			var evict_target_center: Vector2 = evict_target_top_left + evict_overlay.size * 0.5
			evict_target_positions[evict_target_positions.size() - 1] = evict_target_top_left
			evict_motion_plan.append(
				"overlay[%d]: start=%s lane=%s target=%s" % [
					overlay_index,
					_point_pair_str(evict_start_top_left, evict_start_center),
					_point_pair_str_from_center(evict_lane_center),
					_point_pair_str(evict_target_top_left, evict_target_center)
				]
			)
			_append_geo_raw_line(geometry_stage_name, "evict.overlay_%d=%s" % [overlay_index, evict_motion_plan[evict_motion_plan.size() - 1]])
	if not evict_overlays.is_empty():
		var evict_tween: Tween = create_tween()
		evict_tween.set_parallel(true)
		for index: int in range(evict_overlays.size()):
			var overlay: Panel = evict_overlays[index]
			if overlay == null:
				continue
			if index < evict_target_positions.size():
				evict_tween.tween_property(overlay, "position", evict_target_positions[index], evict_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			evict_tween.tween_property(overlay, "scale", Vector2(evict_scale, evict_scale), evict_duration)
			evict_tween.tween_property(overlay, "modulate:a", 0.0, evict_duration)
		await evict_tween.finished
	removed_overlay_indices = created_overlay_indices.duplicate()
	_last_animation_plan_lines = _build_queue_animation_plan(
		before_entries,
		after_entries,
		appended_changes,
		evicted_count,
		occupied_before,
		hidden_slot_indices,
		created_overlay_indices,
		removed_overlay_indices,
		true,
		had_pending_overlay,
		created_incoming_overlay,
		diff_classification,
		incoming_from_top_left,
		incoming_from_center,
		incoming_to_top_left,
		incoming_to_center,
		survivor_shift_plan,
		evict_motion_plan,
		captured_slot_to_overlay
	)
	incoming_overlay.queue_free()
	_incoming_fx_nodes.erase(incoming_overlay)
	for overlay: Panel in existing_overlays:
		if is_instance_valid(overlay):
			overlay.queue_free()


func _build_queue_animation_plan(
	before_entries: Array[ChangeRecord],
	after_entries: Array[ChangeRecord],
	appended_changes: Array[ChangeRecord],
	evicted_count: int,
	survivor_shift_count: int,
	hidden_slot_indices: Array[int],
	created_overlay_indices: Array[int],
	removed_overlay_indices: Array[int],
	shift_applied: bool,
	had_pending_incoming_overlay: bool,
	created_incoming_overlay: bool,
	diff_classification: String,
	incoming_from_top_left: Vector2 = Vector2.INF,
	incoming_from_center: Vector2 = Vector2.INF,
	incoming_to_top_left: Vector2 = Vector2.INF,
	incoming_to_center: Vector2 = Vector2.INF,
	survivor_shift_plan_lines: Array[String] = [],
	evict_motion_plan_lines: Array[String] = [],
	captured_slot_to_overlay_lines: Array[String] = []
) -> Array[String]:
	var capacity: int = _slot_nodes.size()
	var display_entries_before: Array[ChangeRecord] = _to_display_entries(before_entries, capacity)
	var display_entries_after: Array[ChangeRecord] = _to_display_entries(after_entries, capacity)
	var target_display_index: int = resolve_incoming_slot_index(before_entries, capacity)
	var incoming_owned: bool = had_pending_incoming_overlay or created_incoming_overlay
	var mode: String = _resolve_animation_mode(appended_changes.size(), evicted_count, survivor_shift_count, incoming_owned)
	var canonical_entries_before: Array[String] = _canonical_entry_labels(display_entries_before)
	var canonical_entries_after: Array[String] = _canonical_entry_labels(display_entries_after)
	var classification: String = diff_classification if diff_classification != "" else mode
	var lines: Array[String] = []
	lines.append("display_entries_before=%s" % str(_entry_labels(display_entries_before)))
	lines.append("display_entries_after=%s" % str(_entry_labels(display_entries_after)))
	lines.append("canonical_entries_before=%s" % str(canonical_entries_before))
	lines.append("canonical_entries_after=%s" % str(canonical_entries_after))
	lines.append("diff_classification=%s" % classification)
	lines.append("appended_count=%d" % appended_changes.size())
	lines.append("evicted_count=%d" % evicted_count)
	lines.append("target_display_index_for_incoming=%d" % target_display_index)
	lines.append("whether_pending_incoming_overlay_used=%s" % str(had_pending_incoming_overlay))
	lines.append("survivor_shift_count=%d" % survivor_shift_count)
	lines.append("hidden_slot_indices=%s" % str(hidden_slot_indices))
	lines.append("created_overlay_indices=%s" % str(created_overlay_indices))
	lines.append("removed_overlay_indices=%s" % str(removed_overlay_indices))
	lines.append("animation_mode=%s" % mode)
	var old_memory_count: int = mini(before_entries.size(), capacity)
	var old_memory_moved: bool = shift_applied and old_memory_count > 0
	lines.append("append_only_old_memory_moved=%s" % str(old_memory_moved))
	var shift_mappings: Array[String] = []
	if old_memory_moved:
		for from_slot: int in range(old_memory_count):
			shift_mappings.append("%d->%d" % [from_slot, from_slot + 1])
	lines.append("append_only_shift_mapping=%s" % str(shift_mappings))
	var takeover_mode: String = "slot_self_fade_in"
	if had_pending_incoming_overlay:
		takeover_mode = "badge_takeover_slot"
	elif created_incoming_overlay:
		takeover_mode = "overlay_takeover_slot"
	lines.append("new_memory_slot_takeover=%s" % takeover_mode)
	if incoming_from_center != Vector2.INF and incoming_to_center != Vector2.INF:
		lines.append("incoming_motion_plan=incoming: %s -> display_slot_%d_center=%s" % [str(incoming_from_center), target_display_index, str(incoming_to_center)])
	else:
		lines.append("incoming_motion_plan=incoming: source -> display_slot_%d" % target_display_index)
	if not survivor_shift_plan_lines.is_empty():
		lines.append("survivor_shift_plan=%s" % str(survivor_shift_plan_lines))
	elif shift_mappings.is_empty():
		lines.append("survivor_shift_plan=none")
	else:
		lines.append("survivor_shift_plan=survivor_shift: slot%s" % ", slot".join(shift_mappings))
	if not evict_motion_plan_lines.is_empty():
		lines.append("evict_motion_plan=%s" % str(evict_motion_plan_lines))
	elif evicted_count > 0:
		var evict_from: int = max(0, old_memory_count - 1)
		lines.append("evict_motion_plan=evict: display_slot_%d -> right_lane" % evict_from)
	else:
		lines.append("evict_motion_plan=none")
	return lines


func _resolve_animation_mode(
	appended_count: int,
	evicted_count: int,
	survivor_shift_count: int,
	has_incoming_owner: bool = false
) -> String:
	if evicted_count > 0 and (appended_count > 0 or has_incoming_owner):
		if appended_count <= 0 and has_incoming_owner:
			return "incoming_plus_evict"
		return "append_plus_evict"
	if evicted_count > 0:
		return "evict_only"
	if appended_count <= 0:
		return "none"
	if survivor_shift_count > 0:
		return "incoming_plus_shift"
	return "append_only"


func _entry_labels(entries: Array[ChangeRecord]) -> Array[String]:
	var labels: Array[String] = []
	for entry: ChangeRecord in entries:
		if entry == null:
			labels.append("-")
		else:
			labels.append(entry.summary())
	return labels


func _consume_pending_incoming_overlay() -> Control:
	if _pending_incoming_overlay != null and is_instance_valid(_pending_incoming_overlay):
		var overlay: Control = _pending_incoming_overlay
		_pending_incoming_overlay = null
		return overlay
	return null


func _clear_pending_incoming_overlay_if_stale() -> void:
	if _pending_incoming_overlay != null and not is_instance_valid(_pending_incoming_overlay):
		_pending_incoming_overlay = null


func _animate_normalize_in_place_takeover() -> void:
	_clear_pending_incoming_overlay_if_stale()
	if _pending_incoming_overlay == null or not is_instance_valid(_pending_incoming_overlay):
		return
	if _slot_nodes.is_empty() or _slot_nodes[0] == null:
		_clear_pending_incoming_overlay()
		return
	var incoming_overlay: Control = _consume_pending_incoming_overlay()
	if incoming_overlay == null:
		return
	incoming_overlay.pivot_offset = incoming_overlay.size * 0.5
	incoming_overlay.z_index = 64
	_pending_incoming_geometry_points["normalize_takeover_start"] = _point_pair(incoming_overlay.position, incoming_overlay.position + incoming_overlay.size * 0.5)
	_append_geo_line("normalize_in_place", "normalize.takeover_start", _pending_incoming_geometry_points["normalize_takeover_start"])
	var newest_pos: Vector2 = _slot_top_left_in_local(_slot_nodes[0])
	var newest_center: Vector2 = _slot_center_in_local(_slot_nodes[0])
	var move_tween: Tween = create_tween()
	move_tween.tween_property(incoming_overlay, "position", newest_pos, maxf(push_shift_duration, 0.05)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await move_tween.finished
	_pending_incoming_geometry_points["normalize_takeover_final"] = _point_pair(newest_pos, newest_center)
	_append_geo_line("normalize_in_place", "normalize.takeover_final", _pending_incoming_geometry_points["normalize_takeover_final"])
	incoming_overlay.queue_free()
	_incoming_fx_nodes.erase(incoming_overlay)


func _entry_visual_identity(entry: ChangeRecord) -> String:
	if entry == null:
		return "-"
	match entry.type:
		ChangeRecord.ChangeType.POSITION:
			return "POSITION|subject=%s|delta=%s|target=%s" % [str(entry.subject_id), str(entry.move_delta), str(entry.target_position)]
		_:
			return entry.summary()


func _canonical_entry_labels(entries: Array[ChangeRecord]) -> Array[String]:
	var labels: Array[String] = []
	for entry: ChangeRecord in entries:
		labels.append(_entry_visual_identity(entry))
	return labels


func _classify_queue_diff(
	before_entries: Array[ChangeRecord],
	after_entries: Array[ChangeRecord],
	appended_changes: Array[ChangeRecord],
	evicted_changes: Array[ChangeRecord],
	has_pending_incoming_overlay: bool = false
) -> String:
	if _canonical_entry_labels(before_entries) == _canonical_entry_labels(after_entries):
		return "normalize_in_place"
	if not evicted_changes.is_empty():
		if appended_changes.is_empty() and has_pending_incoming_overlay:
			return "pre_recompile_append_plus_evict"
		return "append_plus_evict"
	if not appended_changes.is_empty():
		return "true_append"
	return "none"


func _clear_pending_incoming_overlay() -> void:
	if _pending_incoming_overlay == null:
		return
	if is_instance_valid(_pending_incoming_overlay):
		_pending_incoming_overlay.queue_free()
	_incoming_fx_nodes.erase(_pending_incoming_overlay)
	_pending_incoming_overlay = null


func _capture_stable_queue_anchors() -> void:
	if _slot_nodes.is_empty() or _slot_nodes[0] == null:
		return
	var slot0: Panel = _slot_nodes[0]
	var slot0_top_left: Vector2 = _slot_top_left_in_local(slot0)
	var slot0_center: Vector2 = _slot_center_in_local(slot0)
	var handoff_geometry: Dictionary = _left_handoff_geometry(
		slot0_center,
		slot0_top_left,
		_slot_shift_vector()
	)
	_stable_slot0_top_left = slot0_top_left
	_stable_slot0_center = slot0_center
	_stable_handoff_top_left = handoff_geometry["top_left"]
	_stable_handoff_center = handoff_geometry["center"]


func _incoming_push_entry_point() -> Vector2:
	if _slot_nodes.is_empty() or _slot_nodes[0] == null:
		return _queue_entry_handoff_center()
	var slot0: Panel = _slot_nodes[0]
	var handoff_geometry: Dictionary = _left_handoff_geometry(
		_slot_center_in_local(slot0),
		_slot_top_left_in_local(slot0),
		_slot_shift_vector()
	)
	return handoff_geometry["center"]


func _queue_entry_handoff_center() -> Vector2:
	if _slot_nodes.is_empty() or _slot_nodes[0] == null:
		return _incoming_lane_left_point()
	var slot0_center: Vector2 = _slot_center_in_local(_slot_nodes[0])
	var shift_step: Vector2 = _slot_shift_vector()
	var handoff_dx: float = absf(shift_step.x)
	if handoff_dx <= 0.01:
		handoff_dx = maxf(_slot_nodes[0].size.x, 52.0)
	return slot0_center - Vector2(handoff_dx, 0.0)


func _queue_entry_handoff_top_left() -> Vector2:
	if _slot_nodes.is_empty() or _slot_nodes[0] == null:
		return _queue_entry_handoff_center() - Vector2(52.0, 52.0) * 0.5
	var slot0: Panel = _slot_nodes[0]
	var handoff_geometry: Dictionary = _left_handoff_geometry(
		_slot_center_in_local(slot0),
		_slot_top_left_in_local(slot0),
		_slot_shift_vector()
	)
	return handoff_geometry["top_left"]


func _left_handoff_geometry(newest_center: Vector2, newest_top_left: Vector2, shift_step: Vector2) -> Dictionary:
	var handoff_dx: float = absf(shift_step.x)
	if handoff_dx <= 0.01:
		handoff_dx = 52.0
	var offset := Vector2(handoff_dx, 0.0)
	return {
		"center": newest_center - offset,
		"top_left": newest_top_left - offset,
	}


func _slot_shift_vector() -> Vector2:
	if _slot_nodes.is_empty() or _slot_nodes[0] == null:
		return Vector2(52.0, 0.0)
	var newest_pos: Vector2 = _slot_center_in_local(_slot_nodes[0])
	if _slot_nodes.size() > 1 and _slot_nodes[1] != null:
		var next_pos: Vector2 = _slot_center_in_local(_slot_nodes[1])
		return next_pos - newest_pos
	return Vector2(_slot_nodes[0].size.x, 0.0)


func _slot_top_left_in_local(slot: Control) -> Vector2:
	return _to_local_canvas(slot.get_global_rect().position)


func _slot_center_in_local(slot: Control) -> Vector2:
	return _to_local_canvas(slot.get_global_rect().get_center())


func _existing_overlay_shift_plan(
	overlays: Array[Panel],
	from_top_lefts: Array[Vector2],
	after_top_lefts: Array[Vector2]
) -> Array[String]:
	var lines: Array[String] = []
	for i: int in range(overlays.size()):
		var overlay: Panel = overlays[i]
		if overlay == null:
			continue
		if i < 0 or i >= from_top_lefts.size() or i >= after_top_lefts.size():
			continue
		var from_top_left: Vector2 = from_top_lefts[i]
		var after_top_left: Vector2 = after_top_lefts[i]
		if from_top_left == Vector2.INF or after_top_left == Vector2.INF:
			continue
		var from_center: Vector2 = from_top_left + overlay.size * 0.5
		var to_center: Vector2 = after_top_left + overlay.size * 0.5
		lines.append("overlay[%d]: before=%s after=%s" % [
			i,
			_point_pair_str(from_top_left, from_center),
			_point_pair_str(after_top_left, to_center)
		])
	return lines


func _clear_geometry_points_buffer() -> void:
	_last_geometry_points_lines = []
	_last_geometry_capture_stage = "none"


func _append_geo_line(stage_name: String, label: String, point_pair: Dictionary) -> void:
	_last_geometry_capture_stage = stage_name
	_last_geometry_points_lines.append("stage=%s %s=%s" % [stage_name, label, _point_pair_dict_str(point_pair)])


func _append_geo_raw_line(stage_name: String, value: String) -> void:
	_last_geometry_capture_stage = stage_name
	_last_geometry_points_lines.append("stage=%s %s" % [stage_name, value])


func _point_pair(top_left: Vector2, center: Vector2) -> Dictionary:
	return {
		"top_left": top_left,
		"center": center,
	}


func _point_pair_from_center(center: Vector2) -> Dictionary:
	var default_size: Vector2 = Vector2(52.0, 52.0)
	return _point_pair(center - default_size * 0.5, center)


func _point_pair_str(top_left: Vector2, center: Vector2) -> String:
	return "top_left=%s center=%s" % [str(top_left), str(center)]


func _point_pair_str_from_center(center: Vector2) -> String:
	return _point_pair_str(center - Vector2(52.0, 52.0) * 0.5, center)


func _point_pair_dict_str(point_pair: Dictionary) -> String:
	if point_pair.is_empty():
		return "n/a"
	return _point_pair_str(point_pair.get("top_left", Vector2.ZERO), point_pair.get("center", Vector2.ZERO))


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
