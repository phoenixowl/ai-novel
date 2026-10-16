class_name Person
extends Entity
## 人物模型（Models 层）：作者卡 + 运行时信念/记忆的统一数据结构。
## 信念的确定性算术在 KnowledgeEntry 上；seq 簿记在此；快照读写由 SnapshotStore/CharacterController 负责。

const LEARNED_SEQ_BASE := 10000

var identity := ""                       # 世界内身份（注入对话提示词）
var profile := ""                        # 人设（注入对话提示词静态层）
var appearance := ""                     # 外观（仅玩家使用，NPC 为空）
var affinity := 0                        # 作者卡初始好感度（运行期值在 AffinityStore）
var faction_ids := PackedStringArray()   # 所属组织 id
var memberships: Array[Dictionary] = []  # 解析后的 {faction: Faction, position: String}
var knowledge: Array[KnowledgeEntry] = []  # 信念列表（唯一存放处）
var memories: Array[Dictionary] = []     # [{text, time}]
var is_player := false                   # 玩家实体标记（无知识/记忆、不可对话）
var author_knowledge: Array[Dictionary] = []  # 作者卡原始知识（重置与消解的原料）
var _next_learned_seq := LEARNED_SEQ_BASE


func _init() -> void:
	type = EntityType.PERSON
	source = EntitySource.AUTHOR


## 从作者卡/玩家卡 JSON 构造（knowledge 先以 CARD 形态起步，随后与正典消解）。
static func from_card_dict(data: Dictionary, player := false) -> Person:
	var p := Person.new()
	p.is_player = player
	p.load_common(data)
	if p.entity_id.is_empty() and player:
		p.entity_id = "player"
	p.identity = str(JsonTool.pick(data, ["identity", "身份"], ""))
	p.profile = str(JsonTool.pick(data, ["profile", "设定"], ""))
	p.appearance = str(JsonTool.pick(data, ["appearance", "外观"], ""))
	p.affinity = int(JsonTool.pick(data, ["affinity", "好感度"], 0))
	for faction_id in JsonTool.pick_strings(data, ["factions", "组织"]):
		var fid := faction_id.strip_edges()
		if not fid.is_empty() and not p.faction_ids.has(fid):
			p.faction_ids.append(fid)
	var raw_knowledge: Variant = JsonTool.pick(data, ["knowledge", "知识"], [])
	if raw_knowledge is Array:
		for item in raw_knowledge:
			if item is Dictionary:
				p.author_knowledge.append(item)
	p.reset_knowledge_to_author()
	return p


## 用作者卡原始知识重建信念列表（与正典逐字一致的条目升级为信念引用）。
func reset_knowledge_to_author() -> void:
	knowledge = []
	var seq := 1
	for raw in author_knowledge:
		var item := raw as Dictionary
		var content := str(JsonTool.pick(item, ["content", "内容", "quote"], ""))
		if content.is_empty():
			continue
		var entry := KnowledgeEntry.new()
		entry.seq = seq
		seq += 1
		entry.kind = KnowledgeEntry.EntryKind.CARD
		entry.origin = KnowledgeEntry.EntryOrigin.CARD
		entry.content = content
		entry.speaker = str(JsonTool.pick(item, ["source", "来源"], "常识"))
		var trust_key := str(JsonTool.pick(item, ["trust", "信任", "belief", "可信度"], "比较相信"))
		if trust_key == KnowledgeEntry.TRUST_VOID_KEY:
			entry.trust = KnowledgeEntry.TrustLevel.DOUBT
			entry.status = KnowledgeEntry.EntryStatus.VOIDED
		else:
			entry.trust = KnowledgeEntry.trust_from_key(trust_key)
		knowledge.append(entry)
	resolve_knowledge_against_canon()


