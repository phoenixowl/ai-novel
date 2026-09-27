class_name EventJournal
extends RefCounted
## 事件日志（Common 层）：jsonl 追加式审计日志，每行一个 JSON 对象。
## DialogueEngine 每段对话持有一本（事件流水 + 被拒输入审计共用）；
## 阶段二的世界事件流水（设计 5.6 接入点三）以此为地基扩展。


var _file: FileAccess


## 打开（或切换到）一本新日志；返回文件路径。同一目录按“前缀_时间戳”命名。
func open(dir_path: String, file_prefix := "event") -> String:
	close()
	DirAccess.make_dir_recursive_absolute(dir_path)
	var stamp := Time.get_datetime_string_from_system()
	stamp = stamp.replace(":", "").replace("-", "").replace("T", "_")
	var path := "%s/%s_%s.jsonl" % [dir_path, file_prefix, stamp]
	_file = FileAccess.open(path, FileAccess.WRITE)
	return path


## 追加一行 JSON（未打开时静默忽略）。line：任意 Dictionary。
func append_line(line: Dictionary) -> void:
	if _file != null:
		_file.store_line(JSON.stringify(line))


## 关闭当前日志（幂等）。
func close() -> void:
	if _file != null:
		_file.close()
		_file = null


## 是否有打开中的日志文件。
func is_open() -> bool:
	return _file != null
