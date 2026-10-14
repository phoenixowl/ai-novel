class_name AuthortoolFactionsPage
extends AuthortoolListPage
## AuthorTool 子页：组织编辑——id/名称/介绍 + 成员表（名称+职位，行内增删）。
## 编辑即时写回草稿；导出为 factions.json（全键保真）。

var _id_edit: LineEdit
var _name_edit: LineEdit
var _desc_edit: TextEdit
var _member_rows: VBoxContainer


func _page_hint() -> String:
	return "组织（factions.json；成员可含没有人物卡的配角）"


func _cards() -> Array:
	return draft.factions


func _card_label(card: Dictionary) -> String:
	return "%s（%s）" % [card.get("name", "未命名"), card.get("id", "?")]


func _new_card() -> Dictionary:
	return {"id": "faction_%d" % (draft.factions.size() + 1), "name": "新组织",
		"description": "", "members": []}


func _build_form(form: VBoxContainer) -> void:
	_id_edit = AuthortoolWidgets.line_edit("组织 id（英文/数字/下划线）")
	_id_edit.text_changed.connect(func(t: String): _write("id", AuthortoolWidgets.sanitize_id(t)))
	form.add_child(AuthortoolWidgets.field_row("id", _id_edit))
	_name_edit = AuthortoolWidgets.line_edit("组织名称")
	_name_edit.text_changed.connect(func(t: String): _write("name", t))
	form.add_child(AuthortoolWidgets.field_row("名称", _name_edit))
	_desc_edit = AuthortoolWidgets.text_edit(110)
	_desc_edit.text_changed.connect(func(t: String): _write("description", t))
	form.add_child(AuthortoolWidgets.field_row("介绍", _desc_edit))
	form.add_child(AuthortoolWidgets.caption("成员（名称 + 职位；名称与人物卡姓名匹配可带出职位）", false))
	_member_rows = VBoxContainer.new()
	_member_rows.add_theme_constant_override("separation", 6)
	form.add_child(_member_rows)
	var add_member := AuthortoolWidgets.button("添加成员", false, true)
	add_member.pressed.connect(func():
		if current.is_empty():
			return
		(current["members"] as Array).append({"name": "", "position": ""})
		_rebuild_members())
	form.add_child(add_member)


func _fill_form(card: Dictionary) -> void:
	_id_edit.text = str(card.get("id", ""))
	_name_edit.text = str(card.get("name", ""))
	_desc_edit.text = str(card.get("description", ""))
	_rebuild_members()


## 成员行整表重建（增删与切换选择后调用；行信号按捕获下标写入 current.members）。
func _rebuild_members() -> void:
	for child in _member_rows.get_children():
		child.queue_free()
	if current.is_empty():
		return
	var members: Array = current.get("members", [])
	for i in members.size():
		var member := members[i] as Dictionary
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_edit := AuthortoolWidgets.line_edit("成员名称")
		name_edit.text = str(member.get("name", ""))
		name_edit.text_changed.connect(func(t: String):
			if not _is_filling() and i < (current.get("members", []) as Array).size():
				((current["members"] as Array)[i] as Dictionary)["name"] = t)
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_edit)
		var pos_edit := AuthortoolWidgets.line_edit("职位")
		pos_edit.text = str(member.get("position", ""))
		pos_edit.text_changed.connect(func(t: String):
			if not _is_filling() and i < (current.get("members", []) as Array).size():
				((current["members"] as Array)[i] as Dictionary)["position"] = t)
		pos_edit.custom_minimum_size.x = 140
		row.add_child(pos_edit)
		var del := AuthortoolWidgets.button("删", false, true)
		del.pressed.connect(func():
			if i < (current.get("members", []) as Array).size():
				(current["members"] as Array).remove_at(i)
				_rebuild_members())
		row.add_child(del)
		_member_rows.add_child(row)


func _write(key: String, value: String) -> void:
	if _is_filling() or current.is_empty():
		return
	current[key] = value
	refresh_list()
