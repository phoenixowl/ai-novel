class_name ToolcallParser
extends RefCounted
## 工具调用解析（Toolcall 层）：模型输出 tool_calls 数组 → 权限与结构校验后的调用列表。
## 与 ResponseParser / DMParser 同款哲学：坏项与越权调用丢弃并记 notes，不报错中断。
## 校验顺序：工具名在目录中 → 调用方有权限（越权丢弃并说明）→ 参数逐项校验
## （缺参数丢弃、可回落参数记 note 回落）。调用形状：{"tool": "…", "args": {…}}；
## 宽容：args 缺失时把该项里除 tool 外的键当参数（扁平写法）；args 存在但不是对象时
## 同样按扁平解析并记 notes。
## 上限 CALL_CAP：单回合超过部分丢弃（防刷屏式调用）。
## 注意：本类只做契约校验，不执行任何写入——执行落在各域控制器（硬规则）。


const CALL_CAP := 8


## 解析 data 里的 tool_calls 为校验后的 [{tool: String, args: Dictionary}]（保持输入顺序）。
## data：模型输出的完整 JSON Dictionary；caller：调用方（ToolcallCatalog.CALLER_*）；
## notes：输出参数，解析过程逐条追加（调试页展示）。
static func parse(data: Dictionary, caller: String, notes: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = JsonTool.pick(data, ["tool_calls", "工具调用"], null)
	if raw == null:
		return out
	if not (raw is Array):
		notes.append("tool_calls 不是数组，已忽略。")
		return out
	for item in raw:
		if out.size() >= CALL_CAP:
			notes.append("工具调用超过 %d 个，多余部分已丢弃。" % CALL_CAP)
			break
		if not (item is Dictionary):
			notes.append("tool_calls 含非对象项，已丢弃。")
			continue
		var d: Dictionary = item
		var tool := str(JsonTool.pick(d, ["tool", "name", "工具"], ""))
		if tool.is_empty():
			notes.append("tool_calls 项缺少 tool 名，已丢弃。")
			continue
		var def := ToolcallCatalog.def(tool)
		if def == null:
			notes.append("未知工具「%s」，已丢弃。" % tool)
			continue
		if not ToolcallCatalog.is_allowed(tool, caller):
			notes.append("工具「%s」不允许 %s 调用（仅 %s），已丢弃。" % [
				tool, caller, "、".join(def.callers)])
			continue
		var args_v: Variant = d.get("args", null)
		var args: Dictionary
		if args_v is Dictionary:
			args = args_v
		else:
			args = d.duplicate()
			args.erase("tool")
			args.erase("name")
			args.erase("工具")
			args.erase("args")
			if args_v != null:
				notes.append("工具「%s」的 args 不是对象，已按扁平字段解析。" % tool)
		var validated := _validate_args(tool, caller, args, notes)
		if validated.is_empty():
			continue
		out.append({"tool": tool, "args": validated})
	return out


## 各工具的参数校验（返回清洗后的 args；空 Dictionary = 丢弃，原因已记 notes）。
static func _validate_args(tool: String, caller: String, args: Dictionary, notes: Array[String]) -> Dictionary:
	match tool:
		ToolcallCatalog.FACT_DECLARE:
			var content := str(args.get("content", "")).strip_edges()
			if content.is_empty():
				notes.append("facts.declare 缺少 content，已丢弃。")
				return {}
			var weight := str(args.get("weight", "minor"))
			if not ["major", "minor"].has(weight):
				notes.append("facts.declare 权重非法（%s），按 minor 处理。" % weight)
				weight = "minor"
			return {"content": content, "weight": weight}
		ToolcallCatalog.DIALOGUE_START:
			var npc := str(args.get("npc", "")).strip_edges()
			var speech := str(args.get("speech", "")).strip_edges()
			if npc.is_empty() or speech.is_empty():
				notes.append("dialogue.start 需要 npc 与 speech，已丢弃。")
				return {}
			return {"npc": npc, "speech": speech}
		ToolcallCatalog.DIALOGUE_END:
			if caller == ToolcallCatalog.CALLER_NPC:
				var departure := str(args.get("departure", "")).strip_edges()
				if departure.is_empty():
					notes.append("dialogue.end 缺少离开动作描述，已补默认描述。")
					departure = "（他结束了这场交谈。）"
				return {"departure": departure}
			var reason := str(args.get("reason", "")).strip_edges()
			return {"reason": reason if not reason.is_empty() else "dm_settle"}
		ToolcallCatalog.AFFINITY_CHANGE:
			var delta_v: Variant = args.get("delta", null)
			if not (delta_v is float or delta_v is int):
				notes.append("affinity.change 缺少数值 delta，已丢弃。")
				return {}
			return {"delta": clampi(int(delta_v), -10, 10)}
		ToolcallCatalog.BELIEF_PROPOSE:
			var ref_v: Variant = args.get("ref", null)
			if not (ref_v is float or ref_v is int) or int(ref_v) <= 0:
				notes.append("belief.propose 需要正整数 ref，已丢弃。")
				return {}
			var relation := str(args.get("relation", ""))
			if not ["佐证", "矛盾"].has(relation):
				notes.append("belief.propose 关系非法（%s），已丢弃。" % relation)
				return {}
			return {"ref": int(ref_v), "relation": relation, "note": str(args.get("note", ""))}
	return {}
