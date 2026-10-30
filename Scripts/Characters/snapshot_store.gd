class_name SnapshotStore
extends RefCounted
## 人物运行时快照（Characters 层）：saves/characters/<id>.json 是单个人物设定集的运行时快照。
## 一切修改（对话学习、编辑页保存）都写这里；settings/ 的作者卡面是初始世界观基准，
## 只有「写回作者卡面」按钮会反向写入它。
##
## 文件分两区，读-改-写互不覆盖：
##   persona 区：name / identity / profile —— 键存在才接管该字段，缺失 = 跟随作者卡面
##   journal 区：knowledge（全量条目）/ memories / next_seq —— "knowledge" 键存在即接管知识日志
##
## 玩家卡覆盖在 saves/player.json（不属于本类）。
## 与其它静态存取器（CanonStore 等）一致以 class_name 全局引用；
## headless 测试前先跑一次 `godot --headless --path . --import` 刷新类缓存。


static func dir() -> String:
	return GamePaths.characters_dir()


static func _path(npc_id: String) -> String:
	return "%s/%s.json" % [dir(), npc_id]


static func exists(npc_id: String) -> bool:
	return FileAccess.file_exists(_path(npc_id))


static func _read(npc_id: String) -> Dictionary:
	return JsonTool.read_json_file(_path(npc_id))


static func _write(npc_id: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(dir())
	JsonTool.write_json_file(_path(npc_id), data)


## 读 persona 区（无快照或无人设键返回 {}——调用方回落作者卡面）。
## gen 人物快照的 "factions" 键随 persona 区往返（作者人物的归属以卡面为准，不读此键）。
static func read_persona(npc_id: String) -> Dictionary:
	var data := _read(npc_id)
	var out := {}
	for key in ["name", "identity", "profile"]:
		if data.has(key):
			out[key] = str(data[key])
	if data.has("factions"):
		out["factions"] = data.get("factions", [])
	return out


## 写 persona 区（读-改-写保留 journal 区；快照不存在时创建仅含人设的文件）。
static func write_persona(npc_id: String, persona: Dictionary) -> void:
	var data := _read(npc_id)
	for key in ["name", "identity", "profile"]:
		if persona.has(key):
			data[key] = str(persona[key])
	if persona.has("factions"):
		data["factions"] = persona["factions"]
	_write(npc_id, data)


## 读 journal 区；"knowledge" 键不存在返回 {}（调用方回落卡面知识 + 旧学习日志）。
static func read_journal(npc_id: String) -> Dictionary:
	var data := _read(npc_id)
	if not data.has("knowledge"):
		return {}
	return {
		"knowledge": data.get("knowledge", []),
		"memories": data.get("memories", []),
		"next_seq": int(data.get("next_seq", 0)),
	}


## 写 journal 区（读-改-写保留 persona 区）。
static func write_journal(npc_id: String, knowledge: Array, memories: Array, next_seq: int) -> void:
	var data := _read(npc_id)
	data["knowledge"] = knowledge
	data["memories"] = memories
	data["next_seq"] = next_seq
	_write(npc_id, data)


## 删除单个人物快照。
static func erase(npc_id: String) -> void:
	DirAccess.remove_absolute(_path(npc_id))


## 删除目录下全部 .json 文件（文件不存在时静默跳过）。
static func wipe_json_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			DirAccess.remove_absolute("%s/%s" % [dir_path, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()


## 删除全部人物快照（还原设定）。
static func erase_all() -> void:
	wipe_json_dir(dir())
