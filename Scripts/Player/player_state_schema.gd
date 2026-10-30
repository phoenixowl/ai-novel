class_name PlayerStateSchema
extends RefCounted
## 玩家状态模板（Player 层）：创作者在 settings/player_state.json 里声明这个世界观
## 玩家的状态由哪些**计数器**（数值资源）与**条目集**（清单）组成。
## 引擎不含任何世界观词汇——工具校验、界面渲染、
## 提示词注入全部由本模板驱动；模板缺失或损坏时回落内置的通用默认模板。
## 运行期数值在 PlayerStateStore（saves/），模板是作者数据（settings/，只读）。


static func schema_path() -> String:
	return GamePaths.author_player_state_path()

const HARD_COUNTER_DELTA := 999   # 单轮计数器增量硬顶（工具层钳制）
const HARD_COLLECTION_CAP := 40   # 条目集上限硬顶（模板声明再大也被钳到这里）
const HARD_FIELD_MAX := 80        # 字段字长硬顶
const HARD_FIELDS := 6            # 每个条目集最多字段数


static var _counters: Array = []   # [{key, label, min, max, initial, hint}]
static var _collections: Array = []  # [{key, label, cap, canon_sync, npc_visible, fields}]
static var _loaded := false
static var _report: Array[String] = []


## 全部计数器声明（按模板顺序）。
static func counters() -> Array:
	_ensure()
	return _counters


## 全部条目集声明（按模板顺序）。
static func collections() -> Array:
	_ensure()
	return _collections


## 按 key 或显示名（label）解析计数器声明——模型只能看到提示词里的显示名，
## 因此两者都必须可解析（先精确 key，再 label）。无则空 Dictionary。
static func counter(key_or_label: String) -> Dictionary:
	_ensure()
	for c in _counters:
		if str(c.get("key", "")) == key_or_label:
			return c
	for c in _counters:
		if str(c.get("label", "")) == key_or_label:
			return c
	return {}


## 按 key 或显示名（label）解析条目集声明（同上）。无则空 Dictionary。
static func collection(key_or_label: String) -> Dictionary:
	_ensure()
	for c in _collections:
		if str(c.get("key", "")) == key_or_label:
			return c
	for c in _collections:
		if str(c.get("label", "")) == key_or_label:
			return c
	return {}


## 模板加载报告（调试页/加载报告用）。
static func report() -> Array[String]:
	_ensure()
	return _report


# ———— 条目字段校验（工具层与存储层共用；字段规则唯一来源） ————


## 校验并清洗一条记录的全部字段。字段键接受 key 或显示名（label）——模型只能
## 看到提示词里的显示名，落地规范化为 key。require_needed：true=必填缺失视为
## 不合格（新增用，并套字段默认值）；false=只清洗给出的字段（更新 set 用，
## 不套默认值，避免把未提及的字段重置）。返回清洗后的 Dictionary；null = 不合格
## （原因已记 notes）。给出的未知字段聚合为一条 note 后丢弃。
static func validate_entry(collection_key: String, values: Dictionary,
		notes: Array[String], what: String, require_needed := true) -> Variant:
	var col := collection(collection_key)
	if col.is_empty():
		return null  # 条目集不存在由调用方先拦截并记 notes
	var out := {}
	var missing: Array[String] = []
	var unknown: Array[String] = []
	var fields: Array = col.get("fields", [])
	for f in fields:
		var fk := str(f.get("key", ""))
		var label := str(f.get("label", fk))
		var given: Variant = _take_given(values, fk, label)
		if given != null:
			var cleaned: Variant = _clean_field(f, given)
			if cleaned == null:
				notes.append("%s 的字段「%s」类型不合法，整条丢弃。" % [what, label])
				return null
			out[fk] = cleaned
		elif bool(f.get("required", false)):
			if require_needed:
				missing.append(label)
		elif f.has("default") and require_needed:
			out[fk] = f["default"]
	for k in values:
		if _resolve_field_key(fields, str(k)).is_empty():
			unknown.append(str(k))
	if not missing.is_empty():
		notes.append("%s 缺少必填字段：%s，整条丢弃。" % [what, "、".join(missing)])
		return null
	if not unknown.is_empty():
		notes.append("%s 含模板外字段（%s），已忽略。" % [what, "、".join(unknown)])
	return out


