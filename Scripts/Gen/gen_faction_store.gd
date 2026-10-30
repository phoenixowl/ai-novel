class_name GenFactionStore
extends RefCounted
## 动态组织存储（Gen 层，存取器）：saves/world/gen_factions.json 的唯一读写入口。
## 动态生成的组织与作者组织同等对待——LoreRepository 加载时合并进 factions 字典；
## 实体注册表投影只存公共字段，装不下介绍与成员表，故独立文件。
## id 由 EntityRegistry.register_gen 统一分配（gen_N），本类只按给定 id 存取，
## 保证注册表、正典作用域、组织文件三处引用的是同一个 id。


static func path() -> String:
	return GamePaths.gen_factions_path()

static var _factions: Array = []  # [{id, name, description, members: [{name, position}]}]
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var data := JsonTool.read_json_file(path())
	if data.is_empty():
		return
	var raw: Variant = data.get("factions", [])
	if raw is Array:
		for item in raw:
			if item is Dictionary:
				_factions.append(item)


static func save() -> void:
	DirAccess.make_dir_recursive_absolute(GamePaths.world_dir())
	JsonTool.write_json_file(path(), {"factions": _factions})


## 新增一个动态组织（id 已由注册表分配）并落盘。返回完整条目。
static func add(id: String, name: String, description: String, members: Array) -> Dictionary:
	_ensure_loaded()
	var entry := {"id": id, "name": name, "description": description, "members": members}
	_factions.append(entry)
	save()
	return entry


## 全部动态组织条目（LoreRepository 合并用）。
static func all() -> Array:
	_ensure_loaded()
	return _factions


## 按 id 判断动态组织是否存在（批内可见性：同批先生成的组织对后继 agent 可见）。
static func has(id: String) -> bool:
	_ensure_loaded()
	for entry in _factions:
		if str(entry.get("id", "")) == id:
			return true
	return false


## 清空全部动态组织并删除磁盘文件（"清除动态生成内容"入口）。
static func erase_all() -> void:
	_factions = []
	_loaded = true
	if FileAccess.file_exists(path()):
		DirAccess.remove_absolute(path())


## 清空内存状态（测试用；不删磁盘文件）。
static func reset_for_test() -> void:
	_factions = []
	_loaded = true
