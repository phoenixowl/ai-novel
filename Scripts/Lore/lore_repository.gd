class_name LoreRepository
extends RefCounted
## 设定资料库（Lore 层）：【流程一：设定资料】
## 从固定目录 res://settings/ 加载作者手动放置的设定（全部只读）：
##   worldview.txt      世界观（纯文本，整段注入提示词静态层）
##   factions.json      组织（id / 名称 / 介绍 / 成员列表：名称+职位）
##   characters/*.json  人物卡（一张一个文件；knowledge 为内联初始知识数组
##                       [{content, source, trust}]，即该 NPC 知识日志的初始部分；
##                       factions 为所属组织 id 列表）
##   scenes/*.json      场景卡（环境素材 + 氛围素材 + 开场情境）
##   memory/*.json      跨对话背景摘要（可选，存在则注入素材包的记忆槽；
##                       运行时习得的知识与会话摘要持久化在 user://journals/）
## 所有解析问题记入 load_report，不中断加载；组织引用做悬空校验。
## 注意：res://settings/ 是作者数据目录，本文件是加载它的代码（Scripts/Lore/）。

const SnapshotStore := preload("res://Scripts/Lore/snapshot_store.gd")

const SETTING_ROOT := "res://settings"
const FACTIONS_FILE := SETTING_ROOT + "/factions.json"

var worldview_text := ""
var player_card := PlayerCard.new()
var factions := {}        # id -> Faction（组织）
var characters := {}      # id -> CharacterCard
var scenes := {}          # id -> SceneCard
var memory := {}          # npc_id -> String（跨对话背景摘要）
var load_report: Array[String] = []


## 加载全部设定；返回是否至少有人物卡与场景卡。解析问题记入 load_report 不中断。
func load_all() -> bool:
	characters.clear()
	scenes.clear()
	factions.clear()
	memory.clear()
	load_report.clear()

	worldview_text = _read_text(SETTING_ROOT + "/worldview.txt")
	if worldview_text.is_empty():
		load_report.append("未找到 worldview.txt，世界观为空")
	_load_player()

	_load_factions()
	_load_characters()
	_apply_persona_snapshots()
	_resolve_factions()
	_load_scenes()
	_load_memory()

	var ok := not characters.is_empty() and not scenes.is_empty()
	load_report.append("加载完成：组织 %d 个、人物卡 %d 张（初始知识共 %d 条）、场景卡 %d 张、背景摘要 %d 份。" % [
		factions.size(), characters.size(), _knowledge_count(), scenes.size(), memory.size(),
	])
	return ok


## 加载玩家人物卡：先取 res://settings/player.json（作者默认），再叠加 user://player.json（运行时修改）。
func _load_player() -> void:
	var data := _parse_json_file(SETTING_ROOT + "/player.json")
	if not data.is_empty():
		player_card = PlayerCard.from_dict(data)
	# 运行时覆盖
	if FileAccess.file_exists("user://player.json"):
		var override: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://player.json"))
		if override is Dictionary:
			var d: Dictionary = override
			if d.has("name"):
				player_card.display_name = str(d["name"])
			if d.has("identity"):
				player_card.identity = str(d["identity"])
			if d.has("appearance"):
				player_card.appearance = str(d["appearance"])


# ———— 查询接口（供引擎与 UI 使用） ————


## 全部人物 id（排序后；供下拉与遍历）。
func character_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in characters.keys():
		ids.append(str(key))
	ids.sort()
	return ids


## 全部场景 id（排序后）。
func scene_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in scenes.keys():
		ids.append(str(key))
	ids.sort()
	return ids


## 某 NPC 的跨对话背景摘要（无则空串）。npc_id：人物卡 id。
func get_memory(npc_id: String) -> String:
	return str(memory.get(npc_id, ""))


