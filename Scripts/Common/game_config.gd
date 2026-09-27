class_name GameConfig
extends RefCounted
## 游戏行为设置（Common 层）：与模型无关的玩家可调开关，持久化到 user://config.cfg 的 [game] 节。
## 当前条目：input_review_enabled——输入审查（第 0 步）开关，默认开启。


const CONFIG_PATH := "user://config.cfg"
const SECTION := "game"

## 输入审查开关：true=提交前经 LLM 审查（拦动作/注入），false=直通对话流程
var input_review_enabled := true
## 玩家人设（注入提示词静态层，影响 NPC 对玩家的称呼与态度）
var player_identity := ""        # 玩家的世界内身份（如"流浪剑客""初来乍到的学生"）；空=不注入
var player_speech_style := ""    # 玩家的说话风格提示（如"礼貌但好奇"）；空=不注入


## 从本机配置读取；文件不存在或键缺失时保持默认值
func load() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	input_review_enabled = bool(config.get_value(SECTION, "input_review_enabled", true))
	player_identity = str(config.get_value(SECTION, "player_identity", ""))
	player_speech_style = str(config.get_value(SECTION, "player_speech_style", ""))


## 写回本机配置（仅 [game] 节；与 LlmConfig 共用同一文件的不同节）
func save() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)  # 无文件时忽略，保留其它节
	config.set_value(SECTION, "input_review_enabled", input_review_enabled)
	config.set_value(SECTION, "player_identity", player_identity)
	config.set_value(SECTION, "player_speech_style", player_speech_style)
	config.save(CONFIG_PATH)
