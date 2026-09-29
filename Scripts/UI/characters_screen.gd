extends Control
## 人物总览屏（Scripts/UI/）：全部人物以网格卡片呈现——玩家卡置顶，每张 NPC 卡
## 显示姓名、身份、人设预览（超长截断省略）与好感度/知识/记忆计数。
## 点击卡片进入编辑页；顶栏「还原设定」删除全部运行时快照回到作者卡面（确认弹窗）。
## 与逻辑层经 EventBus 集线器中转：cmd_get_characters 拉取、characters_listed 接收。


const COLOR_NAME := Color("#e9c46a")     # 卡片姓名色（与 NPC 气泡昵称色一致）
const COLOR_TEXT := Color("#ced4da")     # 卡片正文色
const COLOR_MUTED := Color("#8d99ae")    # 次要信息色
const COLOR_OK := Color("#90be6d")
const COLOR_ERROR := Color("#e76f51")

@onready var grid: GridContainer = %Grid
@onready var status_label: Label = %StatusLabel
@onready var restore_confirm: AcceptDialog = %RestoreConfirm

# —— 事件集线器 ——
var _characters: CharacterEvents
var _nav: UiEvents


## 取全局事件总线；autoload 未就绪时（理论上仅测试环境）手动创建。
func _bus() -> EventBus:
	return EventBus.shared() if EventBus.shared() != null else EventBus.create_shared()


## 初始化：取得集线器、连接事件并拉取人物总览。
func _ready() -> void:
	_characters = _bus().hub(CharacterEvents) as CharacterEvents
	_nav = _bus().hub(UiEvents) as UiEvents
	_characters.characters_listed.connect(_on_characters_listed)
	_characters.character_action_result.connect(_on_action_result)
	_nav.navigate_requested.connect(_on_navigate_requested)
	_characters.cmd_get_characters.emit()


## 每次进入本屏都重新拉取（编辑保存后返回时是最新数据）。
## screen：目标屏幕标识（"characters" 时处理）。
func _on_navigate_requested(screen: String) -> void:
	if screen == "characters":
		status_label.text = ""
		_characters.cmd_get_characters.emit()


## 人物总览数据到达：整表重建卡片墙。
## items：Array[Dictionary]（首项为玩家）。
func _on_characters_listed(items: Array) -> void:
	for child in grid.get_children():
		child.free()
	for raw in items:
		grid.add_child(_build_card(raw as Dictionary))


## 构建一张人物卡片（Button + 内嵌信息列；点击进入编辑页）。
## item：总览数据 {kind, id, name, identity, profile, affinity, affinity_label, knowledge_count, memory_count}。
func _build_card(item: Dictionary) -> Button:
	var is_player := str(item.get("kind", "")) == "player"
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 168)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var id := str(item.get("id", ""))
	card.pressed.connect(func():
		_nav.character_edit_requested.emit(id)
		_nav.navigate_requested.emit("character_edit")
	)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 12
	box.offset_top = 10
	box.offset_right = -12
	box.offset_bottom = -10
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	var name_label := Label.new()
	name_label.text = "▶ 你（玩家）" if is_player else str(item.get("name", ""))
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", COLOR_NAME)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	var identity := str(item.get("identity", ""))
	if not identity.is_empty():
		var identity_label := Label.new()
		identity_label.text = identity
		identity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		identity_label.max_lines_visible = 2
		identity_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		identity_label.add_theme_font_size_override("font_size", 13)
		identity_label.add_theme_color_override("font_color", COLOR_TEXT)
		identity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(identity_label)

	var profile := str(item.get("profile", ""))
	if not profile.is_empty():
		var profile_label := Label.new()
		profile_label.text = profile
		profile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		profile_label.max_lines_visible = 3
		profile_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		profile_label.add_theme_font_size_override("font_size", 12)
		profile_label.add_theme_color_override("font_color", COLOR_MUTED)
		profile_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(profile_label)

	var spring := Control.new()
	spring.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spring)

	var foot := Label.new()
	if is_player:
		foot.text = "点击编辑你的身份与外观"
	else:
		foot.text = "好感度 %d（%s）· 知识 %d 条 · 记忆 %d 条" % [
			int(item.get("affinity", 0)), str(item.get("affinity_label", "")),
			int(item.get("knowledge_count", 0)), int(item.get("memory_count", 0)),
		]
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", COLOR_MUTED)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(foot)
	return card


## 「还原设定」：弹确认框。
func _on_restore_pressed() -> void:
	restore_confirm.popup_centered()


## 确认还原：删除全部人物运行时快照（好感度与对话日志保留），控制器广播后本屏重拉。
func _on_restore_confirmed() -> void:
	_characters.cmd_restore_lore.emit()


## 引擎操作结果（还原等）：状态行染色显示。
func _on_action_result(_id: String, ok: bool, message: String) -> void:
	status_label.add_theme_color_override("font_color", COLOR_OK if ok else COLOR_ERROR)
	status_label.text = message


## 「← 菜单」：请求导航回开始菜单。
func _on_back_pressed() -> void:
	_nav.navigate_requested.emit("menu")
