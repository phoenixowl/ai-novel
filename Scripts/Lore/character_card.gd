class_name CharacterCard
extends RefCounted
## 人物卡：作者在 settings/characters/ 下编写的 NPC 静态设定。
## 属于【流程一：设定资料】的产物，整个对话期间只读。
## knowledge：内联初始知识数组（每条 content/source/trust）——即该 NPC 知识日志的
## 初始部分，对话开始时由引擎逐条转入 KnowledgeJournal；运行时习得的条目
## 持久化在 user://journals/，与卡片互不遮蔽。
## factions：所属组织 id 列表。


var id := ""
var display_name := ""
var identity := ""           ## 世界内身份（不是“玩家”这类元概念，见设计 4.2）
var personality := ""        ## 性格
var speech_style := ""       ## 说话方式
var mood_baseline := "平和"  ## 心情基准（素材包“自身状态”的初始值）
var knowledge: Array[Dictionary] = []  ## 初始知识 [{content, source, trust}]
var faction_ids: PackedStringArray = PackedStringArray()  ## 所属组织 id 列表
var memberships: Array[Dictionary] = []  ## 解析后的所属组织 {faction: Faction, position: String}


## 从设定 JSON 解析人物卡（中英文键名兼容）。
## data：人物卡 Dictionary；knowledge 数组每项 {content, source, trust}。
static func from_dict(data: Dictionary) -> CharacterCard:
	var card := CharacterCard.new()
	card.id = str(JsonUtil.pick(data, ["id"], ""))
	card.display_name = str(JsonUtil.pick(data, ["name", "display_name", "姓名"], card.id))
	card.identity = str(JsonUtil.pick(data, ["identity", "身份"], ""))
	card.personality = str(JsonUtil.pick(data, ["personality", "性格"], ""))
	card.speech_style = str(JsonUtil.pick(data, ["speech_style", "说话方式"], ""))
	card.mood_baseline = str(JsonUtil.pick(data, ["mood_baseline", "心情基准"], "平和"))
	var raw_knowledge: Variant = JsonUtil.pick(data, ["knowledge", "知识"], [])
	if raw_knowledge is Array:
		for item in raw_knowledge:
			if not (item is Dictionary):
				continue
			var entry := {
				"content": str(JsonUtil.pick(item, ["content", "内容", "quote"], "")),
				"source": str(JsonUtil.pick(item, ["source", "来源"], "常识")),
				"trust": str(JsonUtil.pick(item, ["trust", "信任", "belief", "可信度"], "比较相信")),
			}
			if not (entry["content"] as String).is_empty():
				card.knowledge.append(entry)
	var raw_factions: Variant = JsonUtil.pick(data, ["factions", "组织"], [])
	if raw_factions is Array:
		for faction_id in raw_factions:
			var fid := str(faction_id).strip_edges()
			if not fid.is_empty() and not card.faction_ids.has(fid):
				card.faction_ids.append(fid)
	return card


func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty()
