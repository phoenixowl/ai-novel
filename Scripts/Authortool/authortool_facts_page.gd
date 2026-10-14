class_name AuthortoolFactsPage
extends AuthortoolListPage
## AuthorTool 子页：事实库编辑——草稿装载自运行时正典（作者播种 + 运行期确立），
## 供作者把"实际成为正典的世界"整理成作者数据；被取代条目灰显，导出仅含现行条目。

const COLOR_SUPERSEDED := Color("#6c757d")
const WEIGHTS := ["minor", "major"]
const SOURCES := ["narrator", "player"]

var _content_edit: TextEdit
var _weight_option: OptionButton
var _source_option: OptionButton
var _scope_edit: LineEdit


func _page_hint() -> String:
	return "事实库（草稿取自运行时正典；导出为 canon.json，仅含现行条目——作者正典播种格式）"


func _cards() -> Array:
	return draft.facts


func _card_label(card: Dictionary) -> String:
	var tag := str(card.get("id", 0))
	if int(card.get("id", 0)) == 0:
		tag = "新增"
	var scope: Array = card.get("scope", [])
	var scope_text := "全局" if scope.is_empty() else "、".join(scope)
	return "[%s]（%s · %s）%s" % [tag, card.get("weight", "minor"), scope_text,
		str(card.get("content", "")).substr(0, 30)]


## 被取代条目列表行灰显。
func refresh_list() -> void:
	super.refresh_list()
	for i in _list.item_count:
		if i < _cards().size() and str((_cards()[i] as Dictionary).get("status", "")) == "superseded":
			_list.set_item_custom_fg_color(i, COLOR_SUPERSEDED)


func _new_card() -> Dictionary:
	return {"id": 0, "content": "新事实", "weight": "minor", "source": "narrator",
		"scope": [], "status": "active"}


func _build_form(form: VBoxContainer) -> void:
	form.add_child(AuthortoolWidgets.caption("事实表述", false))
	_content_edit = AuthortoolWidgets.text_edit(90)
	_content_edit.text_changed.connect(func():
		if not _is_filling() and not current.is_empty():
			current["content"] = _content_edit.text
			refresh_list())
	form.add_child(_content_edit)
	_weight_option = AuthortoolWidgets.option(WEIGHTS)
	_weight_option.item_selected.connect(func(index: int):
		if not _is_filling() and not current.is_empty():
			current["weight"] = WEIGHTS[index]
			refresh_list())
	form.add_child(AuthortoolWidgets.field_row("权重", _weight_option))
	_source_option = AuthortoolWidgets.option(SOURCES)
	_source_option.item_selected.connect(func(index: int):
		if not _is_filling() and not current.is_empty():
			current["source"] = SOURCES[index])
	form.add_child(AuthortoolWidgets.field_row("来源", _source_option))
	_scope_edit = AuthortoolWidgets.line_edit("作用域实体 id，逗号分隔（空 = 全局）")
	_scope_edit.text_changed.connect(func(t: String):
		if not _is_filling() and not current.is_empty():
			current["scope"] = AuthortoolWidgets.split_csv(t)
			refresh_list())
	form.add_child(AuthortoolWidgets.field_row("作用域", _scope_edit))
	form.add_child(AuthortoolWidgets.caption("status 为运行时状态（active/superseded）：被取代条目仅作参考，导出时自动排除。"))


func _fill_form(card: Dictionary) -> void:
	_content_edit.text = str(card.get("content", ""))
	_weight_option.selected = maxi(0, WEIGHTS.find(str(card.get("weight", "minor"))))
	_source_option.selected = maxi(0, SOURCES.find(str(card.get("source", "narrator"))))
	_scope_edit.text = AuthortoolWidgets.join_list(card.get("scope", []))
