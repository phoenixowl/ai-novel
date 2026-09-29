class_name MemorySummarizer
extends RefCounted
## 记忆与知识提取器（Dialogue 层）：对话结算后，用一次 LLM 调用从完整对话事件流
## 同时产出两样东西——记忆（"我经历了什么"）和知识（"我知道了什么持久事实"）。
## 输出为 JSON：{memory: "…", knowledge: [{content, evidence, speaker, note}]}。
## 引擎负责结构校验与写入 KnowledgeJournal。


## 组装提示词（system 要求 JSON 输出；user 携带完整对话事件流）。
## events：本段对话全部事件；npc_name：NPC 姓名。
static func build_prompts(events: Array, npc_name: String) -> Dictionary:
	var sys := "你是互动小说中 NPC 的记忆与知识提取器。根据完整对话记录，输出一个 JSON 对象，包含两个字段：\n"
	sys += "memory：用该 NPC 的第一人称写一段简短记忆（不超过 80 字），概括这次交谈中对方是谁、聊了什么关键内容、你的感受。\n"
	sys += "knowledge：从对话中提取该 NPC 真正学到的关于世界的持久事实（数组，可为空）。每项 {content, evidence, speaker}。\n"
	sys += "只提取持久事实——某地发生了某事、某人的真实身份、某个规律。不提取：\n"
	sys += "- 对方的态度、称呼或寒暄（那是对话经历，写进 memory 就够了）\n"
	sys += "- 对方声称但无法确认的事\n"
	sys += "- 已在对话中被反驳或撤回的话\n"
	sys += "只输出 JSON 对象，不要输出其他文字。"

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
			"dialogue_ended":
				lines.append("【对话结束】原因：%s" % e.get("reason", ""))
	var user := "以下是 " + npc_name + " 本段对话的完整记录：\n" + "\n".join(lines) + "\n\n请输出 JSON："
	return {"system": sys, "user": user}


## 清理记忆文本（去除引号包装、截断）。text：JSON 中 memory 字段的值。
static func extract(text: String) -> String:
	var t := text.strip_edges()
	if t.begins_with("\u201c") and t.ends_with("\u201d"):
		t = t.substr(1, t.length() - 2).strip_edges()
	if t.length() > 300:
		t = t.substr(0, 300) + "……"
	return t
