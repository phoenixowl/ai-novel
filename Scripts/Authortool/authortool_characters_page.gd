class_name AuthortoolCharactersPage
extends AuthortoolListPage
## AuthorTool 子页：人物编辑——页顶固定"玩家卡"区（name/identity/appearance），
## 其下为 NPC 列表 + 表单（id/姓名/身份/人设/别名/组织引用/好感度/知识行）。
## 编辑即时写回草稿；每卡导出为 characters/<id>.json（全键保真）。

const TRUSTS := ["怀疑", "比较相信", "绝对可信", "已失效"]

var _player_name: LineEdit
var _player_identity: LineEdit
var _player_appearance: LineEdit
var _id_edit: LineEdit
var _name_edit: LineEdit
var _identity_edit: LineEdit
var _profile_edit: TextEdit
var _aliases_edit: LineEdit
var _factions_edit: LineEdit
var _affinity_spin: SpinBox
var _knowledge_rows: VBoxContainer
var _player_filling := false


## 玩家区先行构建，再让基座把列表+表单挂在下方。
func setup(draft_: AuthortoolDraft) -> void:
	_build_player_section()
	super.setup(draft_)


func apply_draft(draft_: AuthortoolDraft) -> void:
	super.apply_draft(draft_)
	_player_filling = true
	_player_name.text = str(draft.player.get("name", ""))
	_player_identity.text = str(draft.player.get("identity", ""))
	_player_appearance.text = str(draft.player.get("appearance", ""))
	_player_filling = false


func _page_hint() -> String:
	return "人物卡（knowledge 内联初始知识：[{content, source, trust}]；导出每卡一文件，全键保真）"


func _cards() -> Array:
	return draft.characters


func _card_label(card: Dictionary) -> String:
	return "%s（%s）" % [card.get("name", "未命名"), card.get("id", "?")]


func _new_card() -> Dictionary:
	return {"id": "npc_%d" % (draft.characters.size() + 1), "name": "新人物",
		"identity": "", "profile": "", "knowledge": [], "factions": []}


# ———— 玩家卡（固定区，不属于列表） ————


func _build_player_section() -> void:
	add_child(AuthortoolWidgets.caption("玩家卡（settings/player.json；NPC 眼中的你）", false))
	_player_name = AuthortoolWidgets.line_edit("称呼")
	_player_name.text_changed.connect(func(t: String): _write_player("name", t))
	add_child(AuthortoolWidgets.field_row("称呼", _player_name))
	_player_identity = AuthortoolWidgets.line_edit("身份（在你眼中对方的身份）")
	_player_identity.text_changed.connect(func(t: String): _write_player("identity", t))
	add_child(AuthortoolWidgets.field_row("身份", _player_identity))
	_player_appearance = AuthortoolWidgets.line_edit("外观（NPC 看到的样子）")
	_player_appearance.text_changed.connect(func(t: String): _write_player("appearance", t))
	add_child(AuthortoolWidgets.field_row("外观", _player_appearance))
	add_child(HSeparator.new())


func _write_player(key: String, value: String) -> void:
	if not _player_filling:
		draft.player[key] = value


# ———— NPC 表单 ————


