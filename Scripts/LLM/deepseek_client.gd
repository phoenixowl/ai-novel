class_name DeepSeekClient
extends LLMClient
## DeepSeek API 客户端（OpenAI 兼容的 chat/completions 协议）。
## API Key 由用户在 UI『API 设置』中填写，保存在 user://config.cfg；
## 为空时引擎不会使用本客户端，而是切换到离线示例客户端。


const CHAT_URL := "https://api.deepseek.com/chat/completions"
const MODELS_URL := "https://api.deepseek.com/models"
const TIMEOUT_SECONDS := 60.0

var api_key := ""
var model := LlmConfig.DEFAULT_MODEL

var _http: HTTPRequest


## 创建内部 HTTPRequest 并配置超时（60s，线程模式）。
func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_SECONDS
	_http.use_threads = true
	add_child(_http)


func display_name() -> String:
	return "DeepSeek · %s" % model


func is_offline() -> bool:
	return false


## 请求 DeepSeek chat/completions 一次补全。
## system_prompt/user_prompt：系统与用户提示词；_purpose：业务用途（本客户端忽略）。
## 返回 {ok, content, error}：网络/鉴权/解析失败时 ok=false 且 error 含原因。
func complete(system_prompt: String, user_prompt: String, _purpose := PURPOSE_DIALOGUE) -> Dictionary:
	if api_key.strip_edges().is_empty():
		return {"ok": false, "content": "", "error": "API Key 为空，请在『API 设置』中填写。"}
	var body := {
		"model": model,
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": user_prompt},
		],
		"temperature": 0.8,
		"max_tokens": 3072,
	}
	# JSON 输出模式：官方文档示例基于 deepseek-flash；v4-pro 未明确支持，暂不开启。
	# 官方要求提示词中出现 “json” 字样并给出格式示例（静态层已满足）。
	if model == "deepseek-flash":
		body["response_format"] = {"type": "json_object"}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key.strip_edges(),
	])
	var err := _http.request(CHAT_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		return {"ok": false, "content": "", "error": "请求发起失败（错误码 %d）" % err}
	var response: Array = await _http.request_completed
	var result: int = response[0]
	var response_code: int = response[1]
	var response_body: PackedByteArray = response[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "content": "", "error": "网络请求失败：%s" % _result_text(result)}
	if response_code != 200:
		var body_text := response_body.get_string_from_utf8()
		return {"ok": false, "content": "", "error": "HTTP %d：%s" % [response_code, _body_error(body_text)]}
	var data: Variant = JSON.parse_string(response_body.get_string_from_utf8())
	if not (data is Dictionary):
		return {"ok": false, "content": "", "error": "响应不是有效 JSON"}
	var choices: Variant = (data as Dictionary).get("choices", [])
	if choices is Array and not (choices as Array).is_empty():
		var first: Dictionary = (choices as Array)[0]
		var message: Dictionary = first.get("message", {})
		var content: Variant = message.get("content", "")
		if content is String and not (content as String).is_empty():
			# 截断检测：finish_reason=="length" 表明输出被 max_tokens 切断，
			# 截断的 JSON 无法解析——提前报出具体原因，不留给解析器猜
			var finish_reason := str(first.get("finish_reason", ""))
			if finish_reason == "length":
				return {"ok": false, "content": "", "error": "输出被截断（达到 max_tokens 上限，finish_reason=length）"}
			return {"ok": true, "content": content, "error": ""}
		return {"ok": false, "content": "", "error": "响应中没有可用的回复内容"}
	return {"ok": false, "content": "", "error": "响应中没有可用的回复内容"}


## 连通性与鉴权测试（GET /models）
func test_connection() -> Dictionary:
	if api_key.strip_edges().is_empty():
		return {"ok": false, "message": "请先填写 API Key。"}
	var headers := PackedStringArray(["Authorization: Bearer " + api_key.strip_edges()])
	var err := _http.request(MODELS_URL, headers, HTTPClient.METHOD_GET)
	if err != OK:
		return {"ok": false, "message": "请求发起失败（错误码 %d）" % err}
	var response: Array = await _http.request_completed
	var result: int = response[0]
	var response_code: int = response[1]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "message": "网络不可达：%s" % _result_text(result)}
	if response_code == 200:
		return {"ok": true, "message": "连接成功，Key 有效。"}
	var body_text := (response[3] as PackedByteArray).get_string_from_utf8()
	return {"ok": false, "message": "HTTP %d：%s" % [response_code, _body_error(body_text)]}


# ———— 内部 ————


## 从 API 错误响应体提取人类可读信息；解析失败返回原文前 200 字。text：响应体 JSON 文本。
func _body_error(text: String) -> String:
	var data: Variant = JSON.parse_string(text)
	if data is Dictionary and (data as Dictionary).has("error"):
		var error: Dictionary = (data as Dictionary)["error"]
		return str(error.get("message", text))
	return text.substr(0, 200)


## 把 HTTPRequest 错误码翻译成中文原因。result：HTTPRequest.Result 枚举值。
func _result_text(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "无法连接服务器"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "无法解析域名（检查网络 / DNS）"
		HTTPRequest.RESULT_TIMEOUT:
			return "请求超时"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS 握手失败"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "连接错误"
		_:
			return "错误码 %d" % result
