class_name Entity
extends RefCounted
## 实体基类（Models 层）：注册表条目的公共字段与序列化。
## 子类 Person / Location / Faction 在 _init 中钉死自己的 type 并携带特有字段；
## 业务规则（检索、移动、信任算术）不在模型层，模型只承载数据与 JSON 边界转换。
## 注册表投影（entities.json）只序列化本基类字段；子类特有字段由各自的存储负责。

enum EntityType { PERSON, LOCATION, FACTION }
enum EntitySource { AUTHOR, GEN }
enum EntityStatus { ACTIVE }

const TYPE_KEYS := ["person", "location", "faction"]
const SOURCE_KEYS := ["author", "gen"]
const STATUS_KEYS := ["active"]


static func type_to_key(value: int) -> String:
	return TYPE_KEYS[clampi(value, 0, TYPE_KEYS.size() - 1)]


static func type_from_key(key: String) -> int:
	var index := TYPE_KEYS.find(key)
	return index if index != -1 else EntityType.PERSON


static func source_to_key(value: int) -> String:
	return SOURCE_KEYS[clampi(value, 0, SOURCE_KEYS.size() - 1)]


static func source_from_key(key: String) -> int:
	var index := SOURCE_KEYS.find(key)
	return index if index != -1 else EntitySource.AUTHOR


static func status_to_key(value: int) -> String:
	return STATUS_KEYS[clampi(value, 0, STATUS_KEYS.size() - 1)]


static func status_from_key(key: String) -> int:
	var index := STATUS_KEYS.find(key)
	return index if index != -1 else EntityStatus.ACTIVE


var entity_id := ""
var canonical_name := ""          # 规范名：命名闭集与提及扫描使用的名字
var aliases: Array[String] = []   # 别名（提及扫描同样命中）
var source: int = EntitySource.AUTHOR    # EntitySource
var status: int = EntityStatus.ACTIVE    # EntityStatus
var type: int = EntityType.PERSON        # EntityType（子类 _init 钉死）


## 最低有效条件（作者卡导入校验用）。
func is_valid() -> bool:
	return not entity_id.is_empty() and not canonical_name.is_empty()


## 读入注册表公共字段（子类 from_dict 先调本方法再补特有字段）。
func load_common(data: Dictionary) -> void:
	entity_id = str(JsonTool.pick(data, ["id", "entity_id"], ""))
	canonical_name = str(JsonTool.pick(data, ["name", "canonical_name", "姓名"], entity_id))
	aliases = []
	for alias in JsonTool.pick_strings(data, ["aliases", "别名"]):
		aliases.append(alias)
	source = source_from_key(str(JsonTool.pick(data, ["source"], "author")))
	status = status_from_key(str(JsonTool.pick(data, ["status"], "active")))


## 注册表投影（entities.json 的存储格式；不含子类特有字段，避免与各自存储双写）。
func to_registry_dict() -> Dictionary:
	return {
		"entity_id": entity_id,
		"type": type_to_key(type),
		"canonical_name": canonical_name,
		"aliases": aliases,
		"source": source_to_key(source),
		"status": status_to_key(status),
	}
