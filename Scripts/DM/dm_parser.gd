class_name DMParser
extends RefCounted
## 旁白域输出契约校验（受控开放）。JSON 提取由 LLMController.complete_json / JsonTool
## 统一完成，本类只做结构校验与确定性修复，每一步记入 notes（调试页展示）：
##   validate_dm     —— DM 裁决输出（统一入口）：route 路由枚举 / outcome 枚举 /
##                     tool_calls 操作（ToolcallParser 校验权限与结构：dialogue.start 的
##                     npc 在场闭集钳制、facts.declare 申报、dialogue.end 强制收场）；
##                     旧版 npc/speech/facts 顶层字段仍兼容解析（工具调用优先）。
##   validate_facts  —— 事实提取 agent 输出：facts 数组（新事实开放 + 改写闭集引用；
##                     ref 必须在注入的正典编号闭集内，越界降级为新事实）+
##                     confirmed 数组（临时事实点名保留，闭集校验，越界忽略）。
## 非法与缺失字段给安全默认值，坏项丢弃不报错。


const OUTCOMES := ["success", "partial", "failure", "pending"]
const ROUTES := ["action", "speech", "mixed", "reject"]
const WEIGHTS := ["major", "minor"]

## 校验 DM 裁决输出（统一入口的第一站）。
## data：提取好的 JSON Dictionary；present：在场人物 id 集合（闭集）；
## partner：当前交谈对象 id（无对话为空串——闭集额外允许它）。
## 返回 {ok, notes[], route, npc, action, narration, outcome, speech, reason, facts,
## settle, tool_calls}：
##   route 非法回落 action；话语走 dialogue.start 工具（旧版 npc/speech 顶层字段兼容，
##   新旧并存按工具优先并记 notes）；npc 越界钳制（优先 partner，其次首位在场，记 notes）；
##   speech/mixed 缺话语按 action 处理（记 notes）；outcome 非法回落 pending；
##   facts 为 facts.declare 工具申报的 [{content, weight}]（DM 只能新增，无 ref——无改写权）；
##   settle = DM 调用了 dialogue.end（强制结算当前对话，由控制器落地）。
static func validate_dm(data: Dictionary, present: Dictionary, partner := "") -> Dictionary:
	var notes: Array[String] = []

	var route := str(JsonTool.pick(data, ["route", "路由"], ""))
	if not ROUTES.has(route):
		notes.append("route 缺失或非法（%s），按 action 处理。" % route)
		route = "action"

	# 工具调用（caller=dm：dialogue.start / facts.declare / dialogue.end；越权项已被丢弃）
	var calls := ToolcallParser.parse(data, ToolcallCatalog.CALLER_DM, notes)

	# 话语：dialogue.start 优先，旧版 npc/speech 顶层字段兼容；新旧并存时按工具优先并留痕
	var npc := ""
	var speech := ""
	for c in calls:
		if str(c["tool"]) == ToolcallCatalog.DIALOGUE_START:
			var a: Dictionary = c["args"]
			npc = str(a.get("npc", ""))
			speech = str(a.get("speech", ""))
			break
	var legacy_speech := str(JsonTool.pick(data, ["speech", "发言", "话"], "")).strip_edges()
	if npc.is_empty() and speech.is_empty():
		if not legacy_speech.is_empty():
			npc = str(JsonTool.pick(data, ["npc", "目标"], ""))
			speech = legacy_speech
			notes.append("话语未走 dialogue.start 工具，按旧字段兼容解析。")
	elif not legacy_speech.is_empty():
		notes.append("speech 顶层字段与 dialogue.start 工具并存，按工具调用优先，旧字段已忽略。")

	if not npc.is_empty() and not present.has(npc) and npc != partner:
		# 模型可能给了名字而非 id：经注册表按规范名/别名解析兜底一次，命中在场者则采纳
		var resolved := EntityRegistry.resolve(npc)
		if not resolved.is_empty() and (present.has(resolved) or resolved == partner):
			notes.append("说话目标「%s」按名字解析为 [%s]。" % [npc, resolved])
			npc = resolved
		else:
			notes.append("说话目标 [%s] 不在场，钳制到当前对象或首位在场。" % npc)
			npc = ""
	if npc.is_empty() and (route == "speech" or route == "mixed"):
		if not partner.is_empty():
			npc = partner
		elif not present.is_empty():
			npc = str(present.keys()[0])
			notes.append("DM 未给说话目标，按首位在场人物 [%s] 处理。" % npc)

	var action := str(JsonTool.pick(data, ["action", "行动"], "")).strip_edges()
	var narration := str(JsonTool.pick(data, ["narration", "叙述", "旁白"], "")).strip_edges()
	var outcome := str(JsonTool.pick(data, ["outcome", "结果"], ""))
	if (route == "action" or route == "mixed") and not OUTCOMES.has(outcome):
		notes.append("outcome 缺失或非法（%s），按 pending 处理。" % outcome)
		outcome = "pending"
	if (route == "speech" or route == "mixed") and speech.is_empty():
		notes.append("说话路由缺少话语（dialogue.start 缺失或不完整），按 action 处理。")
		route = "action"
	if route == "action" and narration.is_empty():
		notes.append("行动路由缺少叙述，注入保底旁白。")
		narration = "你做了什么，但世界暂时没有回应。（DM 叙述缺失）"
		if outcome.is_empty():
			outcome = "pending"

	# 事实申报：facts.declare 工具优先，旧版 facts 顶层数组兼容；新旧并存时按工具优先并留痕
	var facts: Array[Dictionary] = []
	for c in calls:
		if str(c["tool"]) == ToolcallCatalog.FACT_DECLARE:
			var a: Dictionary = c["args"]
			facts.append({"content": str(a.get("content", "")), "weight": str(a.get("weight", "minor"))})
	if facts.is_empty():
		facts = _parse_declared_facts(data, notes)
	elif data.has("facts"):
		notes.append("facts 顶层字段与 facts.declare 工具并存，按工具调用优先，旧字段已忽略。")

	# 强制收场：DM 调用了 dialogue.end
	var settle := false
	for c in calls:
		if str(c["tool"]) == ToolcallCatalog.DIALOGUE_END:
			settle = true
			break

	return {
		"ok": true,
		"notes": notes,
		"route": route,
		"npc": npc,
		"action": action,
		"narration": narration,
		"outcome": outcome,
		"speech": speech,
		"reason": str(JsonTool.pick(data, ["reason", "理由"], "")),
		"facts": facts,
		"settle": settle,
		"tool_calls": calls,
	}


