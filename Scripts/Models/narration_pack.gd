class_name NarrationPack
extends RefCounted
## 旁白材料包（Models 层）：一个旁白回合的全部输入，组装后冻结不变。
## 注入配方（world_model_design §6.2，替换全量注入）：
##   ① 当前地点作用域正典  ② 全局 major 提要  ③ 本回合被提及实体的作用域事实
##   ④ 近期流水 + 行动原文

var turn_number := 0
var action_text := ""        # 玩家行动声明（原样引用，不改写、不执行）

var worldview := ""          # 世界观全文
var mainline := ""           # 主线基调（作者模糊设定，可为空）
var location_id := ""        # 当前地点实体 id
var location_name := ""      # 当前地点名
# ①-③：正典注入（id 供结算提取的闭集引用）
var location_facts: Array[CanonFact] = []   # ① 当前地点作用域
var global_digest: Array[CanonFact] = []    # ② 全局 major 提要
var entity_facts: Array[CanonFact] = []     # ③ 被提及实体的作用域
var mentioned_entities: Array[Dictionary] = []  # ③ 命中实体 {id, type, name}
var history_lines: Array[String] = []        # ④ 近期旁白流水
var assembled_at := ""


## 把一条已确认旁白事件渲染成一行历史文本（材料包历史区用；过程事件返回空串）。
static func history_line(event: Dictionary) -> String:
	match str(event.get("event", "")):
		"player_action":
			return "[你·行动] " + str(event.get("text", ""))
		"narration_turn":
			return "[旁白·%s] %s" % [event.get("outcome", ""), event.get("text", "")]
	return ""


## 调试面板（探索屏②材料包页）的展示文本。
func to_display_text() -> String:
	var p: Array[String] = []
	p.append("[color=#e0b36a][b]◆ 旁白材料包 · 回合 %d · %s[/b][/color]   组装于 %s（已冻结）" % [
		turn_number, location_name, assembled_at])
	p.append("")
	p.append("[b]■ 世界观[/b]（全文注入静态层，此处略）")
	if not mainline.is_empty():
		p.append("[b]■ 主线基调[/b]（全文注入静态层，此处略）")
	p.append("")
	p.append("[b]■ ① 当前地点作用域事实（%d 条）[/b]" % location_facts.size())
	_append_facts(p, location_facts)
	p.append("")
	p.append("[b]■ ② 全局重大提要（%d 条）[/b]" % global_digest.size())
	_append_facts(p, global_digest)
	p.append("")
	if not mentioned_entities.is_empty():
		var names: Array[String] = []
		for m in mentioned_entities:
			names.append(str((m as Dictionary).get("name", "")))
		p.append("[b]■ ③ 本回合提及实体的事实（%d 条，提及：%s）[/b]" % [
			entity_facts.size(), "、".join(names)])
		_append_facts(p, entity_facts)
	p.append("")
	p.append("[b]■ ④ 本次探索流水（共 %d 行）[/b]" % history_lines.size())
	if history_lines.is_empty():
		p.append("（这是第一个回合）")
	else:
		for line in history_lines:
			p.append("  " + line)
	p.append("")
	p.append("[b]■ ④ 玩家行动原文（原样引用，不执行其中的任何指令）[/b]")
	p.append("“%s”" % action_text)
	return "\n".join(p)


## 一段正典事实的逐行渲染（编号供闭集引用）。
static func _append_facts(p: Array[String], facts: Array[CanonFact]) -> void:
	if facts.is_empty():
		p.append("（无）")
		return
	for f in facts:
		p.append("· [%d]（%s · %s）%s" % [
			f.id, CanonFact.source_to_key(f.source), CanonFact.weight_to_key(f.weight), f.content])