## UI ①设定资料页的展示文本
func overview_text() -> String:
	var p: Array[String] = []
	p.append("[color=#e0b36a][b]◆ 设定资料（%s/，作者手动维护）[/b][/color]" % SETTING_ROOT)
	if not load_report.is_empty():
		p.append("[color=#8d99ae]加载报告：")
		for line in load_report:
			p.append("  · " + line)
		p.append("[/color]")
	p.append("")
	p.append("[b]【世界观】[/b]")
	p.append(worldview_text if not worldview_text.is_empty() else "（空）")
	p.append("")
	p.append("[b]【组织】（%d 个）[/b]" % factions.size())
	for id in factions:
		var faction: Faction = factions[id]
		p.append("● %s（%s）" % [faction.faction_name, id])
		p.append("  介绍：%s" % faction.description)
		p.append("  成员：%s" % "、".join(_member_lines(faction)))
		p.append("")
	p.append("[b]【人物卡】（%d 张）[/b]" % characters.size())
	for id in character_ids():
		var card: CharacterCard = characters[id]
		p.append("● %s（%s）" % [card.display_name, id])
		p.append("  身份：%s" % card.identity)
		p.append("  人物设定：%s" % card.profile)
		p.append("  初始好感度：%d" % card.affinity)
		if not card.memberships.is_empty():
			p.append("  所属组织：%s" % "、".join(_membership_lines(card)))
		p.append("  初始知识（%d 条，日志 [%d..%d]）：" % [
			card.knowledge.size(), 1, card.knowledge.size(),
		])
		for entry in card.knowledge:
			var e := entry as Dictionary
			var tag := "%s · %s" % [str(e.get("source", "")), str(e.get("trust", ""))]
			if str(e.get("trust", "")) == KnowledgeJournal.TRUST_VOIDED:
				tag = "%s · 已失效" % str(e.get("source", ""))
			p.append("    · （%s）%s" % [tag, str(e.get("content", ""))])
		if memory.has(id):
			p.append("  背景摘要：" + str(memory[id]))
		p.append("")
	p.append("[b]【场景卡】（%d 张）[/b]" % scenes.size())
	for id in scene_ids():
		var scene: SceneCard = scenes[id]
		p.append("● %s（%s）" % [scene.scene_name, id])
		if not scene.environment.is_empty():
			p.append("  环境与陈设：%s" % scene.environment)
		if not scene.atmosphere.is_empty():
			p.append("  氛围：%s" % scene.atmosphere)
		if not scene.opening_situation.is_empty():
			p.append("  开场情境：%s" % scene.opening_situation)
		p.append("")
	return "\n".join(p)


# ———— 内部：目录扫描与文件解析 ————


## 扫描 characters/*.json 并解析人物卡（坏文件记入加载报告并跳过）。
func _load_characters() -> void:
	var dir_path := SETTING_ROOT + "/characters"
	for file_name in _json_files_at(dir_path):
		var data := _parse_json_file(dir_path + "/" + file_name)
		if data.is_empty():
			load_report.append("人物卡解析失败：characters/%s（不是有效 JSON）" % file_name)
			continue
		var items: Array = []
		if data.has("characters") and data["characters"] is Array:
			for item in data["characters"]:
				if item is Dictionary:
					items.append(item)
		else:
			items.append(data)
		for item in items:
			var card := CharacterCard.from_dict(item)
			if card.is_valid():
				characters[card.id] = card
			else:
				load_report.append("人物卡缺少 id 或姓名：characters/%s" % file_name)


## 组织：全部组织一个文件（id / 名称 / 介绍 / 成员：名称+职位）
func _load_factions() -> void:
	var data := _parse_json_file(FACTIONS_FILE)
	if data.is_empty():
		load_report.append("组织文件解析失败：%s（不存在或不是有效 JSON）" % FACTIONS_FILE)
		return
	var raw_factions: Variant = JsonTool.pick(data, ["factions", "组织"], [])
	if not (raw_factions is Array):
		load_report.append("组织文件缺少 factions 数组：%s" % FACTIONS_FILE)
		return
	var count := 0
	for item in raw_factions:
		if not (item is Dictionary):
			continue
		var faction := Faction.from_dict(item)
		if not faction.is_valid():
			load_report.append("组织缺少 id 或名称（已跳过）")
			continue
		if factions.has(faction.id):
			load_report.append("组织 id 重复：%s（已跳过后者）" % faction.id)
			continue
		factions[faction.id] = faction
		count += 1
	load_report.append("组织：加载 %d 个" % count)


