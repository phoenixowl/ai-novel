class_name NarrationPackBuilder
extends RefCounted
## 旁白材料包组装（Narration 层，处理器）：冻结现场——按 world_model_design §6.2 配方
## 收集本回合材料：当前地点作用域正典 + 全局提要 + 被提及实体作用域 + 本次探索流水。
## 检索全部确定性（CanonStore 作用域命中 + EntityRegistry 精确名匹配），
## 零概率调用。组装完成后冻结不变。

## 提及实体扫描的字符窗口（行动原文优先占用，余量给流水尾部——近期行先进窗口）
const SCAN_TEXT_LIMIT := 400


## 组装旁白材料包。action_text：玩家行动原文；turn：回合号；worldview/mainline：作者文本；
## location_id/location_name：当前位置（LocationStore/EntityRegistry 给出）；
## history：控制器近期流水行。
static func build(
		action_text: String,
		turn: int,
		worldview: String,
		mainline: String,
		location_id: String,
		location_name: String,
		history: Array[String],
) -> NarrationPack:
	var pack := NarrationPack.new()
	pack.turn_number = turn
	pack.action_text = action_text
	pack.worldview = worldview
	pack.mainline = mainline
	pack.location_id = location_id
	pack.location_name = location_name

	# ① 当前地点作用域：major 全量，minor 超预算保最近
	if not location_id.is_empty():
		pack.location_facts = CanonStore.facts_for_location(location_id)
	# ② 全局提要（跨地理边界的事实）：major 全量，minor 超预算保最近
	pack.global_digest = CanonStore.global_digest()
	# ③ 本回合被提及实体的作用域事实（行动原文 + 流水扫描；确定性精确匹配）
	# 扫描窗口 400 字符：行动原文优先，余量给流水的尾部（近期行优先进窗口）
	var history_text := " ".join(history)
	var scan_budget := maxi(0, SCAN_TEXT_LIMIT - action_text.length())
	if history_text.length() > scan_budget:
		history_text = history_text.substr(history_text.length() - scan_budget)
	var scan_text := action_text + " " + history_text
	pack.mentioned_entities = EntityRegistry.scan_mentioned(scan_text)
	var mentioned_ids: Array = []
	for m in pack.mentioned_entities:
		mentioned_ids.append(str((m as Dictionary).get("id", "")))
	if not mentioned_ids.is_empty():
		pack.entity_facts = CanonStore.facts_for_entities(mentioned_ids)

	# ⑤ 实体命名闭集（2026-10 移除：组装后从未进入任何提示词——防编造名单实际未生效；
	# DM 可点名的确定名单由"在场人物"行承担，恢复时重建 _naming_closure 并渲染进 dm_user_prompt）

	pack.history_lines = history.duplicate()
	pack.assembled_at = Time.get_time_string_from_system()
	return pack
