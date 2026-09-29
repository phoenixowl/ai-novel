class_name AffinityStore
extends RefCounted
## 好感度存取（Lore 层）：每个 NPC 对玩家的好感度，-100 到 +100。
## 运行时变化持久化到 user://affinity/<npc_id>.json；未修改过的 NPC 用人物卡初始值。


const DIR := "user://affinity"
const MIN_VALUE := -100
const MAX_VALUE := 100
const MAX_CHANGE_PER_TURN := 10

## 好感度档位与提示词语句（按区间从低到高匹配）
const TIERS := [
	{"min": -100, "max": -61, "text": "你非常讨厌这个人，恨不得立刻赶走他。"},
	{"min": -60, "max": -31, "text": "你对此人反感，言语间保持冷淡和警惕。"},
	{"min": -30, "max": -11, "text": "你对此人没什么好感，态度公事公办。"},
	{"min": -10, "max": 10, "text": "你对此人的感觉一般，既不亲近也不排斥。"},
	{"min": 11, "max": 30, "text": "你对此人有些好感，愿意多说几句。"},
	{"min": 31, "max": 60, "text": "你对此人很有好感，态度友善热络。"},
	{"min": 61, "max": 100, "text": "你非常喜欢这个人，恨不得掏心掏肺。"},
]


## 读某 NPC 的好感度；无记录时返回 initial（人物卡初始值）。npc_id：人物卡 id。
static func get_value(npc_id: String, initial := 0) -> int:
	var path := "%s/%s.json" % [DIR, npc_id]
	if not FileAccess.file_exists(path):
		return initial
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return int((parsed as Dictionary).get("value", initial))
	return initial


## 写某 NPC 的好感度（自动钳位到 [-100, 100]）。npc_id：人物卡 id；value：新值。
static func set_value(npc_id: String, value: int) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var clamped := clampi(value, MIN_VALUE, MAX_VALUE)
	var data := {"value": clamped}
	var file := FileAccess.open("%s/%s.json" % [DIR, npc_id], FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()


## 增减好感度（每轮最多 ±10，总量钳位）。返回实际变化后的新值。
## npc_id：人物卡 id；change：变化量（正=升温，负=降温）；current：当前值。
static func apply_change(npc_id: String, change: int, current: int) -> int:
	var clamped_change := clampi(change, -MAX_CHANGE_PER_TURN, MAX_CHANGE_PER_TURN)
	var new_value := clampi(current + clamped_change, MIN_VALUE, MAX_VALUE)
	set_value(npc_id, new_value)
	return new_value


## 按好感度值取对应的提示词语句。value：当前好感度。
static func tier_text(value: int) -> String:
	for tier in TIERS:
		if value >= int(tier["min"]) and value <= int(tier["max"]):
			return str(tier["text"])
	return str(TIERS[3]["text"])  # 兜底：中性


## 档位简称（UI 显示用）。value：当前好感度。
static func tier_label(value: int) -> String:
	if value >= 61: return "挚爱"
	if value >= 31: return "好感"
	if value >= 11: return "略有好感"
	if value >= -10: return "中性"
	if value >= -30: return "略反感"
	if value >= -60: return "反感"
	return "敌视"
