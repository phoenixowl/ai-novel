class_name CanonStore
extends RefCounted
## 世界事实库（World 层，存取器）：旁白系统的"正典"——一切被确立的世界事实。
## 条目为 CanonFact 模型（Models 层），本类负责检索、去重、取代链与持久化。
## 临时事实（PROVISIONAL，DM 行动回合申报）与正式事实同库同检索——探索期间
## 即可被 DM 后续回合与对话学习引用；结算由整理者点名复核：confirmed 转正、
## 未点名移除、矛盾取代（永久正典的守门权在整理者手里）。
## 事实被推翻时标记 superseded 并指向取代者，不删除——保留审计链（与信念"只追加"哲学一致）。
## 正典只收客观的、第三人称可验证的陈述；任何人的内心属于对话域的信念层（硬线②）。
##
## 检索（world_model_design §6.1）：确定性评分——按作用域命中取条目，各作用域独立预算；
## 全局提要只取 major。注入配方由各材料包组装器决定，本类只提供取数口。
##
## 持久化 user://world/canon.json；惰性加载：任何公开 API 首次调用时自动读盘并播种
## 作者正典（settings/canon.json）。对话域对本库只读（硬线②）。


const DIR := "user://world"
const PATH := DIR + "/canon.json"
## 作者正典：世界客观真理的底座，惰性加载后播种进内存——establish 的精确文本去重
## 保证幂等；浏览器删除的作者事实会在下次启动回来（res:// 是只读模板的锚语义）。
const AUTHOR_CANON_PATH := "res://settings/canon.json"
## 单作用域 minor 注入预算（major 全量注入；超出的次要事实只保留最近确立的）
const SCOPE_BUDGET := 40
## 全局提要 minor 上限（major 全量注入；每条一行，跨地理边界生效的事实）
const GLOBAL_DIGEST_CAP := 40

static var _entries: Array[CanonFact] = []
static var _next_id := 1
static var _loaded := false
static var _version := 0  # 正典变更计数器：FactIndex 等派生结构的缓存键
static var _embed_model := ""  # 生成现存向量所用模型名（换模型时由调用方清空向量）


## 正典版本号（每次任何写入 +1；派生结构据此感知变更、惰性重建）。
static func version() -> int:
	return _version


## 现存向量对应的嵌入模型名（随 canon.json 持久化）。
static func embedding_model() -> String:
	return _embed_model


## 记录嵌入模型名（嵌入管线完成后调用；随下次 save 落盘）。
static func note_embedding_model(model: String) -> void:
	_embed_model = model


## 清空全部事实向量（换嵌入模型 / provider 关闭时调用；下次 save 落盘）。
static func clear_embeddings() -> void:
	var changed := false
	for fact in _entries:
		if not fact.embedding.is_empty():
			fact.embedding = PackedFloat32Array()
			changed = true
	if changed:
		_embed_model = ""
		_version += 1


## 尚未嵌入向量、需要补齐的事实（现行 + 临时）。
static func facts_missing_embeddings() -> Array[CanonFact]:
	_ensure_loaded()
	var out: Array[CanonFact] = []
	for fact in _entries:
		if fact.status != CanonFact.FactStatus.SUPERSEDED and fact.embedding.is_empty():
			out.append(fact)
	return out


## 确保已从磁盘加载（所有公开 API 的入口守卫）。
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var data := JsonTool.read_json_file(PATH)
	if not data.is_empty():
		_next_id = maxi(1, int(data.get("next_id", 1)))
		_embed_model = str(data.get("embedding_model", ""))
		var raw_entries: Variant = data.get("entries", [])
		if raw_entries is Array:
			for item in raw_entries:
				if item is Dictionary:
					_entries.append(CanonFact.from_dict(item))
			_version += 1
	_seed_authors()


## 作者正典播种：settings/canon.json 的世界事实 establish 进内存（去重幂等，不覆盖运行期事实）。
static func _seed_authors() -> void:
	var data := JsonTool.read_json_file(AUTHOR_CANON_PATH)
	for raw in data.get("facts", []):
		if not (raw is Dictionary):
			continue
		var d: Dictionary = raw
		var scope_ids: Array = []
		var raw_scope: Variant = d.get("scope", [])
		if raw_scope is Array:
			for item in raw_scope:
				scope_ids.append(str(item))
		establish(str(d.get("content", "")), str(d.get("source", "narrator")),
			str(d.get("weight", "minor")), scope_ids)


static func save() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var entries: Array = []
	for fact in _entries:
		entries.append(fact.to_dict())
	JsonTool.write_json_file(PATH, {"next_id": _next_id, "embedding_model": _embed_model,
		"entries": entries})


