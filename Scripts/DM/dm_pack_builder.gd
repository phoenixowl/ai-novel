class_name DMPackBuilder
extends RefCounted
## 旁白材料包组装（DM 层，处理器）：冻结现场——按融合检索流水线收集本回合事实：
##   ① 话题栈喂料：扫描行动原文命中的实体入栈/续命（代词与称谓经此保持可激活）
##   ② FactRetriever.collect：骨架层信号（地点/全局/在场+交谈/话题栈）+ 语义层（BM25）
##      → 合并去重 → 统一评分排序 → 单一预算截断
## 组装完成后冻结不变。旧三通道（地点40/全局40/提及40）已由单一预算取代。


## 组装旁白材料包。action_text：玩家行动原文；turn：回合号；worldview/mainline：作者文本；
## location_id/location_name：当前位置（LocationStore/EntityRegistry 给出）；
## history：控制器近期流水行（进入查询文本）；present_ids：在场 NPC id；
## partner_id：当前交谈对象（可为空）；topics：话题栈（可空——测试/无栈场景）；
## neighbors：相邻地点 id（world.travel 的目标闭集）；player_info：玩家卡
## （称呼/身份/外观——叙述与裁决的对象）；player_state_lines：玩家状态
## 渲染行（player.state 工具的合法键来源）。返回冻结的包。
static func build(
		action_text: String,
		turn: int,
		worldview: String,
		mainline: String,
		location_id: String,
		location_name: String,
		history: Array[String],
		present_ids: Array[String] = [],
		partner_id: String = "",
		topics: TopicStack = null,
		query_vector: PackedFloat32Array = PackedFloat32Array(),
		neighbors: Array[String] = [],
		player_info := {},
		player_state_lines: Array[String] = [],
		ledger_lines: Array[String] = [],
) -> DMPack:
	var pack := DMPack.new()
	pack.turn_number = turn
	pack.action_text = action_text
	pack.worldview = worldview
	pack.mainline = mainline
	pack.location_id = location_id
	pack.location_name = location_name
	pack.neighbors = neighbors.duplicate()

	# ① 话题栈喂料：行动原文（完整输入）命中即入栈/续命——历史行的提及已在过去回合入栈
	var mentioned := EntityRegistry.scan_mentioned(action_text)
	var mentioned_ids: Array = []
	for m in mentioned:
		mentioned_ids.append(str((m as Dictionary).get("id", "")))
	if topics != null:
		topics.touch(mentioned_ids)

	# ② 融合检索：查询文本 = 行动原文 + 流水窗口（话题与相关度都按"刚发生的一切"衡量）
	var topic_ids: Array[String] = []
	if topics != null:
		topic_ids = topics.alive_ids()
	var query_text := action_text + " " + " ".join(history)
	var results := FactRetriever.collect(query_text, location_id, present_ids, partner_id,
		topic_ids, query_vector)
	for r in results:
		var fact: CanonFact = r["fact"]
		pack.facts.append(fact)
		pack.fact_tags[fact.id] = r["tags"]

	pack.history_lines = history.duplicate()
	pack.player_info = player_info.duplicate(true)
	pack.player_state_lines = player_state_lines.duplicate()
	pack.ledger_lines = ledger_lines.duplicate()
	pack.assembled_at = Time.get_time_string_from_system()
	return pack
