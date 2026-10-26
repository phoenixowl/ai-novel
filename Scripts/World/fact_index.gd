class_name FactIndex
extends RefCounted
## 事实检索的内置 BM25 索引（World 层，语义层 builtin 档）：对全部现行事实的表述
## 建倒排索引，纯本地、确定性、零外部依赖。中文按相邻两字切词，英文/数字按连续段。
## 以 CanonStore.version() 为缓存键：正典任何变更后首次查询时惰性重建。


const K1 := 1.5
const B := 0.75

static var _postings := {}   # token -> Array[int]（fact_id）
static var _tf := {}         # fact_id -> {token: 词频}
static var _len := {}        # fact_id -> 文档词数
static var _df := {}         # token -> 含该词的文档数
static var _doc_count := 0
static var _avg_len := 0.0
static var _version := -1


## 正典变更后由 CanonStore 触发（经版本号自动感知，无需显式调用）。
static func invalidate() -> void:
	_version = -1


## 查询与文本词面最相关的至多 top_k 条事实。返回 [{fact_id: int, score: float}]，
## 分数降序；无命中返回空。分数未经归一化，消费方（FactRetriever）自行按最大值归一。
static func query(text: String, top_k := 8) -> Array[Dictionary]:
	_ensure_built()
	var q_tokens := _tokenize(text)
	if q_tokens.is_empty() or _doc_count == 0:
		return []
	var scores := {}
	var seen := {}
	for t in q_tokens:
		if seen.has(t):
			continue
		seen[t] = true
		var df := int(_df.get(t, 0))
		if df == 0:
			continue
		var idf: float = log(1.0 + (float(_doc_count) - float(df) + 0.5) / (float(df) + 0.5))
		for fid in _postings.get(t, []):
			var freq := int((_tf[fid] as Dictionary).get(t, 0))
			var dl := float(_len.get(fid, 0))
			var denom := freq + K1 * (1.0 - B + B * dl / _avg_len)
			var s: float = idf * (freq * (K1 + 1.0)) / denom
			scores[fid] = float(scores.get(fid, 0.0)) + s
	var out: Array[Dictionary] = []
	for fid in scores:
		out.append({"fact_id": int(fid), "score": float(scores[fid])})
	out.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	if out.size() > top_k:
		out = out.slice(0, top_k)
	return out


static func _ensure_built() -> void:
	var v := CanonStore.version()
	if _version == v:
		return
	_version = v
	_postings = {}
	_tf = {}
	_len = {}
	_df = {}
	_doc_count = 0
	_avg_len = 0.0
	var total := 0
	for fact in CanonStore.all_entries():
		if fact.status == CanonFact.FactStatus.SUPERSEDED:
			continue
		var toks := _tokenize(fact.content)
		var counts := {}
		for t in toks:
			counts[t] = int(counts.get(t, 0)) + 1
		_tf[fact.id] = counts
		_len[fact.id] = toks.size()
		total += toks.size()
		_doc_count += 1
		for t in counts:
			if not _postings.has(t):
				_postings[t] = []
			(_postings[t] as Array).append(fact.id)
			_df[t] = int(_df.get(t, 0)) + 1
	_avg_len = float(total) / float(_doc_count) if _doc_count > 0 else 0.0


## 切词：CJK 字符按相邻两字（单字成段时取单字）；ASCII 字母数字连续段小写整体成词；
## 其余（标点/空白）为分隔符。
static func _tokenize(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var lower := text.to_lower()
	var ascii_run := ""
	var cjk_run := ""
	for i in lower.length():
		var c := lower[i]
		if _is_cjk(c):
			_flush_ascii(ascii_run, out)
			ascii_run = ""
			cjk_run += c
		elif _is_alnum(c):
			_flush_cjk(cjk_run, out)
			cjk_run = ""
			ascii_run += c
		else:
			_flush_ascii(ascii_run, out)
			_flush_cjk(cjk_run, out)
			ascii_run = ""
			cjk_run = ""
	_flush_ascii(ascii_run, out)
	_flush_cjk(cjk_run, out)
	return out


static func _flush_ascii(run: String, out: PackedStringArray) -> void:
	if not run.is_empty():
		out.append(run)


static func _flush_cjk(run: String, out: PackedStringArray) -> void:
	if run.is_empty():
		return
	if run.length() == 1:
		out.append(run)
		return
	for i in run.length() - 1:
		out.append(run.substr(i, 2))


static func _is_cjk(c: String) -> bool:
	var u := c.unicode_at(0)
	return (u >= 0x3400 and u <= 0x9FFF) or (u >= 0xF900 and u <= 0xFAFF)


static func _is_alnum(c: String) -> bool:
	var u := c.unicode_at(0)
	return (u >= 0x30 and u <= 0x39) or (u >= 0x61 and u <= 0x7A)
