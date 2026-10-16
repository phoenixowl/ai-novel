class_name AuthortoolWorldPage
extends AuthortoolPage
## AuthorTool 子页：世界观与主线基调（两段全文编辑，改动即时写回草稿）。


var _draft: AuthortoolDraft
var _world_edit: TextEdit
var _mainline_edit: TextEdit
var _filling := false


func setup(draft: AuthortoolDraft) -> void:
	_draft = draft
	add_theme_constant_override("separation", 10)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(AuthortoolWidgets.caption("世界观与主线基调（全文注入提示词静态层；导出为 worldview.txt / mainline.txt）"))
	add_child(AuthortoolWidgets.caption("世界观", false))
	_world_edit = AuthortoolWidgets.text_edit(300)
	_world_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_world_edit.text_changed.connect(_on_world_changed)
	add_child(_world_edit)
	add_child(AuthortoolWidgets.caption("主线基调（可为空；世界张力的方向感）", false))
	_mainline_edit = AuthortoolWidgets.text_edit(140)
	_mainline_edit.text_changed.connect(_on_mainline_changed)
	add_child(_mainline_edit)
	apply_draft(draft)


func apply_draft(draft: AuthortoolDraft) -> void:
	_draft = draft
	_fill()


func _fill() -> void:
	_filling = true
	_world_edit.text = _draft.worldview
	_mainline_edit.text = _draft.mainline
	_filling = false


func _on_world_changed() -> void:
	if not _filling:
		_draft.worldview = _world_edit.text


func _on_mainline_changed() -> void:
	if not _filling:
		_draft.mainline = _mainline_edit.text
