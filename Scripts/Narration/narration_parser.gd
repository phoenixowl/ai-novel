class_name NarrationParser
extends RefCounted
## 旁白域输出契约校验（受控开放）。JSON 提取由 LLMController.complete_json / JsonTool
## 统一完成，本类只做结构校验与确定性修复，每一步记入 notes（调试页展示）：
##   validate_dm     —— DM 裁决输出（统一入口）：route 路由枚举 / npc 在场闭集 /
##                     outcome 枚举 / action-narration-speech 字段拆分。
##   validate_facts  —— 事实提取 agent 输出：facts 数组（新事实开放 + 改写闭集引用；
##                     ref 必须在注入的正典编号闭集内，越界降级为新事实）。
##   validate_turn   —— （已弃用 2026-10）旁白回合契约——统一入口后回合生成由 DM 取代。
## 非法与缺失字段给安全默认值，坏项丢弃不报错。


const OUTCOMES := ["success", "partial", "failure", "pending"]
const ROUTES := ["action", "speech", "mixed", "reject"]
const WEIGHTS := ["major", "minor"]
## discoveries 护栏（暂时弃用 2026-10：动态生成人物/地点从调用链移除，保留常量与解析供恢复）
const DISCOVERY_NAME_MAX := 12
const DISCOVERY_BRIEF_MAX := 100
const DISCOVERY_IDENTITY_MAX := 30


## 校验 DM 裁决输出（统一入口的第一站）。
## data：提取好的 JSON Dictionary；present：在场人物 id 集合（闭集）；
## partner：当前交谈对象 id（无对话为空串——闭集额外允许它）。
## 返回 {ok, notes[], route, npc, action, narration, outcome, speech, reason}：
##   route 非法回落 action；npc 越界钳制（优先 partner，其次首位在场，记 notes）；
##   speech/mixed 缺 speech 按 action 处理（记 notes）；outcome 非法回落 pending。
static func validate_dm(data: Dictionary, present: Dictionary, partner := "") -> Dictionary:
	var notes: Array[String] = []

	var route := str(JsonTool.pick(data, ["route", "路由"], ""))
	if not ROUTES.has(route):
		notes.append("route 缺失或非法（%s），按 action 处理。" % route)
		route = "action"

	var npc := str(JsonTool.pick(data, ["npc", "目标"], ""))
	if not npc.is_empty() and not present.has(npc) and npc != partner:
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
	var speech := str(JsonTool.pick(data, ["speech", "发言", "话"], "")).strip_edges()
	var outcome := str(JsonTool.pick(data, ["outcome", "结果"], ""))
	if (route == "action" or route == "mixed") and not OUTCOMES.has(outcome):
		notes.append("outcome 缺失或非法（%s），按 pending 处理。" % outcome)
		outcome = "pending"
	if (route == "speech" or route == "mixed") and speech.is_empty():
		notes.append("说话路由缺少 speech，按 action 处理。")
		route = "action"
	if route == "action" and narration.is_empty():
		notes.append("行动路由缺少叙述，注入保底旁白。")
		narration = "你做了什么，但世界暂时没有回应。（DM 叙述缺失）"
		if outcome.is_empty():
			outcome = "pending"

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
	}


## （已弃用 2026-10）旁白回合契约校验——统一入口后回合生成由 DM 取代，
## 本函数保留供恢复参考，discoveries 解析同样暂时弃用（不再被调用）。
## 返回 {ok, turn, notes[], narration, outcome, discoveries}。
static func validate_turn(data: Dictionary, expected_turn: int) -> Dictionary:
	var notes: Array[String] = []

	var narration := str(JsonTool.pick(data, ["narration", "叙述", "旁白"], ""))

	var outcome := str(JsonTool.pick(data, ["outcome", "结果"], ""))
	if not OUTCOMES.has(outcome):
		notes.append("outcome 缺失或非法（%s），按 pending 处理。" % outcome)
		outcome = "pending"

	if data.has("facts"):
		notes.append("回合契约不包含 facts（事实由结算时的整理者提取），已忽略模型附带的事实。")

	var discoveries := _parse_discoveries(data, notes)

	return {
		"ok": true,
		"turn": expected_turn,
		"notes": notes,
		"narration": narration,
		"outcome": outcome,
		"discoveries": discoveries,
	}


## 校验事实提取 agent 输出。data：提取好的 JSON Dictionary；pack_ids：本次注入的
## 正典编号集合（supersede 闭集）；strict_canon：正典门槛=严格时丢弃 minor 新事实。
## 返回 {ok, notes[], facts: Array[Dictionary]{ref, content, weight, source}}。
static func validate_facts(data: Dictionary, pack_ids: Dictionary, strict_canon := false) -> Dictionary:
	var notes: Array[String] = []
	var facts := _parse_facts(data, pack_ids, strict_canon, notes)
	return {"ok": true, "notes": notes, "facts": facts}


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


## 解析 discoveries 块（world_model_design §3.6 动态生成提名）：
## 模型只提名与简介；每回合 locations/npcs 各限 1 个（多余丢弃并记 notes），
## 名称/简介/身份超长确定性截断。坏项丢弃。连线、去重、落位、建卡由控制器裁决。
static func _parse_discoveries(data: Dictionary, notes: Array[String]) -> Dictionary:
	var out := {"locations": [], "npcs": []}
	var raw: Variant = JsonTool.pick(data, ["discoveries", "发现"], null)
	if raw == null:
		return out
	if not (raw is Dictionary):
		notes.append("discoveries 不是对象，已忽略。")
		return out
	var d: Dictionary = raw
	_take_discovery(d, "locations", "地点", ["name", "名称"], ["brief", "简介"], "",
		out, notes)
	_take_discovery(d, "npcs", "人物", ["name", "名称"], ["brief", "简介"],
		"identity", out, notes)
	return out


## 取一个类别（locations/npcs）的首个合法提名；超过 1 个丢弃并记录。
## extra_key：npcs 专有的身份字段（locations 传空串）。
static func _take_discovery(d: Dictionary, key: String, label: String,
		name_keys: Array, brief_keys: Array, extra_key: String,
		out: Dictionary, notes: Array[String]) -> void:
	var raw: Variant = d.get(key, [])
	if not (raw is Array) or (raw as Array).is_empty():
		return
	var taken := 0
	for item in raw:
		if not (item is Dictionary):
			continue
		var i: Dictionary = item
		var name := str(JsonTool.pick(i, name_keys, "")).strip_edges()
		if name.is_empty():
			notes.append("discoveries.%s 有缺少名称的项，已丢弃。" % label)
			continue
		taken += 1
		if taken > 1:
			notes.append("discoveries.%s 每回合限 1 个，多余的已丢弃。" % label)
			break
		var item_out := {
			"name": _truncate(name, DISCOVERY_NAME_MAX),
			"brief": _truncate(str(JsonTool.pick(i, brief_keys, "")).strip_edges(), DISCOVERY_BRIEF_MAX),
		}
		if extra_key != "":
			item_out[extra_key] = _truncate(
				str(JsonTool.pick(i, [extra_key, "身份"], "")).strip_edges(), DISCOVERY_IDENTITY_MAX)
		(out[key] as Array).append(item_out)


## 确定性截断（护栏：超长部分直接裁掉，模型措辞不越权）。
static func _truncate(text: String, max_chars: int) -> String:
	if text.length() <= max_chars:
		return text
	return text.substr(0, max_chars)