## 解析 DM 申报的持久事实（旧版 facts 顶层数组的兼容路径——新契约走 facts.declare 工具）：
## 每项 {content, weight}；坏项丢弃并记 notes。仅结构校验——去重与作用域分配由控制器做。
static func _parse_declared_facts(data: Dictionary, notes: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = JsonTool.pick(data, ["facts", "申报事实"], null)
	if raw == null:
		return out
	if not (raw is Array):
		notes.append("facts 不是数组，已忽略。")
		return out
	for item in raw:
		if not (item is Dictionary):
			notes.append("facts 含非对象项，已丢弃。")
			continue
		var d: Dictionary = item
		var content := str(JsonTool.pick(d, ["content", "表述"], "")).strip_edges()
		if content.is_empty():
			notes.append("facts 项缺少 content，已丢弃。")
			continue
		var weight := str(JsonTool.pick(d, ["weight", "权重"], "minor"))
		if not WEIGHTS.has(weight):
			notes.append("facts 权重非法（%s），按 minor 处理。" % weight)
			weight = "minor"
		out.append({"content": content, "weight": weight})
	return out


## 校验事实提取 agent 输出。data：提取好的 JSON Dictionary；pack_ids：本次注入的
## 正典编号集合（supersede 与 confirmed 的闭集）；strict_canon：正典门槛=严格时丢弃
## minor 新事实。
## 返回 {ok, notes[], facts: Array[Dictionary]{ref, content, weight, source},
## confirmed: Array[int]（点名保留的临时事实编号——闭集内有效，去重）}。
static func validate_facts(data: Dictionary, pack_ids: Dictionary, strict_canon := false) -> Dictionary:
	var notes: Array[String] = []
	var facts := _parse_facts(data, pack_ids, strict_canon, notes)
	var confirmed := _parse_confirmed(data, pack_ids, notes)
	return {"ok": true, "notes": notes, "facts": facts, "confirmed": confirmed}


## 解析 confirmed 数组（临时事实点名保留）：逐项取整数编号，非数字或不在注入闭集内
## 的忽略并记 notes；缺失/非数组返回空。
static func _parse_confirmed(data: Dictionary, pack_ids: Dictionary, notes: Array[String]) -> Array[int]:
	var out: Array[int] = []
	var raw: Variant = JsonTool.pick(data, ["confirmed", "保留"], null)
	if raw == null:
		return out
	if not (raw is Array):
		notes.append("confirmed 不是数组，已忽略。")
		return out
	for item in raw:
		if not (item is float or item is int):
			notes.append("confirmed 含非数字项，已忽略。")
			continue
		var id := int(item)
		if not pack_ids.has(id):
			notes.append("confirmed 点名的编号 [%d] 不在本轮正典内，已忽略。" % id)
			continue
		if not out.has(id):
			out.append(id)
	return out


## 解析 facts 数组：每项 {ref(int), content(str), weight(major|minor), adopted_from_player(bool)}。
## 坏项丢弃并记 notes；ref>0 但不在闭集内的降级为新事实（防编造引用）；
## 严格门槛下丢弃 minor 新事实（major 与取代不受影响）。
static func _parse_facts(data: Dictionary, pack_ids: Dictionary, strict_canon: bool, notes: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = JsonTool.pick(data, ["facts", "事实"], null)
	if raw == null:
		return out
	if not (raw is Array):
		notes.append("facts 不是数组，已忽略。")
		return out
	for item in raw:
		if not (item is Dictionary):
			notes.append("facts 含非对象项，已丢弃。")
			continue
		var d: Dictionary = item
		var content := str(JsonTool.pick(d, ["content", "表述"], "")).strip_edges()
		if content.is_empty():
			notes.append("facts 项缺少 content，已丢弃。")
			continue
		var weight := str(JsonTool.pick(d, ["weight", "权重"], "minor"))
		if not WEIGHTS.has(weight):
			notes.append("facts 权重非法（%s），按 minor 处理。" % weight)
			weight = "minor"
		var ref_variant: Variant = JsonTool.pick(d, ["ref", "编号"], null)
		var ref := 0
		if ref_variant is float or ref_variant is int:
			ref = int(ref_variant)
		if ref > 0 and not pack_ids.has(ref):
			notes.append("facts 引用的编号 [%d] 不在本轮正典内，降级为新事实。" % ref)
			ref = 0
		if ref == 0 and strict_canon and weight == "minor":
			notes.append("正典门槛=严格：丢弃 minor 新事实（%s…）。" % content.substr(0, 24))
			continue
		out.append({
			"ref": ref,
			"content": content,
			"weight": weight,
			"source": CanonFact.source_key(JsonTool.pick_bool(d, ["adopted_from_player"], false)),
		})
	return out
