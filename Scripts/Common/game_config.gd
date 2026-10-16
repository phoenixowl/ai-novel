class_name GameConfig
extends RefCounted
## 游戏行为设置（Common 层）：与模型无关的玩家可调开关，持久化到 user://config.cfg 的 [game] 节。
## 当前条目：旁白风格四旋钮（宽松/严格两档，只影响旁白提示词措辞与正典入库门槛，
## 不影响数据结构——设计文档 14 节）。


const CONFIG_PATH := "user://config.cfg"
const SECTION := "game"

## 风格旋钮定义表（键名/标签/选项/说明）——设置屏、AuthorTool 风格页与
## DMController.current_knobs 的唯一来源；加旋钮只改这一处。
const KNOB_DEFS := [
	{"key": "adoption", "label": "采纳度", "options": ["宽松", "严格"],
		"hint": "玩家的想象力（想找什么、假设什么）被旁白接住的方式"},
	{"key": "verdict", "label": "裁决倾向", "options": ["宽松", "严格"],
		"hint": "行动成败的宽严：宽松多成功，严格常有失败与代价"},
	{"key": "density", "label": "描写密度", "options": ["简练", "浓墨"],
		"hint": "旁白叙述的详略"},
	{"key": "threshold", "label": "正典门槛", "options": ["宽松", "严格"],
		"hint": "次要新事实是否写入世界事实库（严格=只有大事实入库）"},
]

## 旁白风格旋钮（两档字符串；密度为 简练/浓墨，其余为 宽松/严格）
var narration_adoption := "宽松"    # 采纳度：玩家发明的接住方式
var narration_verdict := "宽松"     # 裁决倾向：行动成败的宽严
var narration_density := "简练"     # 描写密度：叙述的详略
var narration_threshold := "宽松"   # 正典门槛：minor 新事实是否入库


## 从本机配置读取；文件不存在或键缺失时保持默认值。
## （不叫 load()：避免遮蔽 GDScript 全局函数名）
func load_from_disk() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	narration_adoption = str(config.get_value(SECTION, "narration_adoption", "宽松"))
	narration_verdict = str(config.get_value(SECTION, "narration_verdict", "宽松"))
	narration_density = str(config.get_value(SECTION, "narration_density", "简练"))
	narration_threshold = str(config.get_value(SECTION, "narration_threshold", "宽松"))


## 写回本机配置（仅 [game] 节；与 LLMConfig 共用同一文件的不同节）。
func save_to_disk() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)  # 无文件时忽略，保留其它节
	config.set_value(SECTION, "narration_adoption", narration_adoption)
	config.set_value(SECTION, "narration_verdict", narration_verdict)
	config.set_value(SECTION, "narration_density", narration_density)
	config.set_value(SECTION, "narration_threshold", narration_threshold)
	config.save(CONFIG_PATH)
