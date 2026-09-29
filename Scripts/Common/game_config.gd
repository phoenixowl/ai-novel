class_name GameConfig
extends RefCounted
## 游戏行为设置（Common 层）：与模型无关的玩家可调开关，持久化到 user://config.cfg 的 [game] 节。
## 当前条目：input_review_enabled——输入审查（第 0 步）开关，默认开启。


const CONFIG_PATH := "user://config.cfg"
const SECTION := "game"

## 输入审查开关：true=提交前经 LLM 审查（拦动作/注入），false=直通对话流程
var input_review_enabled := true


## 从本机配置读取；文件不存在或键缺失时保持默认值
func load() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	input_review_enabled = bool(config.get_value(SECTION, "input_review_enabled", true))


## 写回本机配置（仅 [game] 节；与 LlmConfig 共用同一文件的不同节）
func save() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)  # 无文件时忽略，保留其它节
	config.set_value(SECTION, "input_review_enabled", input_review_enabled)
	config.save(CONFIG_PATH)
