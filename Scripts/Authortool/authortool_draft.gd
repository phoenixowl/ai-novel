class_name AuthortoolDraft
extends RefCounted
## AuthorTool 草稿模型（Scripts/Authortool/）：设定编辑页的全部编辑对象。
## 装载来源 = res://settings/ 作者数据 + 运行时正典（CanonStore 全量，含被取代条目）
## + DM 风格四旋钮（GameConfig，只读快照）。
## 编辑永远只改本内存草稿——不写 res://settings、不写 user:// 现有目录；
## 唯一写出动作是 AuthortoolExporter 导出到独立目录。
## 人物/场景/组织卡以完整字典承载：表单只改已知键，未知键导出时原样带回（往返保真）。

const SETTING_ROOT := "res://settings"


var worldview := ""
var mainline := ""
var factions: Array = []      # 组织卡字典（全键保真：id/name/description/members…）
var characters: Array = []    # 人物卡字典（全键保真：id/name/identity/profile/knowledge…）
var scenes: Array = []        # 场景卡字典（全键保真：id/name/links/npcs…）
var player := {}              # 玩家卡 {name, identity, appearance}
var facts: Array = []         # 事实 {id(仅展示), content, weight, source, scope: Array, status}
var memory: Dictionary = {}   # npc_id -> 卡片字典（原样带出，暂无编辑页）
var style := {}               # {adoption, verdict, density, threshold}
var load_report: Array[String] = []


## 从项目装载草稿。返回加载报告（计数与缺失提示，不中断）。
func load_from_project() -> Array[String]:
	load_report = []
	worldview = _read_text(SETTING_ROOT + "/worldview.txt")
	mainline = _read_text(SETTING_ROOT + "/mainline.txt")
	if worldview.is_empty():
		load_report.append("未找到 worldview.txt（世界观为空）")

	factions = _load_factions()
	characters = _load_card_dir(SETTING_ROOT + "/characters", "人物")
	scenes = _load_card_dir(SETTING_ROOT + "/scenes", "场景")

	player = JsonTool.read_json_file(SETTING_ROOT + "/player.json")
	if player.is_empty():
		player = {"name": "来客", "identity": "", "appearance": ""}

	_load_memory()
	_load_facts()
	_load_style()

	load_report.append("装载完成：组织 %d · 人物 %d · 场景 %d · 事实 %d（现行 %d）· 记忆 %d 份。" % [
		factions.size(), characters.size(), scenes.size(), facts.size(), active_fact_count(), memory.size(),
	])
	return load_report


## 现行（未被取代）事实条数。
func active_fact_count() -> int:
	var count := 0
	for raw in facts:
		if str((raw as Dictionary).get("status", "active")) == "active":
			count += 1
	return count


## 按 id 查组织卡（无则空字典）。id：组织 id。
func faction_by_id(id: String) -> Dictionary:
	for raw in factions:
		var f := raw as Dictionary
		if str(f.get("id", "")) == id:
			return f
	return {}


# ———— 装载内部 ————


## 组织：单一文件 factions.json 的 {"factions": […]} 数组（全键保真）。
func _load_factions() -> Array:
	var out: Array = []
	var data := JsonTool.read_json_file(SETTING_ROOT + "/factions.json")
	for raw in JsonTool.pick(data, ["factions", "组织"], []):
		if raw is Dictionary:
			out.append(raw)
	return out


## 人物/场景：目录下每个 .json 一张卡（容忍 {"characters":[…]} 包装形式，与 LoreRepository 一致）。
func _load_card_dir(dir_path: String, label: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		load_report.append("未找到目录 %s（%s 为空）" % [dir_path, label])
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var data := JsonTool.read_json_file(dir_path + "/" + file_name)
			var items: Array = []
			if data.has("characters") and data["characters"] is Array:
				items.append_array(data["characters"])
			elif data.has("scenes") and data["scenes"] is Array:
				items.append_array(data["scenes"])
			elif not data.is_empty():
				items.append(data)
			for raw in items:
				if raw is Dictionary:
					out.append(raw)
		file_name = dir.get_next()
	dir.list_dir_end()
	return out


## 跨对话记忆：settings/memory/*.json（npc_id + summary，原样带出）。
func _load_memory() -> void:
	memory = {}
	var dir := DirAccess.open(SETTING_ROOT + "/memory")
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var data := JsonTool.read_json_file(SETTING_ROOT + "/memory/" + file_name)
			if not data.is_empty():
				memory[str(data.get("npc_id", file_name.trim_suffix(".json")))] = data
		file_name = dir.get_next()
	dir.list_dir_end()


## 事实库：运行时正典全量（作者播种 + 运行期确立；含被取代条目，页面上灰显可删）。
func _load_facts() -> void:
	facts = []
	for fact in CanonStore.all_entries():
		var d := fact.to_dict()
		facts.append({
			"id": d.get("id", 0),
			"content": str(d.get("content", "")),
			"weight": str(d.get("weight", "minor")),
			"source": str(d.get("source", "narrator")),
			"scope": (d.get("scope", []) as Array).duplicate(),
			"status": str(d.get("status", "active")),
		})


## 风格四旋钮：GameConfig 的只读快照（编辑写回草稿，不落游戏配置）。
func _load_style() -> void:
	var config := GameConfig.new()
	config.load_from_disk()
	style = {
		"adoption": config.narration_adoption,
		"verdict": config.narration_verdict,
		"density": config.narration_density,
		"threshold": config.narration_threshold,
	}


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return (FileAccess.get_file_as_string(path) as String).trim_prefix("\uFEFF")
