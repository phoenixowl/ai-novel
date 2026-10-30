class_name GenAgentCharacter
extends GenAgentBase
## 人物生成 agent（Gen 层）：编写一个新人物——身份、人设、初始知识、记忆。
## 知识一致性是核心：候选知识池（ctx.pool）是他能引用的全部事实（编号引用）；
## 主观条目提及知情集外的实体会被整条丢弃——"小市民不知道高层的秘密"由此机械保证。
## 落地后与作者人物完全同权（可对话、可学习、可长记忆）。


const NAME_MAX := 16
const IDENTITY_MAX := 60
const PROFILE_MAX := 240
const KNOWLEDGE_MAX := 8
const CONTENT_MAX := 120
const MEMORY_MAX := 3
const MEMORY_LEN_MAX := 60


func _init() -> void:
	kind = "character"
	purpose = LLMClient.PURPOSE_GEN_CHARACTER


func build_draft_prompt(ctx: GenContext) -> Dictionary:
	var sys := "你是互动小说的世界编写者。根据给定材料编写一个新人物——他就住在指定地点，"
	sys += "刚刚被玩家的行动牵扯进故事。要求：知识边界是铁律——你只能引用候选知识清单里的"
	sys += "编号（ref），或写主观条目（content + basis，注明亲历/本地听说）；主观条目里"
	sys += "只能提到“你可能认识的人”清单里的人。一个铜锈区的居民不会知道天穹台的机密——"
	sys += "写出超出身份的知识，引擎会直接丢弃。语言质感与所在环区一致。\n"
	sys += "只输出一个 JSON 对象：{\"name\": \"…\", \"aliases\": [\"…\"], \"identity\": \"身份（60字内）\", "
	sys += "\"profile\": \"人设与说话风格（240字内）\", \"faction_ids\": [], "
	sys += "\"knowledge\": [{\"ref\": 清单编号} 或 {\"content\": \"…\", \"basis\": \"亲历/本地听说\"}], "
	sys += "\"memories\": [\"最多3条，每条60字内\"], \"affinity\": 0}。禁止输出其他文字。"
	var p: Array[String] = []
	p.append("■ 生成意图：" + ctx.brief)
	p.append("")
	p.append("■ 世界观（节选，不可违背）")
	p.append(ctx.worldview.substr(0, 600))
	p.append("")
	p.append("■ 他所在的地点：%s" % EntityRegistry.display_name(ctx.origin))
	var home_loc := LocationStore.location(ctx.origin)
	if home_loc != null:
		if not home_loc.environment.is_empty():
			p.append("· 环境：" + home_loc.environment.substr(0, 120))
		if not home_loc.atmosphere.is_empty():
			p.append("· 氛围：" + home_loc.atmosphere.substr(0, 120))
	for fact in ctx.origin_facts:
		p.append("· 此地事实：%s" % fact.content)
	p.append("")
	p.append("■ 候选知识清单（knowledge 只能引用这些编号）")
	if ctx.pool == null or ctx.pool.facts.is_empty():
		p.append("（他不知道什么特别的事）")
	else:
		for line in ctx.pool.render_lines():
			p.append(line)
	p.append("")
	p.append("■ 你可能认识的人（主观条目只能提到他们）")
	if ctx.acquaintance_names.is_empty():
		p.append("（没什么熟人）")
	else:
		p.append("· " + "、".join(ctx.acquaintance_names))
	p.append("")
	p.append("■ 现存名字（新名字不得与之重复）")
	p.append("· " + "、".join(ctx.known_names.slice(0, 40)))
	p.append("")
	p.append("■ 可加入的组织（faction_ids 只能填这些 id，没有就空数组）")
	var repo := LoreRepository.shared()
	var faction_ids: Array = []
	for id in repo.factions:
		faction_ids.append("%s（%s）" % [str(id), (repo.factions[id] as Faction).canonical_name])
	for entry in GenFactionStore.all():
		var e := entry as Dictionary
		faction_ids.append("%s（%s）" % [str(e.get("id", "")), str(e.get("name", ""))])
		if faction_ids.size() >= 16:
			break
	p.append("· " + ("、".join(faction_ids) if not faction_ids.is_empty() else "（无）"))
	return {"system": sys, "user": "\n".join(p)}


