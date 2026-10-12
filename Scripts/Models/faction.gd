class_name Faction
extends Entity
## 组织模型（Models 层）：作者在 factions.json 编写的势力/团体。
## 成员可以是没有人物卡的配角；人物通过 faction_ids 引用组织，职位按规范名在成员表匹配。

var description := ""
var members: Array[Dictionary] = []  # [{name, position}]


func _init() -> void:
	type = EntityType.FACTION
	source = EntitySource.AUTHOR


static func from_faction_dict(data: Dictionary) -> Faction:
	var f := Faction.new()
	f.load_common(data)
	f.description = str(JsonTool.pick(data, ["description", "介绍"], ""))
	var raw_members: Variant = JsonTool.pick(data, ["members", "成员"], [])
	if raw_members is Array:
		for item in raw_members:
			if not (item is Dictionary):
				continue
			var member: Dictionary = item
			var record := {
				"name": str(JsonTool.pick(member, ["name", "名称"], "")),
				"position": str(JsonTool.pick(member, ["position", "职位"], "成员")),
			}
			if not (record["name"] as String).is_empty():
				f.members.append(record)
	return f


## 按成员名称查职位；不是成员返回空串。
func position_of(member_name: String) -> String:
	for member in members:
		if str(member.get("name", "")) == member_name:
			return str(member.get("position", ""))
	return ""


## 设定页的一行成员展示："名称（职位）"。
static func member_line(member: Dictionary) -> String:
	var position := str(member.get("position", ""))
	if position.is_empty():
		return str(member.get("name", ""))
	return "%s（%s）" % [member.get("name", ""), position]
