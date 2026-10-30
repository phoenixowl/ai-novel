class_name PlayerStateWindow
extends PanelContainer
## 玩家状态悬浮窗（UI 层）：可拖动（标题栏）、可展开/收起（收起时只显示计数器一行，
## 展开显示各条目集明细）。内容按状态模板渲染（PlayerStateSchema 提供 label，
## PlayerStateStore 提供数值）——引擎不含世界观词汇。数据经 DMEvents.player_state_changed
## 实时刷新；标题栏提供"清空"入口（二次确认，走 PlayerStateStore.reset_all）。


const COLOR_TITLE := Color("#e9c46a")
const COLOR_TEXT := Color("#ced4da")
const COLOR_MUTED := Color("#8d99ae")
const COLOR_VALUE := Color("#90be6d")

var _title_bar: Control
var _counters_row: HFlowContainer
var _lists_box: VBoxContainer
var _toggle_btn: Button
var _clear_dialog: ConfirmationDialog  # 复用的确认框（避免多次点击堆积节点）
var _expanded := false
var _dragging := false


func _init() -> void:
	custom_minimum_size = Vector2(300, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.10, 0.13, 0.96)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.23, 0.23, 0.29)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", sb)


func _ready() -> void:
	_build()
	_refresh(PlayerStateStore.snapshot())
	var dm := EventBus.resolve().hub(DMEvents) as DMEvents
	dm.player_state_changed.connect(_refresh)


func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	# 标题栏（拖动把手）：标题 + 展开按钮 + 清空按钮
	_title_bar = HBoxContainer.new()
	_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_bar.custom_minimum_size = Vector2(0, 24)
	_title_bar.gui_input.connect(_on_title_gui)
	box.add_child(_title_bar)
	var title := Label.new()
	title.text = "玩家状态"
	title.add_theme_color_override("font_color", COLOR_TITLE)
	title.add_theme_font_size_override("font_size", 15)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_bar.add_child(title)
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_bar.add_child(spring)
	_toggle_btn = Button.new()
	_toggle_btn.text = "展开"
	_toggle_btn.flat = true
	_toggle_btn.pressed.connect(_on_toggle)
	_title_bar.add_child(_toggle_btn)
	var clear_btn := Button.new()
	clear_btn.text = "清空"
	clear_btn.flat = true
	clear_btn.pressed.connect(_on_clear_pressed)
	_title_bar.add_child(clear_btn)
	# 计数器行（收起时也显示）
	_counters_row = HFlowContainer.new()
	_counters_row.add_theme_constant_override("h_separation", 14)
	_counters_row.add_theme_constant_override("v_separation", 2)
	box.add_child(_counters_row)
	# 条目集明细（展开时显示）
	_lists_box = VBoxContainer.new()
	_lists_box.visible = false
	_lists_box.add_theme_constant_override("separation", 6)
	box.add_child(_lists_box)


## 用快照刷新渲染（DMEvents.player_state_changed 直达；也可外部手动调用）。
func _refresh(state: Dictionary) -> void:
	for child in _counters_row.get_children():
		child.queue_free()
	for child in _lists_box.get_children():
		child.queue_free()
	var counters: Dictionary = state.get("counters", {})
	var collections: Dictionary = state.get("collections", {})
	for c in PlayerStateSchema.counters():
		var key := str(c.get("key", ""))
		var label := Label.new()
		label.text = "%s %d" % [str(c.get("label", key)), int(counters.get(key, c.get("initial", 0)))]
		label.add_theme_color_override("font_color", COLOR_VALUE)
		label.add_theme_font_size_override("font_size", 14)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_counters_row.add_child(label)
	for col in PlayerStateSchema.collections():
		var key := str(col.get("key", ""))
		var entries: Array = collections.get(key, [])
		var head := Label.new()
		head.text = "%s（%d/%d）" % [str(col.get("label", key)), entries.size(), int(col.get("cap", 20))]
		head.add_theme_color_override("font_color", COLOR_MUTED)
		head.add_theme_font_size_override("font_size", 13)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lists_box.add_child(head)
		if entries.is_empty():
			var empty := Label.new()
			empty.text = "（空）"
			empty.add_theme_color_override("font_color", COLOR_MUTED)
			empty.add_theme_font_size_override("font_size", 12)
			empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_lists_box.add_child(empty)
		for e in entries:
			var line := Label.new()
			line.text = PlayerStateSchema.entry_text(key, e as Dictionary)
			line.add_theme_color_override("font_color", COLOR_TEXT)
			line.add_theme_font_size_override("font_size", 13)
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_lists_box.add_child(line)


func _on_toggle() -> void:
	_set_expanded(not _expanded)


## 展开/收起（测试也直接调用）。
func _set_expanded(value: bool) -> void:
	_expanded = value
	_toggle_btn.text = "收起" if value else "展开"
	_lists_box.visible = value


func _on_clear_pressed() -> void:
	if _clear_dialog == null:
		_clear_dialog = ConfirmationDialog.new()
		_clear_dialog.dialog_text = "清空全部玩家状态（晶石/物品/状态/之约/线索）？\n此操作不影响世界正典与人物设定。"
		_clear_dialog.ok_button_text = "清空"
		_clear_dialog.confirmed.connect(func() -> void:
			PlayerStateStore.reset_all()
			_refresh(PlayerStateStore.snapshot())
			(EventBus.resolve().hub(DMEvents) as DMEvents).player_state_changed.emit(PlayerStateStore.snapshot()))
		add_child(_clear_dialog)
	_clear_dialog.popup_centered()


## 标题栏拖动：按住左键移动窗口；位置钳制在屏幕内。
func _on_title_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_drag_move(event.relative)
		accept_event()


## 按相对位移移动窗口并钳制在父容器内（测试也直接调用验证钳制）。
func _drag_move(relative: Vector2) -> void:
	var parent_rect := Rect2(Vector2.ZERO, get_parent_control().size) if get_parent_control() != null else Rect2()
	var target := position + relative
	var lo := parent_rect.position
	var hi := parent_rect.end - size
	if hi.x < lo.x:
		hi.x = lo.x
	if hi.y < lo.y:
		hi.y = lo.y
	position = Vector2(clampf(target.x, lo.x, hi.x), clampf(target.y, lo.y, hi.y))