## 校验 match（定位用键值）：键同样接受 key 或显示名；返回清洗后的 Dictionary
## （键规范化为字段 key，值转字符串）。参数名用 match_fields 避开关键字 match。
static func validate_match(collection_key: String, match_fields: Dictionary,
		notes: Array[String], what: String) -> Dictionary:
	var col := collection(collection_key)
	if col.is_empty():
		return {}
	var fields: Array = col.get("fields", [])
	var out := {}
	for k in match_fields:
		var fk := _resolve_field_key(fields, str(k))
		if fk.is_empty():
			notes.append("%s 的匹配字段「%s」不在模板里，已忽略该匹配。" % [what, str(k)])
			continue
		out[fk] = str(match_fields[k])
	if out.is_empty():
		notes.append("%s 缺少可用的匹配字段，已忽略。" % what)
	return out


## 条目的一行文本（界面与提示词渲染共用）：按模板字段顺序拼"label：value"。
static func entry_text(collection_key: String, entry: Dictionary) -> String:
	var col := collection(collection_key)
	if col.is_empty():
		return ""
	var parts: Array[String] = []
	for f in col.get("fields", []):
		var fk := str(f.get("key", ""))
		var v: Variant = entry.get(fk, null)
		if v == null or str(v).is_empty():
			continue
		parts.append("%s：%s" % [str(f.get("label", fk)), str(v)])
	return "· " + "；".join(parts) if not parts.is_empty() else "·（空条目）"


# ———— 内部 ————


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var data := JsonTool.read_json_file(schema_path())
	if data.is_empty():
		_report.append("未找到 settings/player_state.json，使用内置默认状态模板")
		_build_builtin()
		return
	if not _build(data):
		_report.append("状态模板结构损坏，回落内置默认模板")
		_counters = []
		_collections = []
		_build_builtin()


## 结构校验（不改全局状态）：counters/collections 是否为可选数组、条目是否为对象。
## 供 AuthorTool 编辑页即时校验用；字段级问题仍由 _build 宽容跳过并记报告。
static func validate_schema_shape(data: Dictionary) -> bool:
	var raw_counters: Variant = data.get("counters", [])
	if not (raw_counters is Array):
		return false
	for item in raw_counters:
		if not (item is Dictionary):
			return false
	var raw_collections: Variant = data.get("collections", [])
	if not (raw_collections is Array):
		return false
	for item in raw_collections:
		if not (item is Dictionary):
			return false
	return true


static func _build(data: Dictionary) -> bool:
	var raw_counters: Variant = data.get("counters", [])
	if not (raw_counters is Array):
		return false
	for item in raw_counters:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item
		var key := str(d.get("key", "")).strip_edges()
		if key.is_empty() or not counter(key).is_empty():
			_report.append("计数器 key 缺失或重复，已跳过：%s" % key)
			continue
		var def := {
			"key": key,
			"label": str(d.get("label", key)),
			"min": int(d.get("min", 0)),
			"max": int(d.get("max", 9999)),
			"initial": int(d.get("initial", 0)),
			"hint": str(d.get("hint", "")),
		}
		if def["max"] < def["min"]:
			def["max"] = def["min"]
		def["initial"] = clampi(int(def["initial"]), int(def["min"]), int(def["max"]))
		_counters.append(def)
	var raw_collections: Variant = data.get("collections", [])
	if not (raw_collections is Array):
		return false
	for item in raw_collections:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item
		var key := str(d.get("key", "")).strip_edges()
		if key.is_empty() or not collection(key).is_empty():
			_report.append("条目集 key 缺失或重复，已跳过：%s" % key)
			continue
		var fields: Array = []
		var raw_fields: Variant = d.get("fields", [])
		if raw_fields is Array:
			for f in raw_fields:
				if not (f is Dictionary) or fields.size() >= HARD_FIELDS:
					continue
				var fd: Dictionary = f
				var fk := str(fd.get("key", "")).strip_edges()
				if fk.is_empty() or _has_field(fields, fk):
					continue
				var type := str(fd.get("type", "string"))
				if not ["string", "int", "bool"].has(type):
					type = "string"
				var field := {
					"key": fk,
					"label": str(fd.get("label", fk)),
					"required": bool(fd.get("required", false)),
					"type": type,
					"max": clampi(int(fd.get("max", HARD_FIELD_MAX)), 1, HARD_FIELD_MAX),
				}
				if type == "int":
					field["min"] = int(fd.get("min", 0))
				if fd.has("default"):
					var cleaned: Variant = _clean_field(field, fd["default"])
					if cleaned != null:
						field["default"] = cleaned
				fields.append(field)
		if fields.is_empty():
			_report.append("条目集「%s」没有可用字段，已跳过。" % key)
			continue
		_collections.append({
			"key": key,
			"label": str(d.get("label", key)),
			"cap": clampi(int(d.get("cap", 20)), 1, HARD_COLLECTION_CAP),
			"canon_sync": bool(d.get("canon_sync", false)),
			"npc_visible": bool(d.get("npc_visible", false)),
			"fields": fields,
		})
	return true


