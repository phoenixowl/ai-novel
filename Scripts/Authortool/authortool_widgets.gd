class_name AuthortoolWidgets
extends RefCounted
## AuthorTool 共享控件构建器（Scripts/Authortool/）：六个子页面复用的暗色样式控件。
## 色板与 character_edit_screen 同源（金主按钮 / 暗底描边 / 灰说明文字），保证观感一致。

const COLOR_TEXT := Color("#ced4da")
const COLOR_MUTED := Color("#8d99ae")
const COLOR_GOLD := Color("#e9c46a")
const COLOR_ERROR := Color("#e76f51")
const COLOR_FIELD_BG := Color("#1c1d26")
const COLOR_FIELD_BORDER := Color("#343648")
const COLOR_BTN_BG := Color("#262835")
const COLOR_BTN_BG_HOVER := Color("#2f3142")
const COLOR_BTN_BORDER := Color("#343648")
const COLOR_BTN_BORDER_HOVER := Color("#4a4d66")
const COLOR_PRIMARY_TEXT := Color("#191a21")


## 灰色说明/标签文字。
static func caption(text: String, muted := true) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", COLOR_MUTED if muted else COLOR_TEXT)
	label.add_theme_font_size_override("font_size", 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## 单行输入框（暗底描边，聚焦描边变金）。
static func line_edit(placeholder := "", min_height := 40) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size.y = min_height
	edit.add_theme_font_size_override("font_size", 15)
	edit.add_theme_stylebox_override("normal", _field_style(false))
	edit.add_theme_stylebox_override("focus", _field_style(true))
	edit.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	return edit


## 多行文本域。
static func text_edit(min_height := 90) -> TextEdit:
	var edit := TextEdit.new()
	edit.custom_minimum_size.y = min_height
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.add_theme_font_size_override("font_size", 14)
	edit.add_theme_stylebox_override("normal", _field_style(false))
	edit.add_theme_stylebox_override("focus", _field_style(true))
	edit.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	return edit


## 下拉选择。
static func option(options: Array, selected := 0) -> OptionButton:
	var btn := OptionButton.new()
	for opt in options:
		btn.add_item(str(opt))
	btn.selected = clampi(selected, 0, options.size() - 1)
	btn.custom_minimum_size = Vector2(132, 40)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_stylebox_override("normal", _field_style(false))
	btn.add_theme_stylebox_override("hover", _field_style(false))
	btn.add_theme_stylebox_override("pressed", _field_style(true))
	btn.add_theme_stylebox_override("focus", _field_style(true))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return btn


## 按钮：primary=true 为金底主按钮（导出等），否则暗底次级按钮。
static func button(text: String, primary := false, compact := false) -> Button:
	var btn := Button.new()
	btn.text = text
	var margin_h := 12 if compact else 18
	var margin_v := 7 if compact else 11
	btn.custom_minimum_size.y = 40 if compact else 46
	btn.add_theme_font_size_override("font_size", 13 if compact else 15)
	if primary:
		btn.custom_minimum_size.x = 170
		btn.add_theme_font_size_override("font_size", 16)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			btn.add_theme_color_override(state, COLOR_PRIMARY_TEXT)
		btn.add_theme_stylebox_override("normal", _flat_style(COLOR_GOLD, COLOR_GOLD))
		btn.add_theme_stylebox_override("hover", _flat_style(Color("#f2d38b"), Color("#f2d38b")))
		btn.add_theme_stylebox_override("pressed", _flat_style(Color("#d9b258"), Color("#d9b258")))
	else:
		btn.add_theme_color_override("font_color", COLOR_TEXT)
		btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
		btn.add_theme_color_override("font_pressed_color", COLOR_TEXT)
		btn.add_theme_stylebox_override("normal", _flat_style(COLOR_BTN_BG, COLOR_BTN_BORDER, margin_h, margin_v))
		btn.add_theme_stylebox_override("hover", _flat_style(COLOR_BTN_BG_HOVER, COLOR_BTN_BORDER_HOVER, margin_h, margin_v))
		btn.add_theme_stylebox_override("pressed", _flat_style(COLOR_BTN_BG, COLOR_GOLD, margin_h, margin_v))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return btn


## 「标签 + 控件」横排（标签固定宽，控件弹开填充）。
static func field_row(label: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var caption_label := caption(label)
	caption_label.custom_minimum_size.x = 120
	row.add_child(caption_label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


## id 清洗：只保留字母/数字/下划线（导出文件名与卡片 id 的安全网）。
static func sanitize_id(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		if ("a" <= c and c <= "z") or ("0" <= c and c <= "9") or c == "_":
			out += c
	return out


## 逗号/顿号分隔 → 去空白后的列表（别名、组织引用、links 等编辑框的解析）。
static func split_csv(text: String) -> Array:
	var out: Array = []
	for part in text.replace("，", ",").split(","):
		var trimmed := part.strip_edges()
		if not trimmed.is_empty():
			out.append(trimmed)
	return out


## 列表 → 逗号分隔文本（split_csv 的逆操作，表单回填用）。
static func join_list(items: Array) -> String:
	var parts: Array = []
	for item in items:
		parts.append(str(item))
	return ", ".join(parts)


static func _field_style(focused: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_FIELD_BG
	sb.border_color = COLOR_GOLD if focused else COLOR_FIELD_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb


static func _flat_style(bg: Color, border: Color, margin_h := 18, margin_v := 11) -> StyleBoxFlat:
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
