class_name KnowledgeEntry
extends RefCounted
## 知识条目（Models 层）：NPC 信念层的一条记录——"我相信 / 知道 / 听说的一件事"。
## 三种形态（kind）：CARD（作者卡初始）/ SUBJECTIVE（主观：谎言、印象、传闻）/ REF（指向正典的信念引用）。
## 富模型：确定性信任算术（佐证/矛盾/复活）在本类上；stale 判定只读正典，不做任何写操作。

enum EntryKind { CARD, SUBJECTIVE, REF }
enum TrustLevel { DOUBT, SOMEWHAT, ABSOLUTE }
enum EntryStatus { ACTIVE, VOIDED }
enum EntryOrigin { CARD, DIALOGUE }

const KIND_KEYS := ["card", "subjective", "ref"]
const TRUST_KEYS := ["怀疑", "比较相信", "绝对可信"]
const TRUST_VOID_KEY := "已失效"   # 卡面上的写法：映射为 VOIDED 状态 + DOUBT 信任
const STATUS_KEYS := ["active", "voided"]
const ORIGIN_KEYS := ["card", "dialogue"]


static func kind_to_key(value: int) -> String:
	return KIND_KEYS[clampi(value, 0, KIND_KEYS.size() - 1)]


static func kind_from_key(key: String) -> int:
	var index := KIND_KEYS.find(key)
	return index if index != -1 else EntryKind.SUBJECTIVE


static func trust_to_key(value: int) -> String:
	return TRUST_KEYS[clampi(value, 0, TRUST_KEYS.size() - 1)]


static func trust_from_key(key: String) -> int:
	var index := TRUST_KEYS.find(key)
	return index if index != -1 else TrustLevel.DOUBT


static func status_to_key(value: int) -> String:
	return STATUS_KEYS[clampi(value, 0, STATUS_KEYS.size() - 1)]


static func status_from_key(key: String) -> int:
	var index := STATUS_KEYS.find(key)
	return index if index != -1 else EntryStatus.ACTIVE


static func origin_to_key(value: int) -> String:
	return ORIGIN_KEYS[clampi(value, 0, ORIGIN_KEYS.size() - 1)]


static func origin_from_key(key: String) -> int:
	var index := ORIGIN_KEYS.find(key)
	return index if index != -1 else EntryOrigin.DIALOGUE


static func no_change(cause: String) -> Dictionary:
	return {"changed": false, "before": "", "after": "", "cause": cause}


var seq := 0                     # 日志编号：卡面 1..N，习得 ≥10000（belief_updates 的 ref 指它）
var kind: int = EntryKind.SUBJECTIVE
var content := ""
var evidence := ""               # 逐字依据（习得条目存玩家原话节选）
var speaker := ""                # 来源标签（常识/目睹/听说：某人/来客/手动）
var trust: int = TrustLevel.DOUBT
var status: int = EntryStatus.ACTIVE
var origin: int = EntryOrigin.DIALOGUE
var turn := 0
var session := 0
var links: Array = []            # 谁佐证过的记录（"佐证：某人"）
var note := ""
var fact_id := 0                 # 仅 REF：指向 CanonFact.id
var learned_at := ""


## 佐证：同来源无效；VOIDED → 复活为 DOUBT；否则信任升一档（上限 ABSOLUTE）。
func apply_corroboration(by_speaker: String) -> Dictionary:
	if speaker == by_speaker:
		return no_change("同来源佐证无效")
	var before := trust_to_key(trust)
	if status == EntryStatus.VOIDED:
		status = EntryStatus.ACTIVE
		trust = TrustLevel.DOUBT
		return {"changed": true, "before": before + "〔已失效〕", "after": trust_to_key(trust), "cause": "佐证复活"}
	links.append("佐证：" + by_speaker)
	var after := _shift(1)
	trust = after
	return {"changed": trust_to_key(trust) != before, "before": before, "after": trust_to_key(trust), "cause": "佐证"}


## 矛盾：信任降一档（下限 DOUBT）。
func apply_contradiction() -> Dictionary:
	var before := trust_to_key(trust)
	var after := _shift(-1)
	trust = after
	return {"changed": trust_to_key(trust) != before, "before": before, "after": trust_to_key(trust), "cause": "矛盾"}


## 过时（stale）：REF 条目指向的正典已被取代——不删除、不改信任，渲染时加标注。
func is_stale() -> bool:
	if kind != EntryKind.REF:
		return false
	var fact := CanonStore.entry(fact_id)
	return fact != null and fact.status == CanonFact.FactStatus.SUPERSEDED


func _shift(delta: int) -> int:
	return clampi(trust + delta, 0, TRUST_KEYS.size() - 1)


func to_dict() -> Dictionary:
	return {
		"seq": seq,
		"kind": kind_to_key(kind),
		"content": content,
		"evidence": evidence,
		"speaker": speaker,
		"trust": trust_to_key(trust),
		"status": status_to_key(status),
		"origin": origin_to_key(origin),
		"turn": turn,
		"session": session,
		"links": links,
		"note": note,
		"fact_id": fact_id,
		"learned_at": learned_at,
	}


static func from_dict(data: Dictionary) -> KnowledgeEntry:
	var e := KnowledgeEntry.new()
	e.seq = int(data.get("seq", 0))
	e.kind = kind_from_key(str(data.get("kind", "")))
	e.content = str(data.get("content", ""))
	e.evidence = str(data.get("evidence", ""))
	e.speaker = str(data.get("speaker", ""))
	e.trust = trust_from_key(str(data.get("trust", "怀疑")))
	e.status = status_from_key(str(data.get("status", "active")))
	e.origin = origin_from_key(str(data.get("origin", "dialogue")))
	e.turn = int(data.get("turn", 0))
	e.session = int(data.get("session", 0))
	var raw_links: Variant = data.get("links", [])
	e.links = raw_links if raw_links is Array else []
	e.note = str(data.get("note", ""))
	e.fact_id = int(data.get("fact_id", 0))
	e.learned_at = str(data.get("learned_at", ""))
	return e
