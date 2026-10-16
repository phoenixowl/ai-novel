extends Control
## AuthorTool 外壳屏（Scripts/Authortool/）：设定编辑页——左侧子页导航（六页单选），
## 右侧内容区切换；底部「重新载入草稿（确认，丢弃未导出修改）」与「一键导出」。
## 草稿（AuthortoolDraft）是唯一编辑对象：装载自 res://settings + 运行时正典 + 风格旋钮；
## 导出（AuthortoolExporter）是唯一写出动作，落 user://authortool_export/<时间戳>/，
## 不触碰 res://settings 与 user:// 其它目录。与 EventBus 的交互只有导航（UiEvents）。


@onready var status_label: Label = %StatusLabel
@onready var page_nav: VBoxContainer = %PageNav
@onready var content_box: VBoxContainer = %ContentBox

var _draft := AuthortoolDraft.new()
var _pages: Array = []          # [{title, page}]
var _nav_buttons: Array[Button] = []
var _reload_confirm: ConfirmationDialog
var _nav: UiEvents



func _ready() -> void:
	_nav = EventBus.resolve().hub(UiEvents) as UiEvents
	_build_pages()
	_build_reload_confirm()
	_load_draft()


## 六个子页：标题 → 页面类（同一目录，authortool_ 前缀）。
func _build_pages() -> void:
	var defs := [
		{"title": "世界观", "page": AuthortoolWorldPage.new()},
		{"title": "组织", "page": AuthortoolFactionsPage.new()},
		{"title": "人物", "page": AuthortoolCharactersPage.new()},
		{"title": "场景", "page": AuthortoolScenesPage.new()},
		{"title": "事实库", "page": AuthortoolFactsPage.new()},
		{"title": "风格", "page": AuthortoolStylePage.new()},
	]
	var group := ButtonGroup.new()
	for i in defs.size():
		var def: Dictionary = defs[i]
		var page: AuthortoolPage = def["page"]
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page.visible = i == 0
		content_box.add_child(page)
		_pages.append(def)
		var btn := AuthortoolWidgets.button(str(def["title"]), false, false)
		btn.toggle_mode = true
		btn.button_group = group
		btn.set_pressed_no_signal(i == 0)
		btn.toggled.connect(func(pressed: bool):
			if pressed:
				_show_page(page))
		page_nav.add_child(btn)
		_nav_buttons.append(btn)


func _build_reload_confirm() -> void:
	_reload_confirm = ConfirmationDialog.new()
	_reload_confirm.dialog_text = "重新装载将丢弃当前草稿的全部未导出修改。\n（来源：res://settings + 运行时正典 + 风格旋钮）"
	_reload_confirm.ok_button_text = "重新装载"
	_reload_confirm.confirmed.connect(func(): _load_draft())
	add_child(_reload_confirm)


## 装载草稿并分发到各页（首次构建 UI，重载仅刷新；状态行给出加载报告末行）。
func _load_draft() -> void:
	_draft = AuthortoolDraft.new()
	var report := _draft.load_from_project()
	for def in _pages:
		var page: AuthortoolPage = def["page"]
		if not def.get("ready", false):
			page.setup(_draft)
			def["ready"] = true
		else:
			page.apply_draft(_draft)
	_set_status(report.back() if not report.is_empty() else "草稿已装载", AuthortoolWidgets.COLOR_MUTED)


func _show_page(page: AuthortoolPage) -> void:
	for def in _pages:
		(def["page"] as AuthortoolPage).visible = def["page"] == page


func _set_status(text: String, color: Color) -> void:
	status_label.add_theme_color_override("font_color", color)
	status_label.text = text


# ———— 按钮处理（信号已在场景 [connection] 中接线） ————


## 「← 菜单」：请求导航回开始菜单。
func _on_back_pressed() -> void:
	_nav.navigate_requested.emit("menu")


## 「重新载入草稿」：确认后丢弃修改重新装载。
func _on_reload_pressed() -> void:
	_reload_confirm.popup_centered()


## 「一键导出」：草稿写成独立目录的完整作者数据包。
func _on_export_pressed() -> void:
	var outcome: Dictionary = AuthortoolExporter.export_draft(_draft)
	if not bool(outcome.get("ok", false)):
		_set_status("导出失败：" + str(outcome.get("error", "未知错误")), AuthortoolWidgets.COLOR_ERROR)
		return
	_set_status("已导出 %d 个文件 → %s（可整目录复制为 settings/ 使用）" % [
		(outcome.get("files", []) as Array).size(), str(outcome.get("abs_path", "")),
	], AuthortoolWidgets.COLOR_GOLD)
