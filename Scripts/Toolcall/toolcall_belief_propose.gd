class_name ToolcallBeliefPropose
extends ToolcallBase
## belief.propose（仅 NPC）：对自身知识日志某条记录的佐证/矛盾提案——信念是 NPC 的
## 私产（硬线①：DM 不碰）。提案延后到对话结束结算（DialogueController._settle_learning）：
## ref 闭集校验（限本轮材料包展示过的编号）通过后走确定性信任算术。


## 信念关系枚举（与旧版 belief_updates 字段共用；ResponseParser 引用此处）。
const RELATIONS := ["佐证", "矛盾"]


func _init() -> void:
	name = ToolcallCatalog.BELIEF_PROPOSE
	title = "信念提案"
	callers = PackedStringArray([ToolcallCatalog.CALLER_NPC])
	args_hint = "{\"ref\": 知识日志编号, \"relation\": \"佐证 或 矛盾\", \"note\": \"一句理由\"}"
	doc = PackedStringArray([
		"对方的话佐证或动摇了你知识日志里某条记录时调用；ref 只能引用本轮材料包展示过的编号。",
		"提案在对话结束结算时才生效——日志当下不会变。",
	])


func validate_args(args: Dictionary, _caller: String, notes: Array[String]) -> Dictionary:
	var ref_v: Variant = args.get("ref", null)
	if not (ref_v is float or ref_v is int) or int(ref_v) <= 0:
		notes.append("belief.propose 需要正整数 ref，已丢弃。")
		return {}
	var relation := str(args.get("relation", ""))
	if not RELATIONS.has(relation):
		notes.append("belief.propose 关系非法（%s），已丢弃。" % relation)
		return {}
	return {"ref": int(ref_v), "relation": relation, "note": str(args.get("note", ""))}
