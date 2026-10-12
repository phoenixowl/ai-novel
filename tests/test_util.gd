class_name TestUtil
extends RefCounted
## 测试辅助（tests/ 专用）：两个 SceneTree 测试脚本共用的断言输出。


static func check(condition: bool, label: String, failures: int) -> int:
	if condition:
		print("  [通过] " + label)
		return failures
	print("  [失败] " + label)
	return failures + 1


## 删除全部 gen_ 前缀的人物运行时快照（discoveries 生成的测试残留；共享 user:// 时保持断言确定性）。
static func clear_gen_characters() -> void:
	var dir := DirAccess.open(OS.get_user_data_dir() + "/characters")
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.begins_with("gen_") and file_name.ends_with(".json"):
			DirAccess.remove_absolute(OS.get_user_data_dir() + "/characters/" + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
