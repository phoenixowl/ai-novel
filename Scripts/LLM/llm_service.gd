class_name LLMService
extends Node
## LLM 基础设施服务（LLM 层，autoload "LLM"）：配置、客户端生命周期与统一调用入口。
## 分层约定：未来任何 AI 功能（AI 旁白、道具生成……）都通过本服务调用模型，
## 不自行创建客户端、不自行解析 JSON——一次 complete_json 即得 {ok, data, notes, raw}。
##
## 与 UI 的交互经 EventBus（autoload "Events"）中转：在 LlmEvents 集线器
##（Scripts/LLM/llm_events.gd）上连接 cmd_* 命令信号、发射事件信号。

var config := LlmConfig.new()

var force_offline := false:
	set(value):
		force_offline = value
		if _client != null:  # 就绪后才重配，避免 _ready 前误触发
			_apply_config()

static var _shared: LLMService

var _client: LLMClient
var _events: LlmEvents  # 事件集线器（_ready 时经总线取得）


static func shared() -> LLMService:
	return _shared


## 测试/嵌入式环境兜底：autoload 未就绪时手动创建并注册共享实例（挂到当前场景树）
static func create_shared() -> LLMService:
	if _shared == null:
		_shared = LLMService.new()
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			(loop as SceneTree).root.add_child(_shared)
	return _shared


## 取全局事件总线；autoload 未就绪时手动创建（兜底）。
func _bus() -> EventBus:
	return EventBus.shared() if EventBus.shared() != null else EventBus.create_shared()


func _ready() -> void:
	_shared = self
	_events = _bus().hub(LlmEvents) as LlmEvents
	config.load()
	_apply_config()
	_events.cmd_set_config.connect(_on_cmd_set_config)
	_events.cmd_test_connection.connect(_on_cmd_test)
	_events.cmd_get_config.connect(_on_cmd_get_config)
	_publish_config()


func _exit_tree() -> void:
	if _shared == self:
		_shared = null
	if _events != null:
		_events.cmd_set_config.disconnect(_on_cmd_set_config)
		_events.cmd_test_connection.disconnect(_on_cmd_test)
		_events.cmd_get_config.disconnect(_on_cmd_get_config)


# ———— 命令处理（UI 经总线发来） ————


## 处理 cmd_set_config：保存 Key/模型并重建客户端。api_key/model：表单值。
func _on_cmd_set_config(api_key: String, model: String) -> void:
	set_api_config(api_key, model)


## 处理 cmd_test_connection：用临时值做连通性测试并广播结果。
## api_key/model：可为编辑中未保存的值（不落盘）。
func _on_cmd_test(api_key: String, model: String) -> void:
	var result: Dictionary = await _run_connection_test(api_key, model)
	_events.test_result.emit(bool(result.get("ok", false)), str(result.get("message", "")))


## 处理 cmd_get_config：重发配置快照（api_key/model/mode）。
func _on_cmd_get_config() -> void:
	_publish_config()


# ———— 配置与状态 ————


## 保存并应用新配置（落盘 + 重建客户端 + 广播快照）。key/model_name：新值。
func set_api_config(key: String, model_name: String) -> void:
	config.api_key = key.strip_edges()
	config.model = model_name
	config.save()
	_apply_config()
	_publish_config()


## 连通性测试（创建临时客户端，不落盘、不更换当前客户端）
func _run_connection_test(api_key: String, model_name: String) -> Dictionary:
	var key := api_key if not api_key.strip_edges().is_empty() else config.api_key
	var model := model_name if not model_name.is_empty() else config.model
	var tester := DeepSeekClient.new()
	tester.api_key = key
	tester.model = model
	add_child(tester)
	var result: Dictionary = await tester.test_connection()
	tester.queue_free()
	return result


## 当前客户端显示名。
func display_name() -> String:
	return _client.display_name()


## 当前是否为离线示例模式。
func is_offline() -> bool:
	return _client.is_offline()


# ———— 调用入口（所有 AI 功能的统一接入口） ————


## 纯文本补全入口。返回 {ok, content, error}。
func complete(system_prompt: String, user_prompt: String, purpose := LLMClient.PURPOSE_DIALOGUE) -> Dictionary:
	return await _client.complete(system_prompt, user_prompt, purpose)


## 请求模型并容错解析 JSON：剥离 markdown 围栏、括号配平提取首个 JSON 对象。
## 返回 {ok, transport, data, notes, raw, error}：
##   transport = true  网络层失败（error 含原因），data 为 null
##   ok = false 且 transport = false  输出不可解析（raw 保留原文）
##   ok = true  data 为提取好的 Dictionary，notes 为提取提示
func complete_json(system_prompt: String, user_prompt: String, purpose := LLMClient.PURPOSE_DIALOGUE) -> Dictionary:
	var result: Dictionary = await _client.complete(system_prompt, user_prompt, purpose)
	if not result.get("ok", false):
		var error_text := str(result.get("error", "未知错误"))
		# 截断（finish_reason=length）不是网络故障——走保底回应路径而非“退回玩家重试”
		var is_truncation := error_text.contains("截断")
		return {"ok": false, "transport": not is_truncation, "data": null, "notes": [],
			"raw": "", "error": error_text}
	var raw := str(result.get("content", ""))
	var data: Variant = JsonUtil.try_parse(raw)
	if data == null:
		# 启发式：以 { 开头但配平失败 → 疑似截断（无 finish_reason 的场景兜底）
		var hint := "模型输出无法解析为 JSON"
		var stripped := raw.strip_edges()
		if stripped.begins_with("{") and not stripped.ends_with("}"):
			hint = "模型输出疑似截断（JSON 不完整：以 { 开头但没有闭合的 }）"
		return {"ok": false, "transport": false, "data": null,
			"notes": ["未能从模型输出中解析出 JSON 对象"],
			"raw": raw, "error": hint}
	return {"ok": true, "transport": false, "data": data, "notes": [], "raw": raw, "error": ""}


# ———— 内部 ————


## 广播配置快照（api_key/model/mode）。
func _publish_config() -> void:
	_events.config.emit(config.api_key, config.model, _client.display_name())


## 按当前配置重建客户端（离线 Key 为空→Mock，否则 DeepSeek）并广播切换。
func _apply_config() -> void:
	if _client != null:
		_client.queue_free()
	if force_offline or config.api_key.strip_edges().is_empty():
		var mock := MockClient.new()
		add_child(mock)
		_client = mock
	else:
		var deepseek := DeepSeekClient.new()
		deepseek.api_key = config.api_key
		deepseek.model = config.model
		add_child(deepseek)
		_client = deepseek
	_events.mode_changed.emit(_client.display_name())
