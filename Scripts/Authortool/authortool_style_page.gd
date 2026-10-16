class_name AuthortoolStylePage
extends AuthortoolPage
## AuthorTool 子页：DM 风格四旋钮（编辑写回草稿，导出为 style.json；不改游戏配置）。
## 旋钮定义（键名/选项/说明）的唯一来源是 GameConfig.KNOB_DEFS——本页只负责渲染。


var _draft: AuthortoolDraft
var _options: Array = []  # [{key, options, node}]


func setup(draft: AuthortoolDraft) -> void:
	_draft = draft
	add_theme_constant_override("separation", 12)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(AuthortoolWidgets.caption("DM 风格四旋钮（当前值取自游戏设置；此处编辑只写草稿并随导出为 style.json）"))
	for def in GameConfig.KNOB_DEFS:
		var options: Array = def["options"]
		var option := AuthortoolWidgets.option(options)
		option.item_selected.connect(func(index: int):
			_write(str(def["key"]), str(options[index])))
		add_child(AuthortoolWidgets.field_row(
			"%s（%s）" % [def["label"], def["hint"]], option))
		_options.append({"key": def["key"], "options": options, "node": option})
	apply_draft(draft)


func apply_draft(draft: AuthortoolDraft) -> void:
	_draft = draft
	for knob in _options:
		var options: Array = knob["options"]
		var option := knob["node"] as OptionButton
		option.selected = maxi(0, options.find(str(_draft.style.get(knob["key"], options[0]))))


func _write(key: String, value: String) -> void:
	_draft.style[key] = value
