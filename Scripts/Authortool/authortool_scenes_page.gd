class_name AuthortoolScenesPage
extends AuthortoolListPage
## AuthorTool 子页：场景编辑——id/名称/别名/路线(links)/在场(npcs)/环境/氛围/开场情境。
## 编辑即时写回草稿；每卡导出为 scenes/<id>.json（全键保真）。

var _id_edit: LineEdit
var _name_edit: LineEdit
var _aliases_edit: LineEdit
var _links_edit: LineEdit
var _npcs_edit: LineEdit
var _env_edit: TextEdit
var _atmo_edit: TextEdit
var _opening_edit: TextEdit


func _page_hint() -> String:
	return "场景（位置图节点；links 声明初始路线，npcs 声明初始在场人物，逗号分隔）"


func _cards() -> Array:
	return draft.scenes


func _card_label(card: Dictionary) -> String:
	return "%s（%s）" % [card.get("name", "未命名"), card.get("id", "?")]


func _new_card() -> Dictionary:
	return {"id": "scene_%d" % (draft.scenes.size() + 1), "name": "新场景",
		"aliases": [], "links": [], "npcs": [], "environment": "", "atmosphere": "",
		"opening_situation": ""}


func _build_form(form: VBoxContainer) -> void:
	_id_edit = AuthortoolWidgets.line_edit("场景 id")
	_id_edit.text_changed.connect(func(t: String): _write("id", AuthortoolWidgets.sanitize_id(t)))
	form.add_child(AuthortoolWidgets.field_row("id", _id_edit))
	_name_edit = AuthortoolWidgets.line_edit("场景名称")
	_name_edit.text_changed.connect(func(t: String): _write("name", t))
	form.add_child(AuthortoolWidgets.field_row("名称", _name_edit))
	_aliases_edit = AuthortoolWidgets.line_edit("别名，逗号分隔")
	_aliases_edit.text_changed.connect(func(t: String): _write("aliases", AuthortoolWidgets.split_csv(t)))
	form.add_child(AuthortoolWidgets.field_row("别名", _aliases_edit))
	_links_edit = AuthortoolWidgets.line_edit("相邻地点 id，逗号分隔")
	_links_edit.text_changed.connect(func(t: String): _write("links", AuthortoolWidgets.split_csv(t)))
	form.add_child(AuthortoolWidgets.field_row("路线 links", _links_edit))
	_npcs_edit = AuthortoolWidgets.line_edit("在场人物 id，逗号分隔")
	_npcs_edit.text_changed.connect(func(t: String): _write("npcs", AuthortoolWidgets.split_csv(t)))
	form.add_child(AuthortoolWidgets.field_row("在场 npcs", _npcs_edit))
	_env_edit = AuthortoolWidgets.text_edit(100)
	_env_edit.text_changed.connect(func(t: String): _write("environment", t))
	form.add_child(AuthortoolWidgets.field_row("环境与陈设", _env_edit))
	_atmo_edit = AuthortoolWidgets.text_edit(100)
	_atmo_edit.text_changed.connect(func(t: String): _write("atmosphere", t))
	form.add_child(AuthortoolWidgets.field_row("氛围", _atmo_edit))
	_opening_edit = AuthortoolWidgets.text_edit(100)
	_opening_edit.text_changed.connect(func(t: String): _write("opening_situation", t))
	form.add_child(AuthortoolWidgets.field_row("开场情境", _opening_edit))


func _fill_form(card: Dictionary) -> void:
	_id_edit.text = str(card.get("id", ""))
	_name_edit.text = str(card.get("name", ""))
	_aliases_edit.text = AuthortoolWidgets.join_list(card.get("aliases", []))
	_links_edit.text = AuthortoolWidgets.join_list(card.get("links", []))
	_npcs_edit.text = AuthortoolWidgets.join_list(card.get("npcs", []))
	_env_edit.text = str(card.get("environment", ""))
	_atmo_edit.text = str(card.get("atmosphere", ""))
	_opening_edit.text = str(card.get("opening_situation", ""))


func _write(key: String, value: Variant) -> void:
	if _is_filling() or current.is_empty():
		return
	current[key] = value
	refresh_list()
