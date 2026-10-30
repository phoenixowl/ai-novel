class_name PlayerStateStore
extends RefCounted
## 玩家状态存取器（Player 层）：saves/world/player_state.json 的唯一读写入口。
## 结构与模板同构——计数器（数值）+ 条目集（清单）；模板变更后旧数值按 key 对号
## 入座，模板里删掉的键自然失效。一切变更经 apply()（模板校验 + 钳制 + notes），
## 返回结构化结果（含 canon_sync 所需的操作回执与摘要行）供 DM 层落地。


static func path() -> String:
	return GamePaths.player_state_path()

static var _data := {}  # {"counters": {key: int}, "collections": {key: [entries]}}
static var _loaded := false


## 当前快照（深拷贝；界面与提示词渲染用）。
static func snapshot() -> Dictionary:
	_ensure()
	return _data.duplicate(true)


## 应用一批变更（ToolcallPlayerState 校验后的规范形态，键已规范化；本层再按模板
## 防御一遍，键/显示名均可解析）。
## changes：{counters: {key: 增量}, add: [{collection, entry}],
##           remove: [{collection, match}], update: [{collection, match, set}]}
## 返回 {changed: bool, summary: String, ops: [{op, key, label, primary, delta, value}]}——
## ops 供 DM 层做 canon_sync 与事件留痕；summary 用模板 label 组装（无世界观硬编码）。
static func apply(changes: Dictionary, notes: Array[String]) -> Dictionary:
	_ensure()
	var result := {"changed": false, "summary": "", "ops": []}
	var parts: Array[String] = []
	# 计数器：增量 + 上下限钳位
	var counters_in: Dictionary = changes.get("counters", {})
	for key in counters_in:
		var def := PlayerStateSchema.counter(str(key))
		if def.is_empty():
			notes.append("未知计数器「%s」，已忽略。" % str(key))
			continue
		var ckey := str(def.get("key", key))
		var delta_v: Variant = counters_in[key]
		if not (delta_v is float or delta_v is int):
			notes.append("计数器「%s」的增量不是数字，已忽略。" % str(def.get("label", key)))
			continue
		var delta := clampi(int(delta_v), -PlayerStateSchema.HARD_COUNTER_DELTA, PlayerStateSchema.HARD_COUNTER_DELTA)
		var old := int(_data["counters"].get(ckey, def.get("initial", 0)))
		var new_v := clampi(old + delta, int(def.get("min", 0)), int(def.get("max", 9999)))
		if new_v == old:
			if delta != 0:
				notes.append("「%s」的变动被上下限钳制，保持 %d。" % [str(def.get("label", key)), old])
			continue
		_data["counters"][ckey] = new_v
		result["changed"] = true
		var op := {"op": "counter", "key": ckey, "label": str(def.get("label", key)),
			"delta": delta, "value": new_v}
		(result["ops"] as Array).append(op)
		parts.append("%s %+d → %d" % [str(def.get("label", key)), delta, new_v])
		if new_v != old + delta:
			notes.append("「%s」触及上下限，钳制为 %d。" % [str(def.get("label", key)), new_v])
	# 条目集三类操作
	for item in changes.get("add", []) as Array:
		var r := _op_add(item, notes)
		if not r.is_empty():
			(result["ops"] as Array).append(r)
			parts.append(str(r.get("text", "")))
			result["changed"] = true
	for item in changes.get("remove", []) as Array:
		var r2 := _op_remove(item, notes)
		if not r2.is_empty():
			(result["ops"] as Array).append(r2)
			parts.append(str(r2.get("text", "")))
			result["changed"] = true
	for item in changes.get("update", []) as Array:
		var r3 := _op_update(item, notes)
		if not r3.is_empty():
			(result["ops"] as Array).append(r3)
			parts.append(str(r3.get("text", "")))
			result["changed"] = true
	if bool(result["changed"]):
		result["summary"] = "；".join(parts)
		save()
	return result


