class_name FactBrowser
extends VBoxContainer
## 事实库浏览器（Scripts/UI/）：探索屏调试侧栏①页的交互版——
## 按类别（全局/地点/人物/势力）与实体筛选浏览世界事实正典，
## 逐条查看与修改（内容/权重）、新增（含作用域选择）、删除、显式保存。
## 纯代码构建（由 narration_screen 挂到调试侧栏首个标签页）。
## 与逻辑层经 EventBus 中转：订阅 canon_listed 快照（CanonFact 模型），
## 编辑走 cmd_add/edit/delete_fact 命令，保存走 cmd_save_canon。


const COLOR_SYSTEM := Color("#8d99ae")
const COLOR_GOLD := Color("#e0b36a")
const COLOR_TEXT := Color("#ced4da")
const COLOR_MUTED := Color("#6c757d")
const COLOR_ERROR := Color("#e76f51")
const COLOR_FIELD_BG := Color("#1c1d26")
const COLOR_FIELD_BORDER := Color("#343648")

## 类别定义：type 为 Entity.EntityType（-1 = 全局，无作用域）
const CATEGORIES := [
	{"label": "全局", "type": -1},
	{"label": "地点", "type": Entity.EntityType.LOCATION},
	{"label": "人物", "type": Entity.EntityType.PERSON},
	{"label": "势力", "type": Entity.EntityType.FACTION},
]
const TYPE_LABELS := {
	Entity.EntityType.LOCATION: "地点",
	Entity.EntityType.PERSON: "人物",
	Entity.EntityType.FACTION: "势力",
}
const WEIGHTS := ["minor", "major"]
const SOURCES := ["narrator", "player"]
const LIST_ROW_MAX := 90  # 列表行内容截断长度（完整内容见编辑区）

var _entries: Array = []  # canon_listed 快照（CanonFact，含 superseded）

var _narration: NarrationEvents
var _category_option: OptionButton
var _entity_option: OptionButton
var _save_store_btn: Button
var _reset_btn: Button
var _reset_confirm: ConfirmationDialog
var _add_btn: Button
var _list_scroll: ScrollContainer
var _list_box: VBoxContainer
var _count_label: Label
var _editor: VBoxContainer
var _editor_title: Label
var _content_edit: TextEdit
var _weight_option: OptionButton
var _source_option: OptionButton
var _scope_label: Label
var _save_btn: Button
var _delete_btn: Button
var _cancel_btn: Button
var _add_mode := false
var _selected_id := 0


## 取全局事件总线；autoload 未就绪时（理论上仅测试环境）手动创建。
func _bus() -> EventBus:
	return EventBus.shared() if EventBus.shared() != null else EventBus.create_shared()


func _ready() -> void:
	_narration = _bus().hub(NarrationEvents) as NarrationEvents
	_narration.canon_listed.connect(_on_canon_listed)
	_narration.canon_saved.connect(_on_canon_saved)
	_narration.canon_reset.connect(_on_canon_reset)
	_build()
	_narration.cmd_get_canon.emit()  # 拉取快照（浏览器可能晚于控制器就绪）


# ============================================================
#  构建（纯代码）
# ============================================================