# ———— 写入 ————


## 确立一条新事实（精确文本去重：同表述的非取代条目直接复用）。返回条目 id。
## content：事实表述；source_key：narrator / player；weight_key：major / minor；
## scope_ids：作用域实体 id 列表（空 = 全局）；provisional：true = DM 行动回合申报的
## 临时事实（立即入典可检索，结算复核后转正）。确认性写入（结算/作者播种）逐字命中
## 临时条目时顺带转正——重述即确认。
static func establish(content: String, source_key: String, weight_key: String, scope_ids: Array = [], provisional := false) -> int:
	_ensure_loaded()
	var text := content.strip_edges()
	if text.is_empty():
		return 0
	for fact in _entries:
		if fact.status != CanonFact.FactStatus.SUPERSEDED and fact.content == text:
			if not provisional and fact.status == CanonFact.FactStatus.PROVISIONAL:
				fact.status = CanonFact.FactStatus.ACTIVE
				_version += 1
			return fact.id
	var fact := CanonFact.new()
	fact.id = _next_id
	_next_id += 1
	fact.content = text
	fact.source = CanonFact.source_from_key(source_key)
	fact.weight = CanonFact.weight_from_key(weight_key)
	fact.status = CanonFact.FactStatus.PROVISIONAL if provisional else CanonFact.FactStatus.ACTIVE
	for scope_id in scope_ids:
		var sid := str(scope_id).strip_edges()
		if not sid.is_empty() and not fact.scope.has(sid):
			fact.scope.append(sid)
	fact.created_at = Time.get_datetime_string_from_system()
	_entries.append(fact)
	_version += 1
	return fact.id


## 用新表述取代既有事实（旧条目标记 superseded 并指向新条目，不删除；新条目继承作用域）。
## ref：被取代条目的 id（调用方已做闭集校验）——现行与临时条目均可被取代
## （结算复核路径：整理者推翻 DM 的申报）。返回 {old_id, new_id}；ref 无效时退化为新增。
static func supersede(ref: int, new_content: String, source_key: String, weight_key := "minor") -> Dictionary:
	_ensure_loaded()
	var old := entry(ref)
	if old == null or old.status == CanonFact.FactStatus.SUPERSEDED:
		return {"old_id": 0, "new_id": establish(new_content, source_key, weight_key)}
	var new_id := establish(new_content, source_key, weight_key, old.scope)
	if new_id == old.id:
		return {"old_id": ref, "new_id": new_id}  # 文本与某 active 条目相同（含自身）——无需取代
	old.status = CanonFact.FactStatus.SUPERSEDED
	old.superseded_by = new_id
	_version += 1
	return {"old_id": ref, "new_id": new_id}


## 按精确文本查找现行条目（对话学习路径的实体消解入口）；未命中返回 0。
## 含临时事实：DM 刚申报的事实现场即可被 NPC 学习引用（结算后被取代则信念自动标过时）。
static func find_by_content(content: String) -> int:
	_ensure_loaded()
	var text := content.strip_edges()
	if text.is_empty():
		return 0
	for fact in _entries:
		if fact.status != CanonFact.FactStatus.SUPERSEDED and fact.content == text:
			return fact.id
	return 0


## 结算复核收尾（点名制）：confirmed_ids 里的临时事实转正，其余临时条目移除——
## 未被整理者点名的申报不进入永久正典（审计由调用方的事件流水承担）。
## 返回 {confirmed: 转正数, discarded: 移除数}。
static func settle_provisional(confirmed_ids: Array) -> Dictionary:
	_ensure_loaded()
	var wanted := {}
	for id in confirmed_ids:
		wanted[int(id)] = true
	var confirmed := 0
	var discarded := 0
	for fact in _entries.duplicate():  # erase 会修改 _entries，遍历其快照
		if fact.status != CanonFact.FactStatus.PROVISIONAL:
			continue
		if wanted.has(fact.id):
			fact.status = CanonFact.FactStatus.ACTIVE
			confirmed += 1
		elif erase(fact.id):
			discarded += 1
	if confirmed > 0 or discarded > 0:
		_version += 1
	return {"confirmed": confirmed, "discarded": discarded}


## 删除条目（事实库浏览器与结算移除未点名临时申报共用）：其余条目指向它的取代链置 0，
## 不留悬空引用。注意：这是正典"只追加"哲学的例外，仅供引擎结算与作者/调试编辑入口调用。
static func erase(id: int) -> bool:
	_ensure_loaded()
	var index := -1
	for i in _entries.size():
		if _entries[i].id == id:
			index = i
			break
	if index == -1:
		return false
	_entries.remove_at(index)
	for fact in _entries:
		if fact.superseded_by == id:
			fact.superseded_by = 0
	_version += 1
	return true


