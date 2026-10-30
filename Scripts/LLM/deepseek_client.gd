class_name DeepSeekClient
extends LLMClient
## DeepSeek API 客户端（OpenAI 兼容的 chat/completions 协议）。
## API Key 由用户在 UI『API 设置』中填写，保存在 saves/config.cfg；
## 为空时引擎不会使用本客户端，而是切换到离线示例客户端。
##
## 连接健壮性：每次请求新建一个短命的 HTTPRequest 子节点、用完即弃——
## HTTPRequest 在异常网络失败（断网/TLS 中断）后可能永久停留在"请求中"状态
##（use_threads 的已知缺陷类），复用节点会让之后所有请求立即报错且 await 永不恢复；
## 一次性节点保证跨请求零共享状态。另设看门狗竞速：引擎超时失灵时强制按
## 传输失败返回，让上游状态机（DM 退回输入 / 对话退回玩家轮）照常恢复。


const CHAT_URL := "https://api.deepseek.com/chat/completions"
const MODELS_URL := "https://api.deepseek.com/models"
const TIMEOUT_SECONDS := 60.0
## 看门狗余量：引擎自身超时之外的兜底窗口
const WATCHDOG_MARGIN := 10.0

var api_key := ""
var model := LLMConfig.DEFAULT_MODEL
var max_tokens := LLMConfig.DEFAULT_MAX_TOKENS  # 单次补全输出上限（LLMController 按配置下发）


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
		"max_tokens": clampi(max_tokens, LLMConfig.MIN_MAX_TOKENS, LLMConfig.MAX_MAX_TOKENS),
	}
	# JSON 输出模式：官方文档示例基于 deepseek-flash；v4-pro 未明确支持，暂不开启。
	# 官方要求提示词中出现 “json” 字样并给出格式示例（静态层已满足）。
	if model == "deepseek-flash":
		body["response_format"] = {"type": "json_object"}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key.strip_edges(),
	])
	_busy = true
	var outcome: Dictionary = await _request(CHAT_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	_release_busy()
	if not outcome.get("ok", false):
		return {"ok": false, "content": "", "error": str(outcome.get("error", "未知错误"))}
	var response: Array = outcome.get("response", [])
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
			# 截断的 JSON 无法解析——以 truncated 标志上报具体原因，供上层区分传输故障
			var finish_reason := str(first.get("finish_reason", ""))
			if finish_reason == "length":
				return {"ok": false, "content": "", "truncated": true,
					"error": "输出被截断（达到 max_tokens 上限，finish_reason=length）"}
			return {"ok": true, "content": content, "error": ""}
		return {"ok": false, "content": "", "error": "响应中没有可用的回复内容"}
	return {"ok": false, "content": "", "error": "响应中没有可用的回复内容"}


## 连通性与鉴权测试（GET /models）
func test_connection() -> Dictionary:
	if api_key.strip_edges().is_empty():
		return {"ok": false, "message": "请先填写 API Key。"}
	var headers := PackedStringArray(["Authorization: Bearer " + api_key.strip_edges()])
	var outcome: Dictionary = await _request(MODELS_URL, headers, HTTPClient.METHOD_GET)
	if not outcome.get("ok", false):
		return {"ok": false, "message": str(outcome.get("error", "未知错误"))}
	var response: Array = outcome.get("response", [])
	var result: int = response[0]
	var response_code: int = response[1]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "message": "网络不可达：%s" % _result_text(result)}
	if response_code == 200:
		return {"ok": true, "message": "连接成功，Key 有效。"}
	var body_text := (response[3] as PackedByteArray).get_string_from_utf8()
	return {"ok": false, "message": "HTTP %d：%s" % [response_code, _body_error(body_text)]}


# ———— 内部 ————


## 发起一次 HTTP 请求并等待完成。返回：
##   {"ok": true, "response": [result, code, headers, body]}——request_completed 已到达
##   {"ok": false, "error": "…"}——请求发起失败，或看门狗超时（引擎层卡死，永不完成）
## 每次调用新建短命 HTTPRequest 子节点、用后即弃：无论哪条路径先返回都 queue_free，
## 一次异常网络失败留下的脏状态不可能带入下一次请求。
## 等待方式：共享旗标 + 帧轮询（Godot 4.7 的 await 不支持信号数组的"先到者胜"——
## 实测立即返回数组本身，故 request_completed 与看门狗各自置旗标，先置者胜）。
func _request(url: String, headers: PackedStringArray, method: int, body := "") -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	http.use_threads = true
	add_child(http)
	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "请求发起失败（错误码 %d）" % err}
	# 看门狗竞速：引擎超时失灵（request_completed 永不发出）时由定时器兜底置旗标
	var settled := {"done": false, "args": []}
	http.request_completed.connect(
		func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
			if not settled["done"]:
				settled["done"] = true
				settled["args"] = [result, code, headers, body]
	)
	var watchdog := get_tree().create_timer(TIMEOUT_SECONDS + WATCHDOG_MARGIN)
	watchdog.timeout.connect(func() -> void:
		if not settled["done"]:
			settled["done"] = true
			settled["args"] = [])
	while not settled["done"]:
		await get_tree().process_frame
	http.queue_free()
	var response: Array = settled["args"]
	if response.is_empty():
		return {"ok": false, "error": "请求超时未响应（看门狗 %.0f 秒）——网络可能已中断。" % (TIMEOUT_SECONDS + WATCHDOG_MARGIN)}
	return {"ok": true, "response": response}


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
