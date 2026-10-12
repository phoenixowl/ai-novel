class_name EntityRegistry
extends RefCounted
## 实体注册表（Narration 层，存取器，world_model_design §2）：作用域的"挂靠点"。
## 一切可被事实关联的东西（Person / Location / Faction）都在注册表里，条目为 Models 层对象。
##   作者导入（每次启动从设定资料重建，是锚：不可被生成物覆盖）
##   玩家实体（id="player"，无知识库无记忆，只作"关于玩家的公开事实"的挂靠点）
##   动态生成（探索 discoveries → gen_ 前缀 id，游玩中诞生）
## 持久化 user://world/entities.json 只存注册表投影（六公共字段）——
## Person 的知识、Location 的 brief/npcs 由各自的存储负责，避免双写。

const DIR := "user://world"
const PATH := DIR + "/entities.json"
const PREFIX_GEN := "gen_"

static var _entries: Dictionary = {}  # entity_id(String) → Entity（与各域持有的是同一批对象）
static var _loaded := false


## 确保已从磁盘加载（所有公开 API 的入口守卫）。
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var data := JsonTool.read_json_file(PATH)
	if data.is_empty():
		return
	var raw: Variant = data.get("entities", [])
	if raw is Array:
		for item in raw:
			if item is Dictionary and str((item as Dictionary).get("entity_id", "")) != "":
				var e := Entity.new()
				e.load_common(item)
				e.type = Entity.type_from_key(str((item as Dictionary).get("type", "person")))
				_entries[e.entity_id] = e


static func save() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var arr: Array = []
	for id in _entries:
		arr.append((_entries[id] as Entity).to_registry_dict())
	JsonTool.write_json_file(PATH, {"entities": arr})


## 作者实体导入（world_model_design §2.2）：以设定资料构造的模型对象为准
## （覆盖文件加载的泛型条目），幂等。repository：已加载的设定资料库。
static func load_authors(repository: LoreRepository) -> void:
	_ensure_loaded()
	_entries[repository.player.entity_id] = repository.player
	for id in repository.character_ids():
		_entries[id] = repository.characters[id]
	for id in repository.scene_ids():
		_entries[id] = repository.scenes[id]
	for id in repository.factions:
		_entries[id] = repository.factions[id]


## 注册一个动态生成实体：分配 gen_ id 并标记 gen 来源。返回分配的 id。
static func register_gen(entity: Entity) -> String:
	_ensure_loaded()
	entity.entity_id = "%s%d" % [PREFIX_GEN, _next_gen_number()]
	entity.source = Entity.EntitySource.GEN
	_entries[entity.entity_id] = entity
	return entity.entity_id


## 注册时把名字登记为实体别名（生成物互认的去重锚点）。
static func add_alias(entity_id: String, alias: String) -> void:
	_ensure_loaded()
	var e := entry(entity_id)
	if e == null or alias.strip_edges().is_empty():
		return
	if not e.aliases.has(alias):
		e.aliases.append(alias)


## 按规范名或别名精确解析实体 id（闭集命名的唯一入口）；未命中返回空串。
static func resolve(name: String) -> String:
	_ensure_loaded()
	var trimmed := name.strip_edges()
	if trimmed.is_empty():
		return ""
	for id in _entries:
		var e := _entries[id] as Entity
		if e.canonical_name == trimmed:
			return id
		for alias in e.aliases:
			if alias == trimmed:
				return id
	return ""


## 在一段文本中扫描全部被提及的实体（规范名/别名精确匹配）。
## 返回 Array[Dictionary]{id, type_key, name}。text：待扫描的行动/历史文本。
static func scan_mentioned(text: String) -> Array[Dictionary]:
	_ensure_loaded()
	var out: Array[Dictionary] = []
	for id in _entries:
		var e := _entries[id] as Entity
		var names: Array[String] = [e.canonical_name]
		for alias in e.aliases:
			names.append(alias)
		for name in names:
			if not name.is_empty() and text.contains(name):
				out.append({"id": id, "type": Entity.type_to_key(e.type), "name": e.canonical_name})
				break
	return out


static func entry(entity_id: String) -> Entity:
	_ensure_loaded()
	return _entries.get(entity_id, null)


static func has(entity_id: String) -> bool:
	_ensure_loaded()
	return _entries.has(entity_id)


## 实体显示名（规范名缺失时回落 id）。
static func display_name(entity_id: String) -> String:
	var e := entry(entity_id)
	if e == null:
		return entity_id
	return e.canonical_name if not e.canonical_name.is_empty() else entity_id


## 某类型的全部 active 实体（调试页与清单用）。
static func entities_of_type(type: int) -> Array[Entity]:
	_ensure_loaded()
	var out: Array[Entity] = []
	for id in _entries:
		var e := _entries[id] as Entity
		if e.type == type and e.status == Entity.EntityStatus.ACTIVE:
			out.append(e)
	return out


## 清空全部内存状态（测试用；不删磁盘文件）。
static func reset_for_test() -> void:
	_entries = {}
	_loaded = true


static func _next_gen_number() -> int:
	var best := 0
	for id in _entries:
		var key := str(id)
		if key.begins_with(PREFIX_GEN):
			var tail := key.substr(PREFIX_GEN.length())
			if tail.is_valid_int():
				best = maxi(best, int(tail))
	return best + 1
