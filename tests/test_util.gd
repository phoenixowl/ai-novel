class_name TestUtil
extends RefCounted
## 测试辅助（tests/ 专用）：断言输出与运行期数据的确定性重置。


static func check(condition: bool, label: String, failures: int) -> int:
	if condition:
		print("  [通过] " + label)
		return failures
	print("  [失败] " + label)
	return failures + 1


## 运行期数据确定性重置：删除整个 saves/ 目录树（动态世界观/快照/配置全清——
## settings/ 是初始世界观不动）。仅测试环境使用。
static func reset_runtime() -> void:
	_wipe_dir(GamePaths.save_dir())


## 删除全部 gen_ 前缀的人物运行时快照（测试残留清理；保持断言确定性）。
static func clear_gen_characters() -> void:
	var dir := DirAccess.open(GamePaths.characters_dir())
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.begins_with("gen_") and file_name.ends_with(".json"):
			DirAccess.remove_absolute(GamePaths.characters_dir() + "/" + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


static func _wipe_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var names: Array[String] = []
	var name := dir.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			names.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	for n in names:
		var sub := path + "/" + n
		if DirAccess.dir_exists_absolute(sub):
			_wipe_dir(sub)
		else:
			DirAccess.remove_absolute(sub)
	DirAccess.remove_absolute(path)
