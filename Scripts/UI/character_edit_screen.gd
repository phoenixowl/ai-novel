extends Control
## 人物编辑屏（Scripts/UI/）：编辑人物的运行时快照——人设、好感度、知识日志、记忆。
## 数据流：进入屏幕时 cmd_get_character 拉详情 → character_loaded 填表；
## 「保存并刷新」组装全量期望状态 → cmd_save_character → character_saved 后重拉详情。
## 「恢复卡面」删单人快照回落作者卡；「写回作者卡面」把快照反向写入 res://（仅开发环境）；
## 「对话」跳转对话屏并自动以该 NPC 开始。
## 知识/记忆行数据存内存数组，任何增删改后整表重建行；保存时按数组整表生效
## （未列出的知识 seq 即删除——与"修改即改快照"的语义一致）。


const TRUST_OPTIONS := ["怀疑", "比较相信", "绝对可信", "已失效"]
const COLOR_MUTED := Color("#8d99ae")
const COLOR_OK := Color("#90be6d")
const COLOR_ERROR := Color("#e76f51")

# —— 样式常量（与人物总览屏同一套暗色圆角风格） ——
const COLOR_TEXT := Color("#ced4da")
const COLOR_ACCENT := Color("#e9c46a")            # 主按钮 / 聚焦描边（金）
const COLOR_FIELD_BG := Color("#1c1d26")          # 输入框底色
const COLOR_FIELD_BORDER := Color("#343648")      # 输入框常态描边
const COLOR_BTN_BG := Color("#262835")            # 次级按钮底色
const COLOR_BTN_BG_HOVER := Color("#2f3142")      # 次级按钮悬停底色
const COLOR_BTN_BORDER := Color("#343648")        # 次级按钮描边
const COLOR_BTN_BORDER_HOVER := Color("#4a4d66")  # 次级按钮悬停描边
const COLOR_PRIMARY_TEXT := Color("#191a21")      # 主按钮文字（金底配深字）

# —— 顶栏 ——
@onready var title_label: Label = %TitleLabel
@onready var status_label: Label = %StatusLabel
# —— 人设区 ——
@onready var name_edit: LineEdit = %NameEdit
@onready var identity_edit: LineEdit = %IdentityEdit
@onready var profile_caption: Label = %ProfileCaption
@onready var profile_edit: TextEdit = %ProfileEdit
# —— NPC 专属区（玩家整段隐藏） ——
@onready var npc_only_box: VBoxContainer = %NpcOnlyBox
@onready var affinity_slider: HSlider = %AffinitySlider
@onready var affinity_value: Label = %AffinityValue
@onready var knowledge_rows: VBoxContainer = %KnowledgeRows
@onready var new_knowledge_edit: LineEdit = %NewKnowledgeEdit
@onready var new_knowledge_source: LineEdit = %NewKnowledgeSource
@onready var new_knowledge_trust: OptionButton = %NewKnowledgeTrust
@onready var add_knowledge_btn: Button = %AddKnowledgeBtn
@onready var memory_rows: VBoxContainer = %MemoryRows
@onready var new_memory_edit: LineEdit = %NewMemoryEdit
@onready var add_memory_btn: Button = %AddMemoryBtn
# —— 底部按钮 ——
@onready var back_btn: Button = %BackBtn
@onready var save_btn: Button = %SaveBtn
@onready var reset_btn: Button = %ResetBtn
@onready var write_back_btn: Button = %WriteBackBtn
@onready var talk_btn: Button = %TalkBtn

# —— 事件集线器 ——
var _characters: CharacterEvents
var _nav: UiEvents

# —— 行数据（保存时整表生效） ——
var _character_id := ""                 # "player" 或人物卡 id
var _kind := "npc"
var _entries: Array[Dictionary] = []    # {seq, content, speaker, trust_view}
var _memories: Array[String] = []       # 记忆文本


## 取全局事件总线；autoload 未就绪时（理论上仅测试环境）手动创建。
func _bus() -> EventBus:
	return EventBus.shared() if EventBus.shared() != null else EventBus.create_shared()


