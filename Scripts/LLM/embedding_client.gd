class_name EmbeddingClient
extends Node
## OpenAI 兼容 /embeddings 客户端（LLM 层）：语义检索向量档的取数通道。
## DeepSeek 官方无 embeddings 端点，本客户端对接第二家供应商
##（SiliconFlow / 智谱 / OpenAI 等，base_url 可配）。
## 健壮性与 DeepSeekClient 同款：每次请求短命 HTTPRequest + 看门狗竞速，
## 异常网络失败不可能污染下一次请求。


const TIMEOUT_SECONDS := 8.0
const WATCHDOG_MARGIN := 4.0
## 单次请求批量上限（OpenAI 兼容端点的常规安全值）
const MAX_BATCH := 16


var api_key := ""
var model := EmbeddingConfig.DEFAULT_MODEL
var base_url := EmbeddingConfig.DEFAULT_BASE_URL


## 批量嵌入。返回 {ok, embeddings: Array[PackedFloat32Array]（与输入同序）, error}。
func embed_texts(texts: Array[String]) -> Dictionary:
	if api_key.strip_edges().is_empty():
		return {"ok": false, "embeddings": [], "error": "Embedding API Key 为空。"}
	if texts.is_empty():
		return {"ok": true, "embeddings": [], "error": ""}
	var body := {
		"model": model,
		"input": texts,
		"encoding_format": "float",
	}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key.strip_edges(),
	])
	var outcome: Dictionary = await _request(base_url.rstrip("/") + "/embeddings", headers,
		HTTPClient.METHOD_POST, JSON.stringify(body))
	if not outcome.get("ok", false):
		return {"ok": false, "embeddings": [], "error": str(outcome.get("error", "未知错误"))}
	var response: Array = outcome.get("response", [])
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "embeddings": [], "error": "网络请求失败（错误码 %d）" % int(response[0])}
	if int(response[1]) != 200:
		return {"ok": false, "embeddings": [], "error": "HTTP %d：%s" % [
			int(response[1]), (response[3] as PackedByteArray).get_string_from_utf8().substr(0, 200)]}
	var data: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if not (data is Dictionary):
		return {"ok": false, "embeddings": [], "error": "响应不是有效 JSON"}
	var rows: Variant = (data as Dictionary).get("data", [])
	if not (rows is Array) or (rows as Array).size() != texts.size():
		return {"ok": false, "embeddings": [], "error": "响应条数与输入不一致"}
	var out: Array[PackedFloat32Array] = []
	for row in rows:
		var raw: Variant = (row as Dictionary).get("embedding", [])
		if not (raw is Array):
			return {"ok": false, "embeddings": [], "error": "响应缺少向量字段"}
		var vec := PackedFloat32Array()
		vec.resize((raw as Array).size())
		for i in (raw as Array).size():
			vec[i] = float((raw as Array)[i])
		out.append(vec)
	return {"ok": true, "embeddings": out, "error": ""}


## 发起一次 HTTP 请求并等待完成（短命节点 + 看门狗，与 DeepSeekClient._request 同款）。
func _request(url: String, headers: PackedStringArray, method: int, body := "") -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	http.use_threads = true
	add_child(http)
	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "请求发起失败（错误码 %d）" % err}
	var settled := {"done": false, "args": []}
	http.request_completed.connect(
		func(result: int, code: int, resp_headers: PackedStringArray, resp_body: PackedByteArray) -> void:
			if not settled["done"]:
				settled["done"] = true
				settled["args"] = [result, code, resp_headers, resp_body]
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
		return {"ok": false, "error": "请求超时未响应（看门狗 %0.f 秒）" % (TIMEOUT_SECONDS + WATCHDOG_MARGIN)}
	return {"ok": true, "response": response}
