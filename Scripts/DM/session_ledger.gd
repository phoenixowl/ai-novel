class_name SessionLedger
extends RefCounted
## 会话草稿账（DM 层）：DM 申报的"未定案变化"——玩家行动造成的疑似持久变化，
## 但尚未经过结算确认，因此**不是正典**：不写入正典文件、不约束后续叙述、
## NPC 不可引用。作用：让 DM 在后续回合稳定记得这些未定案的变化（世界流水
## 窗口会滑走，而申报的内容提炼自叙述）；结算时由整理者 agent 通读全量记录
## 定夺去留——升格为正典事实或随流水自然消亡。
## 逐字去重（同表述只记一次）；随探索开始清空；纯内存（与流水同生命周期）。


const RENDER_CAP := 8  # 注入 DM 材料层的最大行数

var _items: Array[String] = []


## 申报一条草稿（逐字去重）。返回是否新增。
func push(content: String) -> bool:
	var text := content.strip_edges()
	if text.is_empty() or _items.has(text):
		return false
	_items.append(text)
	return true


## 渲染为 DM 材料层的"未定事项"行（最近 RENDER_CAP 条，正序）。
func render_lines(cap := RENDER_CAP) -> Array[String]:
	var start := maxi(0, _items.size() - cap)
	var out: Array[String] = []
	for i in range(start, _items.size()):
		out.append("· " + _items[i])
	return out


func size() -> int:
	return _items.size()


func clear() -> void:
	_items.clear()
