class_name ToolcallPlayerState
extends ToolcallBase
## player.state（仅 DM）：申报玩家状态的变更——计数器增减与条目集增删改。
## 合法键完全由状态模板决定（settings/player_state.json）：模板里的计数器/条目集/
## 字段名构成三级闭集，模板之外的键一律丢弃记 notes——引擎不含任何世界观词汇。
## NPC 无权调用（玩家的状态由世界裁定，不由对方嘴说了算）。


const OPS_ARRAY_CAP := 8  # 单次调用每类操作的条数上限


func _init() -> void:
	name = ToolcallCatalog.PLAYER_STATE
	title = "更新玩家状态"
	callers = PackedStringArray([ToolcallCatalog.CALLER_DM])
	args_hint = "{\"counters\": {计数器键: 增量}, \"add\": [{\"collection\": 键, \"entry\": {…}}], \"remove\": [{\"collection\": 键, \"match\": {…}}], \"update\": [{\"collection\": 键, \"match\": {…}, \"set\": {…}}]}"
	doc = PackedStringArray([
		"玩家行动确实改变了其随身状态时调用（获得/失去物品、钱财增减、身心变化、立下约定）；计数器与清单的名称以材料层「玩家状态」段列出的为准，名称之外的一律不认。",
		"counters 给增量（正负数），不是新值；条目字段规则同样以材料层为准。",
		"没有实际变更就不要调用——叙述性细节不需要进状态。",
	])


func validate_args(args: Dictionary, _caller: String, notes: Array[String]) -> Dictionary:
	var out := {"counters": {}, "add": [], "remove": [], "update": []}
	var any := false
	# 计数器：键过模板闭集（key 或显示名均可解析），值须为数字；落地规范化为 key
	var counters_v: Variant = args.get("counters", {})
	if counters_v is Dictionary:
		for key in counters_v:
			var def := PlayerStateSchema.counter(str(key))
			if def.is_empty():
				notes.append("player.state 的计数器「%s」不在模板里，已忽略。" % str(key))
				continue
			var v: Variant = counters_v[key]
			if not (v is float or v is int):
				notes.append("计数器「%s」的增量不是数字，已忽略。" % str(def.get("label", key)))
				continue
			out["counters"][str(def.get("key", key))] = clampi(int(v),
				-PlayerStateSchema.HARD_COUNTER_DELTA, PlayerStateSchema.HARD_COUNTER_DELTA)
			any = true
	elif counters_v != null:
		notes.append("player.state 的 counters 不是对象，已忽略。")
	# 三类条目操作（条目集键同样接受显示名；落地规范化为 key）
	for op_name in ["add", "remove", "update"]:
		var arr: Variant = args.get(op_name, [])
		if not (arr is Array):
			if arr != null:
				notes.append("player.state 的 %s 不是数组，已忽略。" % op_name)
			continue
		var kept := 0
		for item in arr:
			if kept >= OPS_ARRAY_CAP:
				notes.append("player.state 的 %s 超过 %d 条，多余部分已丢弃。" % [op_name, OPS_ARRAY_CAP])
				break
			if not (item is Dictionary):
				notes.append("player.state 的 %s 含非对象项，已丢弃。" % op_name)
				continue
			var d: Dictionary = item
			var col := PlayerStateSchema.collection(str(d.get("collection", "")))
			if col.is_empty():
				notes.append("player.state 的条目集「%s」不在模板里，已丢弃。" % str(d.get("collection", "")))
				continue
			var ckey := str(col.get("key", ""))
			var clean: Dictionary = {"collection": ckey}
			match op_name:
				"add":
					var entry: Variant = PlayerStateSchema.validate_entry(ckey,
						d.get("entry", {}), notes, "player.state 新增条目")
					if entry == null:
						continue
					clean["entry"] = entry
				"remove":
					var m := PlayerStateSchema.validate_match(ckey, d.get("match", {}), notes, "player.state 删除")
					if m.is_empty():
						continue
					clean["match"] = m
				"update":
					var m2 := PlayerStateSchema.validate_match(ckey, d.get("match", {}), notes, "player.state 更新")
					var set_v: Variant = PlayerStateSchema.validate_entry(ckey,
						d.get("set", {}), notes, "player.state 更新条目", false)
					if m2.is_empty() or set_v == null or (set_v as Dictionary).is_empty():
						continue
					clean["match"] = m2
					clean["set"] = set_v
			(out[op_name] as Array).append(clean)
			kept += 1
			any = true
	if not any:
		notes.append("player.state 调用没有任何有效变更，已丢弃。")
		return {}
	return out