func _build() -> void:
	add_theme_constant_override("separation", 8)

	# —— 筛选行：类别 + 实体 + 保存 + 新增 ——
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 8)
	filter_row.add_child(_caption("类别："))
	_category_option = OptionButton.new()
	_category_option.custom_minimum_size.x = 90
	for cat in CATEGORIES:
		_category_option.add_item(str(cat["label"]))
	_category_option.item_selected.connect(func(_i: int): _on_filter_changed())
	filter_row.add_child(_category_option)
	filter_row.add_child(_caption("筛选："))
	_entity_option = OptionButton.new()
	_entity_option.custom_minimum_size.x = 150
	_entity_option.item_selected.connect(func(_i: int): _refresh_list())
	filter_row.add_child(_entity_option)
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_row.add_child(spring)
	_save_store_btn = Button.new()
	_save_store_btn.text = "保存"
	_save_store_btn.tooltip_text = "显式保存事实库到本地文件（平时的增删改也会自动保存）"
	_save_store_btn.pressed.connect(func(): _narration.cmd_save_canon.emit())
	filter_row.add_child(_save_store_btn)
	_reset_btn = Button.new()
	_reset_btn.text = "重置"
	_reset_btn.tooltip_text = "把事实库恢复为作者正典（settings/canon.json），清除全部探索产生的事实"
	_reset_btn.pressed.connect(func(): _reset_confirm.popup_centered())
	filter_row.add_child(_reset_btn)
	_reset_confirm = ConfirmationDialog.new()
	_reset_confirm.dialog_text = "确认把事实库重置为作者正典？\n探索中产生的事实与取代记录将被清除，人物信念不受影响。"
	_reset_confirm.ok_button_text = "重置"
	_reset_confirm.confirmed.connect(func(): _narration.cmd_reset_canon.emit())
	add_child(_reset_confirm)
	_add_btn = Button.new()
	_add_btn.text = "新增事实"
	_add_btn.pressed.connect(_enter_add_mode)
	filter_row.add_child(_add_btn)
	add_child(filter_row)

	# —— 列表 ——
	_list_scroll = ScrollContainer.new()
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 4)
	_list_scroll.add_child(_list_box)
	add_child(_list_scroll)
	_count_label = _caption("")
	add_child(_count_label)

	# —— 编辑区（默认收起） ——
	_editor = VBoxContainer.new()
	_editor.visible = false
	_editor.add_theme_constant_override("separation", 6)
	_editor_title = Label.new()
	_editor_title.add_theme_color_override("font_color", COLOR_GOLD)
	_editor.add_child(_editor_title)
	_content_edit = TextEdit.new()
	_content_edit.custom_minimum_size = Vector2(0, 76)
	_content_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_content_edit.add_theme_font_size_override("font_size", 14)
	_editor.add_child(_content_edit)
	var attr_row := HBoxContainer.new()
	attr_row.add_theme_constant_override("separation", 8)
	attr_row.add_child(_caption("权重："))
	_weight_option = OptionButton.new()
	_weight_option.add_item("minor 次要")
	_weight_option.add_item("major 重大")
	attr_row.add_child(_weight_option)
	attr_row.add_child(_caption("来源："))
	_source_option = OptionButton.new()
	_source_option.add_item("narrator 旁白")
	_source_option.add_item("player 玩家")
	attr_row.add_child(_source_option)
	var attr_spring := Control.new()
	attr_spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attr_row.add_child(attr_spring)
	_editor.add_child(attr_row)
	_scope_label = _caption("")
	_scope_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_editor.add_child(_scope_label)
	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	_save_btn = Button.new()
	_save_btn.pressed.connect(_on_save_pressed)
	button_row.add_child(_save_btn)
	_delete_btn = Button.new()
	_delete_btn.text = "删除"
	_delete_btn.pressed.connect(_on_delete_pressed)
	button_row.add_child(_delete_btn)
	_cancel_btn = Button.new()
	_cancel_btn.text = "取消"
	_cancel_btn.pressed.connect(_close_editor)
	button_row.add_child(_cancel_btn)
	_editor.add_child(button_row)
	add_child(_editor)

	_refresh_entity_options()


