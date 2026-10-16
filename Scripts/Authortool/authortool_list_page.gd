class_name AuthortoolListPage
extends AuthortoolPage
## AuthorTool 列表型子页基座（Scripts/Authortool/）：左列表（新增/删除）+ 右表单双栏骨架。
## 选中即编辑：控件信号即时写回所选卡片（草稿是唯一真值，无"保存"步骤）。
## 子类实现六个钩子：_page_hint / _cards / _card_label / _new_card / _build_form / _fill_form。

var draft: AuthortoolDraft
var current: Dictionary = {}   # 当前选中的卡片（子类表单信号把编辑写进它的键）

var _list: ItemList
var _del_btn: Button
var _form: VBoxContainer
var _index := -1
var _filling := false         # 表单回填期闸门：程序赋值触发的信号不再写回


## 注入草稿并构建 UI（每个页面实例只调一次）。
func setup(draft_: AuthortoolDraft) -> void:
	draft = draft_
	add_theme_constant_override("separation", 10)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(AuthortoolWidgets.caption(_page_hint()))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 左栏：卡片列表 + 增删
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(230, 240)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	left.add_child(_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var add_btn := AuthortoolWidgets.button("新增", false, true)
	add_btn.pressed.connect(_on_add)
	row.add_child(add_btn)
	_del_btn = AuthortoolWidgets.button("删除", false, true)
	_del_btn.disabled = true
	_del_btn.pressed.connect(_on_delete)
	row.add_child(_del_btn)
	left.add_child(row)
	body.add_child(left)

	# 右栏：表单（本页滚动）
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_theme_constant_override("separation", 10)
	scroll.add_child(_form)
	body.add_child(scroll)
	add_child(body)

	_build_form(_form)
	apply_draft(draft)


## 重新载入/换草稿：刷新列表并清空选择（子类若持额外表单可重写并调用父类）。
func apply_draft(draft_: AuthortoolDraft) -> void:
	draft = draft_
	_index = -1
	current = {}
	refresh_list()


# ———— 钩子（子类实现） ————


## 页顶说明文字。
func _page_hint() -> String:
	return ""


## 本页编辑的卡片数组（直接指向草稿的区段）。
func _cards() -> Array:
	return []


## 列表行文字。
func _card_label(_card: Dictionary) -> String:
	return str(_card.get("name", "（未命名）"))


## 「新增」按钮创建的卡片（追加进 _cards()）。
func _new_card() -> Dictionary:
	return {}


## 构建表单控件（只调一次；信号把编辑写入 current）。
func _build_form(_form: VBoxContainer) -> void:
	pass


## 用所选卡片回填表单（card 为空字典表示未选中）。
func _fill_form(_card: Dictionary) -> void:
	pass


# ———— 列表与选择 ————


func refresh_list() -> void:
	_list.clear()
	for raw in _cards():
		_list.add_item(_card_label(raw as Dictionary))
	_apply_selection()


func _on_selected(index: int) -> void:
	_index = index
	_apply_selection()


func _on_add() -> void:
	_cards().append(_new_card())
	_index = _cards().size() - 1
	refresh_list()


func _on_delete() -> void:
	if _index < 0 or _index >= _cards().size():
		return
	_cards().remove_at(_index)
	_index = mini(_index, _cards().size() - 1)
	refresh_list()


## 把当前下标应用到列表高亮与表单（越界即视为未选中）。
func _apply_selection() -> void:
	if _index >= 0 and _index < _list.item_count and _index < _cards().size():
		_list.select(_index)
		current = _cards()[_index]
		_del_btn.disabled = false
	else:
		_index = -1
		current = {}
		_del_btn.disabled = true
		_list.deselect_all()
	_filling = true
	_fill_form(current)
	_filling = false
	_set_form_enabled(not current.is_empty())


## 回填期闸门（子类信号处理器开头调用：回填引发的信号不写回）。
func _is_filling() -> bool:
	return _filling


## 递归启停表单控件（未选中时整表置灰）。
func _set_form_enabled(enabled: bool) -> void:
	_set_children_enabled(_form, enabled)


static func _set_children_enabled(node: Node, enabled: bool) -> void:
	for child in node.get_children():
		if child is Control and "disabled" in child:
			(child as Control).set("disabled", not enabled)
		_set_children_enabled(child, enabled)
