class_name SceneCard
extends RefCounted
## 场景卡：作者在 settings/scenes/ 下编写的场景设定。
## 环境与氛围是“素材”（供模型消化发挥），不是“只能说这些”的清单（设计 4.3）。
## 开场情境说明：本段对话的背景，阶段一由发起对话时给定。


var id := ""
var scene_name := ""
var environment := ""        ## 环境与陈设素材
var atmosphere := ""         ## 氛围素材
var opening_situation := ""  ## 开场情境说明


## 从设定 JSON 解析场景卡（环境/氛围/开场情境）。data：场景卡 Dictionary。
static func from_dict(data: Dictionary) -> SceneCard:
	var card := SceneCard.new()
	card.id = str(JsonTool.pick(data, ["id"], ""))
	card.scene_name = str(JsonTool.pick(data, ["name", "scene_name", "场景名"], card.id))
	card.environment = str(JsonTool.pick(data, ["environment", "环境"], ""))
	card.atmosphere = str(JsonTool.pick(data, ["atmosphere", "氛围"], ""))
	card.opening_situation = str(JsonTool.pick(data, ["opening_situation", "开场情境"], ""))
	return card


## 是否具备最低有效条件（id 与场景名非空）。
func is_valid() -> bool:
	return not id.is_empty() and not scene_name.is_empty()
