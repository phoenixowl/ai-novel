class_name ToolcallDialogueStart
extends ToolcallBase
## dialogue.start（仅 DM）：递话——把玩家话语交给在场 NPC，即"开启/继续对话"。
## 落地：DMParser.validate_dm 提取 npc/speech（npc 过在场闭集钳制）后，
## 由 DMController._deliver_speech 分派（开新对话 / 送当前对象 / 结算后切换）。


func _init() -> void:
	name = ToolcallCatalog.DIALOGUE_START
	title = "开启对话 / 递话"
	callers = PackedStringArray([ToolcallCatalog.CALLER_DM])
	args_hint = "{\"npc\": \"在场人物 id\", \"speech\": \"要交给这位 NPC 的话\"}"
	doc = PackedStringArray([
		"route 为 speech / mixed 时必须调用一次，把玩家要说的话原样或轻度整理后交给 NPC，不改写意思。",
		"npc 只能填在场清单里的 [id]；对话进行中没点名对象时，默认交给当前交谈对象。",
	])


func validate_args(args: Dictionary, _caller: String, notes: Array[String]) -> Dictionary:
	var npc := str(args.get("npc", "")).strip_edges()
	var speech := str(args.get("speech", "")).strip_edges()
	if npc.is_empty() or speech.is_empty():
		notes.append("dialogue.start 需要 npc 与 speech，已丢弃。")
		return {}
	return {"npc": npc, "speech": speech}
