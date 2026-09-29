class_name PlayerCard
extends RefCounted
## 玩家人物卡（Lore 层）：玩家的世界内身份，由作者在 settings/player.json 编写默认值，
## 运行时可经设置屏修改（持久化到 user://player.json，作者默认不被遮蔽）。
## 不含说话方式——玩家怎么说话由玩家自己决定。


var display_name := "来客"
var identity := ""       ## 世界内身份（不是"玩家"元概念）
var appearance := ""     ## 外观描述（NPC 看到的样子）


## 从设定 JSON 解析（中英文键名兼容）。data：玩家卡 Dictionary。
static func from_dict(data: Dictionary) -> PlayerCard:
	var card := PlayerCard.new()
	card.display_name = str(JsonTool.pick(data, ["name", "姓名"], "来客"))
	card.identity = str(JsonTool.pick(data, ["identity", "身份"], ""))
	card.appearance = str(JsonTool.pick(data, ["appearance", "外观"], ""))
	return card


## 渲染为提示词可用的描述行。
func to_prompt_lines() -> Array[String]:
	var lines: Array[String] = []
	if not identity.is_empty():
		lines.append("身份：" + identity)
	if not appearance.is_empty():
		lines.append("外观：" + appearance)
	return lines


## 序列化为 Dictionary（材料包传递用）。name：玩家称呼。
func to_dict() -> Dictionary:
	return {"name": display_name, "identity": identity, "appearance": appearance}