func _build_form(form: VBoxContainer) -> void:
	_id_edit = AuthortoolWidgets.line_edit("人物 id")
	_id_edit.text_changed.connect(func(t: String): _write("id", AuthortoolWidgets.sanitize_id(t)))
	form.add_child(AuthortoolWidgets.field_row("id", _id_edit))
	_name_edit = AuthortoolWidgets.line_edit("姓名")
	_name_edit.text_changed.connect(func(t: String): _write("name", t))
	form.add_child(AuthortoolWidgets.field_row("姓名", _name_edit))
	_identity_edit = AuthortoolWidgets.line_edit("身份（一句话：角色/年龄/所属）")
	_identity_edit.text_changed.connect(func(t: String): _write("identity", t))
	form.add_child(AuthortoolWidgets.field_row("身份", _identity_edit))
	_profile_edit = AuthortoolWidgets.text_edit(120)
	_profile_edit.text_changed.connect(func(t: String): _write("profile", t))
	form.add_child(AuthortoolWidgets.field_row("人设", _profile_edit))
	_aliases_edit = AuthortoolWidgets.line_edit("别名，逗号分隔")
	_aliases_edit.text_changed.connect(func(t: String): _write("aliases", AuthortoolWidgets.split_csv(t)))
	form.add_child(AuthortoolWidgets.field_row("别名", _aliases_edit))
	_factions_edit = AuthortoolWidgets.line_edit("组织 id，逗号分隔")
	_factions_edit.text_changed.connect(func(t: String): _write("factions", AuthortoolWidgets.split_csv(t)))
	form.add_child(AuthortoolWidgets.field_row("所属组织", _factions_edit))
	_affinity_spin = SpinBox.new()
	_affinity_spin.min_value = -100
	_affinity_spin.max_value = 100
	_affinity_spin.step = 1
	_affinity_spin.custom_minimum_size.y = 40
	_affinity_spin.value_changed.connect(func(v: float):
		if not _is_filling() and not current.is_empty():
			current["affinity"] = int(v))
	form.add_child(AuthortoolWidgets.field_row("初始好感度", _affinity_spin))
	form.add_child(AuthortoolWidgets.caption("知识日志（content + 来源 + 信任；来源如 常识/目睹/听说：某人）", false))
	_knowledge_rows = VBoxContainer.new()
	_knowledge_rows.add_theme_constant_override("separation", 6)
	form.add_child(_knowledge_rows)
	var add_knowledge := AuthortoolWidgets.button("添加知识", false, true)
	add_knowledge.pressed.connect(func():
		if current.is_empty():
			return
		(current["knowledge"] as Array).append({"content": "", "source": "常识", "trust": "比较相信"})
		_rebuild_knowledge())
	form.add_child(add_knowledge)


func _fill_form(card: Dictionary) -> void:
	_id_edit.text = str(card.get("id", ""))
	_name_edit.text = str(card.get("name", ""))
	_identity_edit.text = str(card.get("identity", ""))
	_profile_edit.text = str(card.get("profile", ""))
	_aliases_edit.text = AuthortoolWidgets.join_list(card.get("aliases", []))
	_factions_edit.text = AuthortoolWidgets.join_list(card.get("factions", []))
	_affinity_spin.set_value_no_signal(float(int(card.get("affinity", 0))))
	_rebuild_knowledge()


## 知识行整表重建（行信号按捕获下标写入 current.knowledge）。
func _rebuild_knowledge() -> void:
	for child in _knowledge_rows.get_children():
		child.queue_free()
	if current.is_empty():
		return
	var knowledge: Array = current.get("knowledge", [])
	for i in knowledge.size():
		var entry := knowledge[i] as Dictionary
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var content := AuthortoolWidgets.line_edit("知识表述")
		content.text = str(entry.get("content", ""))
		content.text_changed.connect(func(t: String):
			if not _is_filling() and i < (current.get("knowledge", []) as Array).size():
				((current["knowledge"] as Array)[i] as Dictionary)["content"] = t)
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(content)
		var source := AuthortoolWidgets.line_edit("来源")
		source.text = str(entry.get("source", ""))
		source.text_changed.connect(func(t: String):
			if not _is_filling() and i < (current.get("knowledge", []) as Array).size():
				((current["knowledge"] as Array)[i] as Dictionary)["source"] = t)
		source.custom_minimum_size.x = 150
		row.add_child(source)
		var trust := AuthortoolWidgets.option(TRUSTS, TRUSTS.find(str(entry.get("trust", "比较相信"))))
		trust.custom_minimum_size.x = 118
		trust.item_selected.connect(func(index: int):
			if not _is_filling() and i < (current.get("knowledge", []) as Array).size():
				((current["knowledge"] as Array)[i] as Dictionary)["trust"] = TRUSTS[index])
		row.add_child(trust)
		var del := AuthortoolWidgets.button("删", false, true)
		del.pressed.connect(func():
			if i < (current.get("knowledge", []) as Array).size():
				(current["knowledge"] as Array).remove_at(i)
				_rebuild_knowledge())
		row.add_child(del)
		_knowledge_rows.add_child(row)


func _write(key: String, value: Variant) -> void:
	if _is_filling() or current.is_empty():
		return
	current[key] = value
	refresh_list()
