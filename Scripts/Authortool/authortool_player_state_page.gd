class_name AuthortoolPlayerStatePage
extends AuthortoolPage
## AuthorTool 子页：玩家状态模板的结构化编辑——计数器（数值资源）与条目集（清单）
## 两区，各自增删改；条目集内嵌字段行（key/显示名/类型/必填/范围/默认值）增删改。
## 编辑即时写回草稿（player_state），导出为 player_state.json；两个数组都为空时
## 不导出该文件（引擎回落内置默认模板）。引擎通用：页面不含任何世界观词汇。


const FIELD_TYPES := ["string", "int", "bool"]
const TYPE_LABELS := {"string": "文本", "int": "整数", "bool": "布尔"}


var _draft: AuthortoolDraft
var _root: VBoxContainer


func setup(draft: AuthortoolDraft) -> void:
	_draft = draft
	add_theme_constant_override("separation", 10)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(AuthortoolWidgets.caption(
		"玩家状态模板（引擎通用：计数器=数值资源，条目集=清单；导出为 player_state.json。全部删空则不导出——引擎使用内置默认模板）"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 12)
	scroll.add_child(_root)
	add_child(scroll)
	apply_draft(draft)


func apply_draft(draft: AuthortoolDraft) -> void:
	_draft = draft
	if not (_draft.player_state.get("counters", []) is Array):
		_draft.player_state["counters"] = []
	if not (_draft.player_state.get("collections", []) is Array):
		_draft.player_state["collections"] = []
	_rebuild()


# ———— 结构变更入口（测试也直接调用） ————


## 新增一个计数器声明。
func _add_counter() -> void:
	var n := (_draft.player_state["counters"] as Array).size() + 1
	(_draft.player_state["counters"] as Array).append(
		{"key": "counter_%d" % n, "label": "新计数器",
			"min": 0, "max": 9999, "initial": 0, "hint": ""})
	_rebuild()


## 新增一个条目集声明。
func _add_collection() -> void:
	var n := (_draft.player_state["collections"] as Array).size() + 1
	(_draft.player_state["collections"] as Array).append(
		{"key": "list_%d" % n, "label": "新清单", "cap": 20,
			"canon_sync": false, "npc_visible": false,
			"fields": [{"key": "name", "label": "名称", "required": true, "type": "string", "max": 40}]})
	_rebuild()


# ———— 整表重建（结构变更后；文本编辑不重建，直接写字典） ————


func _rebuild() -> void:
	for child in _root.get_children():
		child.queue_free()
	_build_counters_section()
	_root.add_child(HSeparator.new())
	_build_collections_section()


func _build_counters_section() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var title := AuthortoolWidgets.caption("计数器（带上下限的数值资源；DM 的 player.state 按显示名引用）", false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var add_btn := AuthortoolWidgets.button("新增计数器", false, true)
	add_btn.pressed.connect(_add_counter)
	header.add_child(add_btn)
	_root.add_child(header)
	var counters: Array = _draft.player_state["counters"]
	if counters.is_empty():
		_root.add_child(AuthortoolWidgets.caption("（暂无计数器）"))
	for i in counters.size():
		_root.add_child(_build_counter_group(counters[i] as Dictionary, i))


func _build_counter_group(c: Dictionary, index: int) -> Control:
	var group := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.18, 0.6)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	group.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	group.add_child(box)
	# 头：序号 + 删除
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := AuthortoolWidgets.caption("计数器 %d · %s" % [index + 1, str(c.get("label", "?"))], false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var del := AuthortoolWidgets.button("删除", false, true)
	del.pressed.connect(func():
		(_draft.player_state["counters"] as Array).erase(c)
		_rebuild())
	head.add_child(del)
	box.add_child(head)
	# key / 显示名
	var key_edit := AuthortoolWidgets.line_edit("内部 key（英文/数字/下划线）")
	key_edit.text = str(c.get("key", ""))
	key_edit.text_changed.connect(func(t: String): c["key"] = AuthortoolWidgets.sanitize_id(t))
	box.add_child(AuthortoolWidgets.field_row("key", key_edit))
	var label_edit := AuthortoolWidgets.line_edit("显示名（提示词与界面展示）")
	label_edit.text = str(c.get("label", ""))
	label_edit.text_changed.connect(func(t: String):
		c["label"] = t
		title.text = "计数器 %d · %s" % [index + 1, t])
	box.add_child(AuthortoolWidgets.field_row("显示名", label_edit))
	# 下限 / 上限 / 初始值
	var range_row := HBoxContainer.new()
	range_row.add_theme_constant_override("separation", 8)
	range_row.add_child(AuthortoolWidgets.caption("下限/上限/初始值", false))
	var min_edit := _int_edit(str(int(c.get("min", 0))), func(v: int): c["min"] = v)
	var max_edit := _int_edit(str(int(c.get("max", 9999))), func(v: int): c["max"] = v)
	var init_edit := _int_edit(str(int(c.get("initial", 0))), func(v: int): c["initial"] = v)
	range_row.add_child(min_edit)
	range_row.add_child(max_edit)
	range_row.add_child(init_edit)
	box.add_child(range_row)
	# 提示语
	var hint_edit := AuthortoolWidgets.line_edit("注入提示词的一句说明（可空）")
	hint_edit.text = str(c.get("hint", ""))
	hint_edit.text_changed.connect(func(t: String): c["hint"] = t)
	box.add_child(AuthortoolWidgets.field_row("说明", hint_edit))
	return group


func _build_collections_section() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var title := AuthortoolWidgets.caption("条目集（清单：字段化的记录；物品/状态/之约都是清单）", false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var add_btn := AuthortoolWidgets.button("新增条目集", false, true)
	add_btn.pressed.connect(_add_collection)
	header.add_child(add_btn)
	_root.add_child(header)
	var collections: Array = _draft.player_state["collections"]
	if collections.is_empty():
		_root.add_child(AuthortoolWidgets.caption("（暂无条目集）"))
	for i in collections.size():
		_root.add_child(_build_collection_group(collections[i] as Dictionary, i))


func _build_collection_group(col: Dictionary, index: int) -> Control:
	var group := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.18, 0.6)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	group.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	group.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := AuthortoolWidgets.caption("条目集 %d · %s" % [index + 1, str(col.get("label", "?"))], false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var del := AuthortoolWidgets.button("删除", false, true)
	del.pressed.connect(func():
		(_draft.player_state["collections"] as Array).erase(col)
		_rebuild())
	head.add_child(del)
	box.add_child(head)
	# key / 显示名 / 上限
	var key_edit := AuthortoolWidgets.line_edit("内部 key（英文/数字/下划线）")
	key_edit.text = str(col.get("key", ""))
	key_edit.text_changed.connect(func(t: String): col["key"] = AuthortoolWidgets.sanitize_id(t))
	box.add_child(AuthortoolWidgets.field_row("key", key_edit))
	var label_edit := AuthortoolWidgets.line_edit("显示名")
	label_edit.text = str(col.get("label", ""))
	label_edit.text_changed.connect(func(t: String):
		col["label"] = t
		title.text = "条目集 %d · %s" % [index + 1, t])
	box.add_child(AuthortoolWidgets.field_row("显示名", label_edit))
	var cap_edit := _int_edit(str(int(col.get("cap", 20))), func(v: int): col["cap"] = maxi(1, v))
	box.add_child(AuthortoolWidgets.field_row("条数上限", cap_edit))
	# 两个引擎开关
	var sync_check := AuthortoolWidgets.check(bool(col.get("canon_sync", false)))
	sync_check.text = "增删自动同步正典（背包类开——NPC 侧世界与档案一致）"
	sync_check.toggled.connect(func(on: bool): col["canon_sync"] = on)
	box.add_child(sync_check)
	var visible_check := AuthortoolWidgets.check(bool(col.get("npc_visible", false)))
	visible_check.text = "NPC 可见（注入 NPC 材料层——默认关：玩家的牌面）"
	visible_check.toggled.connect(func(on: bool): col["npc_visible"] = on)
	box.add_child(visible_check)
	# 字段子表
	box.add_child(AuthortoolWidgets.caption("字段（每条记录由这些字段组成；至少一个）", false))
	var fields: Array = col.get("fields", [])
	if not (fields is Array) or fields.is_empty():
		col["fields"] = [{"key": "name", "label": "名称", "required": true, "type": "string", "max": 40}]
		fields = col["fields"]
	for fi in fields.size():
		box.add_child(_build_field_row(fields[fi] as Dictionary, col, fi))
	var add_field := AuthortoolWidgets.button("添加字段", false, true)
	add_field.pressed.connect(func():
		(col["fields"] as Array).append(
			{"key": "field_%d" % (col["fields"] as Array).size(), "label": "新字段",
				"required": false, "type": "string", "max": 40})
		_rebuild())
	box.add_child(add_field)
	return group


## 单个字段行（紧凑两行布局：主属性行 + 类型属性行）。
func _build_field_row(f: Dictionary, col: Dictionary, fi: int) -> VBoxContainer:
	var row_box := VBoxContainer.new()
	row_box.add_theme_constant_override("separation", 6)
	# 主行：key、显示名、删除
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 6)
	var key_edit := AuthortoolWidgets.line_edit("字段 key")
	key_edit.text = str(f.get("key", ""))
	key_edit.text_changed.connect(func(t: String): f["key"] = AuthortoolWidgets.sanitize_id(t))
	key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(key_edit)
	var label_edit := AuthortoolWidgets.line_edit("显示名")
	label_edit.text = str(f.get("label", ""))
	label_edit.text_changed.connect(func(t: String): f["label"] = t)
	label_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(label_edit)
	var del := AuthortoolWidgets.button("删", false, true)
	del.pressed.connect(func():
		(col["fields"] as Array).erase(f)
		_rebuild())
	main.add_child(del)
	row_box.add_child(main)
	# 属性行：类型、必填、字长/范围、默认值
	var attrs := HBoxContainer.new()
	attrs.add_theme_constant_override("separation", 6)
	var type_labels: Array = []
	for t in FIELD_TYPES:
		type_labels.append(TYPE_LABELS[t])
	var type_option := AuthortoolWidgets.option(type_labels, FIELD_TYPES.find(str(f.get("type", "string"))))
	type_option.custom_minimum_size.x = 100
	type_option.item_selected.connect(func(i: int):
		f["type"] = FIELD_TYPES[i]
		if FIELD_TYPES[i] == "int" and not f.has("min"):
			f["min"] = 0
		_rebuild())
	attrs.add_child(type_option)
	var required_check := AuthortoolWidgets.check(bool(f.get("required", false)))
	required_check.text = "必填"
	required_check.toggled.connect(func(on: bool): f["required"] = on)
	attrs.add_child(required_check)
	if str(f.get("type", "string")) == "int":
		var min_edit := _int_edit(str(int(f.get("min", 0))), func(v: int): f["min"] = v)
		min_edit.placeholder_text = "下限"
		min_edit.custom_minimum_size.x = 70
		attrs.add_child(min_edit)
		var max_edit := _int_edit(str(int(f.get("max", 999))), func(v: int): f["max"] = v)
		max_edit.placeholder_text = "上限"
		max_edit.custom_minimum_size.x = 70
		attrs.add_child(max_edit)
	else:
		var max_edit := _int_edit(str(int(f.get("max", 40))), func(v: int): f["max"] = maxi(1, v))
		max_edit.placeholder_text = "字数上限"
		max_edit.custom_minimum_size.x = 80
		attrs.add_child(max_edit)
	var default_edit := AuthortoolWidgets.line_edit("默认值（可空）")
	default_edit.text = str(f.get("default", ""))
	default_edit.custom_minimum_size.x = 120
	default_edit.text_changed.connect(func(t: String):
		if str(f.get("type", "string")) == "int" and t.is_valid_int():
			f["default"] = int(t)
		elif str(f.get("type", "string")) == "bool" and ["true", "false", "是", "否"].has(t.to_lower()):
			f["default"] = t.to_lower() == "true" or t.to_lower() == "是"
		elif str(f.get("type", "string")) == "string":
			f["default"] = t
		else:
			f.erase("default"))
	attrs.add_child(default_edit)
	row_box.add_child(attrs)
	return row_box


## 整数输入框（非法输入不写回）。
func _int_edit(initial: String, on_write: Callable) -> LineEdit:
	var edit := AuthortoolWidgets.line_edit("整数")
	edit.text = initial
	edit.custom_minimum_size.x = 90
	edit.text_changed.connect(func(t: String):
		if t.is_valid_int():
			on_write.call(int(t)))
	return edit
