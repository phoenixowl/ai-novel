class_name GameConfig
extends RefCounted
## 游戏行为设置（Common 层）：与模型无关的玩家可调开关，持久化到 user://config.cfg 的 [game] 节。
## 当前条目：input_review_enabled（输入审查开关）与旁白风格四旋钮（宽松/严格两档，
## 只影响旁白提示词措辞与正典入库门槛，不影响数据结构——设计文档 14 节）。


const CONFIG_PATH := "user://config.cfg"
const SECTION := "game"

## （已弃用 2026-10）输入审查开关：统一入口后审查由 DM 路由取代，UI 不再提供开关；
## 字段保留只为兼容旧配置文件（读取后无消费方）。
var input_review_enabled := true

## 旁白风格旋钮（两档字符串；密度为 简练/浓墨，其余为 宽松/严格）
var narration_adoption := "宽松"    # 采纳度：玩家发明的接住方式
var narration_verdict := "宽松"     # 裁决倾向：行动成败的宽严
var narration_density := "简练"     # 描写密度：叙述的详略
var narration_threshold := "宽松"   # 正典门槛：minor 新事实是否入库


## 从本机配置读取；文件不存在或键缺失时保持默认值
func load() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	input_review_enabled = bool(config.get_value(SECTION, "input_review_enabled", true))
	narration_adoption = str(config.get_value(SECTION, "narration_adoption", "宽松"))
	narration_verdict = str(config.get_value(SECTION, "narration_verdict", "宽松"))
	narration_density = str(config.get_value(SECTION, "narration_density", "简练"))
	narration_threshold = str(config.get_value(SECTION, "narration_threshold", "宽松"))


## 写回本机配置（仅 [game] 节；与 LlmConfig 共用同一文件的不同节）
func save() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)  # 无文件时忽略，保留其它节
	config.set_value(SECTION, "input_review_enabled", input_review_enabled)
	config.set_value(SECTION, "narration_adoption", narration_adoption)
	config.set_value(SECTION, "narration_verdict", narration_verdict)
	config.set_value(SECTION, "narration_density", narration_density)
	config.set_value(SECTION, "narration_threshold", narration_threshold)
	config.save(CONFIG_PATH)
