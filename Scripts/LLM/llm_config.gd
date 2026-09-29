class_name LlmConfig
extends RefCounted
## DeepSeek API 配置存取（LLM 层）。保存在本机 user://config.cfg。
## API Key 默认为空——为空时 LLMController 自动改用离线示例客户端。
## 模型名以官方文档为准（deepseek-chat / deepseek-reasoner 已于 2026-07-24 停用）：
##   deepseek-flash   默认模型（V4.1-Flash，低价快速）
##   deepseek-v4-pro  旗舰模型（长上下文，适合复杂生成）


const CONFIG_PATH := "user://config.cfg"
const SECTION := "deepseek"
const AVAILABLE_MODELS := ["deepseek-flash", "deepseek-v4-pro"]
const DEFAULT_MODEL := "deepseek-flash"


var api_key := ""
var model := DEFAULT_MODEL


## 从本机配置读取 Key/模型；文件缺失保持默认，停用模型名回落默认。
func load() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	api_key = str(config.get_value(SECTION, "api_key", ""))
	model = str(config.get_value(SECTION, "model", DEFAULT_MODEL))
	if not AVAILABLE_MODELS.has(model):
		# 旧配置里已停用的模型名（如 deepseek-chat）回落到默认模型
		model = DEFAULT_MODEL


## 写回本机配置（[deepseek] 节）。
func save() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "api_key", api_key)
	config.set_value(SECTION, "model", model)
	config.save(CONFIG_PATH)
