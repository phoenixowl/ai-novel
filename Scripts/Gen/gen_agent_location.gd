class_name GenAgentLocation
extends GenAgentBase
## 地点生成 agent（Gen 层）：编写一个新地点——名字、进场描述（直接冻结为 brief）、
## 环境素材、0–3 条本地事实、可选的住户简报（链式触发人物生成）。
## 可以空无一人：inhabitants 默认为空，只有 brief 明确说有人时模型才会给。


const NAME_MAX := 24
const BRIEF_MAX := 200
const FIELD_MAX := 150
const OPENING_MAX := 120
const FACT_MAX := 3
const FACT_LEN_MAX := 80
const INHABITANT_MAX := 2
const INHABITANT_BRIEF_MAX := 40


func _init() -> void:
	kind = "location"
	purpose = LLMClient.PURPOSE_GEN_LOCATION


func build_draft_prompt(ctx: GenContext) -> Dictionary:
	var sys := "你是互动小说的世界编写者。根据给定材料编写一个新地点，它是玩家刚刚在世界里"
	sys += "发现的地方。要求：与世界观的时代质感一致；进场描述用第二人称（“你……”），"
	sys += "只描述当下可见的东西；名字不得与现存任何地点/人物/组织重复。\n"
	sys += "住户（inhabitants）是可选的：只有生成意图明确说这个地方有人时才给（0–2 个，"
	sys += "每个一句话简报）；没提人就给空数组——空巷、封死的井、锁着的仓库都是好地点。\n"
	sys += "只输出一个 JSON 对象：{\"name\": \"…\", \"aliases\": [\"…\"], \"brief\": \"进场描述（200字内）\", "
	sys += "\"environment\": \"环境与陈设\", \"atmosphere\": \"氛围\", \"opening_situation\": \"开场情境\", "
	sys += "\"facts\": [{\"content\": \"此地的客观事实（最多3条）\"}], \"inhabitants\": [{\"brief\": \"住户简报\"}]}。"
	sys += "禁止输出其他文字。"
	var p: Array[String] = []
	p.append("■ 生成意图：" + ctx.brief)
	p.append("")
	p.append("■ 世界观（节选，不可违背）")
	p.append(ctx.worldview.substr(0, 600))
	if not ctx.mainline.is_empty():
		p.append("")
		p.append("■ 主线基调")
		p.append(ctx.mainline.substr(0, 300))
	p.append("")
	p.append("■ 相连地点：%s" % EntityRegistry.display_name(ctx.origin))
	for fact in ctx.origin_facts:
		p.append("· %s" % fact.content)
	p.append("")
	p.append("■ 近期世界流水")
	if ctx.history_lines.is_empty():
		p.append("（一切刚刚开始）")
	else:
		for line in ctx.history_lines:
			p.append("  " + line)
	p.append("")
	p.append("■ 现存名字（新名字不得与之重复）")
	p.append("· " + "、".join(ctx.known_names.slice(0, 40)))
	return {"system": sys, "user": "\n".join(p)}


func validate_draft(data: Dictionary, ctx: GenContext, notes: Array[String]) -> Dictionary:
	var name := str(JsonTool.pick(data, ["name", "名称"], "")).strip_edges()
	if name.is_empty():
		notes.append("缺少地点名。")
		return {}
	if name.length() > NAME_MAX:
		name = name.substr(0, NAME_MAX)
	if ctx.name_conflicts(name):
		notes.append("名字「%s」与现存实体重复，请换一个。" % name)
		return {}
	var brief := _cap(str(JsonTool.pick(data, ["brief", "进场描述"], "")), BRIEF_MAX)
	if brief.is_empty():
		notes.append("缺少进场描述（brief）。")
		return {}
	var facts: Array = []
	var raw_facts: Variant = JsonTool.pick(data, ["facts", "事实"], [])
	if raw_facts is Array:
		for item in raw_facts:
			if not (item is Dictionary):
				continue
			var content := str(JsonTool.pick(item, ["content", "表述"], "")).strip_edges()
			if content.is_empty():
				continue
			facts.append(_cap(content, FACT_LEN_MAX))
			if facts.size() >= FACT_MAX:
				break
	var inhabitants: Array = []
	var raw_inh: Variant = JsonTool.pick(data, ["inhabitants", "住户"], [])
	if raw_inh is Array:
		for item in raw_inh:
			var brief_i := ""
			if item is Dictionary:
				brief_i = str(JsonTool.pick(item, ["brief", "简报"], ""))
			else:
				brief_i = str(item)
			brief_i = brief_i.strip_edges()
			if brief_i.is_empty():
				continue
			inhabitants.append(_cap(brief_i, INHABITANT_BRIEF_MAX))
			if inhabitants.size() >= INHABITANT_MAX:
				break
	return {
		"name": name,
		"aliases": _clean_aliases(JsonTool.pick(data, ["aliases", "别名"], []), 3, 12),
		"brief": brief,
		"environment": _cap(str(JsonTool.pick(data, ["environment", "环境"], "")), FIELD_MAX),
		"atmosphere": _cap(str(JsonTool.pick(data, ["atmosphere", "氛围"], "")), FIELD_MAX),
		"opening_situation": _cap(str(JsonTool.pick(data, ["opening_situation", "开场情境"], "")), OPENING_MAX),
		"facts": facts,
		"inhabitants": inhabitants,
	}


func land(draft: Dictionary, ctx: GenContext, notes: Array[String]) -> Dictionary:
	var loc := Location.new()
	loc.canonical_name = str(draft["name"])
	loc.aliases = draft["aliases"]
	loc.environment = str(draft["environment"])
	loc.atmosphere = str(draft["atmosphere"])
	loc.opening_situation = str(draft["opening_situation"])
	var id := EntityRegistry.register_gen(loc)
	if id.is_empty():
		notes.append("地点注册失败。")
		return {"ok": false, "ids": [], "message": "", "followups": []}
	LocationStore.add_gen_location(loc, ctx.origin)
	LocationStore.set_brief(id, str(draft["brief"]))  # 进场描述直接冻结——首次进入零调用
	for content in draft["facts"]:
		CanonStore.establish(str(content), "narrator", "minor", [id])
	var origin_name := EntityRegistry.display_name(ctx.origin)
	var exist_id := CanonStore.establish("%s是%s新近出现的地方" % [loc.canonical_name, origin_name],
		"narrator", "minor", [id, ctx.origin])
	LocationStore.save()
	if exist_id > 0:
		CanonStore.save()
	var followups: Array = []
	for inh_brief in draft["inhabitants"]:
		followups.append({"kind": "character", "brief": str(inh_brief), "home": id})
	return {"ok": true, "ids": [id],
		"message": "新地点「%s」出现在%s附近" % [loc.canonical_name, origin_name],
		"followups": followups}