## DM 材料层渲染行（全部计数器与条目集；模板驱动，模板里没有的段落不出现）。
static func render_dm_lines() -> Array[String]:
	_ensure()
	var lines: Array[String] = []
	for c in PlayerStateSchema.counters():
		var key := str(c.get("key", ""))
		var value := int(_data["counters"].get(key, c.get("initial", 0)))
		var line := "· %s：%d" % [str(c.get("label", key)), value]
		if not str(c.get("hint", "")).is_empty():
			line += "（%s）" % str(c.get("hint", ""))
		lines.append(line)
	for col in PlayerStateSchema.collections():
		var key := str(col.get("key", ""))
		var entries: Array = _data["collections"].get(key, [])
		lines.append("· %s（%d/%d）" % [str(col.get("label", key)), entries.size(), int(col.get("cap", 20))])
		for e in entries:
			lines.append("  " + PlayerStateSchema.entry_text(key, e as Dictionary).substr(2))
	return lines


## NPC 材料层渲染行：只含 npc_visible=true 的条目集（默认一个都没有）。
static func render_npc_lines() -> Array[String]:
	_ensure()
	var lines: Array[String] = []
	for col in PlayerStateSchema.collections():
		if not bool(col.get("npc_visible", false)):
			continue
		var key := str(col.get("key", ""))
		var entries: Array = _data["collections"].get(key, [])
		if entries.is_empty():
			continue
		lines.append("· %s（%s）" % [str(col.get("label", key)),
			"；".join(entries.map(func(e): return PlayerStateSchema.entry_text(key, e as Dictionary).substr(2)))])
	return lines


## 一键清空（删除存档文件并按模板重建初始值）——玩家状态窗的"清空"入口。
static func reset_all() -> void:
	_data = {}
	_loaded = true
	_init_from_schema()
	if FileAccess.file_exists(path()):
		DirAccess.remove_absolute(path())


## 清空内存状态（测试用；不删磁盘文件）。
static func reset_for_test() -> void:
	_data = {}
	_loaded = false


static func save() -> void:
	DirAccess.make_dir_recursive_absolute(GamePaths.world_dir())
	JsonTool.write_json_file(path(), _data)


# ———— 内部 ————


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var data := JsonTool.read_json_file(path())
	if data.is_empty():
		_init_from_schema()
		return
	# 按当前模板归位：模板外的键丢弃，计数器值钳位；条目原样保留（写入时已校验）
	_data = {"counters": {}, "collections": {}}
	var raw_counters: Dictionary = data.get("counters", {})
	for c in PlayerStateSchema.counters():
		var key := str(c.get("key", ""))
		if raw_counters.has(key):
			_data["counters"][key] = clampi(int(raw_counters[key]),
				int(c.get("min", 0)), int(c.get("max", 9999)))
		else:
			_data["counters"][key] = int(c.get("initial", 0))
	var raw_collections: Dictionary = data.get("collections", {})
	for col in PlayerStateSchema.collections():
		var key := str(col.get("key", ""))
		var entries: Variant = raw_collections.get(key, [])
		_data["collections"][key] = entries if entries is Array else []


static func _init_from_schema() -> void:
	_data = {"counters": {}, "collections": {}}
	for c in PlayerStateSchema.counters():
		_data["counters"][str(c.get("key", ""))] = int(c.get("initial", 0))
	for col in PlayerStateSchema.collections():
		_data["collections"][str(col.get("key", ""))] = []