## 初始化：取得集线器、连接事件、填充信任下拉。
func _ready() -> void:
	_characters = _bus().hub(CharacterEvents) as CharacterEvents
	_nav = _bus().hub(UiEvents) as UiEvents
	_characters.character_loaded.connect(_on_character_loaded)
	_characters.character_saved.connect(_on_character_saved)
	_characters.character_action_result.connect(_on_action_result)
	_nav.character_edit_requested.connect(_on_character_edit_requested)
	_nav.navigate_requested.connect(_on_navigate_requested)
	for opt in TRUST_OPTIONS:
		new_knowledge_trust.add_item(opt)
	new_knowledge_trust.selected = 1  # 默认"比较相信"
	_apply_styles()


# ———— 样式（暗色圆角 + 悬停高亮；色值见文件头常量） ————


## 统一放大并美化：输入类加高加描边、按钮分主次、光标手型。
## 仅在 _ready 调一次；tscn 里的字号/间距为静态兜底，动态行在重建时同样套用。
func _apply_styles() -> void:
	for edit: LineEdit in [name_edit, identity_edit, new_knowledge_edit, new_knowledge_source, new_memory_edit]:
		edit.custom_minimum_size.y = maxf(edit.custom_minimum_size.y, 46)
		edit.add_theme_font_size_override("font_size", 16)
		edit.add_theme_stylebox_override("normal", _field_style(false))
		edit.add_theme_stylebox_override("focus", _field_style(true))
		edit.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	profile_edit.custom_minimum_size.y = maxf(profile_edit.custom_minimum_size.y, 150)
	profile_edit.add_theme_font_size_override("font_size", 15)
	profile_edit.add_theme_stylebox_override("normal", _field_style(false))
	profile_edit.add_theme_stylebox_override("focus", _field_style(true))
	for option: OptionButton in [new_knowledge_trust]:
		option.add_theme_font_size_override("font_size", 14)
		option.custom_minimum_size = Vector2(maxf(option.custom_minimum_size.x, 132), 46)
		option.add_theme_stylebox_override("normal", _field_style(false))
		option.add_theme_stylebox_override("hover", _field_style(false))
		option.add_theme_stylebox_override("pressed", _field_style(true))
		option.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_primary_button(save_btn)
	for btn: Button in [back_btn, reset_btn, write_back_btn, talk_btn, add_knowledge_btn, add_memory_btn]:
		_style_secondary_button(btn)
	affinity_slider.custom_minimum_size.y = 32
	affinity_value.add_theme_font_size_override("font_size", 15)
	affinity_value.custom_minimum_size.x = 156


## 输入框样式：暗底圆角，聚焦时描边变金。
func _field_style(focused: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_FIELD_BG
	sb.border_color = COLOR_ACCENT if focused else COLOR_FIELD_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb


## 扁平按钮底样式。
func _flat_style(bg: Color, border: Color, margin_h := 18, margin_v := 11) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	return sb


## 主按钮：金底深字（仅「保存并刷新」）。
func _style_primary_button(btn: Button) -> void:
	btn.custom_minimum_size = Vector2(maxf(btn.custom_minimum_size.x, 170), 48)
	btn.add_theme_font_size_override("font_size", 16)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, COLOR_PRIMARY_TEXT)
	btn.add_theme_stylebox_override("normal", _flat_style(COLOR_ACCENT, COLOR_ACCENT))
	btn.add_theme_stylebox_override("hover", _flat_style(Color("#f2d38b"), Color("#f2d38b")))
	btn.add_theme_stylebox_override("pressed", _flat_style(Color("#d9b258"), Color("#d9b258")))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## 次级按钮：暗底描边，悬停提亮。
func _style_secondary_button(btn: Button, compact := false) -> void:
	if not compact:
		btn.custom_minimum_size.y = maxf(btn.custom_minimum_size.y, 48)
	var margin_h := 12 if compact else 18
	var margin_v := 7 if compact else 11
	btn.add_theme_font_size_override("font_size", 14 if compact else 15)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	btn.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	btn.add_theme_stylebox_override("normal", _flat_style(COLOR_BTN_BG, COLOR_BTN_BORDER, margin_h, margin_v))
	btn.add_theme_stylebox_override("hover", _flat_style(COLOR_BTN_BG_HOVER, COLOR_BTN_BORDER_HOVER, margin_h, margin_v))
	btn.add_theme_stylebox_override("pressed", _flat_style(COLOR_BTN_BG, COLOR_ACCENT, margin_h, margin_v))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## 卡片点击先行到达：暂存待编辑人物（此时编辑屏可能尚未可见）。
