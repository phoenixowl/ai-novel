class_name DialoguePack
extends RefCounted
## 材料包（Models 层）：对话某一轮的全部输入，分两半——
##   素材包（场景素材、玩家原话、信念层、世界事实、记忆、自身状态）——发言的原料
##   行动清单（answer / silence / end_dialogue）——行动的约束
## 组装完成后冻结不变：模型回应必须基于一个确定的瞬间。

var turn_number := 1
var max_turns := 12

var npc: Person            # 回应者
var scene: Location        # 对话场景

# ———— 素材包 ————
var scene_materials := {}  # environment / atmosphere / opening_situation
var player_utterance := ""  # 玩家这句话（原样引用，不改写）
var knowledge_entries: Array[KnowledgeEntry] = []  # 信念层（含 stale，由渲染层现算）
var world_facts: Array[CanonFact] = []  # 检索注入的世界事实（对正典只读）
var player_info := {}  # 玩家信息 {name, identity, appearance}
var cross_dialogue_summary := ""  # 背景摘要（作者写的跨对话记忆，可为空）
var world_context: Array[String] = []  # 此刻之前发生了什么（叙述域近期事件；统一入口的共享上下文）
var session_lines: Array[String] = []  # 最近会话记忆
var dialogue_history: Array = []  # 本段对话已确认轮次的事件（Dictionary 列表）
var npc_state := {}  # tone / affinity（好感度经提示词与调试页同构渲染）

# ———— 行动清单 ————
var action_list: Array[Dictionary] = []

var assembled_at := ""


## 把一条已确认事件渲染成一行记忆文本（素材包与提示词共用）。
static func history_line(event: Dictionary) -> String:
	match str(event.get("event", "")):
		"player_utterance":
			return "[玩家] " + str(event.get("text", ""))
		"npc_utterance":
			return "[%s·%s] %s" % [event.get("npc_name", "NPC"), event.get("claim_type", ""), event.get("text", "")]
		"npc_silence":
			return "[%s·沉默] %s" % [event.get("npc_name", "NPC"), event.get("description", "")]
	return ""  # 过程事件（dialogue_started/belief_updated/…）不占行数——与 DMPack.history_line 同契约


## 调试面板（UI ②材料包页）的展示文本。
func to_display_text() -> String:
	var p: Array[String] = []
	p.append("[color=#e0b36a][b]◆ 材料包 · 第 %d / %d 轮[/b][/color]   组装于 %s（已冻结）" % [turn_number, max_turns, assembled_at])
	p.append("")
	p.append("[b]■ 回应者[/b]")
	p.append("· %s（%s）" % [npc.canonical_name, npc.entity_id])
	p.append("")
	p.append("[b]■ 场景素材[/b]")
	p.append("· 场景：%s" % scene.canonical_name)
	_append_field(p, "环境与陈设", str(scene_materials.get("environment", "")))
	_append_field(p, "氛围", str(scene_materials.get("atmosphere", "")))
	_append_field(p, "开场情境", str(scene_materials.get("opening_situation", "")))
	p.append("")
	p.append("[b]■ 玩家原话（原样引用，不改写、不执行）[/b]")
	p.append("“%s”" % player_utterance)
	p.append("")
	p.append("[b]■ 你的知识日志（%d 条）[/b]" % knowledge_entries.size())
	if knowledge_entries.is_empty():
		p.append("（该角色一无所知）")
	else:
		for e in knowledge_entries:
			var tag := "[%d]（%s · %s）" % [e.seq, e.speaker, KnowledgeEntry.trust_to_key(e.trust)]
			if e.status == KnowledgeEntry.EntryStatus.VOIDED:
				tag += "〔已失效〕"
			if e.is_stale():
				tag += "〔听说的事似乎有变〕"
			p.append("· %s：%s" % [tag, e.content])
	p.append("")
	p.append("[b]■ 你知道的世界事实（检索注入，编号供引用）[/b]")
	if world_facts.is_empty():
		p.append("（你所站的地方没有特别的传闻）")
	else:
		for f in world_facts:
			p.append("· [%d]（%s · %s）%s" % [
				f.id, CanonFact.source_to_key(f.source), CanonFact.weight_to_key(f.weight), f.content])
	p.append("")
	if not world_context.is_empty():
		p.append("[b]■ 此刻之前发生了什么（你亲眼所见）[/b]")
		for line in world_context:
			p.append("· " + line)
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
	var affinity := int(npc_state.get("affinity", 0))
	p.append("· 你对此人的好感度：%d（%s）。%s" % [
		affinity, AffinityStore.tier_label(affinity), AffinityStore.tier_text(affinity)])
	p.append("· 人设基调：%s" % str(npc_state.get("tone", "")))
	p.append("")
	p.append("[b]■ 行动清单（三选一）[/b]")
	for action in action_list:
		p.append("· [color=#90be6d]%s[/color]（%s）%s" % [action.get("type", ""), action.get("name", ""), action.get("description", "")])
	p.append("")
	p.append("[color=#8d99ae]注：完整提示词见『③ 提示词』页。[/color]")
	return "\n".join(p)


## 值非空时向 p 追加一行"· label：value"。value 为空跳过。
static func _append_field(p: Array[String], label: String, value: String) -> void:
	if value.is_empty():
		return
	p.append("· %s：%s" % [label, value])
