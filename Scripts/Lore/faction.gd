class_name Faction
extends RefCounted
## 组织（Lore 层）：作者在 settings/factions.json 中编写的势力/团体设定。
## 属性：id、名称、介绍、成员列表（成员名称 + 所属职位）。
## 成员可以是没有人物卡的角色（如街坊配角）；角色卡通过 factions 字段
## 引用组织 id，职位以组织成员表为准（由 LoreRepository 解析为 memberships）。


var id := ""
var faction_name := ""
var description := ""
var members: Array[Dictionary] = []  # 每项 {name: String, position: String}


## 从设定 JSON 解析组织（名称/介绍/成员表：名称+职位）。data：组织 Dictionary。
static func from_dict(data: Dictionary) -> Faction:
	var faction := Faction.new()
	faction.id = str(JsonUtil.pick(data, ["id"], ""))
	faction.faction_name = str(JsonUtil.pick(data, ["name", "名称"], faction.id))
	faction.description = str(JsonUtil.pick(data, ["description", "介绍"], ""))
	var raw_members: Variant = JsonUtil.pick(data, ["members", "成员"], [])
	if raw_members is Array:
		for item in raw_members:
			if item is Dictionary:
				var member: Dictionary = item
				var record := {
					"name": str(JsonUtil.pick(member, ["name", "名称"], "")),
					"position": str(JsonUtil.pick(member, ["position", "职位"], "成员")),
				}
				if not record["name"].is_empty():
					faction.members.append(record)
	return faction


## 是否具备最低有效条件（id 与名称非空）。
func is_valid() -> bool:
	return not id.is_empty() and not faction_name.is_empty()


## 按成员名称查职位；不是成员返回空串
func position_of(member_name: String) -> String:
	for member in members:
		if str(member.get("name", "")) == member_name:
			return str(member.get("position", ""))
	return ""


## 设定页的一行成员展示：“名称（职位）”
static func member_line(member: Dictionary) -> String:
	var position := str(member.get("position", ""))
	if position.is_empty():
		return str(member.get("name", ""))
	return "%s（%s）" % [member.get("name", ""), position]