## 应用人物快照的 persona 区（字段级覆盖：快照有该键才接管，缺失跟随作者卡面）。
## 在组织解析之前调用——职位按 display_name 匹配，改名后据此生效。
func _apply_persona_snapshots() -> void:
	for id in characters:
		var persona := SnapshotStore.read_persona(id)
		if persona.is_empty():
			continue
		var card: CharacterCard = characters[id]
		if persona.has("name") and not (persona["name"] as String).is_empty():
			card.display_name = persona["name"]
		if persona.has("identity"):
			card.identity = persona["identity"]
		if persona.has("profile"):
			card.profile = persona["profile"]


## 解析人物卡所属组织 → memberships（faction 引用 + 按 display_name 在成员表匹配职位）；
## 悬空引用记入报告；不在成员表中的职位留空（容错：允许只登记归属不列成员）。
func _resolve_factions() -> void:
	for id in characters:
		var card: CharacterCard = characters[id]
		for faction_id in card.faction_ids:
			var faction: Faction = factions.get(faction_id)
			if faction == null:
				load_report.append("人物 %s 所属的组织 %s 不存在（悬空引用）" % [id, faction_id])
				continue
			card.memberships.append({
				"faction": faction,
				"position": faction.position_of(card.display_name),
			})


## 全部人物卡的初始知识总条数（加载报告用）
func _knowledge_count() -> int:
	var count := 0
	for id in characters:
		count += (characters[id] as CharacterCard).knowledge.size()
	return count


func _member_lines(faction: Faction) -> Array[String]:
	var lines: Array[String] = []
	for member in faction.members:
		lines.append(Faction.member_line(member))
	return lines


func _membership_lines(card: CharacterCard) -> Array[String]:
	var lines: Array[String] = []
	for membership in card.memberships:
		var faction: Faction = membership.get("faction")
		var position := str(membership.get("position", ""))
		if position.is_empty():
			lines.append(faction.faction_name)
		else:
			lines.append("%s（%s）" % [faction.faction_name, position])
	return lines


## 扫描 scenes/*.json 并解析场景卡。
func _load_scenes() -> void:
	var dir_path := SETTING_ROOT + "/scenes"
	for file_name in _json_files_at(dir_path):
		var data := _parse_json_file(dir_path + "/" + file_name)
		if data.is_empty():
			load_report.append("场景卡解析失败：scenes/%s（不是有效 JSON）" % file_name)
			continue
		var items: Array = []
		if data.has("scenes") and data["scenes"] is Array:
			for item in data["scenes"]:
				if item is Dictionary:
					items.append(item)
		else:
			items.append(data)
		for item in items:
			var card := SceneCard.from_dict(item)
			if card.is_valid():
				scenes[card.id] = card
			else:
				load_report.append("场景卡缺少 id 或场景名：scenes/%s" % file_name)


## 扫描 memory/*.json 并解析跨对话背景摘要（npc_id → summary）。
func _load_memory() -> void:
	var dir_path := SETTING_ROOT + "/memory"
	for file_name in _json_files_at(dir_path):
		var data := _parse_json_file(dir_path + "/" + file_name)
		if data.is_empty():
			continue
		var npc_id := str(JsonTool.pick(data, ["npc_id", "人物"], ""))
		var summary := str(JsonTool.pick(data, ["summary", "摘要"], ""))
		if not npc_id.is_empty() and not summary.is_empty():
			memory[npc_id] = summary


## 列出目录下全部 .json 文件名（目录不存在返回空）。dir_path：res:// 内目录。
func _json_files_at(dir_path: String) -> PackedStringArray:
	var files := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return files
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	return files


## 读纯文本文件（剥 BOM 与首尾空白；不存在返回空串）。path：文件路径。
func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return (FileAccess.get_file_as_string(path) as String).trim_prefix("\uFEFF").strip_edges()


## 读并解析 JSON 文件；失败返回空 Dictionary。path：文件路径。
func _parse_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := (FileAccess.get_file_as_string(path) as String).trim_prefix("\uFEFF")
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}