## npc_id：人物卡 id 或 "player"。
func _on_character_edit_requested(npc_id: String) -> void:
	_character_id = npc_id


## 进入编辑屏时拉取详情（character_edit_requested 可能早于导航到达）。
## screen：目标屏幕标识（"character_edit" 时处理）。
func _on_navigate_requested(screen: String) -> void:
	if screen == "character_edit" and not _character_id.is_empty():
		_characters.cmd_get_character.emit(_character_id)


## 详情到达：整表填单。
## detail：引擎发布的详情 Dictionary（kind=player/npc）。
func _on_character_loaded(detail: Dictionary) -> void:
	if detail.is_empty():
		_set_status("未找到该人物", COLOR_ERROR)
		return
	_kind = str(detail.get("kind", "npc"))
	title_label.text = "编辑 · %s（%s）" % [detail.get("name", ""), detail.get("id", "")]
	name_edit.text = str(detail.get("name", ""))
	identity_edit.text = str(detail.get("identity", ""))
	profile_caption.text = str(detail.get("profile_label", "人设"))
	profile_edit.text = str(detail.get("profile", ""))
	var is_player := _kind == "player"
	npc_only_box.visible = not is_player
	reset_btn.visible = not is_player
	write_back_btn.visible = not is_player
	talk_btn.visible = not is_player
	if is_player:
		_set_status("", COLOR_MUTED)
		return
	affinity_slider.set_value_no_signal(float(detail.get("affinity", 0)))
	_update_affinity_label()
	_entries.clear()
	for raw in detail.get("knowledge", []):
		var d: Dictionary = (raw as Dictionary).duplicate()
		_entries.append({
			"seq": int(d.get("seq", 0)),
			"content": str(d.get("content", "")),
			"speaker": str(d.get("speaker", "")),
			"trust_view": str(d.get("trust_view", "怀疑")),
		})
	_rebuild_knowledge_rows()
	_memories.clear()
	for raw in detail.get("memories", []):
		_memories.append(str(raw))
	_rebuild_memory_rows()
	_set_status("", COLOR_MUTED)


# ———— 好感度 ————


## 滑杆变化：刷新数值与档位显示。
func _on_affinity_slider_value_changed(_value: float) -> void:
	_update_affinity_label()


func _update_affinity_label() -> void:
	var v := int(affinity_slider.value)
	affinity_value.text = "%d（%s）" % [v, AffinityStore.tier_label(v)]


# ———— 知识行 ————


## 整表重建知识行（增删改后调用）。
func _rebuild_knowledge_rows() -> void:
	for child in knowledge_rows.get_children():
		child.queue_free()  # 可能正处于被删按钮自身的 pressed 信号内，不能立即 free
	for i in _entries.size():
		knowledge_rows.add_child(_build_knowledge_row(i))


