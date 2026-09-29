class_name KnowledgeJournal
extends RefCounted
## 知识日志（Lore 层）：来源锚定的知识系统核心。
## 每个 NPC 一本只追加日志；条目 = 知识表述（content）+ 逐字依据（evidence，习得条目）+
## 来源（speaker）+ 信任（trust）。运行时零开放生成：模型只给闭集引用与（可校验的）
## 逐字证据，表述总结（summary→content）交给模型但证据锚定真实发言。
##
## 条目 seq 规则：卡片初始条目按卡片顺序 1..N（会话内稳定）；习得条目从 10000 持久递增。
## 持久化 = 人物运行时快照 user://characters/<npc_id>.json 的 journal 区（全量条目 + 记忆）：
## 对话学习与编辑页保存都写快照（统一写路径）；旧版 user://journals/<npc_id>.json 仅兼容读取。
##
## 信任算术（全部确定性，引擎定事实）：
##   独立来源佐证 → +1 档（上限 绝对可信）；同来源佐证无效
##   矛盾 → -1 档（下限 怀疑）
##   voided 条目被佐证 → 复活为 怀疑
##   玩家言论永不直接产生 绝对可信 / voided（void 预留给阶段二引擎事件）

const SnapshotStore := preload("res://Scripts/Lore/snapshot_store.gd")

## 信任梯（索引即强度：0 < 1 < 2）
const TRUST_LADDER := ["怀疑", "比较相信", "绝对可信"]
## 卡片上的“已失效”：映射为 status=voided + trust=怀疑
const TRUST_VOIDED := "已失效"
const STATUS_ACTIVE := "active"
const STATUS_VOIDED := "voided"
## 习得条目 seq 起点（1..9999 保留给卡片条目）
const LEARNED_SEQ_BASE := 10000
## 材料包注入的条目预算（超出触发佐证链合并压缩）
const PACK_BUDGET := 80
## 材料包展示的最近会话摘要条数
const SESSION_LINES := 3

var _entries: Array[Dictionary] = []   # 全部条目（卡片 + 习得），按 seq 升序
var _memories: Array[Dictionary] = []  # 记忆条目 [{turn, session, text, time}]（每轮一条，只追加）
var _next_learned_seq := LEARNED_SEQ_BASE


# ———— 构建 ————


## 追加一条卡片初始条目（对话开始时按卡片顺序调用）。
## content：知识表述；speaker：来源（常识/目睹/听说：某人）；trust：信任档；
## voided：卡片是否标注“已失效”。返回分配的 seq（1..N）。
func add_card_entry(content: String, speaker: String, trust: String, voided := false) -> int:
	var mapped_trust := trust
	var status := STATUS_ACTIVE
	if voided or trust == TRUST_VOIDED:
		mapped_trust = TRUST_LADDER[0]
		status = STATUS_VOIDED
	var seq := _entries.size() + 1  # 卡片条目顺序分配（与卡片顺序一致）
	_entries.append({
		"seq": seq,
		"content": content,
		"evidence": "",
		"speaker": speaker,
		"trust": mapped_trust,
		"origin": "card",
		"turn": 0,
		"session": 0,
		"links": [],
		"status": status,
		"note": "",
	})
	return seq


## 习得一条新知识（默认怀疑）。返回分配的 seq（≥10000）。
## content：模型总结的知识表述；evidence：逐字依据（玩家原话节选，引擎已校验）；
## speaker：来源（通常是“来客”）；turn/session：习得位置；note：模型的理由。
func learn(content: String, evidence: String, speaker: String, turn: int, session: int, note := "") -> int:
	var seq := _next_learned_seq
	_next_learned_seq += 1
	_entries.append({
		"seq": seq,
		"content": content,
		"evidence": evidence,
		"speaker": speaker,
		"trust": TRUST_LADDER[0],
		"origin": "dialogue",
		"turn": turn,
		"session": session,
		"links": [],
		"status": STATUS_ACTIVE,
		"note": note,
	})
	return seq


# ———— 查询 ————


## 按 seq 取条目（Dictionary，注意调用方不得原地修改）；不存在返回空 Dictionary。
func entry(seq: int) -> Dictionary:
	for e in _entries:
		if int(e.get("seq", 0)) == seq:
			return e
	return {}


func has_seq(seq: int) -> bool:
	return not entry(seq).is_empty()


## 全部条目数（含 voided）
func size() -> int:
	return _entries.size()


## active 条目（按 seq 升序）
func active_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _entries:
		if str(e.get("status", STATUS_ACTIVE)) == STATUS_ACTIVE:
			out.append(e)
	return out


## 全部条目（含 voided；编辑页与写回用）。注意调用方不得原地修改。
func entries_all() -> Array[Dictionary]:
	return _entries


