class_name LocationStore
extends RefCounted
## 位置图（World 层，存取器，world_model_design §3）：世界的骨架——结构层，引擎读写。
## 节点即 Models 层的 Location 对象（与 EntityRegistry 持有同一批对象）；本类另持边与当前位置。
## 作者场景卡导入为初始节点：links 声明邻接，未声明 links 的场景默认连通到第一个场景（防死锁）；
## 首次进入的进场描述由旁白生成后冻结为 brief（§3.3），再次进入零延迟零调用。
## 移动零模型参与（引擎校验邻接即达）。
## 持久化 saves/world/locations.json（节点只序列化 brief/npcs 等运行期字段）。

static func path() -> String:
	return GamePaths.locations_path()

static var _locations: Dictionary = {}  # entity_id(String) → Location（与注册表同对象）
static var _edges: Array = []           # [{a, b}] 无向
static var _current := ""
static var _loaded := false


## 确保已从磁盘加载（所有公开 API 的入口守卫）。
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var data := JsonTool.read_json_file(path())
	if data.is_empty():
		return
	var raw_locations: Variant = data.get("locations", [])
	if raw_locations is Array:
		for item in raw_locations:
			if item is Dictionary and str((item as Dictionary).get("entity_id", "")) != "":
				var loc := Location.from_scene_dict(item)
				_locations[loc.entity_id] = loc
	var raw_edges: Variant = data.get("edges", [])
	if raw_edges is Array:
		for item in raw_edges:
			if item is Dictionary:
				var d: Dictionary = item
				_add_edge(str(d.get("a", "")), str(d.get("b", "")))
	_current = str(data.get("current", ""))


static func save() -> void:
	DirAccess.make_dir_recursive_absolute(GamePaths.world_dir())
	var arr: Array = []
	for id in _locations:
		arr.append((_locations[id] as Location).to_node_dict())
	JsonTool.write_json_file(path(), {"locations": arr, "edges": _edges, "current": _current})


## 作者场景导入（world_model_design §3.1）：幂等——已有节点保留 brief 与 npcs，
## 只刷新作者字段并补边补在场表。repository：已加载的设定资料库。
static func load_authors(repository: LoreRepository) -> void:
	_ensure_loaded()
	var scene_ids := repository.scene_ids()
	if scene_ids.is_empty():
		return
	var first := scene_ids[0]
	for id in scene_ids:
		var author: Location = repository.scenes[id]
		var existing: Location = _locations.get(id, null)
		var loc := existing if existing != null else author
		if existing != null:
			existing.merge_author(author)
		else:
			_locations[id] = loc
		for npc_id in author.npcs:
			if not loc.npcs.has(npc_id):
				loc.npcs.append(npc_id)
		if author.links.is_empty():
			_add_edge(id, first)  # 未声明路线：默认连通第一个场景（防死锁兜底）
		else:
			for other in author.links:
				if repository.scenes.has(other):
					_add_edge(id, other)
	if _current.is_empty() or not _locations.has(_current):
		_current = first


## 校验邻接并移动（§3.2：无 LLM，不相邻不可达）。返回是否移动成功。
static func travel_to(entity_id: String) -> bool:
	_ensure_loaded()
	if not _locations.has(entity_id) or not has_edge(_current, entity_id):
		return false
	_current = entity_id
	return true


## 当前位置 id（无地点时为空串）。
static func current() -> String:
	_ensure_loaded()
	return _current


static func has(entity_id: String) -> bool:
	_ensure_loaded()
	return _locations.has(entity_id)


## 相邻地点 id 列表（无向；移动按钮数据源）。
static func neighbors(entity_id: String) -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for edge in _edges:
		var d: Dictionary = edge
		if str(d.get("a", "")) == entity_id:
			out.append(str(d.get("b", "")))
		elif str(d.get("b", "")) == entity_id:
			out.append(str(d.get("a", "")))
	return out


