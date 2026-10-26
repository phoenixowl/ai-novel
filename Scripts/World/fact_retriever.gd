class_name FactRetriever
extends RefCounted
## DM 材料包的事实融合检索器（World 层）：骨架层（世界状态信号，确定性）+
## 语义层（BM25 内容相关度）→ 合并去重 → 统一评分排序 → 预算截断。
## 分数表（与 docs/retrieval_design.md 一致）：
##   基础分 major=10 / minor=4；S1 地点 +6；S3 在场/交谈 +8；S4 话题 +5；S2 全局 +0；
##   临时 +2；语义 = 归一化 BM25 × 8。major 截断时一律保留，预算只淘汰 minor。


const BUDGET := 32
const SCORE_MAJOR := 10.0
const SCORE_MINOR := 4.0
const BONUS_LOCATION := 6.0
const BONUS_PRESENT := 8.0
const BONUS_TOPIC := 5.0
const BONUS_PROVISIONAL := 2.0
const SEMANTIC_WEIGHT_BM25 := 8.0
const SEMANTIC_WEIGHT_VECTOR := 10.0
const SEMANTIC_TOP_K := 8


## 收集本回合材料包的事实。返回 [{fact: CanonFact, score: float, tags: PackedStringArray}]
## 按分数降序（同分 id 升序），已按预算截断。tags 描述每条事实"为何在此"：
## 此地 / 全局 / 在场·名字 / 话题·名字 / 相关。
## 语义层二选一：query_vector 非空走向量 cosine（×10，只覆盖已嵌入的事实），
## 否则回落本地 BM25（×8）。
static func collect(query_text: String, location_id: String, present_ids: Array[String],
		partner_id: String, topic_ids: Array[String],
		query_vector: PackedFloat32Array = PackedFloat32Array()) -> Array[Dictionary]:
	var wanted_present := {}
	for id in present_ids:
		wanted_present[str(id)] = true
	if not partner_id.is_empty():
		wanted_present[partner_id] = true
	var wanted_topic := {}
	for id in topic_ids:
		wanted_topic[str(id)] = true

	# 骨架层：任一信号命中即入候选池
	var cands := {}  # fact_id -> {fact, score, tags}
	for fact in CanonStore.all_entries():
		if fact.status == CanonFact.FactStatus.SUPERSEDED:
			continue
		var score := SCORE_MAJOR if fact.weight == CanonFact.FactWeight.MAJOR else SCORE_MINOR
		var tags := PackedStringArray()
		var hit := false
		if not location_id.is_empty() and fact.scope.has(location_id):
			score += BONUS_LOCATION
			tags.append("此地")
			hit = true
		if fact.scope.is_empty():
			tags.append("全局")  # S2 全局事实天然在场，无加分
			hit = true
		var present_hits := _scope_names(fact, wanted_present)
		if not present_hits.is_empty():
			score += BONUS_PRESENT
			tags.append("在场·" + "、".join(present_hits))
			hit = true
		var topic_hits := _scope_names(fact, wanted_topic)
		if not topic_hits.is_empty():
			score += BONUS_TOPIC
			tags.append("话题·" + "、".join(topic_hits))
			hit = true
		if fact.status == CanonFact.FactStatus.PROVISIONAL:
			score += BONUS_PROVISIONAL
		if hit:
			cands[fact.id] = {"fact": fact, "score": score, "tags": tags}

	# 语义层：向量（api 档）或 BM25（builtin 档/向量失败回落）二选一，加"相关"标记与分数
	if query_vector.size() > 0:
		for fact in CanonStore.all_entries():
			if fact.status == CanonFact.FactStatus.SUPERSEDED or fact.embedding.is_empty():
				continue
			var sim := cosine(query_vector, fact.embedding)
			if sim <= 0.05:
				continue  # 近乎正交 = 无关
			var add := sim * SEMANTIC_WEIGHT_VECTOR
			var entry: Dictionary = cands.get(fact.id, {})
			if entry.is_empty():
				var vscore := SCORE_MAJOR if fact.weight == CanonFact.FactWeight.MAJOR else SCORE_MINOR
				if fact.status == CanonFact.FactStatus.PROVISIONAL:
					vscore += BONUS_PROVISIONAL
				cands[fact.id] = {"fact": fact, "score": vscore + add,
					"tags": PackedStringArray(["相关"])}
			else:
				entry["score"] = float(entry["score"]) + add
				var vtags: PackedStringArray = entry["tags"]  # Packed*Array 值类型：改完写回
				vtags.append("相关")
				entry["tags"] = vtags
	else:
		var hits := FactIndex.query(query_text, SEMANTIC_TOP_K)
		var top := 0.0
		for h in hits:
			top = maxf(top, float(h["score"]))
		if top > 0.0:
			for h in hits:
				var fact := CanonStore.entry(int(h["fact_id"]))
				if fact == null or fact.status == CanonFact.FactStatus.SUPERSEDED:
					continue
				var add: float = (float(h["score"]) / top) * SEMANTIC_WEIGHT_BM25
				var entry: Dictionary = cands.get(fact.id, {})
				if entry.is_empty():
					var score := SCORE_MAJOR if fact.weight == CanonFact.FactWeight.MAJOR else SCORE_MINOR
					if fact.status == CanonFact.FactStatus.PROVISIONAL:
						score += BONUS_PROVISIONAL
					cands[fact.id] = {"fact": fact, "score": score + add,
						"tags": PackedStringArray(["相关"])}
				else:
					entry["score"] = float(entry["score"]) + add
					var tags: PackedStringArray = entry["tags"]  # Packed*Array 值类型：改完写回
					tags.append("相关")
					entry["tags"] = tags

	var out: Array[Dictionary] = []
	for id in cands:
		out.append(cands[id])
	out.sort_custom(_rank)
	if out.size() > BUDGET:
		out = _truncate(out)
	return out


## 预算截断：major 一律保留，minor 按分数降序保留到预算上限，再整体重排。
static func _truncate(ranked: Array[Dictionary]) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	var minors: Array[Dictionary] = []
	var majors := 0
	for e in ranked:
		if (e["fact"] as CanonFact).weight == CanonFact.FactWeight.MAJOR:
			kept.append(e)
			majors += 1
		else:
			minors.append(e)
	var allowance := maxi(0, BUDGET - majors)
	for i in mini(allowance, minors.size()):
		kept.append(minors[i])
	kept.sort_custom(_rank)
	return kept


static func _rank(a: Dictionary, b: Dictionary) -> bool:
	if float(a["score"]) != float(b["score"]):
		return float(a["score"]) > float(b["score"])
	return (a["fact"] as CanonFact).id < (b["fact"] as CanonFact).id


## 事实作用域与目标集合的交集的显示名（保持作用域声明顺序，去重）。
static func _scope_names(fact: CanonFact, wanted: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for sid in fact.scope:
		if wanted.has(sid) and not out.has(EntityRegistry.display_name(sid)):
			out.append(EntityRegistry.display_name(sid))
	return out


## 向量余弦相似度（0≈无关，1=同向）；维度不一致或零向量返回 0。
static func cosine(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.is_empty() or b.size() != a.size():
		return 0.0
	var dot := 0.0
	var na := 0.0
	var nb := 0.0
	for i in a.size():
		dot += a[i] * b[i]
		na += a[i] * a[i]
		nb += b[i] * b[i]
	if na <= 0.0 or nb <= 0.0:
		return 0.0
	return dot / sqrt(na * nb)
