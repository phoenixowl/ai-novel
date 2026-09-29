# -*- coding: utf-8 -*-
"""一次性脚本：架构重构——learned 从每轮回应中移除，改为结算时由 MemorySummarizer 一次产出。"""
import io
import os

BS = chr(92)


def patch(rel, pairs):
    p = rel.replace("/", BS)
    s = io.open(p, encoding="utf-8").read()
    for old, new in pairs:
        assert old in s, "%s anchor missing: %s" % (rel, old[:70])
        s = s.replace(old, new)
    io.open(p, "w", encoding="utf-8", newline="\n").write(s)
    print("patched:", rel)


# ---------- 1) PromptBuilder：静态层删 learned 字段和条款，保留 belief_updates ----------
patch(os.path.join("Scripts", "Dialogue", "prompt_builder.gd"), [
    # 删静态层输出格式中的 learned
    ('''		"learned": [{"quote": "对方原话中值得记住的连续片段（逐字复制，作依据）", "summary": "一句话概括这件事", "note": "为什么记"}],
		"belief_updates": [{"ref": 0, "relation": "佐证 或 矛盾", "note": "一句理由"}],''',
     '''		"belief_updates": [{"ref": 0, "relation": "佐证 或 矛盾", "note": "一句理由"}],'''),
    # 学习条款 → 删除整段
    ('''	p.append("## 学习与记性（固定条款）")
	p.append("- 对方说了值得记住的新事 → 在 learned 里登记：quote 必须逐字复制对方原话的连续片段")
	p.append("  （不改一字），summary 用一句话概括这件事；没学到就给空数组。")
	p.append("- summary 只能概括 quote 里的事实，不得添加对方没有说过的信息。")
	p.append("- 对方的话与日志中某条佐证或矛盾 → 在 belief_updates 里引用那条的编号（ref），")
	p.append("  只准引用“你的知识日志”里展示过的编号；没变化就给空数组。")
	p.append("- 你从对方那里学来的东西只能当传闻说（“听人讲过……”），不得当作确知。")
	p.append("")
''', ''),
])

# ---------- 2) ResponseParser：删 learned 解析，保留 belief_updates + affinity_change ----------
patch(os.path.join("Scripts", "Dialogue", "response_parser.gd"), [
    ('''##   learned: Array[Dictionary]{quote, summary, note}   —— 结构合法的习得提案
##   belief_updates: Array[Dictionary]{ref, relation, note} —— 结构合法的信念提案''',
     '''##   belief_updates: Array[Dictionary]{ref, relation, note} —— 结构合法的信念提案'''),
    ('''	var learned := _parse_learned(data, notes)
	var belief_updates := _parse_belief_updates(data, notes)''',
     '''	var belief_updates := _parse_belief_updates(data, notes)'''),
    ('''		"learned": learned,
		"belief_updates": belief_updates,''',
     '''		"belief_updates": belief_updates,'''),
    # 删除 _parse_learned 方法
    ('''## 解析 learned 数组：每项 {quote(非空), summary(可空回退用 quote), note}；
## 坏项丢弃并记 notes。仅结构校验——quote 是否真是玩家原话由引擎子串校验。
static func _parse_learned(data: Dictionary, notes: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = JsonUtil.pick(data, ["learned", "习得"], null)
	if raw == null:
		return out
	if not (raw is Array):
		notes.append("learned 不是数组，已忽略。")
		return out
	for item in raw:
		if not (item is Dictionary):
			notes.append("learned 含非对象项，已丢弃。")
			continue
		var d: Dictionary = item
		var quote := str(JsonUtil.pick(d, ["quote", "依据", "原话"], "")).strip_edges()
		if quote.is_empty():
			notes.append("learned 项缺少 quote（依据），已丢弃。")
			continue
		var summary := str(JsonUtil.pick(d, ["summary", "概括", "总结"], "")).strip_edges()
		if summary.is_empty():
			summary = quote
			notes.append("learned 项缺少 summary，用 quote 代替。")
		out.append({"quote": quote, "summary": summary, "note": str(JsonUtil.pick(d, ["note", "理由"], ""))})
	return out''', ''),
    # 类头部注释更新
    ('''##   发言文本 / 发言性质声明 claim_type / 行动提案 / 内心想法（仅调试用）/
##   learned（习得提案 {quote, summary, note}）/ belief_updates（信念提案 {ref, relation, note}）。''',
     '''##   发言文本 / 发言性质声明 claim_type / 行动提案 / 内心想法（仅调试用）/
##   belief_updates（信念提案 {ref, relation, note}）/ affinity_change（好感度变化量）。'''),
])

