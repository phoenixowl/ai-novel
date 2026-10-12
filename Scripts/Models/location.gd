class_name Location
extends Entity
## 地点模型（Models 层）：吸收场景卡（作者素材）与位置图节点（运行期状态）的全部字段。
## brief（冻结进场描述）与 npcs（在场人物）是运行期状态——merge_author 刷新作者字段时保留它们。

var environment := ""        # 环境与陈设素材
var atmosphere := ""         # 氛围素材
var opening_situation := ""  # 开场情境说明
var links := PackedStringArray()  # 作者声明的初始路线（对方地点 id）
var brief := ""              # 冻结的进场描述（空 = 尚未生成）
var npcs: Array[String] = [] # 在场人物 id（对话入口与检索依据）


func _init() -> void:
	type = EntityType.LOCATION
	source = EntitySource.AUTHOR


## 从场景卡 JSON / 位置图节点 JSON 构造（两者键名有交集，缺省容忍）。
static func from_scene_dict(data: Dictionary) -> Location:
	var l := Location.new()
	l.load_common(data)
	l.environment = str(JsonTool.pick(data, ["environment", "环境"], ""))
	l.atmosphere = str(JsonTool.pick(data, ["atmosphere", "氛围"], ""))
	l.opening_situation = str(JsonTool.pick(data, ["opening_situation", "开场情境"], ""))
	l.links = JsonTool.pick_strings(data, ["links", "路线"])
	l.npcs = []
	for npc_id in JsonTool.pick_strings(data, ["npcs", "在场"]):
		l.npcs.append(npc_id)
	l.brief = str(JsonTool.pick(data, ["brief"], ""))
	return l


## 作者数据重载时刷新作者字段，保留运行期状态（brief / npcs）。
func merge_author(new: Location) -> void:
	canonical_name = new.canonical_name
	aliases = new.aliases
	environment = new.environment
	atmosphere = new.atmosphere
	opening_situation = new.opening_situation
	links = new.links
	for npc_id in new.npcs:
		if not npcs.has(npc_id):
			npcs.append(npc_id)


## 位置图节点序列化（locations.json 的节点格式）。
func to_node_dict() -> Dictionary:
	return {
		"entity_id": entity_id,
		"brief": brief,
		"source": Entity.source_to_key(source),
		"status": Entity.status_to_key(status),
		"npcs": npcs,
	}
