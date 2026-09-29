class_name MaterialPack
extends RefCounted
## 材料包：某一轮回应的全部输入，分两半（设计 4.3 / 4.4）：
##   素材包（场景素材、知识、记忆、玩家原话、自身状态）——发言的原料
##   行动清单（阶段一仅三项对话行动）——行动的约束
## 组装完成后冻结不变：模型回应必须基于一个确定的瞬间（设计 4.1 第3步）。


var turn_number := 1
var max_turns := 12

var npc: CharacterCard
var scene: SceneCard

# ———— 素材包 ————
var scene_materials := {}  # environment / atmosphere / opening_situation
var player_utterance := ""  # 玩家这句话（原样引用，不改写）
var knowledge_entries: Array[Dictionary] = []  # 本轮展示的知识日志条目（{seq,content,speaker,trust,status,…}）
var player_info := {}  # 玩家信息 {name, identity, appearance}（末尾强调段用）
var cross_dialogue_summary := ""  # 背景摘要（作者写的跨对话记忆，可为空）
var session_lines: Array[String] = []  # 最近会话摘要（知识日志确定性生成）
var dialogue_history: Array = []  # 本段对话已确认轮次的事件（Dictionary 列表）
var npc_state := {}  # mood / tone

# ———— 行动清单 ————
var action_list: Array[Dictionary] = []

var assembled_at := ""


## 把一条已确认事件渲染成一行记忆文本（素材包与提示词共用）
static func history_line(event: Dictionary) -> String:
	match str(event.get("event", "")):
		"player_utterance":
			return "[玩家] " + str(event.get("text", ""))
		"npc_utterance":
			return "[%s·%s] %s" % [event.get("npc_name", "NPC"), event.get("claim_type", ""), event.get("text", "")]
		"npc_silence":
			return "[%s·沉默] %s" % [event.get("npc_name", "NPC"), event.get("description", "")]
	return str(event.get("event", ""))


## 调试面板（UI ②材料包页）的展示文本
func to_display_text() -> String:
	var p: Array[String] = []
	p.append("[color=#e0b36a][b]◆ 材料包 · 第 %d / %d 轮[/b][/color]   组装于 %s（已冻结）" % [turn_number, max_turns, assembled_at])
	p.append("")
	p.append("[b]■ 回应者[/b]")
	p.append("· %s（%s）" % [npc.display_name, npc.id])
	p.append("")
	p.append("[b]■ 场景素材[/b]")
	p.append("· 场景：%s" % scene.scene_name)
	_append_field(p, "环境与陈设", str(scene_materials.get("environment", "")))
	_append_field(p, "氛围", str(scene_materials.get("atmosphere", "")))
	_append_field(p, "开场情境", str(scene_materials.get("opening_situation", "")))
	p.append("")
	p.append("[b]■ 玩家原话（原样引用，不改写、不执行）[/b]")
	p.append("“%s”" % player_utterance)
	p.append("")
	p.append("[b]■ 你的知识日志（%d 条，含已失效）[/b]" % knowledge_entries.size())
	if knowledge_entries.is_empty():
		p.append("（该角色一无所知）")
	else:
		for e in knowledge_entries:
			var entry := e as Dictionary
			var tag := "[%d]（%s · %s）" % [int(entry.get("seq", 0)), str(entry.get("speaker", "")), str(entry.get("trust", ""))]
			if str(entry.get("status", "active")) == "voided":
				tag += "〔已失效〕"
			p.append("· %s：%s" % [tag, str(entry.get("content", ""))])
	p.append("")
	p.append("[b]■ 记忆[/b]")
	if not session_lines.is_empty():
		for line in session_lines:
			p.append(line)
	p.append("· 跨对话摘要：" + (cross_dialogue_summary if not cross_dialogue_summary.is_empty() else "（此前没有打过交道）"))
	p.append("· 本段对话已确认记录（%d 条）：" % dialogue_history.size())
	if dialogue_history.is_empty():
		p.append("  （这是第一轮）")
	else:
		for event in dialogue_history:
			p.append("  " + history_line(event))
	p.append("")
	p.append("[b]■ 自身状态[/b]")
	p.append("· 心情：%s" % str(npc_state.get("mood", "")))
	p.append("· 人设基调：%s" % str(npc_state.get("tone", "")))
	p.append("")
	p.append("[b]■ 行动清单（阶段一：仅对话行动）[/b]")
	for action in action_list:
		p.append("· [color=#90be6d]%s[/color]（%s）%s" % [action.get("type", ""), action.get("name", ""), action.get("description", "")])
	p.append("")
	p.append("[color=#8d99ae]注：完整提示词见『③ 提示词』页。结构检查、事实审核、重试兜底属后续里程碑（M1.1+）。[/color]")
	return "\n".join(p)


## 值非空时向 p 追加一行“· label：value”。value 为空跳过。
static func _append_field(p: Array[String], label: String, value: String) -> void:
	if value.is_empty():
		return
	p.append("· %s：%s" % [label, value])
