class_name ResponseParser
extends RefCounted
## 模型回应（对话域）的字段校验（设计 4.5）。
## JSON 提取由 LLMController.complete_json / JsonTool 统一完成，本类只负责把
## 提取好的 Dictionary 校验为对话回应结构：
##   发言文本 / 发言性质声明 claim_type / 行动提案 / 内心想法（仅调试用）/
##   belief_updates（信念提案 {ref, relation, note}）/ affinity_change（好感度变化量）。
## 非法与缺失字段给安全默认值，并把每一步自动修复记入 notes（供调试面板展示）。
## belief_updates 仅做结构校验；闭集引用由
## DialogueController 结算时校验。


const CLAIM_TYPES := ["确知", "猜测", "虚张声势"]
const ACTION_TYPES := ["answer", "silence", "end_dialogue"]
const RELATIONS := ["佐证", "矛盾"]


## 返回 Dictionary：
##   ok / error / notes[]
##   turn_id / expected_turn / utterance / claim_type / action{type,name,description} / inner_thought
##   belief_updates: Array[Dictionary]{ref, relation, note} —— 结构合法的信念提案
static func validate(data: Dictionary, expected_turn: int) -> Dictionary:
	var notes: Array[String] = []

	var utterance := str(JsonTool.pick(data, ["utterance", "发言", "发言文本"], ""))

	var claim := str(JsonTool.pick(data, ["claim_type", "性质声明", "发言性质"], ""))
	if not CLAIM_TYPES.has(claim):
		notes.append("claim_type 缺失或非法（%s），按“猜测”处理。" % claim)
		claim = "猜测"

	var turn_id := expected_turn
	var turn_variant: Variant = JsonTool.pick(data, ["turn_id", "本轮编号"], null)
	if turn_variant is float or turn_variant is int:
		turn_id = int(turn_variant)
	else:
		notes.append("turn_id 缺失或非数字，按本轮编号 %d 处理。" % expected_turn)
	if turn_id != expected_turn:
		notes.append("turn_id 回显不一致（模型给 %d，本轮为 %d），按本轮编号处理。" % [turn_id, expected_turn])
		turn_id = expected_turn

	var action := {"type": "answer", "name": "答话", "description": ""}
	var action_variant: Variant = JsonTool.pick(data, ["action", "行动提案"], null)
	if action_variant is Dictionary:
		var ad: Dictionary = action_variant
		var type := str(JsonTool.pick(ad, ["type", "类型"], "answer"))
		if not ACTION_TYPES.has(type):
			notes.append("行动类型非法（%s），按“答话”处理。" % type)
			type = "answer"
		action["type"] = type
		action["name"] = str({"answer": "答话", "silence": "沉默", "end_dialogue": "结束对话"}.get(type, "答话"))
		action["description"] = str(JsonTool.pick(ad, ["description", "说明"], ""))
	elif action_variant == null:
		notes.append("缺少行动提案，按默认“答话”处理。")
	else:
		notes.append("行动提案不是对象，按默认“答话”处理。")
	if str(action["type"]) == "end_dialogue" and str(action["description"]).strip_edges().is_empty():
		notes.append("结束对话未附带离开动作描述（设计要求必须附带），已在记录中标注。")

	var inner := str(JsonTool.pick(data, ["inner_thought", "内心想法"], ""))

	var belief_updates := _parse_belief_updates(data, notes)
	var affinity_change := 0
	var affinity_variant: Variant = JsonTool.pick(data, ["affinity_change"], null)
	if affinity_variant is float or affinity_variant is int:
		affinity_change = clampi(int(affinity_variant), -10, 10)

	return {
		"ok": true,
		"error": "",
		"notes": notes,
		"turn_id": turn_id,
		"expected_turn": expected_turn,
		"utterance": utterance,
		"claim_type": claim,
		"action": action,
		"inner_thought": inner,
		"belief_updates": belief_updates,
		"affinity_change": affinity_change,
	}





## 解析 belief_updates 数组：每项 {ref(int), relation(佐证|矛盾), note}；
## 坏项丢弃并记 notes。仅结构校验——ref 是否在闭集内由引擎校验。
static func _parse_belief_updates(data: Dictionary, notes: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = JsonTool.pick(data, ["belief_updates", "信念更新"], null)
	if raw == null:
		return out
	if not (raw is Array):
		notes.append("belief_updates 不是数组，已忽略。")
		return out
	for item in raw:
		if not (item is Dictionary):
			notes.append("belief_updates 含非对象项，已丢弃。")
			continue
		var d: Dictionary = item
		var ref_variant: Variant = JsonTool.pick(d, ["ref", "编号"], null)
		if not (ref_variant is float or ref_variant is int):
			notes.append("belief_updates 项缺少数字 ref，已丢弃。")
			continue
		var relation := str(JsonTool.pick(d, ["relation", "关系"], ""))
		if not RELATIONS.has(relation):
			notes.append("belief_updates 关系非法（%s），已丢弃。" % relation)
			continue
		out.append({"ref": int(ref_variant), "relation": relation, "note": str(JsonTool.pick(d, ["note", "理由"], ""))})
	return out
