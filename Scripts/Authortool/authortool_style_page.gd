class_name AuthortoolStylePage
extends VBoxContainer
## AuthorTool 子页：DM 风格四旋钮（编辑写回草稿，导出为 style.json；不改游戏配置）。


## 旋钮定义：键（草稿 style / GameConfig 的字段名）→ [选项表, 标签, 说明]
const KNOBS := [
	{"key": "adoption", "options": ["宽松", "严格"], "label": "采纳度",
		"hint": "玩家的想象力（想找什么、假设什么）被旁白接住的方式"},
	{"key": "verdict", "options": ["宽松", "严格"], "label": "裁决倾向",
		"hint": "行动成败的宽严：宽松多成功，严格常有失败与代价"},
	{"key": "density", "options": ["简练", "浓墨"], "label": "描写密度",
		"hint": "旁白叙述的详略"},
	{"key": "threshold", "options": ["宽松", "严格"], "label": "正典门槛",
		"hint": "次要新事实是否写入世界事实库（严格=只有大事实入库）"},
]

var _draft: AuthortoolDraft
var _options: Array = []  # [{key, options, node}]


func setup(draft: AuthortoolDraft) -> void:
	_draft = draft
	add_theme_constant_override("separation", 12)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(AuthortoolWidgets.caption("DM 风格四旋钮（当前值取自游戏设置；此处编辑只写草稿并随导出为 style.json）"))
	for def in KNOBS:
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
