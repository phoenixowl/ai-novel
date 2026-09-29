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
@onready var memory_rows: VBoxContainer = %MemoryRows
@onready var new_memory_edit: LineEdit = %NewMemoryEdit
# —— 底部按钮 ——
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
		child.free()
	for i in _entries.size():
		knowledge_rows.add_child(_build_knowledge_row(i))


## 构建一行知识条目：内容（截断显示）+ 信任下拉 + 删除。
func _build_knowledge_row(index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var e := _entries[index]
	var content := Label.new()
	content.text = "[%d]（%s）%s" % [int(e.get("seq", 0)), str(e.get("speaker", "")), str(e.get("content", ""))]
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.max_lines_visible = 2
	content.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_font_size_override("font_size", 13)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(content)

	var trust := OptionButton.new()
	for opt in TRUST_OPTIONS:
		trust.add_item(opt)
	trust.selected = maxi(0, TRUST_OPTIONS.find(str(e.get("trust_view", "怀疑"))))
	trust.custom_minimum_size = Vector2(110, 0)
	trust.item_selected.connect(func(idx: int): _entries[index]["trust_view"] = TRUST_OPTIONS[idx])
	row.add_child(trust)

	var del := Button.new()
	del.text = "删"
	del.tooltip_text = "删除此条（保存后生效）"
	del.pressed.connect(func(): _remove_entry(index))
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
		child.free()
	for i in _memories.size():
		memory_rows.add_child(_build_memory_row(i))


## 构建一行记忆：文本（截断显示）+ 删除。
func _build_memory_row(index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var content := Label.new()
	content.text = _memories[index]
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.max_lines_visible = 2
	content.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_font_size_override("font_size", 13)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(content)
	var del := Button.new()
	del.text = "删"
	del.tooltip_text = "删除此条（保存后生效）"
	del.pressed.connect(func():
		_memories.remove_at(index)
		_rebuild_memory_rows())
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


## 「对话」：跳转对话屏并自动以该 NPC 开始（场景用对话屏当前默认值）。
func _on_talk_pressed() -> void:
	_nav.navigate_requested.emit("dialogue")
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
