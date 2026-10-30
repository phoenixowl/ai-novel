class_name CanonFact
extends RefCounted
## 世界事实条目（Models 层）：正典（CanonStore）里的一条客观事实——
## "世界里确定成立/发生过的事"，是整个世界状态的原子单位。
## scope 是实体 id 列表（空 = 全局）；类型可由 EntityRegistry 反查，不冗余存储。
## PROVISIONAL（临时）：DM 行动回合申报的持久事实——立即入典、可检索、可被信念引用，
## 结算时由整理者复核：矛盾走取代（SUPERSEDED），其余转正（ACTIVE）。

enum FactSource { NARRATOR, PLAYER }
enum FactWeight { MAJOR, MINOR }
enum FactStatus { ACTIVE, SUPERSEDED, PROVISIONAL }
enum FactVisibility { LAW, PUBLIC, LOCAL, SECRET }

const SOURCE_KEYS := ["narrator", "player"]
const WEIGHT_KEYS := ["major", "minor"]
const STATUS_KEYS := ["active", "superseded", "provisional"]
const VISIBILITY_KEYS := ["law", "public", "local", "secret"]


static func source_to_key(value: int) -> String:
	return SOURCE_KEYS[clampi(value, 0, SOURCE_KEYS.size() - 1)]


static func source_from_key(key: String) -> int:
	var index := SOURCE_KEYS.find(key)
	return index if index != -1 else FactSource.NARRATOR


## 便捷：按"是否玩家发明"给出来源键（解析器输出用）。
static func source_key(is_player: bool) -> String:
	return SOURCE_KEYS[1] if is_player else SOURCE_KEYS[0]


static func visibility_to_key(value: int) -> String:
	return VISIBILITY_KEYS[clampi(value, 0, VISIBILITY_KEYS.size() - 1)]


## 可见性默认推导：未标注时按作用域推导——无作用域（全局）→ PUBLIC（公共传闻），
## 有作用域 → LOCAL（本地限定）。SECRET 只能显式标注（知情者很少的事）。
static func visibility_default(has_scope: bool) -> int:
	return FactVisibility.PUBLIC if not has_scope else FactVisibility.LOCAL


static func visibility_from_key(key: String) -> int:
	var index := VISIBILITY_KEYS.find(key)
	return index if index != -1 else -1  # -1 = 未标注，走默认推导


static func weight_to_key(value: int) -> String:
	return WEIGHT_KEYS[clampi(value, 0, WEIGHT_KEYS.size() - 1)]


static func weight_from_key(key: String) -> int:
	var index := WEIGHT_KEYS.find(key)
	return index if index != -1 else FactWeight.MINOR


static func status_to_key(value: int) -> String:
	return STATUS_KEYS[clampi(value, 0, STATUS_KEYS.size() - 1)]


static func status_from_key(key: String) -> int:
	var index := STATUS_KEYS.find(key)
	return index if index != -1 else FactStatus.ACTIVE


var id := 0                     # 正典递增编号——闭集引用的凭证
var content := ""               # 事实表述（精确去重键）
var source: int = FactSource.NARRATOR
var weight: int = FactWeight.MINOR
var status: int = FactStatus.ACTIVE
var visibility: int = FactVisibility.PUBLIC  # 谁能知道（生成候选知识池的分层依据；运行期检索不受影响）
var superseded_by := 0          # 取代者的 id；未被取代 = 0
var scope: Array[String] = []   # 作用域实体 id 列表；空 = 全局
var created_at := ""
var embedding := PackedFloat32Array()  # 语义层向量（api 档；空 = 未嵌入，不参与向量召回）


## 这条事实是否挂在某实体名下（检索判断）。
func has_entity(entity_id: String) -> bool:
	return scope.has(entity_id)


func to_dict() -> Dictionary:
	var out := {
		"id": id,
		"content": content,
		"source": source_to_key(source),
		"weight": weight_to_key(weight),
		"status": status_to_key(status),
		"visibility": visibility_to_key(visibility),
		"superseded_by": superseded_by,
		"scope": scope,
		"created_at": created_at,
	}
	if not embedding.is_empty():
		out["embedding_b64"] = Marshalls.raw_to_base64(embedding.to_byte_array())
	return out


static func from_dict(data: Dictionary) -> CanonFact:
	var f := CanonFact.new()
	f.id = int(data.get("id", 0))
	f.content = str(data.get("content", ""))
	f.source = source_from_key(str(data.get("source", "narrator")))
	f.weight = weight_from_key(str(data.get("weight", "minor")))
	f.status = status_from_key(str(data.get("status", "active")))
	f.superseded_by = int(data.get("superseded_by", 0))
	var raw_scope: Variant = data.get("scope", [])
	if raw_scope is Array:
		for item in raw_scope:
			if item is String:
				if not (item as String).is_empty():
					f.scope.append(item)
			elif item is Dictionary:
				# 兼容旧的标签形式 [{type, entity_id}]
				var entity_id := str((item as Dictionary).get("entity_id", ""))
				if not entity_id.is_empty():
					f.scope.append(entity_id)
	f.visibility = visibility_from_key(str(data.get("visibility", "")))
	if f.visibility == -1:
		f.visibility = visibility_default(not f.scope.is_empty())
	f.created_at = str(data.get("created_at", ""))
	var b64 := str(data.get("embedding_b64", ""))
	if not b64.is_empty():
		f.embedding = Marshalls.base64_to_raw(b64).to_float32_array()
	return f
