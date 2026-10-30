class_name ToolcallParser
extends RefCounted
## 工具调用解析（Toolcall 层）：模型输出 tool_calls 数组 → 权限与结构校验后的调用列表。
## 与 ResponseParser / DMParser 同款哲学：坏项与越权调用丢弃并记 notes，不报错中断。
## 校验顺序：工具名在目录中 → 调用方有权限（越权丢弃并说明）→ 参数校验
## 委托给工具实例自身（ToolcallBase.validate_args——每个工具的规则内聚在自己的类里）。
## 调用形状：{"tool": "…", "args": {…}}；
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
		var def: ToolcallBase = ToolcallCatalog.def(tool)
		if def == null:
			notes.append("未知工具「%s」，已丢弃。" % tool)
			continue
		if not def.is_allowed(caller):
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
		var validated := def.validate_args(args, caller, notes)
		if validated.is_empty():
			continue
		out.append({"tool": tool, "args": validated})
	return out
