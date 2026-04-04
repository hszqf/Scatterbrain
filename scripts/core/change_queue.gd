class_name ChangeQueue
extends RefCounted

## In-memory queue for remembered changes with support for pinned records.
var _changes: Array[ChangeRecord] = []


func clear() -> void:
	_changes.clear()


func append(change: ChangeRecord) -> void:
	_changes.append(change)


func entries() -> Array[ChangeRecord]:
	return _changes.duplicate()


func size() -> int:
	return _changes.size()


func remove_oldest_unpinned() -> ChangeRecord:
	for i: int in range(_changes.size()):
		if not _changes[i].pinned:
			var removed: ChangeRecord = _changes[i]
			_changes.remove_at(i)
			return removed
	return null


func normalize_to_capacity(capacity: int) -> Array[ChangeRecord]:
	var removed: Array[ChangeRecord] = []
	while _changes.size() > capacity:
		var popped: ChangeRecord = remove_oldest_unpinned()
		if popped == null:
			break
		removed.append(popped)
	return removed
