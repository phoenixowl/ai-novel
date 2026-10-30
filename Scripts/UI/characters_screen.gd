extends Control
## 人物总览屏（Scripts/UI/）：全部人物以网格卡片呈现——玩家卡置顶，每张 NPC 卡
## 显示（可选立绘）+ 姓名、身份、人设预览（超长截断省略）与好感度/知识/记忆计数。
## 立绘约定：res://assets/portraits/<id>.jpg|.png；有则图上叠字（底部渐变防挡脸），无则纯文字卡。
## 点击卡片进入编辑页；顶栏「还原设定」删除全部运行时快照回到作者卡面（确认弹窗）。
## 与逻辑层经 EventBus 集线器中转：cmd_get_characters 拉取、characters_listed 接收。
## 卡片样式：暗底圆角 + 悬停描边高亮；玩家蓝 / NPC 金做姓名点缀（色值集中在本文件头）。


const COLOR_NAME_NPC := Color("#e9c46a")           # NPC 卡姓名（金）
const COLOR_NAME_PLAYER := Color("#7ec8e3")        # 玩家卡姓名（蓝）
const COLOR_TEXT := Color("#ced4da")               # 卡片正文
const COLOR_MUTED := Color("#8d99ae")              # 次要信息
const COLOR_CARD_BG := Color("#1e1f2a")            # 卡片常态底色
const COLOR_CARD_BG_HOVER := Color("#262838")      # 卡片悬停底色
const COLOR_CARD_BORDER := Color("#343648")        # 卡片常态描边
const COLOR_CARD_BORDER_HOVER := Color("#e9c46a")  # 卡片悬停描边（金）
const COLOR_OK := Color("#90be6d")
const COLOR_ERROR := Color("#e76f51")

@onready var grid: GridContainer = %Grid
@onready var status_label: Label = %StatusLabel
@onready var restore_confirm: AcceptDialog = %RestoreConfirm

# —— 事件集线器 ——
var _characters: CharacterEvents
var _nav: UiEvents



## 初始化：取得集线器、连接事件并拉取人物总览。
func _ready() -> void:
	_characters = EventBus.resolve().hub(CharacterEvents) as CharacterEvents
	_nav = EventBus.resolve().hub(UiEvents) as UiEvents
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


## 卡片底样式：圆角 + 1px 描边；常态与悬停换底色/描边色。
func _card_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	return sb


## 人物立绘路径约定：res://assets/portraits/<id>.jpg（或 .png）；没有文件则不上图。
const PORTRAIT_DIR := "res://assets/portraits/"

# —— 立绘排版（自己改这几个数即可，改完重新运行看效果）——
const PORTRAIT_CARD_HEIGHT := 400.0   # 有立绘的卡片高度；越大脸和字越宽松
const PORTRAIT_Y_OFFSET := -50.0       # 图片上下偏移：负数上移（多露下巴），正数下移（多露头顶）
const PORTRAIT_FADE_TOP := 0.40      # 渐变从卡片多高开始（0~1）；越大，脸上方越干净
const PORTRAIT_INFO_HEIGHT := 138.0  # 底部叠字区域高度；越大字越多、越挡图


## 按角色 id 查找立绘；优先 jpg，其次 png；都不存在返回 null。
func _load_portrait(id: String) -> Texture2D:
	if id.is_empty():
		return null
	var exts: Array[String] = [".jpg", ".jpeg", ".png", ".webp"]
	for ext in exts:
		var path: String = PORTRAIT_DIR + id + ext
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


