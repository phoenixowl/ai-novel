extends Control
## 设置屏（Scripts/UI/）：DeepSeek API 配置（Key/模型/测试连接/保存应用）与
## DM 风格四旋钮（即选即存）。输入审查开关已随统一入口退役（2026-10）。
## 玩家人设编辑已移至「人物」总览/编辑页（cmd_save_character）。
## 与逻辑层的交互经 EventBus 集线器中转：连接 LLMEvents / DMEvents
## 的相关信号、发射命令信号；返回主菜单经 UiEvents.navigate_requested。


const COLOR_SYSTEM := Color("#8d99ae")  # 中性提示文字颜色
const COLOR_ERROR := Color("#e76f51")   # 测试失败的颜色
const COLOR_OK := Color("#90be6d")       # 测试成功/保存成功的颜色

## 旋钮定义（键名/选项/说明）的唯一来源是 GameConfig.KNOB_DEFS——本屏只负责渲染。

# —— 表单控件 ——
@onready var api_key_edit: LineEdit = %ApiKeyEdit
@onready var api_model_option: OptionButton = %ApiModelOption
@onready var api_test_label: Label = %ApiTestLabel
@onready var max_tokens_spin: SpinBox = %MaxTokensSpin
@onready var knobs_box: VBoxContainer = %KnobsBox
# —— 检索配置区（事实召回语义层档位） ——
@onready var embedding_provider_option: OptionButton = %EmbeddingProviderOption
@onready var embedding_base_url_edit: LineEdit = %EmbeddingBaseUrlEdit
@onready var embedding_model_edit: LineEdit = %EmbeddingModelEdit
@onready var embedding_key_edit: LineEdit = %EmbeddingKeyEdit
@onready var embedding_status: Label = %EmbeddingStatus

# —— 事件集线器 ——
var _llm: LLMEvents        # LLM 域（API 配置与连接测试）
var _dm: DMEvents  # 旁白域（风格旋钮）
var _nav: UiEvents         # UI 导航

# —— 状态缓存 ——
var _api_key := ""                        # 已保存的 DeepSeek Key（表单回填用）
var _model := LLMConfig.DEFAULT_MODEL     # 已保存的模型名
var _max_tokens := LLMConfig.DEFAULT_MAX_TOKENS  # 已保存的输出上限
var _knob_options: Array[Dictionary] = []  # 动态创建的旋钮 OptionButton（含 key 与选项表）
var _embed_cfg := EmbeddingConfig.new()    # 检索配置（进屏时读盘回填；保存经 DM 总线命令下发）



## 初始化：填充模型下拉、构建旋钮区、取得集线器、连接事件并拉取快照。
func _ready() -> void:
	for model_name in LLMConfig.AVAILABLE_MODELS:
		api_model_option.add_item(model_name)
	for choice in EmbeddingConfig.PROVIDER_CHOICES:
		embedding_provider_option.add_item(str(choice["label"]))
	_build_knobs()
	_llm = EventBus.resolve().hub(LLMEvents) as LLMEvents
	_dm = EventBus.resolve().hub(DMEvents) as DMEvents
	_nav = EventBus.resolve().hub(UiEvents) as UiEvents
	_llm.config.connect(_on_llm_config)
	_llm.test_result.connect(_on_llm_test_result)
	_dm.knobs_changed.connect(_on_knobs_changed)
	_nav.navigate_requested.connect(_on_navigate_requested)
	_llm.cmd_get_config.emit()        # 拉取配置快照（UI 可能晚于逻辑层就绪）


