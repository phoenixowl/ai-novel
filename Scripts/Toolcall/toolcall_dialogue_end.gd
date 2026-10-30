class_name ToolcallDialogueEnd
extends ToolcallBase
## dialogue.end（DM + NPC）：结束当前正在进行的对话。
## DM = 世界层面的强制收场（学习与记忆照常落档；与递话同回合等冲突由
## DMController._apply_force_end 消解并记 notes）；NPC = 结束自己这一场，
## 必须附带离开的动作描述。落地：DialogueController.end_dialogue。


func _init() -> void:
	name = ToolcallCatalog.DIALOGUE_END
	title = "结束当前对话"
	callers = PackedStringArray([ToolcallCatalog.CALLER_DM, ToolcallCatalog.CALLER_NPC])
	args_hint = "DM：{\"reason\": \"一句话理由\"}；NPC：{\"departure\": \"离开的动作描述\"}"
	doc = PackedStringArray([
		"结束当前正在进行的对话。DM 用于世界层面的强制结算（NPC 的学习与记忆照常落档）。",
		"NPC 用于自己收场：必须写明离开的动作（departure），不允许凭空消失。",
	])


func validate_args(args: Dictionary, caller: String, notes: Array[String]) -> Dictionary:
	if caller == ToolcallCatalog.CALLER_NPC:
		var departure := str(args.get("departure", "")).strip_edges()
		if departure.is_empty():
			notes.append("dialogue.end 缺少离开动作描述，已补默认描述。")
			departure = "（他结束了这场交谈。）"
		return {"departure": departure}
	var reason := str(args.get("reason", "")).strip_edges()
	return {"reason": reason if not reason.is_empty() else "dm_settle"}