## 立绘底部渐变遮罩：上透明、下半透明黑，文字压在图上但不挡住上半张脸。
func _portrait_fade_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([
		Color(0.04, 0.03, 0.08, 0.0),
		Color(0.04, 0.03, 0.08, 0.55),
		Color(0.04, 0.03, 0.08, 0.92),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 4
	tex.height = 256
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	return tex


## Cover 铺满 + 顶部对齐：优先露出完整脸；多裁衣领以下，叠字区正好盖住裁掉的部分。
func _fit_portrait_top(tex_rect: TextureRect, host: Control) -> void:
	var tex := tex_rect.texture
	if tex == null:
		return
	var hs := host.size
	if hs.x < 1.0 or hs.y < 1.0:
		return
	var ts := tex.get_size()
	if ts.x < 1.0 or ts.y < 1.0:
		return
	var s := maxf(hs.x / ts.x, hs.y / ts.y)
	var w := ts.x * s
	var h := ts.y * s
	tex_rect.anchor_left = 0.0
	tex_rect.anchor_top = 0.0
	tex_rect.anchor_right = 0.0
	tex_rect.anchor_bottom = 0.0
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	tex_rect.size = Vector2(w, h)
	# 水平居中；垂直用 PORTRAIT_Y_OFFSET 微调（正=图下移，多露头顶）
	tex_rect.position = Vector2((hs.x - w) * 0.5, PORTRAIT_Y_OFFSET)


## 构建介绍文字列（姓名 / 身份 / 人设 / 底栏），供纯文字卡与立绘叠字共用。
func _build_info_column(item: Dictionary, is_player: bool, compact: bool) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4 if compact else 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_label := Label.new()
	name_label.text = "▶ 你（玩家）" if is_player else str(item.get("name", ""))
	name_label.add_theme_font_size_override("font_size", 22 if compact else 21)
	name_label.add_theme_color_override("font_color", COLOR_NAME_PLAYER if is_player else COLOR_NAME_NPC)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_label)

	var identity := str(item.get("identity", ""))
	if not identity.is_empty():
		var identity_label := Label.new()
		identity_label.text = identity
		identity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		identity_label.max_lines_visible = 2 if compact else 3
		identity_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		identity_label.add_theme_font_size_override("font_size", 14 if compact else 15)
		identity_label.add_theme_color_override("font_color", COLOR_TEXT)
		identity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(identity_label)

	var profile := str(item.get("profile", ""))
	if not profile.is_empty():
		var profile_label := Label.new()
		profile_label.text = profile
		profile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		profile_label.max_lines_visible = 2 if compact else 4
		profile_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		profile_label.add_theme_font_size_override("font_size", 12 if compact else 13)
		profile_label.add_theme_color_override("font_color", COLOR_MUTED)
		profile_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(profile_label)

	var foot := Label.new()
	if is_player:
		foot.text = "点击编辑你的身份与外观"
	else:
		foot.text = "好感度 %d（%s）· 知识 %d 条 · 记忆 %d 条" % [
			int(item.get("affinity", 0)), str(item.get("affinity_label", "")),
			int(item.get("knowledge_count", 0)), int(item.get("memory_count", 0)),
		]
	foot.add_theme_font_size_override("font_size", 12 if compact else 13)
	foot.add_theme_color_override("font_color", COLOR_MUTED)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(foot)
	return col


## 构建一张人物卡片：有立绘则「图上叠字 + 底部渐变」；无立绘保持纯文字。
## item：总览数据 {kind, id, name, identity, profile, affinity, affinity_label, knowledge_count, memory_count}。
func _build_card(item: Dictionary) -> Button:
	var is_player := str(item.get("kind", "")) == "player"
	var id := str(item.get("id", ""))
	var portrait := _load_portrait(id)
	var card := Button.new()
	# 有立绘的卡加高，给脸和叠字都留空间（高度见 PORTRAIT_CARD_HEIGHT）。
	card.custom_minimum_size = Vector2(0, PORTRAIT_CARD_HEIGHT if portrait != null else 220)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("normal", _card_style(COLOR_CARD_BG, COLOR_CARD_BORDER))
	card.add_theme_stylebox_override("hover", _card_style(COLOR_CARD_BG_HOVER, COLOR_CARD_BORDER_HOVER))
	card.add_theme_stylebox_override("pressed", _card_style(COLOR_CARD_BG, COLOR_CARD_BORDER_HOVER))
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	card.pressed.connect(func():
		_nav.character_edit_requested.emit(id)
		_nav.navigate_requested.emit("character_edit")
	)

	if portrait != null:
		# 立绘顶部对齐铺满：完整露脸；介绍仍压在下部渐变上。
		var host := Control.new()
		host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.offset_left = 8
		host.offset_top = 8
		host.offset_right = -8
		host.offset_bottom = -8
		host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.clip_contents = true
		card.add_child(host)

		var tex := TextureRect.new()
		tex.texture = portrait
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(tex)
		host.resized.connect(func(): _fit_portrait_top(tex, host))
		# 首帧尺寸可能为 0，延后一帧再顶部对齐。
		_fit_portrait_top.call_deferred(tex, host)

		var fade := TextureRect.new()
		fade.texture = _portrait_fade_texture()
		fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fade.anchor_top = PORTRAIT_FADE_TOP
		fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fade.stretch_mode = TextureRect.STRETCH_SCALE
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(fade)

		var info := _build_info_column(item, is_player, true)
		info.anchor_left = 0.0
		info.anchor_right = 1.0
		info.anchor_top = 1.0
		info.anchor_bottom = 1.0
		info.grow_vertical = Control.GROW_DIRECTION_BEGIN
		info.offset_left = 10.0
		info.offset_right = -10.0
		info.offset_top = -PORTRAIT_INFO_HEIGHT
		info.offset_bottom = -8.0
		host.add_child(info)
		return card

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 18
	box.offset_top = 14
	box.offset_right = -16
	box.offset_bottom = -12
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	box.add_child(_build_info_column(item, is_player, false))
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