## 与正典逐字一致的卡面知识升级为信念引用（world_model_design §5.1：引用而非复制品）。
func resolve_knowledge_against_canon() -> void:
	for entry in knowledge:
		if entry.kind != KnowledgeEntry.EntryKind.CARD or entry.status != KnowledgeEntry.EntryStatus.ACTIVE:
			continue
		var fact_id := CanonStore.find_by_content(entry.content)
		if fact_id > 0:
			entry.kind = KnowledgeEntry.EntryKind.REF
			entry.fact_id = fact_id
			entry.note = "作者卡初始知识"


# ———— 信念簿记（信任算术在 KnowledgeEntry 上） ————


func entry(seq: int) -> KnowledgeEntry:
	for e in knowledge:
		if e.seq == seq:
			return e
	return null


func has_seq(seq: int) -> bool:
	return entry(seq) != null


func active_knowledge() -> Array[KnowledgeEntry]:
	var out: Array[KnowledgeEntry] = []
	for e in knowledge:
		if e.status == KnowledgeEntry.EntryStatus.ACTIVE:
			out.append(e)
	return out


## 卡面形态的初始条目（作者导入路径）。
func add_card_entry(content: String, speaker: String, trust: String, voided := false) -> int:
	var e := KnowledgeEntry.new()
	e.seq = knowledge.size() + 1
	e.kind = KnowledgeEntry.EntryKind.CARD
	e.origin = KnowledgeEntry.EntryOrigin.CARD
	e.content = content
	e.speaker = speaker
	if voided or trust == KnowledgeEntry.TRUST_VOID_KEY:
		e.trust = KnowledgeEntry.TrustLevel.DOUBT
		e.status = KnowledgeEntry.EntryStatus.VOIDED
	else:
		e.trust = KnowledgeEntry.trust_from_key(trust)
	knowledge.append(e)
	return e.seq


## 习得一条主观知识（默认怀疑）。
func learn_entry(content: String, evidence: String, speaker: String, turn: int, session: int, note := "") -> int:
	return _append_learned(KnowledgeEntry.EntryKind.SUBJECTIVE, 0, content, evidence, speaker, turn, session, note)


## 习得一条信念引用（所学内容实为正典事实时）。
func learn_ref(fact_id: int, content: String, evidence: String, speaker: String, turn: int, session: int, note := "") -> int:
	return _append_learned(KnowledgeEntry.EntryKind.REF, fact_id, content, evidence, speaker, turn, session, note)


func _append_learned(kind: int, fact_id: int, content: String, evidence: String, speaker: String,
		turn: int, session: int, note := "") -> int:
	var e := KnowledgeEntry.new()
	e.seq = _next_learned_seq
	_next_learned_seq += 1
	e.kind = kind
	e.fact_id = fact_id
	e.content = content
	e.evidence = evidence
	e.speaker = speaker
	e.turn = turn
	e.session = session
	e.note = note
	e.learned_at = Time.get_datetime_string_from_system()
	knowledge.append(e)
	return e.seq


func corroborate(seq: int, by_speaker: String) -> Dictionary:
	var e := entry(seq)
	if e == null:
		return KnowledgeEntry.no_change("条目不存在")
	return e.apply_corroboration(by_speaker)


func contradict(seq: int) -> Dictionary:
	var e := entry(seq)
	if e == null:
		return KnowledgeEntry.no_change("条目不存在")
	return e.apply_contradiction()


## 编辑页修改条目（trust_key 取信任档键或"已失效"）。返回条目是否存在。
func update_entry(seq: int, content: String, speaker: String, trust_key: String) -> bool:
	var e := entry(seq)
	if e == null:
		return false
	e.content = content
	e.speaker = speaker
	# 信念引用被改写后不再指向正典：表述与所指事实不一致（或事实已删除）时
	# 降级为主观条目，否则正典变动时会按 fact_id 误标"过时"（is_stale 只看指向）
	if e.kind == KnowledgeEntry.EntryKind.REF and e.fact_id > 0:
		var fact := CanonStore.entry(e.fact_id)
		if fact == null or fact.content != content.strip_edges():
			e.kind = KnowledgeEntry.EntryKind.SUBJECTIVE
			e.fact_id = 0
	if trust_key == KnowledgeEntry.TRUST_VOID_KEY:
		e.trust = KnowledgeEntry.TrustLevel.DOUBT
		e.status = KnowledgeEntry.EntryStatus.VOIDED
	else:
		e.trust = KnowledgeEntry.trust_from_key(trust_key)
		e.status = KnowledgeEntry.EntryStatus.ACTIVE
	return true


