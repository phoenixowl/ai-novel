class_name GenKnowledgePool
extends RefCounted
## 候选知识池（Gen 层，确定性构建器）：生成一个新人物前，按"他的身份允许知道什么"
## 从正典里筛出一张带编号的清单——这是知识边界的物理边界：清单外的事实不注入
## 提示词，模型引用清单外编号会被丢弃，内容里提及知情集外的实体也会被丢弃。
## 三条规则（docs/gen_design.md §5.2）：
##   人人皆知的：visibility ∈ {LAW, PUBLIC}；
##   本地的：visibility = LOCAL 且作用域命中 home 地点；
##   圈子里的：visibility ∈ {LOCAL, SECRET} 且作用域命中知情集实体。
##   其余（包括未命中作用域的 SECRET）一律排除。


var facts: Array[CanonFact] = []  # 池内事实（渲染为 [1]..[N]）
var _index := {}                  # 编号(1..N) -> CanonFact


## 构建候选知识池。home：新人物的家/所在地 id；acquaintance：知情集实体 id 列表
## （同地点 NPC、玩家等）。确定性：同样输入同样输出。
static func build(home: String, acquaintance: Array) -> GenKnowledgePool:
	var pool := GenKnowledgePool.new()
	var seen := {}
	for fact in CanonStore.all_entries():
		if fact.status == CanonFact.FactStatus.SUPERSEDED:
			continue
		var hit := false
		match fact.visibility:
			CanonFact.FactVisibility.LAW, CanonFact.FactVisibility.PUBLIC:
				hit = true
			CanonFact.FactVisibility.LOCAL:
				hit = (not home.is_empty() and fact.scope.has(home)) or _scope_hits(fact, acquaintance)
			CanonFact.FactVisibility.SECRET:
				hit = _scope_hits(fact, acquaintance)
		if hit and not seen.has(fact.id):
			seen[fact.id] = true
			pool.facts.append(fact)
	for i in pool.facts.size():
		pool._index[i + 1] = pool.facts[i]
	return pool


static func _scope_hits(fact: CanonFact, entity_ids: Array) -> bool:
	for id in entity_ids:
		if fact.scope.has(str(id)):
			return true
	return false


## 按编号取事实（越界返回 null——闭集校验的基础）。
func fact_of(ref: int) -> CanonFact:
	return _index.get(ref, null)


## 渲染为提示词用的编号清单行。
func render_lines() -> Array[String]:
	var lines: Array[String] = []
	for i in facts.size():
		var f := facts[i]
		lines.append("· [%d]（%s）%s" % [i + 1, _visibility_label(f), f.content])
	return lines


func _visibility_label(f: CanonFact) -> String:
	match f.visibility:
		CanonFact.FactVisibility.LAW:
			return "人人皆知"
		CanonFact.FactVisibility.PUBLIC:
			return "公共传闻"
		CanonFact.FactVisibility.LOCAL:
			return "本地之事"
		CanonFact.FactVisibility.SECRET:
			return "圈内隐秘"
	return ""
