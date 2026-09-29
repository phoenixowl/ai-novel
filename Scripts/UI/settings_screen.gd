extends Control
## 设置屏（Scripts/UI/）：DeepSeek API 配置（Key/模型/测试连接/保存应用）
## 与输入审查开关（立即生效并持久化）。
## 玩家人设编辑已移至「人物」总览/编辑页（cmd_save_character）。
## 与逻辑层的交互经 EventBus 集线器中转：连接 LlmEvents 与 DialogueEvents 的
## 相关信号、发射命令信号；返回主菜单经 UiEvents.navigate_requested。


const COLOR_SYSTEM := Color("#8d99ae")  # 中性提示文字颜色
const COLOR_ERROR := Color("#e76f51")   # 测试失败的颜色
const COLOR_OK := Color("#90be6d")       # 测试成功/保存成功的颜色

# —— 表单控件 ——
@onready var api_key_edit: LineEdit = %ApiKeyEdit
@onready var api_model_option: OptionButton = %ApiModelOption
@onready var api_test_label: Label = %ApiTestLabel
@onready var review_toggle: CheckButton = %ReviewToggle

# —— 事件集线器 ——
var _llm: LlmEvents        # LLM 域（API 配置与连接测试）
var _dialogue: DialogueEvents  # 对话域（输入审查开关）
var _nav: UiEvents         # UI 导航

# —— 状态缓存 ——
var _api_key := ""                        # 已保存的 DeepSeek Key（表单回填用）
var _model := LlmConfig.DEFAULT_MODEL     # 已保存的模型名


## 取全局事件总线；autoload 未就绪时（理论上仅测试环境）手动创建。
func _bus() -> EventBus:
	return EventBus.shared() if EventBus.shared() != null else EventBus.create_shared()


## 初始化：填充模型下拉、取得集线器、连接事件并拉取配置/设置快照。
func _ready() -> void:
	for model_name in LlmConfig.AVAILABLE_MODELS:
		api_model_option.add_item(model_name)
	_llm = _bus().hub(LlmEvents) as LlmEvents
	_dialogue = _bus().hub(DialogueEvents) as DialogueEvents
	_nav = _bus().hub(UiEvents) as UiEvents
	_llm.config.connect(_on_llm_config)
	_llm.test_result.connect(_on_llm_test_result)
	_dialogue.review_enabled_changed.connect(_on_review_enabled_changed)
	_nav.navigate_requested.connect(_on_navigate_requested)
	_llm.cmd_get_config.emit()        # 拉取配置快照（UI 可能晚于逻辑层就绪）
	_dialogue.cmd_get_settings.emit() # 拉取审查开关快照


# ———— 事件处理 ————


## LLM 配置快照到达：缓存 Key/模型（进入本屏时回填表单）。
## api_key/model：已保存配置；mode：当前客户端显示名（本屏不展示，忽略）。
func _on_llm_config(api_key: String, model: String, _mode: String) -> void:
	_api_key = api_key
	_model = model


## 连接测试结果：状态标签染色显示。ok：是否成功；message：结果文案。
func _on_llm_test_result(ok: bool, message: String) -> void:
	api_test_label.add_theme_color_override("font_color", COLOR_OK if ok else COLOR_ERROR)
	api_test_label.text = message


## 输入审查开关状态变化（启动广播/设置变更/主动查询）：同步本屏开关。
## enabled：true=开启审查，false=关闭。
func _on_review_enabled_changed(enabled: bool) -> void:
	review_toggle.set_pressed_no_signal(enabled)


## 导航事件：进入本屏时用缓存回填表单并重拉审查开关（防引擎侧变更）。
## screen：目标屏幕标识（"settings" 时处理）。
func _on_navigate_requested(screen: String) -> void:
	if screen != "settings":
		return
	api_key_edit.text = _api_key
	api_model_option.selected = maxi(0, LlmConfig.AVAILABLE_MODELS.find(_model))
	api_test_label.text = " "
	api_test_label.add_theme_color_override("font_color", COLOR_SYSTEM)
	_dialogue.cmd_get_settings.emit()


# ———— 玩家操作（信号已在场景 [connection] 中接线） ————


## 「返回主菜单」：请求导航回开始菜单。
func _on_back_pressed() -> void:
	_nav.navigate_requested.emit("menu")


## 「保存 API 设置并应用」：把表单中的 Key/模型经命令信号发给 LLM 服务
##（保存到 user://config.cfg 并重建客户端），状态标签反馈结果。
func _on_settings_save_pressed() -> void:
	_llm.cmd_set_config.emit(api_key_edit.text, _selected_model())
	api_test_label.add_theme_color_override("font_color", COLOR_OK)
	api_test_label.text = "已保存并应用。"


## 「测试连接」：用表单中正在编辑的 Key/模型发起临时连通性测试（不落盘）。
func _on_api_test_pressed() -> void:
	api_test_label.text = "测试中…"
	_llm.cmd_test_connection.emit(api_key_edit.text, _selected_model())


## 审查开关：立即生效并持久化（引擎侧完成），无需额外保存动作。
## enabled：true=开启输入审查，false=关闭。
func _on_review_toggle_toggled(enabled: bool) -> void:
	_dialogue.cmd_set_review.emit(enabled)


## 当前选中的模型名（下拉无效时回落默认模型）。
func _selected_model() -> String:
	if api_model_option.selected >= 0 and api_model_option.selected < LlmConfig.AVAILABLE_MODELS.size():
		return LlmConfig.AVAILABLE_MODELS[api_model_option.selected]
	return LlmConfig.DEFAULT_MODEL