## 仅保留 seq 在集合内的条目（编辑页全量保存的删除语义）。
func retain_seqs(seqs: Dictionary) -> void:
	var kept: Array[KnowledgeEntry] = []
	for e in knowledge:
		if seqs.has(e.seq):
			kept.append(e)
	knowledge = kept


# ———— 记忆 ————


func memory_lines() -> Array[String]:
	var lines: Array[String] = []
	var start := maxi(0, memories.size() - 3)  # 最近 3 条（SESSION_LINES）
	for i in range(start, memories.size()):
		lines.append("· " + str((memories[i] as Dictionary).get("text", "")))
	return lines


func memory_count() -> int:
	return memories.size()


func memory_texts() -> Array[String]:
	var out: Array[String] = []
	for m in memories:
		out.append(str((m as Dictionary).get("text", "")))
	return out


## 整表替换记忆（编辑页保存；与旧文本相同的条目保留原时间戳）。
func set_memories(texts: Array) -> void:
	var old_times := {}
	for m in memories:
		old_times[str((m as Dictionary).get("text", ""))] = (m as Dictionary).get("time", "")
	memories = []
	for raw in texts:
		var text := str(raw).strip_edges()
		if text.is_empty():
			continue
		memories.append({"text": text, "time": str(old_times.get(text, Time.get_datetime_string_from_system()))})


## 追加一段结算生成的记忆。
func add_memory(text: String) -> void:
	memories.append({"text": text, "time": Time.get_datetime_string_from_system()})


# ———— 快照序列化边界 ————


func knowledge_dicts() -> Array:
	var out: Array = []
	for e in knowledge:
		out.append(e.to_dict())
	return out


## 用快照 journal 区整体接管信念与记忆（对话开始/编辑页的接管语义）。
func load_journal_dicts(knowledge_dicts: Array, memory_dicts: Array, next_seq_hint: int) -> void:
	knowledge = []
	if knowledge_dicts is Array:
		for item in knowledge_dicts:
			if item is Dictionary:
				knowledge.append(KnowledgeEntry.from_dict(item))
	memories = []
	if memory_dicts is Array:
		for m in memory_dicts:
			if m is Dictionary:
				memories.append(m)
	_next_learned_seq = maxi(maxi(next_seq_hint, _max_knowledge_seq() + 1), LEARNED_SEQ_BASE)


func next_seq_value() -> int:
	return _next_learned_seq


func _max_knowledge_seq() -> int:
	var best := 0
	for e in knowledge:
		best = maxi(best, e.seq)
	return best


## 对话材料包"交谈对象"段用的玩家信息。
func to_prompt_dict() -> Dictionary:
	return {"name": canonical_name, "identity": identity, "appearance": appearance}


## 作者卡写回格式（仅作者字段；aliases/factions/affinity 一并带回，写回不丢组织归属）。
func to_author_dict() -> Dictionary:
	var knowledge_out: Array = []
	for e in knowledge:
		knowledge_out.append({
			"content": e.content,
			"source": e.speaker,
			"trust": KnowledgeEntry.TRUST_VOID_KEY if e.status == KnowledgeEntry.EntryStatus.VOIDED
				else KnowledgeEntry.trust_to_key(e.trust),
		})
	var out := {
		"id": entity_id,
		"name": canonical_name,
		"identity": identity,
		"profile": profile,
		"knowledge": knowledge_out,
	}
	if not aliases.is_empty():
		out["aliases"] = aliases
	if affinity != 0:
		out["affinity"] = affinity
	if not faction_ids.is_empty():
		out["factions"] = Array(faction_ids)
	return out