## 材料包用条目：active 全量；超过 PACK_BUDGET 时压缩——
## 有佐证链（links 指向更早条目）的合并到链首（content 保留链首、links 累计、trust 取最强）。
func entries_for_pack() -> Array[Dictionary]:
	var active := active_entries()
	if active.size() <= PACK_BUDGET:
		return active
	# 压缩：习得条目若 links 指向已有条目，折叠进链首
	var merged := {}
	var heads: Array[Dictionary] = []
	for e in active:
		var links: Array = e.get("links", [])
		var head_seq := 0
		for link in links:
			if int(link) < int(e.get("seq", 0)) and has_seq(int(link)):
				head_seq = int(link)
				break
		if head_seq > 0:
			var head := _entries[_index_of(head_seq)]
			var count := int(head.get("corroboration_count", 1)) + 1
			head["corroboration_count"] = count
			head["trust"] = _stronger(str(head.get("trust", "")), str(e.get("trust", "")))
			merged[int(e.get("seq", 0))] = true
		else:
			heads.append(e)
	return heads


## 调试/材料包展示行（含 voided 标注）
func to_display_lines() -> Array[String]:
	var lines: Array[String] = []
	for e in _entries:
		var tag := "[%d]（%s · %s）" % [int(e.get("seq", 0)), str(e.get("speaker", "")), str(e.get("trust", ""))]
		if str(e.get("status", STATUS_ACTIVE)) == STATUS_VOIDED:
			tag += "〔已失效〕"
		var extra := ""
		var count := int(e.get("corroboration_count", 0))
		if count > 1:
			extra += "（%d 方说法一致）" % count
		lines.append("· %s%s：%s" % [tag, extra, str(e.get("content", ""))])
	return lines


# ———— 信任算术 ————


## 佐证：独立来源（by_speaker 与条目 speaker 不同）→ +1 档；voided → 复活为怀疑。
## seq：目标条目；by_speaker：佐证者。返回 {changed, before, after, cause}。
func corroborate(seq: int, by_speaker: String) -> Dictionary:
	var e := entry(seq)
	if e.is_empty():
		return _no_change("条目不存在")
	if str(e.get("speaker", "")) == by_speaker:
		return _no_change("同来源佐证无效")
	var before := str(e.get("trust", TRUST_LADDER[0]))
	if str(e.get("status", STATUS_ACTIVE)) == STATUS_VOIDED:
		e["status"] = STATUS_ACTIVE
		e["trust"] = TRUST_LADDER[0]
		return {"changed": true, "before": before + "〔已失效〕", "after": TRUST_LADDER[0], "cause": "佐证复活"}
	(e.get("links", []) as Array).append(_speaker_seq_hint(by_speaker))
	var after := _shift(before, 1)
	e["trust"] = after
	return {"changed": after != before, "before": before, "after": after, "cause": "佐证"}


## 矛盾：-1 档（下限怀疑）。seq：目标条目。返回 {changed, before, after, cause}。
func contradict(seq: int) -> Dictionary:
	var e := entry(seq)
	if e.is_empty():
		return _no_change("条目不存在")
	var before := str(e.get("trust", TRUST_LADDER[0]))
	var after := _shift(before, -1)
	e["trust"] = after
	return {"changed": after != before, "before": before, "after": after, "cause": "矛盾"}


# ———— 记忆层（每轮一条，确定性生成，只追加） ————


## 最近 SESSION_LINES 条记忆的渲染行（材料包记忆区用）。
func memory_lines() -> Array[String]:
	var lines: Array[String] = []
	var start := maxi(0, _memories.size() - SESSION_LINES)
	for i in range(start, _memories.size()):
		var m: Dictionary = _memories[i]
		lines.append("· " + str(m.get("text", "")))
	return lines


## 已记录的记忆条数。
func memory_count() -> int:
	return _memories.size()


## 记忆文本列表（编辑页用）。
func memory_texts() -> Array[String]:
	var out: Array[String] = []
	for m in _memories:
		out.append(str(m.get("text", "")))
	return out


## 整表替换记忆（编辑页保存；与旧文本相同的条目保留原时间戳）。
func set_memories(texts: Array) -> void:
	var old_times := {}
	for m in _memories:
		old_times[str(m.get("text", ""))] = m.get("time", "")
	_memories.clear()
	for raw in texts:
		var text := str(raw).strip_edges()
		if text.is_empty():
			continue
		_memories.append({
			"text": text,
			"time": str(old_times.get(text, Time.get_datetime_string_from_system())),
		})


## 追加一段整理好的记忆文本（由引擎在对话结算后调用 LLM 生成后传入）。
## text：LLM 归纳的整段记忆表述；session：会话序号。
func add_memory(text: String, _session: int) -> void:
	_memories.append({
		"text": text,
		"time": Time.get_datetime_string_from_system(),
	})