static func _op_add(item: Dictionary, notes: Array[String]) -> Dictionary:
	var ckey := str(item.get("collection", ""))
	var col := PlayerStateSchema.collection(ckey)
	if col.is_empty():
		notes.append("未知条目集「%s」，已忽略。" % ckey)
		return {}
	ckey = str(col.get("key", ckey))  # 规范化为模板 key（显示名解析后落地仍进同一个桶）
	var entry: Variant = PlayerStateSchema.validate_entry(ckey, item.get("entry", {}), notes, "新增条目")
	if entry == null:
		return {}
	var entries: Array = _data["collections"].get(ckey, [])
	if entries.size() >= int(col.get("cap", 20)):
		notes.append("「%s」已满（上限 %d），新条目被拒绝。" % [str(col.get("label", ckey)), int(col.get("cap", 20))])
		return {}
	entries.append(entry)
	_data["collections"][ckey] = entries
	return {"op": "add", "key": ckey, "label": str(col.get("label", ckey)),
		"primary": _primary(col, entry as Dictionary),
		"text": "获得%s：%s" % [str(col.get("label", ckey)), _primary(col, entry as Dictionary)],
		"canon_sync": bool(col.get("canon_sync", false))}


static func _op_remove(item: Dictionary, notes: Array[String]) -> Dictionary:
	var ckey := str(item.get("collection", ""))
	var col := PlayerStateSchema.collection(ckey)
	if col.is_empty():
		notes.append("未知条目集「%s」，已忽略。" % ckey)
		return {}
	ckey = str(col.get("key", ckey))  # 规范化为模板 key
	var match_fields := PlayerStateSchema.validate_match(ckey, item.get("match", {}), notes, "删除条目")
	if match_fields.is_empty():
		return {}
	var entries: Array = _data["collections"].get(ckey, [])
	var index := _find_match(entries, match_fields)
	if index == -1:
		notes.append("「%s」里没有匹配的条目，删除忽略。" % str(col.get("label", ckey)))
		return {}
	var removed: Dictionary = entries[index]
	entries.remove_at(index)
	_data["collections"][ckey] = entries
	return {"op": "remove", "key": ckey, "label": str(col.get("label", ckey)),
		"primary": _primary(col, removed),
		"text": "失去%s：%s" % [str(col.get("label", ckey)), _primary(col, removed)],
		"canon_sync": bool(col.get("canon_sync", false))}


static func _op_update(item: Dictionary, notes: Array[String]) -> Dictionary:
	var ckey := str(item.get("collection", ""))
	var col := PlayerStateSchema.collection(ckey)
	if col.is_empty():
		notes.append("未知条目集「%s」，已忽略。" % ckey)
		return {}
	ckey = str(col.get("key", ckey))  # 规范化为模板 key
	var match_fields := PlayerStateSchema.validate_match(ckey, item.get("match", {}), notes, "更新条目")
	if match_fields.is_empty():
		return {}
	var set_values: Variant = PlayerStateSchema.validate_entry(ckey, item.get("set", {}),
		notes, "更新条目", false)
	if set_values == null or (set_values as Dictionary).is_empty():
		return {}
	var entries: Array = _data["collections"].get(ckey, [])
	var index := _find_match(entries, match_fields)
	if index == -1:
		notes.append("「%s」里没有匹配的条目，更新忽略。" % str(col.get("label", ckey)))
		return {}
	var entry: Dictionary = entries[index]
	entry.merge(set_values as Dictionary, true)
	entries[index] = entry
	_data["collections"][ckey] = entries
	return {"op": "update", "key": ckey, "label": str(col.get("label", ckey)),
		"primary": _primary(col, entry),
		"text": "更新%s：%s" % [str(col.get("label", ckey)), _primary(col, entry)],
		"canon_sync": false}


static func _find_match(entries: Array, match_fields: Dictionary) -> int:
	for i in entries.size():
		var e: Dictionary = entries[i]
		var hit := true
		for k in match_fields:
			if str(e.get(k, "")) != str(match_fields[k]):
				hit = false
				break
		if hit:
			return i
	return -1


## 条目的首要文本（canon_sync 事实与摘要用）：第一个必填字段的值，退而求其次第一个字段。
static func _primary(col: Dictionary, entry: Dictionary) -> String:
	var fields: Array = col.get("fields", [])
	for f in fields:
		if bool(f.get("required", false)):
			return str(entry.get(str(f.get("key", "")), ""))
	if not fields.is_empty():
		return str(entry.get(str(fields[0].get("key", "")), ""))
	return ""
