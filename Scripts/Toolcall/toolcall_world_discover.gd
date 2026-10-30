class_name ToolcallWorldDiscover
extends ToolcallBase
## world.discover（仅 DM）：请求动态生成一个新地点/人物/组织。DM 只表达意图，
## 生成由 Gen 层的独立 agent 完成（构思 → 审核 → 修订多轮管线）。
## 引擎闸门：每段探索上限与 gen 实体总量上限在 GenController 落地处拦截。


const KINDS := ["location", "character", "faction"]
const BRIEF_MAX := 60


func _init() -> void:
	name = ToolcallCatalog.WORLD_DISCOVER
	title = "发现新事物（动态生成）"
	callers = PackedStringArray([ToolcallCatalog.CALLER_DM])
	args_hint = "{\"kind\": \"location / character / faction\", \"brief\": \"一句话意图，60 字内\"}"
	doc = PackedStringArray([
		"仅当玩家行为指向一个此前未描写过的存在时调用（敲开没开过的门、打听没出场的人、卷入没提过的势力）。",
		"不能凭空刷出新东西，不能用生成替代既有实体；每段探索最多 3 次。",
		"生成由独立的编写者完成，需要较长时间（构思与多轮校验），期间世界暂停。",
	])


func validate_args(args: Dictionary, _caller: String, notes: Array[String]) -> Dictionary:
	var kind := str(JsonTool.pick(args, ["kind", "类型"], "")).strip_edges()
	if not KINDS.has(kind):
		notes.append("world.discover 的 kind 非法（%s），已丢弃。" % kind)
		return {}
	var brief := str(JsonTool.pick(args, ["brief", "意图"], "")).strip_edges()
	if brief.is_empty():
		notes.append("world.discover 缺少 brief，已丢弃。")
		return {}
	if brief.length() > BRIEF_MAX:
		brief = brief.substr(0, BRIEF_MAX)
		notes.append("world.discover 的 brief 超长，已截断到 %d 字。" % BRIEF_MAX)
	return {"kind": kind, "brief": brief}
