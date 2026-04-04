class_name CompileResult
extends RefCounted

## Result payload of one full compile transaction.
var world: CompiledWorld
var queue_entries: Array[ChangeRecord] = []
var pushed_out_changes: Array[ChangeRecord] = []
var generated_ghost_changes: Array[ChangeRecord] = []
var iterations: int = 0
var reached_safety_limit: bool = false
