class_name LLMConfig
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

## 最大输出 Token 上下限（SpinBox 同步此范围）：太小的值会频繁触发输出截断
const MIN_MAX_TOKENS := 256
const MAX_MAX_TOKENS := 8192
const DEFAULT_MAX_TOKENS := 3072


var api_key := ""
var model := DEFAULT_MODEL
var max_tokens := DEFAULT_MAX_TOKENS  # 单次补全的输出上限（finish_reason=length 即被此值截断）


## 从本机配置读取 Key/模型/输出上限；文件缺失保持默认，停用模型名回落默认，越界值钳位。
## （不叫 load()：避免遮蔽 GDScript 全局函数名）
func load_from_disk() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	api_key = str(config.get_value(SECTION, "api_key", ""))
	model = str(config.get_value(SECTION, "model", DEFAULT_MODEL))
	if not AVAILABLE_MODELS.has(model):
		# 旧配置里已停用的模型名（如 deepseek-chat）回落到默认模型
		model = DEFAULT_MODEL
	max_tokens = clampi(int(config.get_value(SECTION, "max_tokens", DEFAULT_MAX_TOKENS)),
		MIN_MAX_TOKENS, MAX_MAX_TOKENS)


## 写回本机配置（[deepseek] 节）。先读旧文件再写，保留 GameConfig 的 [game] 节。
func save_to_disk() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)  # 无文件时忽略
	config.set_value(SECTION, "api_key", api_key)
	config.set_value(SECTION, "model", model)
	config.set_value(SECTION, "max_tokens", max_tokens)
	config.save(CONFIG_PATH)