# ---------- 3) DialogueEngine：删 _collect_learning 中的 learned 部分；结算时统一提取 ----------
patch(os.path.join("Scripts", "Dialogue", "dialogue_engine.gd"), [
    # _collect_learning 简化：只收 belief_updates
    ('''func _collect_learning(parsed: Dictionary, player_text: String, pack: MaterialPack) -> void:
	var learned: Array = parsed.get("learned", [])
	var updates: Array = parsed.get("belief_updates", [])
	if learned.is_empty() and updates.is_empty():
		return
	var pack_seqs := {}
	for e in pack.knowledge_entries:
		pack_seqs[int((e as Dictionary).get("seq", 0))] = true
	_pending_learning.append({
		"turn": turn_number,
		"learned": learned,
		"belief_updates": updates,
		"player_text": player_text,
		"pack_seqs": pack_seqs,
	})''',
     '''func _collect_learning(parsed: Dictionary, player_text: String, pack: MaterialPack) -> void:
	var updates: Array = parsed.get("belief_updates", [])
	if updates.is_empty():
		return
	var pack_seqs := {}
	for e in pack.knowledge_entries:
		pack_seqs[int((e as Dictionary).get("seq", 0))] = true
	_pending_learning.append({
		"turn": turn_number,
		"belief_updates": updates,
		"pack_seqs": pack_seqs,
	})'''),
    # _settle_learning：删 learned 处理（只处理 belief_updates）
    ('''## 结算学习（对话结束时调用）：遍历全部延后提案，执行确定性校验并写入知识日志。
## \t learned：quote 逐字子串校验（防编造），失败回退整句锚定（每轮至多一条）。
## \t belief_updates：ref 闭集校验（限该轮材料包展示过的编号）。
func _settle_learning() -> void:
	if _pending_learning.is_empty():
		return
	var anchored_turns := {}
	for proposal in _pending_learning:
		var p := proposal as Dictionary
		var player_text := str(p.get("player_text", ""))
		var pack_seqs: Dictionary = p.get("pack_seqs", {})
		var turn := int(p.get("turn", 0))

		for item in p.get("learned", []):
			var d := item as Dictionary
			var quote := str(d.get("quote", ""))
			var evidence := quote
			if not player_text.contains(quote):
				if anchored_turns.has(turn) or player_text.is_empty():
					continue
				evidence = player_text
				anchored_turns[turn] = true
			var seq := journal.learn(
				str(d.get("summary", quote)),
				evidence,
				"来客",
				turn,
				_journal_session,
				str(d.get("note", "")),
			)
			_emit_event({
				"event": "knowledge_learned",
				"journal_seq": seq,
				"content": str(d.get("summary", quote)),
				"evidence": evidence,
				"npc_name": current_npc.display_name,
			})

		for item in p.get("belief_updates", []):''',
     '''## 结算学习（对话结束时调用）：遍历全部延后的信念提案，执行闭集校验并应用信任算术。
## belief_updates：ref 闭集校验（限该轮材料包展示过的编号）。
func _settle_learning() -> void:
	if _pending_learning.is_empty():
		return
	for proposal in _pending_learning:
		var p := proposal as Dictionary
		var pack_seqs: Dictionary = p.get("pack_seqs", {})

		for item in p.get("belief_updates", []):'''),
    # _summarize_memory 改为同时产出记忆和知识提取
    ('''	var prompts := MemorySummarizer.build_prompts(events, current_npc.display_name)
	_events.llm_request.emit("记忆整理中…")
	var result: Dictionary = await LLMService.shared().complete(
		str(prompts.get("system", "")), str(prompts.get("user", "")), LLMClient.PURPOSE_DIALOGUE,
	)
	if not result.get("ok", false):
		return
	var text := MemorySummarizer.extract(str(result.get("content", "")))
	if not text.is_empty():
		journal.add_memory(text, _journal_session)
	journal.save(current_npc.id)''',
     '''	var prompts := MemorySummarizer.build_prompts(events, current_npc.display_name)
	_events.llm_request.emit("记忆与知识整理中…")
	var result: Dictionary = await LLMService.shared().complete_json(
		str(prompts.get("system", "")), str(prompts.get("user", "")), LLMClient.PURPOSE_DIALOGUE,
	)
	if not result.get("ok", false):
		return
	var data: Dictionary = result.get("data", {})
	var memory_text := str(data.get("memory", ""))
	if not memory_text.is_empty():
		journal.add_memory(MemorySummarizer.extract(memory_text), _journal_session)
	# 知识提取：从 data.knowledge 数组写入日志
	for item in data.get("knowledge", []):
		if not (item is Dictionary):
			continue
		var d: Dictionary = item
		var content := str(d.get("content", "")).strip_edges()
		if content.is_empty():
			continue
		journal.learn(content, str(d.get("evidence", "")), str(d.get("speaker", "来客")),
			int(d.get("turn", 0)), _journal_session, str(d.get("note", "")))
	journal.save(current_npc.id)'''),
])