## 内置默认模板：无任何世界观词汇（作者未提供模板文件时的兜底）。
static func _build_builtin() -> void:
	_counters = [
		{"key": "money", "label": "货币", "min": 0, "max": 9999, "initial": 0, "hint": "通用的价值媒介"},
	]
	_collections = [
		{"key": "items", "label": "随身物品", "cap": 20, "canon_sync": false, "npc_visible": false,
			"fields": [
				{"key": "name", "label": "名称", "required": true, "type": "string", "max": 40},
				{"key": "qty", "label": "数量", "type": "int", "min": 1, "max": 99, "default": 1},
				{"key": "note", "label": "备注", "type": "string", "max": 60},
			]},
		{"key": "conditions", "label": "状态", "cap": 10, "canon_sync": false, "npc_visible": false,
			"fields": [
				{"key": "name", "label": "状况", "required": true, "type": "string", "max": 40},
				{"key": "note", "label": "说明", "type": "string", "max": 60},
			]},
		{"key": "bonds", "label": "未了之约", "cap": 20, "canon_sync": false, "npc_visible": false,
			"fields": [
				{"key": "text", "label": "内容", "required": true, "type": "string", "max": 80},
				{"key": "done", "label": "已完成", "type": "bool", "default": false},
			]},
		{"key": "notes", "label": "备注", "cap": 30, "canon_sync": false, "npc_visible": false,
			"fields": [
				{"key": "text", "label": "内容", "required": true, "type": "string", "max": 80},
			]},
	]


static func _clean_field(field: Dictionary, value: Variant) -> Variant:
	var ftype := str(field.get("type", "string"))
	if ftype == "int":
		if not (value is float or value is int):
			return null
		return clampi(int(value), int(field.get("min", 0)), int(field.get("max", 99999)))
	if ftype == "bool":
		if value is bool:
			return value
		if value is String and ["true", "yes", "1", "是"].has((value as String).to_lower()):
			return true
		if value is String and ["false", "no", "0", "否"].has((value as String).to_lower()):
			return false
		return null
	var t := str(value).strip_edges()
	if t.length() > int(field.get("max", HARD_FIELD_MAX)):
		t = t.substr(0, int(field.get("max", HARD_FIELD_MAX)))
	return t


static func _has_field(fields: Array, key: String) -> bool:
	for f in fields:
		if str(f.get("key", "")) == key:
			return true
	return false


## 从 values 里取出某字段的给定值：先按字段 key，再按显示名；都没有返回 null。
static func _take_given(values: Dictionary, field_key: String, field_label: String) -> Variant:
	if values.has(field_key):
		return values[field_key]
	if not field_label.is_empty() and values.has(field_label):
		return values[field_label]
	return null


## 把给出的键解析为字段 key（先 key 后显示名）；未命中返回空串。
static func _resolve_field_key(fields: Array, given_key: String) -> String:
	if _has_field(fields, given_key):
		return given_key
	for f in fields:
		if str(f.get("label", "")) == given_key:
			return str(f.get("key", ""))
	return ""


# ———— 测试辅助 ————


## 清空内存状态（下次访问重新读盘）。测试用。
static func reset_for_test() -> void:
	_counters = []
	_collections = []
	_loaded = false
	_report = []