# ———— 持久化（人物运行时快照 user://characters/<npc_id>.json 的 journal 区） ————


## 尝试从人物快照整体载入 journal 区（存在即接管知识日志与记忆）。
## 返回是否接管（false = 无快照，调用方以卡面知识起步）。
func load_snapshot(npc_id: String) -> bool:
	var data := SnapshotStore.read_journal(npc_id)
	if data.is_empty():
		return false
	_entries.clear()
	_memories.clear()
	var raw_entries: Variant = data.get("knowledge", [])
	if raw_entries is Array:
		for item in raw_entries:
			if item is Dictionary:
				var e: Dictionary = item
				e["seq"] = int(e.get("seq", 0))
				e["links"] = e.get("links", []) if e.get("links", []) is Array else []
				_entries.append(e)
	_entries.sort_custom(func(a, b): return int(a.get("seq", 0)) < int(b.get("seq", 0)))
	var raw_memories: Variant = data.get("memories", [])
	if raw_memories is Array:
		for m in raw_memories:
			if m is Dictionary:
				_memories.append(m)
	_next_learned_seq = maxi(int(data.get("next_seq", LEARNED_SEQ_BASE)), _max_entry_seq() + 1)
	return true


## 全量落盘 journal 区到人物快照（对话学习与编辑保存的统一写路径）。
func save(npc_id: String) -> void:
	SnapshotStore.write_journal(npc_id, _entries, _memories, _next_learned_seq)


## 旧版兼容：读回 user://journals/<npc_id>.json 的习得条目与记忆，追加到当前日志。
## 仅在无人物快照时由 _build_journal_for 调用；该文件不再新写。
## 文件不存在或损坏时静默跳过（日志为空起步）。
func load_learned(npc_id: String) -> void:
	var path := "user://journals/%s.json" % npc_id
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed
	_next_learned_seq = maxi(int(data.get("next_seq", LEARNED_SEQ_BASE)), LEARNED_SEQ_BASE)
	var raw_memories: Variant = data.get("memories", [])
	if raw_memories is Array:
		for m in raw_memories:
			if m is Dictionary:
				_memories.append(m)
	var raw_entries: Variant = data.get("entries", [])
	if raw_entries is Array:
		for item in raw_entries:
			if item is Dictionary:
				var e: Dictionary = item
				e["seq"] = int(e.get("seq", 0))
				e["links"] = e.get("links", []) if e.get("links", []) is Array else []
				_entries.append(e)
	_entries.sort_custom(func(a, b): return int(a.get("seq", 0)) < int(b.get("seq", 0)))


# ———— 编辑（编辑页保存用） ————


## 原地更新条目内容/来源/信任（编辑页保存）。trust="已失效" 映射为 voided 状态；
## 其余合法档恢复 active。返回条目是否存在。
func update_entry(seq: int, content: String, speaker: String, trust: String) -> bool:
	var e := entry(seq)
	if e.is_empty():
		return false
	e["content"] = content
	e["speaker"] = speaker
	if trust == TRUST_VOIDED:
		e["trust"] = TRUST_LADDER[0]
		e["status"] = STATUS_VOIDED
	else:
		e["trust"] = trust if TRUST_LADDER.has(trust) else TRUST_LADDER[0]
		e["status"] = STATUS_ACTIVE
	return true


## 仅保留 seq 在集合内的条目（编辑页全量保存的删除语义：未列出的即删除）。
func retain_seqs(seqs: Dictionary) -> void:
	var kept: Array[Dictionary] = []
	for e in _entries:
		if seqs.has(int(e.get("seq", 0))):
			kept.append(e)
	_entries = kept


# ———— 内部 ————


## 当前最大条目 seq（快照载入后保证习得序号不回退）。
func _max_entry_seq() -> int:
	var best := 0
	for e in _entries:
		best = maxi(best, int(e.get("seq", 0)))
	return best


## 信任档位移：delta +1/-1，钳位到梯内。trust：当前档；delta：位移量。
func _shift(trust: String, delta: int) -> String:
	var index := TRUST_LADDER.find(trust)
	if index == -1:
		index = 0
	index = clampi(index + delta, 0, TRUST_LADDER.size() - 1)
	return TRUST_LADDER[index]


## 两条信任档取较强者
func _stronger(a: String, b: String) -> String:
	return a if TRUST_LADDER.find(a) >= TRUST_LADDER.find(b) else b


## links 里记录“谁佐证过”（不存 seq 存来源名，避免跨会话悬空）
func _speaker_seq_hint(speaker: String) -> String:
	return "佐证：" + speaker


func _index_of(seq: int) -> int:
	for i in _entries.size():
		if int(_entries[i].get("seq", 0)) == seq:
			return i
	return -1


func _no_change(cause: String) -> Dictionary:
	return {"changed": false, "before": "", "after": "", "cause": cause}