static func has_edge(a: String, b: String) -> bool:
	_ensure_loaded()
	for edge in _edges:
		var d: Dictionary = edge
		if (str(d.get("a", "")) == a and str(d.get("b", "")) == b) \
				or (str(d.get("a", "")) == b and str(d.get("b", "")) == a):
			return true
	return false


## 某地点的进场描述（未生成过为空串）。
static func brief(entity_id: String) -> String:
	_ensure_loaded()
	var loc: Location = _locations.get(entity_id, null)
	return loc.brief if loc != null else ""


## 按 id 取地点对象（不存在返回 null；对话场景解析的回退来源之一）。
static func location(entity_id: String) -> Location:
	_ensure_loaded()
	return _locations.get(entity_id, null)


## 冻结进场描述（首次生成后调用，§3.3：同一地点两次进门不能长得不一样）。
static func set_brief(entity_id: String, text: String) -> void:
	_ensure_loaded()
	var loc: Location = _locations.get(entity_id, null)
	if loc != null:
		loc.brief = text


## 是否已有冻结的进场描述。
static func has_brief(entity_id: String) -> bool:
	return not brief(entity_id).is_empty()


## 新增动态生成的地点节点（discoveries 落地）：挂载 Location 对象并与 origin 连边。
static func add_gen_location(location: Location, origin: String) -> void:
	_ensure_loaded()
	if not location.entity_id.is_empty():
		_locations[location.entity_id] = location
	_add_edge(origin, location.entity_id)


## 补一条无向边（已知地点之间发现新路线；重复幂等）。
static func add_edge(a: String, b: String) -> void:
	_ensure_loaded()
	_add_edge(a, b)


## 在场人物（§3.5：作者场景卡声明 + 生成人物落位）。
static func npcs_at(entity_id: String) -> Array[String]:
	_ensure_loaded()
	var loc: Location = _locations.get(entity_id, null)
	var out: Array[String] = []
	if loc != null:
		for npc_id in loc.npcs:
			out.append(npc_id)
	return out


## 把人物落位到某地点（重复落位幂等）。
static func place_npc(entity_id: String, npc_id: String) -> void:
	_ensure_loaded()
	var loc: Location = _locations.get(entity_id, null)
	if loc != null and not loc.npcs.has(npc_id):
		loc.npcs.append(npc_id)


## 某人物现在站在哪（对话材料包按 NPC 所在地检索世界事实；不在任何地方返回空串）。
static func location_of_npc(npc_id: String) -> String:
	_ensure_loaded()
	for id in _locations:
		if npcs_at(id).has(npc_id):
			return id
	return ""


## 清空全部内存状态（测试用；不删磁盘文件）。
static func reset_for_test() -> void:
	_locations = {}
	_edges = []
	_current = ""
	_loaded = true


## 移除全部动态生成的地点节点及其邻接边（"清除动态生成内容"入口）并落盘。
## 当前位置若是 gen 地点，回落到首个作者场景。
static func remove_gen_locations() -> void:
	_ensure_loaded()
	var victims: Array[String] = []
	for id in _locations:
		if id.begins_with(EntityRegistry.PREFIX_GEN):
			victims.append(id)
	for id in victims:
		_locations.erase(id)
	_edges = _edges.filter(_edge_is_author)
	if _current.begins_with(EntityRegistry.PREFIX_GEN):
		_current = ""
		for id in _locations:
			_current = id
			break
	if not victims.is_empty():
		save()


## 边过滤谓词：两端都不是 gen 地点（remove_gen_locations 用）。
static func _edge_is_author(edge: Dictionary) -> bool:
	var a_ok := not str(edge.get("a", "")).begins_with(EntityRegistry.PREFIX_GEN)
	var b_ok := not str(edge.get("b", "")).begins_with(EntityRegistry.PREFIX_GEN)
	return a_ok and b_ok


static func _add_edge(a: String, b: String) -> void:
	if a.is_empty() or b.is_empty() or a == b or has_edge(a, b):
		return
	_edges.append({"a": a, "b": b})