# ———— 查询 ————


## 按 id 取条目（不存在返回 null）。
static func entry(id: int) -> CanonFact:
	_ensure_loaded()
	for fact in _entries:
		if fact.id == id:
			return fact
	return null


## 全部条目（含 superseded；调试页与测试用）。
static func all_entries() -> Array[CanonFact]:
	_ensure_loaded()
	return _entries


## 现行条目数（ACTIVE，不含临时；测试用）。
static func active_count() -> int:
	_ensure_loaded()
	var count := 0
	for fact in _entries:
		if fact.status == CanonFact.FactStatus.ACTIVE:
			count += 1
	return count


## 某地点作用域的 active 事实（§6.2 ①）：major 全量注入，minor 超预算保最近确立的。
static func facts_for_location(loc_id: String, minor_cap := SCOPE_BUDGET) -> Array[CanonFact]:
	return _scoped_facts([loc_id], minor_cap)


## 某组实体作用域的 active 事实（§6.2 ③：本回合被提及实体名下的事实）。
static func facts_for_entities(entity_ids: Array, cap := SCOPE_BUDGET) -> Array[CanonFact]:
	_ensure_loaded()
	var wanted := {}
	for id in entity_ids:
		wanted[str(id)] = true
	var hits: Array[CanonFact] = []
	for fact in _entries:
		if fact.status == CanonFact.FactStatus.SUPERSEDED:
			continue
		for scope_id in fact.scope:
			if wanted.has(scope_id):
				hits.append(fact)
				break
	return _cap_newest(hits, cap)


## 全局事实提要（§6.2 ②：无作用域的事实，跨地理边界生效）——major 全量，minor 超预算保最近。
static func global_digest(minor_cap := GLOBAL_DIGEST_CAP) -> Array[CanonFact]:
	_ensure_loaded()
	var hits: Array[CanonFact] = []
	for fact in _entries:
		if fact.status == CanonFact.FactStatus.SUPERSEDED:
			continue
		if not fact.scope.is_empty():
			continue
		hits.append(fact)
	return _split_by_weight_and_cap(hits, minor_cap)


# ———— 内部 ————


## 按 id 升序返回；超预算保最近确立的（id 最大）。
static func _cap_newest(hits: Array[CanonFact], cap: int) -> Array[CanonFact]:
	hits.sort_custom(func(a, b): return a.id < b.id)
	if hits.size() > cap:
		hits = hits.slice(hits.size() - cap)
	return hits


static func _scoped_facts(scope_ids: Array, minor_cap: int) -> Array[CanonFact]:
	_ensure_loaded()
	var hits: Array[CanonFact] = []
	for fact in _entries:
		if fact.status == CanonFact.FactStatus.SUPERSEDED:
			continue
		for scope_id in scope_ids:
			if fact.has_entity(str(scope_id)):
				hits.append(fact)
				break
	return _split_by_weight_and_cap(hits, minor_cap)


## 权重分层预算：major 全量保留，minor 超预算保最近确立的（id 最大）；输出按 id 升序。
static func _split_by_weight_and_cap(hits: Array[CanonFact], minor_cap: int) -> Array[CanonFact]:
	var out: Array[CanonFact] = []
	var minors: Array[CanonFact] = []
	for fact in hits:
		if fact.weight == CanonFact.FactWeight.MAJOR:
			out.append(fact)
		else:
			minors.append(fact)
	out.append_array(_cap_newest(minors, minor_cap))
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


# ———— 测试辅助 ————


## 一键重置为作者正典（settings/canon.json）：清空全部运行期事实与取代链，
## 删除磁盘文件后重新播种。返回播种条数。
## 信念引用悬空时按创建时快照渲染（与 erase 同语义）；人物信念不受影响（那属于「重置记忆/恢复卡面」）。
static func reset_to_authors() -> int:
	_entries = []
	_next_id = 1
	_loaded = true
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	_seed_authors()
	_version += 1
	return _entries.size()


## 清空全部状态（测试用；不删磁盘文件；此后不会重新读盘/播种）。
static func reset_for_test() -> void:
	_entries = []
	_next_id = 1
	_loaded = true
	_embed_model = ""
	_version += 1


## 清空内存并强制重载（读盘 + 作者播种；测试用）。
static func reload_for_test() -> void:
	_entries = []
	_next_id = 1
	_loaded = false
	_ensure_loaded()