func validate_draft(data: Dictionary, ctx: GenContext, notes: Array[String]) -> Dictionary:
	var name := str(JsonTool.pick(data, ["name", "名称"], "")).strip_edges()
	if name.is_empty():
		notes.append("缺少人名。")
		return {}
	if name.length() > NAME_MAX:
		name = name.substr(0, NAME_MAX)
	if ctx.name_conflicts(name):
		notes.append("名字「%s」与现存实体重复，请换一个。" % name)
		return {}
	var identity := _cap(str(JsonTool.pick(data, ["identity", "身份"], "身份不明")), IDENTITY_MAX)
	var profile := _cap(str(JsonTool.pick(data, ["profile", "人设", "设定"], "")), PROFILE_MAX)
	if profile.is_empty():
		notes.append("缺少人设（profile）。")
		return {}
	# 组织引用闭集：现存组织（repo）+ 本批已落地的动态组织（GenFactionStore）均可见；
	# 之外的 id 丢弃
	var repo := LoreRepository.shared()
	var faction_ids: Array[String] = []
	for fid in JsonTool.pick_strings(data, ["faction_ids", "组织"]):
		if repo.factions.has(fid) or GenFactionStore.has(fid):
			if not faction_ids.has(fid):
				faction_ids.append(fid)
		else:
			notes.append("组织 id「%s」不存在，已丢弃。" % fid)
	# 知识双通道：ref 引用（池内闭集）或主观条目（实体提及闭集）
	var knowledge: Array = []
	var raw_k: Variant = JsonTool.pick(data, ["knowledge", "知识"], [])
	if raw_k is Array:
		for item in raw_k:
			if not (item is Dictionary) or knowledge.size() >= KNOWLEDGE_MAX:
				continue
			var d: Dictionary = item
			var ref_v: Variant = JsonTool.pick(d, ["ref", "编号"], null)
			if ref_v is float or ref_v is int:
				var fact := ctx.pool.fact_of(int(ref_v)) if ctx.pool != null else null
				if fact == null:
					notes.append("知识引用的编号 [%s] 不在候选清单内，已丢弃——他不该知道这件事。" % str(ref_v))
					continue
				knowledge.append({"content": fact.content,
					"source": "常识",
					"trust": "绝对可信" if fact.visibility == CanonFact.FactVisibility.LAW else "比较相信"})
				continue
			var content := _cap(str(JsonTool.pick(d, ["content", "内容"], "")), CONTENT_MAX)
			if content.is_empty():
				continue
			var leak := false
			for mentioned in EntityRegistry.scan_mentioned(content):
				var mid := str((mentioned as Dictionary).get("id", ""))
				if mid != "player" and not ctx.acquaintance.has(mid):
					notes.append("主观条目提到「%s」，不在他认识的人里，整条丢弃——%s" % [
						(mentioned as Dictionary).get("name", mid), content.substr(0, 24)])
					leak = true
					break
			if leak:
				continue
			knowledge.append({"content": content,
				"source": _cap(str(JsonTool.pick(d, ["basis", "来源"], "听说")), 20),
				"trust": "比较相信"})
	# 记忆：主观纹理，只做结构校验
	var memories: Array = []
	var raw_m: Variant = JsonTool.pick(data, ["memories", "记忆"], [])
	if raw_m is Array:
		for item in raw_m:
			var text := str(item).strip_edges()
			if text.is_empty():
				continue
			memories.append(_cap(text, MEMORY_LEN_MAX))
			if memories.size() >= MEMORY_MAX:
				break
	return {
		"card": {
			"name": name,
			"aliases": _clean_aliases(JsonTool.pick(data, ["aliases", "别名"], []), 3, 12),
			"identity": identity,
			"profile": profile,
			"affinity": clampi(int(JsonTool.pick(data, ["affinity", "好感度"], 0)), -100, 100),
			"knowledge": knowledge,
			"factions": Array(faction_ids),
		},
		"memories": memories,
	}


func land(draft: Dictionary, ctx: GenContext, notes: Array[String]) -> Dictionary:
	var card: Dictionary = draft["card"]
	var person := Person.from_card_dict(card)
	var id := EntityRegistry.register_gen(person)
	if id.is_empty():
		notes.append("人物注册失败。")
		return {"ok": false, "ids": [], "message": "", "followups": []}
	person.set_memories(draft["memories"])
	SnapshotStore.write_persona(id, {
		"name": person.canonical_name,
		"identity": person.identity,
		"profile": person.profile,
		"factions": Array(person.faction_ids),
	})
	CharacterController.shared().save_journal(person, id)
	LocationStore.place_npc(ctx.origin, id)
	LocationStore.save()
	var exist_id := CanonStore.establish(
		_cap("%s是%s的%s" % [person.canonical_name, EntityRegistry.display_name(ctx.origin), person.identity], 80),
		"narrator", "minor", [id, ctx.origin])
	if exist_id > 0:
		CanonStore.save()
	return {"ok": true, "ids": [id],
		"message": "「%s」出现在%s" % [person.canonical_name, EntityRegistry.display_name(ctx.origin)],
		"followups": []}
