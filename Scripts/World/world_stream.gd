class_name WorldStream
extends RefCounted
## 世界流水（World 层，静态存取器）：叙述事件 + 对话回声副本的单一混排事件流——
## DM 上下文、世界屏渲染、结算提取三处共用的唯一数据源（与 CanonStore 同款全局入口）。
## 写入只来自 DMController（叙述域）与对话回声订阅；对话域对世界上下文**只读**
##（recent_narration_only_lines，硬线②）。all() 返回内部数组的引用——按只读约定使用。


static var _events: Array = []


# ———— 写入（旁白控制器专用） ————


## 追加一条叙述域事件：打上回合号与统一序号（调用方已持有回合号）。
## turn：当前世界回合号；event：统一记录格式的 Dictionary（event 键必需）。
static func append_narration(event: Dictionary, turn: int) -> void:
	if not event.has("turn"):
		event["turn"] = turn
	_finish_append(event, "narration")


## 追加一条对话事件的回声副本：打 domain 标记与统一序号（对话自身的 turn 保留原值）。
static func append_dialogue_echo(event: Dictionary) -> void:
	_finish_append(event.duplicate(true), "dialogue")


static func _finish_append(event: Dictionary, domain: String) -> void:
	event["seq"] = _events.size() + 1
	event["domain"] = domain
	_events.append(event)


# ———— 查询（三处共用；只统计有内容的事件行） ————


## 近期混排行（叙述与对话回声，最近 n 行，正序）——DM 材料层与进场描述用。
static func recent_mixed_lines(n: int) -> Array[String]:
	var lines: Array[String] = []
	var count := 0
	for i in range(_events.size() - 1, -1, -1):
		var line := _render_line(_events[i] as Dictionary)
		if not line.is_empty():
			lines.push_front(line)
			count += 1
			if count >= n:
				break
	return lines


## 叙述域近期行（不含对话回声，最近 n 行，正序）——对话材料包"此刻之前发生了什么"用，
## 与对话自身的已确认记录槽避免重复。
static func recent_narration_only_lines(n: int) -> Array[String]:
	var lines: Array[String] = []
	var count := 0
	for i in range(_events.size() - 1, -1, -1):
		var event := _events[i] as Dictionary
		if str(event.get("domain", "")) == "dialogue":
			continue
		var line := _render_line(event)
		if not line.is_empty():
			lines.push_front(line)
			count += 1
			if count >= n:
				break
	return lines


## 本段探索的全部有内容行（正序）——结算提取的输入。
static func session_lines() -> Array[String]:
	var lines: Array[String] = []
	for raw in _events:
		var line := _render_line(raw as Dictionary)
		if not line.is_empty():
			lines.append(line)
	return lines


## 全部事件（只读约定：返回内部数组引用，供 UI/测试观察；不要外部修改）。
static func all() -> Array:
	return _events


## 当前条数。
static func size() -> int:
	return _events.size()


# ———— 管理 ————


## 清空流水（开始新探索：回合与记录重置，世界正典与位置保留）。
static func clear() -> void:
	_events.clear()


## 清空全部状态（测试用）。
static func reset_for_test() -> void:
	_events = []


# ———— 内部 ————


## 一条世界流水的渲染行：叙述域与对话域各自渲染，过程事件返回空串（不占行数）。
static func _render_line(event: Dictionary) -> String:
	if str(event.get("domain", "")) == "dialogue":
		return DialoguePack.history_line(event)
	return DMPack.history_line(event)
