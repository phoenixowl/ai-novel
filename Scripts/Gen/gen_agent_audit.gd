class_name GenAuditAgent
extends RefCounted
## 审核者 agent（Gen 层）：三种生成共用的"世界一致性检查员"——独立于生成 agent
## 的第二个视角，专查确定性代码查不了的语义问题。输出契约 {verdict, issues}；
## 引擎只认 pass/revise 枚举与字符串清单（闭集），verdict 非法按 pass 处理
## （防审核者自身输出异常导致死循环；漏报由引擎硬门兜底）。


func _init() -> void:
	pass


## 审核提示词。draft_text：生成 agent 的规范化草稿（render_for_audit 产出）。
func build_prompt(ctx: GenContext, draft_text: String) -> Dictionary:
	var sys := "你是互动小说的世界一致性检查员。下面是一个即将写入世界的新内容草稿，"
	sys += "请逐项体检，只回答通过与否与问题清单：\n"
	sys += "1. 信息越权：人物知道的事/口吻是否超出其身份（一个铜锈区居民不该懂天穹台的内幕）？\n"
	sys += "2. 世界观冲突：与世界观、候选知识清单有无矛盾？\n"
	sys += "3. 风格错位：用语质感与所在环区是否匹配？\n"
	sys += "4. 重复：是否只是既有角色/地点/组织换了个名字？\n"
	sys += "5. 引用自洽：内容里的相互指涉（人物-地点-组织）是否对得上？\n"
	sys += "没有实质问题就通过；不要吹毛求疵地否决风格选择。\n"
	sys += "只输出一个 JSON 对象：{\"verdict\": \"pass 或 revise\", \"issues\": [\"问题一句话\"]}。"
	sys += "verdict 为 pass 时 issues 给空数组。禁止输出其他文字。"
	var p: Array[String] = []
	p.append("■ 生成类型：%s　■ 生成意图：%s" % [ctx.kind, ctx.brief])
	p.append("")
	p.append("■ 草稿")
	p.append(draft_text)
	return {"system": sys, "user": "\n".join(p)}


## 校验审核输出：verdict 闭集（非法按 pass 处理并记 note）；issues 清洗为字符串列表。
func validate(data: Dictionary, notes: Array[String]) -> Dictionary:
	var verdict := str(JsonTool.pick(data, ["verdict", "裁决"], "pass"))
	if not ["pass", "revise"].has(verdict):
		notes.append("审核输出的 verdict 非法（%s），按 pass 处理。" % verdict)
		verdict = "pass"
	var issues: Array = []
	var raw: Variant = JsonTool.pick(data, ["issues", "问题"], [])
	if raw is Array:
		for item in raw:
			var text := str(item).strip_edges()
			if not text.is_empty() and not issues.has(text):
				issues.append(_cap(text, 80))
	if verdict == "pass" and not issues.is_empty():
		verdict = "revise"  # 给了问题清单却判 pass：以问题清单为准
	return {"verdict": verdict, "issues": issues}


static func _cap(text: String, max_len: int) -> String:
	if text.length() > max_len:
		return text.substr(0, max_len) + "……"
	return text