## 构建旁白风格旋钮区（四行：说明 + 两档 OptionButton，即选即存）。
func _build_knobs() -> void:
	for def in GameConfig.KNOB_DEFS:
		var options: Array = def["options"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var caption := Label.new()
		caption.text = "%s：%s" % [def["label"], def["hint"]]
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.custom_minimum_size.x = 430
		caption.add_theme_color_override("font_color", COLOR_SYSTEM)
		caption.add_theme_font_size_override("font_size", 13)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(caption)
		var option := OptionButton.new()
		option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for opt in options:
			option.add_item(opt)
		option.item_selected.connect(func(index: int):
			_dm.cmd_set_knobs.emit({def["key"]: options[index]}))
		row.add_child(option)
		knobs_box.add_child(row)
		_knob_options.append({"key": def["key"], "options": options, "node": option})


## 旋钮状态到达（启动/变更）：同步各下拉的选中项（无信号，防回环）。
func _on_knobs_changed(knobs: Dictionary) -> void:
	for knob in _knob_options:
		var options: Array = knob["options"]
		var option := knob["node"] as OptionButton
		var value := str(knobs.get(knob["key"], options[0]))
		option.selected = maxi(0, options.find(value))


# ———— 事件处理 ————


## LLM 配置快照到达：缓存 Key/模型/输出上限（进入本屏时回填表单）。
## api_key/model/max_tokens：已保存配置；mode：当前客户端显示名（本屏不展示，忽略）。
func _on_llm_config(api_key: String, model: String, _mode: String, max_tokens: int) -> void:
	_api_key = api_key
	_model = model
	_max_tokens = max_tokens


## 连接测试结果：状态标签染色显示。ok：是否成功；message：结果文案。
func _on_llm_test_result(ok: bool, message: String) -> void:
	api_test_label.add_theme_color_override("font_color", COLOR_OK if ok else COLOR_ERROR)
	api_test_label.text = message


## 导航事件：进入本屏时用缓存回填表单并重拉风格旋钮（防引擎侧变更）。
## screen：目标屏幕标识（"settings" 时处理）。
func _on_navigate_requested(screen: String) -> void:
	if screen != "settings":
		return
	api_key_edit.text = _api_key
	api_model_option.selected = maxi(0, LLMConfig.AVAILABLE_MODELS.find(_model))
	max_tokens_spin.set_value_no_signal(_max_tokens)
	api_test_label.text = " "
	api_test_label.add_theme_color_override("font_color", COLOR_SYSTEM)
	_embed_cfg.load_from_disk()
	for i in EmbeddingConfig.PROVIDER_CHOICES.size():
		if str(EmbeddingConfig.PROVIDER_CHOICES[i]["key"]) == _embed_cfg.provider:
			embedding_provider_option.selected = i
			break
	embedding_base_url_edit.text = _embed_cfg.base_url
	embedding_model_edit.text = _embed_cfg.model
	embedding_key_edit.text = _embed_cfg.api_key
	embedding_status.text = " "
	_dm.cmd_get_knobs.emit()


# ———— 玩家操作（信号已在场景 [connection] 中接线） ————


## 「返回主菜单」：请求导航回开始菜单。
func _on_back_pressed() -> void:
	_nav.navigate_requested.emit("menu")


## 「保存 API 设置并应用」：把表单中的 Key/模型/输出上限经命令信号发给 LLM 服务
##（保存到 saves/config.cfg 并重建客户端），状态标签反馈结果。
func _on_settings_save_pressed() -> void:
	_llm.cmd_set_config.emit(api_key_edit.text, _selected_model(), int(max_tokens_spin.value))
	api_test_label.add_theme_color_override("font_color", COLOR_OK)
	api_test_label.text = "已保存并应用。"


## 「测试连接」：用表单中正在编辑的 Key/模型发起临时连通性测试（不落盘）。
func _on_api_test_pressed() -> void:
	api_test_label.text = "测试中…"
	_llm.cmd_test_connection.emit(api_key_edit.text, _selected_model())


## 「保存检索设置并应用」：表单值经 DM 总线命令下发（引擎侧持久化 + 换模型清向量）。
func _on_embedding_save_pressed() -> void:
	var provider := str(EmbeddingConfig.PROVIDER_CHOICES[
		clampi(embedding_provider_option.selected, 0, EmbeddingConfig.PROVIDER_CHOICES.size() - 1)]["key"])
	_dm.cmd_set_embedding_config.emit(provider, embedding_key_edit.text.strip_edges(),
		embedding_model_edit.text.strip_edges(), embedding_base_url_edit.text.strip_edges())
	embedding_status.add_theme_color_override("font_color", COLOR_OK)
	if provider == EmbeddingConfig.PROVIDER_API:
		embedding_status.text = "已保存并应用（向量档；请求失败时自动回落内置 BM25）。"
	else:
		embedding_status.text = "已保存并应用。"


## 当前选中的模型名（下拉无效时回落默认模型）。
func _selected_model() -> String:
	if api_model_option.selected >= 0 and api_model_option.selected < LLMConfig.AVAILABLE_MODELS.size():
		return LLMConfig.AVAILABLE_MODELS[api_model_option.selected]
	return LLMConfig.DEFAULT_MODEL
