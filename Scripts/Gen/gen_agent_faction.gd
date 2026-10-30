class_name GenAgentFaction
extends GenAgentBase
## 组织生成 agent（Gen 层）：编写一个新势力——名字、介绍、成员表。
## 成员可以引用现存人物（按名字），也可以是没有人物卡的配角；组织可以先于
## 任何可对话的成员存在（一个只有名号的传闻势力也是好势力）。


const NAME_MAX := 16
const DESC_MAX := 150
const MEMBER_MAX := 6
const MEMBER_NAME_MAX := 16
const POSITION_MAX := 12


func _init() -> void:
	kind = "faction"
	purpose = LLMClient.PURPOSE_GEN_FACTION


func build_draft_prompt(ctx: GenContext) -> Dictionary:
	var sys := "你是互动小说的世界编写者。根据生成意图编写一个新出现的势力（组织/帮派/行会）。"
	sys += "要求：与世界观的时代质感一致；规模贴合一处环区的体量（不要一步写出统治全城的庞然大物）；"
	sys += "名字不得与现存任何组织/人物/地点重复。members 里的 name 可以是现存人物的名字，"
	sys += "也可以是没有出场卡的配角名（配角不需要有卡）。\n"
	sys += "只输出一个 JSON 对象：{\"name\": \"…\", \"description\": \"介绍（150字内）\", "
	sys += "\"members\": [{\"name\": \"…\", \"position\": \"职位\"}]}（最多 6 名成员）。禁止输出其他文字。"
	var p: Array[String] = []
	p.append("■ 生成意图：" + ctx.brief)
	p.append("")
	p.append("■ 世界观（节选，不可违背）")
	p.append(ctx.worldview.substr(0, 600))
	p.append("")
	p.append("■ 现存组织名（新名字不得重复）")
	var repo := LoreRepository.shared()
	var org_names: Array[String] = []
	for id in repo.factions:
		org_names.append((repo.factions[id] as Faction).canonical_name)
	p.append("· " + ("、".join(org_names) if not org_names.is_empty() else "（无）"))
	p.append("")
	p.append("■ 现存人物名（members 可引用他们）")
	p.append("· " + "、".join(ctx.known_names.slice(0, 40)))
	return {"system": sys, "user": "\n".join(p)}


func validate_draft(data: Dictionary, ctx: GenContext, notes: Array[String]) -> Dictionary:
	var name := str(JsonTool.pick(data, ["name", "名称"], "")).strip_edges()
	if name.is_empty():
		notes.append("缺少组织名。")
		return {}
	if name.length() > NAME_MAX:
		name = name.substr(0, NAME_MAX)
	if ctx.name_conflicts(name):
		notes.append("名字「%s」与现存实体重复，请换一个。" % name)
		return {}
	var description := _cap(str(JsonTool.pick(data, ["description", "介绍"], "")), DESC_MAX)
	if description.is_empty():
		notes.append("缺少介绍（description）。")
		return {}
	var members: Array = []
	var raw: Variant = JsonTool.pick(data, ["members", "成员"], [])
	if raw is Array:
		for item in raw:
			if not (item is Dictionary) or members.size() >= MEMBER_MAX:
				continue
			var mname := str(JsonTool.pick(item, ["name", "名称"], "")).strip_edges()
			if mname.is_empty() or mname.length() > MEMBER_NAME_MAX:
				continue
			members.append({"name": mname,
				"position": _cap(str(JsonTool.pick(item, ["position", "职位"], "成员")), POSITION_MAX)})
	return {"name": name, "description": description, "members": members}


func land(draft: Dictionary, _ctx: GenContext, notes: Array[String]) -> Dictionary:
	var faction := Faction.new()
	faction.canonical_name = str(draft["name"])
	faction.description = str(draft["description"])
	for m in draft["members"]:
		faction.members.append(m as Dictionary)
	var id := EntityRegistry.register_gen(faction)
	if id.is_empty():
		notes.append("组织注册失败。")
		return {"ok": false, "ids": [], "message": "", "followups": []}
	GenFactionStore.add(id, faction.canonical_name, faction.description, faction.members)
	var exist_id := CanonStore.establish("「%s」是近来出现的一股势力：%s" % [
		faction.canonical_name, faction.description],
		"narrator", "minor", [id])
	if exist_id > 0:
		CanonStore.save()
	return {"ok": true, "ids": [id],
		"message": "新势力「%s」浮出水面" % faction.canonical_name,
		"followups": []}
