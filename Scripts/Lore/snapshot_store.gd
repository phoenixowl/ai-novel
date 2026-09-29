extends RefCounted
## 人物运行时快照（Lore 层）：user://characters/<id>.json 是单个人物设定集的运行时快照。
## 一切修改（对话学习、编辑页保存）都写这里；res://settings/ 的作者卡面是只读模板，
## 只有「写回作者卡面」按钮会反向写入它。
##
## 文件分两区，读-改-写互不覆盖：
##   persona 区：name / identity / profile —— 键存在才接管该字段，缺失 = 跟随作者卡面
##   journal 区：knowledge（全量条目）/ memories / next_seq —— "knowledge" 键存在即接管知识日志
##
## 玩家快照是 user://player.json（不属于本类，由 DialogueController 写）。
## 注意：本文件刻意不用 class_name——以 preload 引用，避免 headless 运行时全局类缓存滞后。

const DIR := "user://characters"


static func _path(npc_id: String) -> String:
	return "%s/%s.json" % [DIR, npc_id]


static func exists(npc_id: String) -> bool:
	return FileAccess.file_exists(_path(npc_id))


static func _read(npc_id: String) -> Dictionary:
	if not exists(npc_id):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path(npc_id)))
	return parsed if parsed is Dictionary else {}


static func _write(npc_id: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var file := FileAccess.open(_path(npc_id), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "  "))
		file.close()


## 读 persona 区（无快照或无人设键返回 {}——调用方回落作者卡面）。
static func read_persona(npc_id: String) -> Dictionary:
	var data := _read(npc_id)
	var out := {}
	for key in ["name", "identity", "profile"]:
		if data.has(key):
			out[key] = str(data[key])
	return out


## 写 persona 区（读-改-写保留 journal 区；快照不存在时创建仅含人设的文件）。
static func write_persona(npc_id: String, persona: Dictionary) -> void:
	var data := _read(npc_id)
	for key in ["name", "identity", "profile"]:
		if persona.has(key):
			data[key] = str(persona[key])
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
	wipe_json_dir(DIR)
