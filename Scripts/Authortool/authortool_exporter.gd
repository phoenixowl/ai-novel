class_name AuthortoolExporter
extends RefCounted
## AuthorTool 导出器（Scripts/Authortool/）：把草稿写成一份完整的作者数据包，
## 落在独立目录 user://authortool_export/<时间戳>/（同秒重导追加序号）——
## 镜像 settings/ 目录结构，另附 style.json 与 authortool_manifest.json；
## 不触碰 res://settings 与 user:// 其它任何目录。
## 事实只导出 active 条目（settings/canon.json 的作者播种格式；narrator 来源省略以贴合既有文件风格）。


const EXPORT_ROOT := "user://authortool_export"
const INDENT := "  "


## 导出草稿到 <root>/<时间戳>/。返回 {ok, path(user:// 目录), abs_path, files[user://…], error}。
## draft：编辑完成的草稿；root：导出根目录（测试可注入别的目录）。
static func export_draft(draft: AuthortoolDraft, root := EXPORT_ROOT) -> Dictionary:
	var stamp := Time.get_datetime_string_from_system()
	stamp = stamp.replace(":", "").replace("-", "").replace("T", "_")
	var dir := "%s/%s" % [root, stamp]
	var serial := 1
	while DirAccess.dir_exists_absolute(dir):
		serial += 1
		dir = "%s/%s_%d" % [root, stamp, serial]
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		return {"ok": false, "path": dir, "abs_path": ProjectSettings.globalize_path(dir),
			"files": [], "error": "无法创建导出目录（错误码 %d）：%s" % [err, dir]}

	var files: Array = []
	var problems: Array[String] = []

	# 纯文本与单文件
	files.append(_write_text(dir + "/worldview.txt", draft.worldview))
	files.append(_write_text(dir + "/mainline.txt", draft.mainline))
	files.append(_write_json(dir + "/factions.json", {"factions": draft.factions}))
	files.append(_write_json(dir + "/player.json", draft.player))
	files.append(_write_json(dir + "/canon.json", {"facts": _facts_for_export(draft)}))

	# 人物/场景/记忆：每卡一文件，文件名取卡片 id（清洗后）
	for raw in draft.characters:
		var card := raw as Dictionary
		var id := AuthortoolWidgets.sanitize_id(str(card.get("id", "")))
		if id.is_empty():
			problems.append("一张人物卡缺少 id，已跳过")
			continue
		files.append(_write_json("%s/characters/%s.json" % [dir, id], card))
	for raw in draft.scenes:
		var card := raw as Dictionary
		var id := AuthortoolWidgets.sanitize_id(str(card.get("id", "")))
		if id.is_empty():
			problems.append("一张场景卡缺少 id，已跳过")
			continue
		files.append(_write_json("%s/scenes/%s.json" % [dir, id], card))
	for npc_id in draft.memory:
		var id := AuthortoolWidgets.sanitize_id(str(npc_id))
		if id.is_empty():
			continue
		files.append(_write_json("%s/memory/%s.json" % [dir, id], draft.memory[npc_id]))

	# 风格与清单
	files.append(_write_json(dir + "/style.json", draft.style))
	var manifest := {
		"tool": "authortool",
		"exported_at": Time.get_datetime_string_from_system(),
		"counts": {
			"factions": draft.factions.size(),
			"characters": draft.characters.size(),
			"scenes": draft.scenes.size(),
			"facts": _facts_for_export(draft).size(),
			"memory": draft.memory.size(),
		},
		"notes": "本目录是完整作者数据包，可整目录覆盖 settings/ 使用；"
			+ "style.json 对应 DM 风格四旋钮（采纳度/裁决倾向/描写密度/正典门槛）。",
	}
	if not problems.is_empty():
		manifest["problems"] = problems
	files.append(_write_json(dir + "/authortool_manifest.json", manifest))

	return {"ok": true, "path": dir, "abs_path": ProjectSettings.globalize_path(dir),
		"files": files, "error": ""}


## 事实导出形态：仅 active；{content, weight, scope}（player 来源显式标注，narrator 省略）。
static func _facts_for_export(draft: AuthortoolDraft) -> Array:
	var out: Array = []
	for raw in draft.facts:
		var f := raw as Dictionary
		if str(f.get("status", "active")) != "active":
			continue
		var item := {"content": str(f.get("content", "")), "weight": str(f.get("weight", "minor"))}
		var scope: Array = f.get("scope", [])
		if not scope.is_empty():
			item["scope"] = scope
		if str(f.get("source", "narrator")) != "narrator":
			item["source"] = str(f.get("source", "narrator"))
		out.append(item)
	return out


static func _write_text(path: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("AuthorTool 导出失败：" + path)
		return path
	file.store_string(text)
	file.close()
	return path


static func _write_json(path: String, data: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("AuthorTool 导出失败：" + path)
		return path
	file.store_string(JSON.stringify(data, INDENT))
	file.close()
	return path