## 构建一行知识条目：内容（截断显示）+ 信任下拉 + 删除。
func _build_knowledge_row(index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var e := _entries[index]
	var content := Label.new()
	content.text = "[%d]（%s）%s" % [int(e.get("seq", 0)), str(e.get("speaker", "")), str(e.get("content", ""))]
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.max_lines_visible = 2
	content.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_font_size_override("font_size", 15)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(content)

	var trust := OptionButton.new()
	for opt in TRUST_OPTIONS:
		trust.add_item(opt)
	trust.selected = maxi(0, TRUST_OPTIONS.find(str(e.get("trust_view", "怀疑"))))
	trust.custom_minimum_size = Vector2(132, 40)
	trust.add_theme_font_size_override("font_size", 14)
	trust.add_theme_stylebox_override("normal", _field_style(false))
	trust.add_theme_stylebox_override("hover", _field_style(false))
	trust.add_theme_stylebox_override("pressed", _field_style(true))
	trust.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	trust.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	trust.item_selected.connect(func(idx: int): _entries[index]["trust_view"] = TRUST_OPTIONS[idx])
	row.add_child(trust)

	var del := Button.new()
	del.text = "删"
	del.tooltip_text = "删除此条（保存后生效）"
	del.custom_minimum_size = Vector2(48, 40)
	del.pressed.connect(func(): _remove_entry(index))
	_style_secondary_button(del, true)
	row.add_child(del)
	return row


## 删除一条知识（内存表；保存后写快照）。
func _remove_entry(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	_entries.remove_at(index)
	_rebuild_knowledge_rows()


## 「添加」知识：来源留空按"手动"处理。
func _on_add_knowledge_pressed() -> void:
	var content := new_knowledge_edit.text.strip_edges()
	if content.is_empty():
		return
	_entries.append({
		"seq": 0,
		"content": content,
		"speaker": new_knowledge_source.text.strip_edges(),
		"trust_view": TRUST_OPTIONS[clampi(new_knowledge_trust.selected, 0, TRUST_OPTIONS.size() - 1)],
	})
	new_knowledge_edit.clear()
	new_knowledge_source.clear()
	_rebuild_knowledge_rows()


# ———— 记忆行 ————


## 整表重建记忆行（增删后调用）。
func _rebuild_memory_rows() -> void:
	for child in memory_rows.get_children():
		child.queue_free()  # 可能正处于被删按钮自身的 pressed 信号内，不能立即 free
	for i in _memories.size():
		memory_rows.add_child(_build_memory_row(i))


## 构建一行记忆：文本（截断显示）+ 删除。
func _build_memory_row(index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var content := Label.new()
	content.text = _memories[index]
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.max_lines_visible = 2
	content.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_font_size_override("font_size", 15)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(content)
	var del := Button.new()
	del.text = "删"
	del.tooltip_text = "删除此条（保存后生效）"
	del.custom_minimum_size = Vector2(48, 40)
	del.pressed.connect(func():
		_memories.remove_at(index)
		_rebuild_memory_rows())
	_style_secondary_button(del, true)
	row.add_child(del)
	return row


## 「添加记忆」。
func _on_add_memory_pressed() -> void:
	var text := new_memory_edit.text.strip_edges()
	if text.is_empty():
		return
	_memories.append(text)
	new_memory_edit.clear()
	_rebuild_memory_rows()


# ———— 底部按钮 ————


## 「保存并刷新」：组装全量期望状态发往引擎（NPC 含好感度/知识/记忆；玩家仅人设）。
func _on_save_pressed() -> void:
	var payload := {
		"id": _character_id,
		"kind": _kind,
		"name": name_edit.text.strip_edges(),
		"identity": identity_edit.text.strip_edges(),
		"profile": profile_edit.text.strip_edges(),
	}
	if _kind != "player":
		var knowledge: Array = []
		for e in _entries:
			var content := str(e.get("content", "")).strip_edges()
			if content.is_empty():
				continue
			knowledge.append({
				"seq": int(e.get("seq", 0)),
				"content": content,
				"speaker": str(e.get("speaker", "")),
				"trust": str(e.get("trust_view", "怀疑")),
			})
		payload["affinity"] = int(affinity_slider.value)
		payload["knowledge"] = knowledge
		payload["memories"] = _memories
	_set_status("保存中…", COLOR_MUTED)
	_characters.cmd_save_character.emit(payload)


## 保存完成：重拉详情（引擎侧真值回填表单）。
func _on_character_saved(id: String) -> void:
	if id != _character_id:
		return
	_set_status("已保存并刷新", COLOR_OK)
	_characters.cmd_get_character.emit(_character_id)


## 「恢复卡面」：删除该 NPC 的运行时快照（好感度保留），引擎回发新详情刷新表单。
func _on_reset_pressed() -> void:
	_characters.cmd_reset_character.emit(_character_id)


## 「写回作者卡面」：把当前快照反向写入 res://（仅 Godot 编辑器环境可行）。
func _on_write_back_pressed() -> void:
	_characters.cmd_write_back_character.emit(_character_id)


## 「对话」：跳转世界屏并直接与该 NPC 开始交谈（统一入口；场景为当前位置）。
func _on_talk_pressed() -> void:
	_nav.navigate_requested.emit("narration")
	_nav.dialogue_requested.emit(_character_id)


## 「← 返回」：回人物总览。
func _on_back_pressed() -> void:
	_nav.navigate_requested.emit("characters")


## 引擎操作结果（写回/恢复卡面）：状态行染色显示。
func _on_action_result(id: String, ok: bool, message: String) -> void:
	if not id.is_empty() and id != _character_id:
		return
	_set_status(message, COLOR_OK if ok else COLOR_ERROR)


func _set_status(text: String, color: Color) -> void:
	status_label.add_theme_color_override("font_color", color)
	status_label.text = text
