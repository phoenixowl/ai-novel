class_name ToolcallFactsDeclare
extends ToolcallBase
## facts.declare（仅 DM）：申报本回合行动确立的持久事实——以 PROVISIONAL 状态
## 临时入典（立即可检索、可被信念引用），结算时由整理者逐条复核。
## 落地：DMController._land_declared_facts（去重、条数/长度闸门、作用域分配）。


func _init() -> void:
	name = ToolcallCatalog.FACT_DECLARE
	title = "申报持久事实"
	callers = PackedStringArray([ToolcallCatalog.CALLER_DM])
	args_hint = "{\"content\": \"简短的状态陈述\", \"weight\": \"major / minor\"}"
	doc = PackedStringArray([
		"只有本回合的行动确实确立了持久状态变化才调用（申报标准见事实纪律）；拿不准就不调。",
		"只能新增：你没有改写或推翻既有事实（[编号] 条目）的权力。",
	])


func validate_args(args: Dictionary, _caller: String, notes: Array[String]) -> Dictionary:
	var content := str(args.get("content", "")).strip_edges()
	if content.is_empty():
		notes.append("facts.declare 缺少 content，已丢弃。")
		return {}
	var weight := str(args.get("weight", "minor"))
	if not CanonFact.WEIGHT_KEYS.has(weight):
		notes.append("facts.declare 权重非法（%s），按 minor 处理。" % weight)
		weight = "minor"
	return {"content": content, "weight": weight}