# ---------- 4) MemorySummarizer：JSON 输出（记忆 + 知识提取合一） ----------
patch(os.path.join("Scripts", "Dialogue", "memory_summarizer.gd"), [
    # 整体重写类内容
    ('''class_name MemorySummarizer
extends RefCounted
## 记忆整理器（Dialogue 层）：对话结束后（或玩家点击"结算"时），
## 用 LLM 从完整对话事件流归纳一段记忆，写入 NPC 的知识日志。
## 输出经过结构校验：只接受非空文本，截断到合理长度。


const MAX_MEMORY_CHARS := 300  # 单条记忆最大字符数
const PURPOSE := "memory_summary"


## 组装记忆整理提示词（system + user），传入完整对话事件流。
## events：本段对话全部事件；npc_name：NPC 姓名。
static func build_prompts(events: Array, npc_name: String) -> Dictionary:
	var sys := "你是互动小说中 NPC 的记忆整理器。根据完整对话记录，用该 NPC 的第一人称视角写一段简短记忆（不超过80字），概括这次交谈中对方是谁、聊了什么关键内容、你的感受或态度变化。只输出记忆文本本身，不要任何前缀、标点包装或 JSON。"

	var lines: Array[String] = []
	for raw in events:
		var e := raw as Dictionary
		match str(e.get("event", "")):
			"dialogue_started":
				lines.append("【对话开始】%s · %s" % [e.get("scene_name", ""), e.get("npc_name", "")])
			"player_utterance":
				lines.append("对方说：%s" % e.get("text", ""))
			"npc_utterance":
				lines.append("%s说：%s" % [npc_name, e.get("text", "")])
			"npc_silence":
				lines.append("%s选择了沉默" % npc_name)
			"knowledge_learned":
				lines.append("（记住了新事：%s）" % e.get("content", ""))
			"belief_updated":
				lines.append("（对某事的想法变为：%s）" % e.get("after", ""))
			"dialogue_ended":
				lines.append("【对话结束】原因：%s" % e.get("reason", ""))
	var user := "以下是 %s 本段对话的完整记录：\\n%s\\n\\n请写一段 %s 的第一人称记忆：" % [
		npc_name, "\\n".join(lines), npc_name,
	]
	return {"system": sys, "user": user}


## 从 LLM 原始输出提取记忆文本（去除多余包装；失败返回空串）。
## raw：LLM 的纯文本输出。
static func extract(raw: String) -> String:
	var text := raw.strip_edges()
	# 去除可能的引号包装
	if (text.begins_with("\\u201c") and text.ends_with("\\u201d")) or (text.begins_with("\\"") and text.ends_with("\\"")):
		text = text.substr(1, text.length() - 2).strip_edges()
	# 去除可能的前缀
	for prefix in ["记忆：", "记忆:", "总结：", "总结:"]:
		if text.begins_with(prefix):
			text = text.substr(prefix.length()).strip_edges()
	# 截断
	if text.length() > MAX_MEMORY_CHARS:
		text = text.substr(0, MAX_MEMORY_CHARS) + "……"
	return text''',
     '''class_name MemorySummarizer
extends RefCounted
## 记忆与知识提取器（Dialogue 层）：对话结算后，用一次 LLM 调用从完整对话事件流
## 同时产出两样东西——记忆（"我经历了什么"）和知识（"我知道了什么持久事实"）。
## 输出为 JSON：{memory: "…", knowledge: [{content, evidence, speaker, note}]}。
## 引擎负责结构校验与写入 KnowledgeJournal。


## 组装提示词（system + user）。system 要求 JSON 输出；user 携带完整对话事件流。
## events：本段对话全部事件；npc_name：NPC 姓名。
static func build_prompts(events: Array, npc_name: String) -> Dictionary:
	var sys := "你是互动小说中 NPC 的记忆与知识整理器。根据完整对话记录，完成两件事：\\n"
	sys += "1. 用该 NPC 的第一人称写一段简短记忆（不超过 80 字），概括这次交谈中对方是谁、聊了什么关键内容、你的感受。\\n"
	sys += "2. 从对话中提取该 NPC 真正学到的新知识——只包括关于世界的持久事实（如某地发生了某事、某人的身份），不包括：\\n"
	sys += "   - 对方在对话中的态度、称呼或寒暄\\n"
	sys += "   - 对方声称但无法确认的事（这些只是对话经历，写进记忆即可）\\n"
	sys += "   - 已经在对话里被反驳或撤回的话\\n"
	sys += "只输出一个 JSON 对象。"
	var lines: Array[String] = []
	for raw in events:
		var e := raw as Dictionary
		match str(e.get("event", "")):
			"dialogue_started":
				lines.append("【对话开始】%s · %s" % [e.get("scene_name", ""), e.get("npc_name", "")])
			"player_utterance":
				lines.append("对方说：%s" % e.get("text", ""))
			"npc_utterance":
				lines.append("%s说：%s" % [npc_name, e.get("text", "")])
			"npc_silence":
				lines.append("%s选择了沉默" % npc_name)
			"knowledge_learned":
				lines.append("（此前记住了：%s）" % e.get("content", ""))
			"belief_updated":
				lines.append("（对某事的想法变为：%s）" % e.get("after", ""))
			"dialogue_ended":
				lines.append("【对话结束】原因：%s" % e.get("reason", ""))
	var user := "以下是 %s 本段对话的完整记录：\\n%s\\n\\n请输出 JSON：" % [
		npc_name, "\\n".join(lines), npc_name,
	]
	return {"system": sys, "user": user}


## 从 LLM JSON 输出提取记忆文本（去除包装、截断）。text：memory 字段的值。
static func extract(text: String) -> String:
	var t := text.strip_edges()
	# 去除引号包装
	if (t.begins_with("\\u201c") and t.ends_with("\\u201d")):
		t = t.substr(1, t.length() - 2).strip_edges()
	if t.length() > 300:
		t = t.substr(0, 300) + "……"
	return t'''),
])