static func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", COLOR_SYSTEM)
	label.add_theme_font_size_override("font_size", 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# ============================================================
#  数据到达 / 筛选
# ============================================================


## 世界事实快照到达（启动/变更/查询）：刷新列表（保留当前选中与筛选）。
func _on_canon_listed(entries: Array) -> void:
	_entries = entries
	_refresh_list()


## 事实库已保存：在计数行显示绝对路径（下一次刷新会覆盖）。
func _on_canon_saved(path: String) -> void:
	_count_label.text = "已保存到本地文件：" + path


## 事实库已重置为作者正典：计数行显示条数（下一次刷新会覆盖）。
func _on_canon_reset(count: int) -> void:
	_count_label.text = "事实库已重置为作者正典（%d 条）" % count


## 当前类别（CATEGORIES 项）。
func _category() -> Dictionary:
	var index := clampi(_category_option.selected, 0, CATEGORIES.size() - 1)
	return CATEGORIES[index]


## 当前实体筛选 id（空串 = 全部；全局类别恒为空）。
func _entity_filter() -> String:
	if _entity_option.selected <= 0 or _entity_option.selected >= _entity_option.item_count:
		return ""
	return str(_entity_option.get_item_metadata(_entity_option.selected))


## 类别或实体选项变化：重建实体下拉（保持类别切换时的可选项正确）并刷新列表。
func _on_filter_changed() -> void:
	_refresh_entity_options()
	_refresh_list()


## 填充实体筛选下拉（按当前类别类型；全局禁用）。
func _refresh_entity_options() -> void:
	_entity_option.clear()
	var type := int(_category()["type"])
	if type < 0:
		_entity_option.add_item("（全局）")
		_entity_option.selected = 0
		_entity_option.disabled = true
		return
	_entity_option.disabled = false
	_entity_option.add_item("全部")
	var entities := EntityRegistry.entities_of_type(type)
	entities.sort_custom(func(a, b): return a.canonical_name < b.canonical_name)
	for e in entities:
		_entity_option.add_item(e.canonical_name)
		_entity_option.set_item_metadata(_entity_option.item_count - 1, e.entity_id)
	_entity_option.selected = 0


## 当前筛选下的条目（active 在前，superseded 灰显示在后）。
func _filtered_entries() -> Array:
	var type := int(_category()["type"])
	var entity_id := _entity_filter()
	var active: Array = []
	var superseded: Array = []
	for raw in _entries:
		var fact := raw as CanonFact
		var hit := false
		if type < 0:
			hit = fact.scope.is_empty()
		else:
			# 作用域类别：条目挂在选定类型（及选定实体）名下
			for scope_id in fact.scope:
				var scope_entity := EntityRegistry.entry(scope_id)
				if scope_entity != null and scope_entity.type == type \
						and (entity_id.is_empty() or scope_id == entity_id):
					hit = true
					break
		if not hit:
			continue
		if fact.status == CanonFact.FactStatus.SUPERSEDED:
			superseded.append(fact)
		else:
			active.append(fact)
	return active + superseded


## 重建列表；选中条目若仍存在则保持编辑区，否则收起。
func _refresh_list() -> void:
	for child in _list_box.get_children():
		child.queue_free()
	var shown := _filtered_entries()
	var active_count := 0
	for raw in shown:
		var fact := raw as CanonFact
		if fact.status != CanonFact.FactStatus.SUPERSEDED:
			active_count += 1
		_list_box.add_child(_build_row(fact))
	var cat_label := str(_category()["label"])
	var scope_text := "全部" if _entity_filter().is_empty() else EntityRegistry.display_name(_entity_filter())
	_count_label.text = "%s事实库 · %s：现行 %d 条（含被取代 %d 条）" % [
		cat_label, scope_text, active_count, shown.size() - active_count]
	if _selected_id != 0 and not _add_mode:
		var found := false
		for raw in shown:
			if (raw as CanonFact).id == _selected_id:
				found = true
				break
		if not found:
			_close_editor()


## 构建一行事实按钮（截断展示；完整内容在编辑区）。
func _build_row(fact: CanonFact) -> Button:
	var btn := Button.new()
	var content := fact.content
	var preview := content.substr(0, mini(content.length(), LIST_ROW_MAX))
	if content.length() > LIST_ROW_MAX:
		preview += "…"
	var status := ""
	if fact.status == CanonFact.FactStatus.SUPERSEDED:
		status = "〔已被 [%d] 取代〕" % fact.superseded_by
		btn.modulate = COLOR_MUTED
	btn.text = "[%d]（%s · %s · %s）%s %s" % [
		fact.id, CanonFact.source_to_key(fact.source), CanonFact.weight_to_key(fact.weight),
		_scope_names(fact), preview, status,
	]
	btn.tooltip_text = content
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var id := fact.id
	btn.pressed.connect(func(): _select(id))
	if id == _selected_id and not _add_mode:
		btn.modulate = COLOR_GOLD
	return btn


## 条目的作用域显示名（全局 = "全局"；类型经注册表反查）。
static func _scope_names(fact: CanonFact) -> String:
	var tags: Array[String] = []
	for scope_id in fact.scope:
		var entity := EntityRegistry.entry(scope_id)
		if entity != null:
			tags.append("%s·%s" % [
				str(TYPE_LABELS.get(entity.type, Entity.type_to_key(entity.type))), entity.canonical_name])
		else:
			tags.append("未知·%s" % scope_id)
	if tags.is_empty():
		return "全局"
	return "、".join(tags)


# ============================================================
#  编辑区（选中编辑 / 新增）
# ============================================================


## 选中一条事实进入编辑模式。
func _select(id: int) -> void:
	_add_mode = false
	_selected_id = id
	var fact := _entry_of(id)
	if fact == null:
		_close_editor()
		return
	_editor.visible = true
	_editor_title.text = "修改事实 [%d]" % id
	_content_edit.text = fact.content
	_weight_option.selected = maxi(0, WEIGHTS.find(CanonFact.weight_to_key(fact.weight)))
	_source_option.visible = false
	var superseded_note := " · 状态：已被取代（修改不改变其被取代地位）" \
		if fact.status == CanonFact.FactStatus.SUPERSEDED else ""
	_scope_label.text = "作用域：%s · 来源：%s%s" % [
		_scope_names(fact), CanonFact.source_to_key(fact.source), superseded_note]
	_save_btn.text = "保存修改"
	_delete_btn.visible = true
	_refresh_list()


## 进入新增模式：作用域由当前类别+实体筛选决定（全局类别 = 全局）。
func _enter_add_mode() -> void:
	_add_mode = true
	_selected_id = 0
	_editor.visible = true
	_editor_title.text = "新增事实"
	_content_edit.text = ""
	_weight_option.selected = 0
	_source_option.visible = true
	_source_option.selected = 0
	var type := int(_category()["type"])
	var scope_text := "全局（无作用域）"
	if type >= 0:
		var entity_id := _entity_filter()
		if entity_id.is_empty():
			# 未选具体实体：提示先选（保存时也会拦）
			scope_text = "请先在上方筛选中选择一个具体%s" % str(TYPE_LABELS.get(type, str(type)))
		else:
			scope_text = "%s · %s" % [str(TYPE_LABELS.get(type, str(type))), EntityRegistry.display_name(entity_id)]
	_scope_label.text = "作用域：" + scope_text
	_save_btn.text = "确认新增"
	_delete_btn.visible = false
	_refresh_list()


## 保存（编辑模式 = 修改；新增模式 = 新增）。命令发往控制器，结果经 canon_listed 回流。
func _on_save_pressed() -> void:
	var content := _content_edit.text.strip_edges()
	if content.is_empty():
		return
	var weight: String = WEIGHTS[clampi(_weight_option.selected, 0, WEIGHTS.size() - 1)]
	if _add_mode:
		var type := int(_category()["type"])
		var entity_id := _entity_filter()
		if type >= 0 and entity_id.is_empty():
			return  # 作用域类别必须选定具体实体
		_narration.cmd_add_fact.emit({
			"content": content,
			"weight": weight,
			"source": SOURCES[clampi(_source_option.selected, 0, SOURCES.size() - 1)],
			"scope_id": entity_id,
		})
	else:
		_narration.cmd_edit_fact.emit({"id": _selected_id, "content": content, "weight": weight})
	_close_editor()


## 删除当前选中事实（不可恢复——正典"只追加"的唯一例外入口）。
func _on_delete_pressed() -> void:
	if _selected_id == 0:
		return
	_narration.cmd_delete_fact.emit(_selected_id)
	_close_editor()


func _close_editor() -> void:
	_add_mode = false
	_selected_id = 0
	_editor.visible = false
	_refresh_list()


func _entry_of(id: int) -> CanonFact:
	for raw in _entries:
		var fact := raw as CanonFact
		if fact.id == id:
			return fact
	return null
