class_name ToolcallAffinityChange
extends ToolcallBase
## affinity.change（仅 NPC）：NPC 对玩家好感度的变化提案——好感度是 NPC 自己的心，
## DM 无权代写。多次调用合计后钳位 ±10（ResponseParser），经 AffinityStore 落盘。


func _init() -> void:
	name = ToolcallCatalog.AFFINITY_CHANGE
	title = "好感度变化"
	callers = PackedStringArray([ToolcallCatalog.CALLER_NPC])
	args_hint = "{\"delta\": -10 到 10 的整数}"
	doc = PackedStringArray([
		"对方的言行让你对此人的观感发生变化时调用；平淡交流不要调用。",
		"数值只在这里给，不要在发言中直接提及。",
	])


func validate_args(args: Dictionary, _caller: String, notes: Array[String]) -> Dictionary:
	var delta_v: Variant = args.get("delta", null)
	if not (delta_v is float or delta_v is int):
		notes.append("affinity.change 缺少数值 delta，已丢弃。")
		return {}
	return {"delta": clampi(int(delta_v), -10, 10)}