# ---------- 5) MockClient：记忆整理请求返回 JSON ----------
patch(os.path.join("Scripts", "LLM", "mock_client.gd"), [
    ('''	if system_prompt.contains("记忆整理器"):
		return {"ok": true, "content": "上次有个生面孔来茶馆，问起黑潮带拳手的事，我提醒他别多管闲事。", "error": ""}''',
     '''	if system_prompt.contains("记忆整理器"):
		return {"ok": true, "content": JSON.stringify({
			"memory": "上次有个生面孔来茶馆，问起黑潮带拳手的事，我提醒他别多管闲事。",
			"knowledge": [],
		}), "error": ""}'''),
])

# ---------- 6) dialogue_screen_ui：删 response 中的 learned 展示 ----------
patch(os.path.join("Scripts", "UI", "dialogue_screen_ui.gd"), [
    ('''		var learned: Array = r.get("learned", [])
		if not learned.is_empty():
			p.append("")
			p.append("[b]■ 习得（quote 依据 / summary 表述）[/b]")
			for item in learned:
				var d := item as Dictionary
				p.append("· 表述：" + _bb_escape(str(d.get("summary", ""))))
				p.append("  依据：“%s”" % _bb_escape(str(d.get("quote", ""))))
		var updates: Array = r.get("belief_updates", [])''',
     '''		var updates: Array = r.get("belief_updates", [])'''),
])

print("ALL PATCHED")
