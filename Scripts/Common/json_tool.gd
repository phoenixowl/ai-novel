class_name JsonTool
extends RefCounted
## JSON 读取工具（静态，Common 层）。
## 吸收了原 SettingKeys（中英文键名兼容读取）与原 ResponseParser 的通用提取实现，
## 是全项目唯一的「宽容 JSON 处理」实现处，供设定资料加载、模型输出解析、
## 以及未来的旁白/道具生成等功能共用。


## 按顺序取第一个存在且非 null 的键（兼容作者/模型输出的中英文键名）
static func pick(data: Dictionary, keys: Array, default_value: Variant = "") -> Variant:
	for key in keys:
		if data.has(key) and data[key] != null:
			return data[key]
	return default_value


## 同 pick 的布尔版（“是/敏感/true/1”等字面量也接受）。
static func pick_bool(data: Dictionary, keys: Array, default_value: bool = false) -> bool:
	var value: Variant = pick(data, keys, default_value)
	if value is bool:
		return value
	if value is String:
		return ["true", "yes", "1", "是", "敏感"].has((value as String).to_lower())
	return default_value


## 同 pick 的字符串数组版（非数组返回空）。
static func pick_strings(data: Dictionary, keys: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var value: Variant = pick(data, keys, [])
	if value is Array:
		for item in value:
			out.append(str(item))
	return out


## 剥离 markdown 代码围栏（```json … ```），容忍模型输出带围栏的情况
static func strip_code_fence(raw: String) -> String:
	var text := raw.strip_edges()
	if text.begins_with("```"):
		var first_newline := text.find("\n")
		if first_newline != -1:
			text = text.substr(first_newline + 1)
		var fence_end := text.rfind("```")
		if fence_end != -1:
			text = text.substr(0, fence_end)
	return text.strip_edges()


## 从任意文本中提取首个完整 JSON 对象（括号配平，跳过字符串内的括号）；失败返回 null
static func extract_object(text: String) -> Variant:
	var trimmed := text.strip_edges()
	if trimmed.begins_with("{"):
		var direct: Variant = JSON.parse_string(trimmed)
		if direct is Dictionary:
			return direct
	var start := text.find("{")
	while start != -1:
		var depth := 0
		var in_string := false
		var escaped := false
		for i in range(start, text.length()):
			var c := text[i]
			if in_string:
				if escaped:
					escaped = false
				elif c == "\\":
					escaped = true
				elif c == "\"":
					in_string = false
			else:
				if c == "\"":
					in_string = true
				elif c == "{":
					depth += 1
				elif c == "}":
					depth -= 1
					if depth == 0:
						var candidate := text.substr(start, i - start + 1)
						var parsed: Variant = JSON.parse_string(candidate)
						if parsed is Dictionary:
							return parsed
						break
		start = text.find("{", start + 1)
	return null


## 剥围栏 + 提取的组合（模型输出解析的标准入口）；失败返回 null
static func try_parse(text: String) -> Variant:
	return extract_object(strip_code_fence(text))
