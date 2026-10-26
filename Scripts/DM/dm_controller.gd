class_name DMController
extends Node
## DM / 世界控制器（DM 层，autoload "DM"）：统一入口的裁判层（DM）。
## 玩家的任何输入先经 DM 裁决（PURPOSE_DM，一次 LLM 调用）：
##   action → 行动域：DM 直接叙述行动后果（原旁白回合职责并入 DM）
##   speech / mixed → 人物域：DM 拆出对 NPC 说的话，调度 DialogueController；
##     mixed 时 DM 先叙述行动部分，再把话送给人物（边聊边做）
##   reject → 纯注入/元输入，退回玩家（顶替原输入审查）
## 对话进行中：未点名的话语默认送当前对象；明确冲别人说的话 → 自动结算当前对话
## （学习与记忆落档完成后）再开启新对话。纯行动不打断对话。
##
## 世界流水（叙述事件 + 对话事件副本混排）的唯一数据源是 WorldStream 全局存取器；
## 本控制器只负责写入与广播。
##
## 行动回合申报的持久事实走临时通道（输出契约 facts → CanonStore PROVISIONAL）：
## 立即入典、可检索、可被对话学习引用；只报状态变化——环境氛围类申报被提示词
## 申报标准与引擎确定性闸门（条数/长度）双重拦截。结算时由整理者逐条复核：
## confirmed 点名才转正，未点名的移除，矛盾走取代。
## DM 始终没有改写既有事实的权力（facts 只能新增）。
## 探索结算（cmd_settle_exploration）：事实整理者 agent 通读完整记录复核与提取世界事实；
## 进场描述（DESCRIBING）：首次进入一次性生成后冻结为 brief——两者职责不变。
## 对话域对正典只读（硬线②）；DM 对 NPC 信念不读不写（硬线①）。
##
## 状态机五态：WAITING_PLAYER / DM_RESOLVING / DESCRIBING / EXTRACTING / ENDED。
## 对外交互：UI 经 EventBus 在 DMEvents 集线器上连命令/收事件。


enum State {WAITING_PLAYER, DM_RESOLVING, DESCRIBING, EXTRACTING, ENDED}

const EVENT_LOG_DIR := GamePaths.EVENT_LOG_DIR
## 进场描述注入的近期流水行数（叙述与对话混排）。
const DM_HISTORY_LINES := 10
## DM 材料包的流水窗口（混排行数）：持久后果已由 DM 申报进正典（临时事实通道），
## 流水只保留近期片段——结算提取仍读全量记录（WorldStream.session_lines）。
const DM_HISTORY_WINDOW := 14
## DM 单轮 facts 申报条数上限（超出拦截——一回合叙述极少确立更多持久事实，超额多为总结式噪声）
const DECLARE_PER_TURN_CAP := 3
## DM 单条申报长度上限（超长多为叙述句摘录而非状态陈述，拦截）
const DECLARE_CONTENT_MAX := 80
## 进场描述冻结的长度上限（护栏：与旧 discoveries.brief 同一量级）
const ENTRY_BRIEF_MAX := 200
## 结算提取注入正典的上限（超出保最近确立的；取代闭集以此为限）
const EXTRACT_CANON_CAP := 300

var repository: LoreRepository  # 统一入口 LoreRepository.shared()——作者数据全项目一份
var prompt_builder := DMPromptBuilder.new()

var state: State = State.WAITING_PLAYER
var turn_number := 0

var _events: DMEvents      # 事件集线器（_ready 时经总线取得）
var _dialogue_events: DialogueEvents  # 人物域集线器（DM 调度与回声订阅）
var _character_events: CharacterEvents  # 人物域集线器（lore_changed 订阅）
var _audit_log := AuditLog.new()
var _audit_open := false
var _game_config := GameConfig.new()
var _embed_cfg := EmbeddingConfig.new()  # 语义检索向量档配置（builtin 默认；api 需第二家 Key）
var _embed_busy := false                 # 向量补齐在途标记（防重入）
var _partner_id := ""             # 当前交谈对象（空 = 无对话）
var _topics := TopicStack.new()   # 话题栈：最近被提及实体（骨架层 S4 信号；随探索重置）
var _dialogue_busy := false       # 人物域生成中（门控统一输入）
var _dialogue_settling := false   # 对话结算中（dialogue_ended 引擎事件到信号之间的窗口）
var _pending_switch: Dictionary = {}  # 自动切换对话：{npc, speech}，等结算完成后续送

static var _shared: DMController


static func shared() -> DMController:
	return _shared


## 测试/嵌入式环境兜底：autoload 未就绪时手动创建并注册共享实例（挂到当前场景树）
static func create_shared() -> DMController:
	if _shared == null:
		_shared = DMController.new()
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			(loop as SceneTree).root.add_child(_shared)
	return _shared


func _ready() -> void:
	_shared = self
	_events = EventBus.resolve().hub(DMEvents) as DMEvents
	_dialogue_events = EventBus.resolve().hub(DialogueEvents) as DialogueEvents
	repository = LoreRepository.shared()  # 统一入口：作者数据全项目一份
	_game_config.load_from_disk()
	_embed_cfg.load_from_disk()
	_sync_embedding_model()
	# 世界结构层：作者实体与场景导入注册表/位置图（幂等，gen 数据不受影响）
	EntityRegistry.load_authors(repository)
	LocationStore.load_authors(repository)
	# 人物域广播：设定被编辑后重载设定资料（与对话域对称，见 _on_lore_changed）
	_character_events = EventBus.resolve().hub(CharacterEvents) as CharacterEvents
	_character_events.lore_changed.connect(_on_lore_changed)
	# DM 命令
	_events.cmd_submit_input.connect(_on_cmd_submit_input)
	_events.cmd_talk_to.connect(_on_cmd_talk_to)
	_events.cmd_travel_to.connect(_on_cmd_travel_to)
	_events.cmd_get_canon.connect(_on_cmd_get_canon)
	_events.cmd_get_state.connect(_on_cmd_get_state)
	_events.cmd_set_knobs.connect(_on_cmd_set_knobs)
	_events.cmd_get_knobs.connect(_on_cmd_get_knobs)
	_events.cmd_set_embedding_config.connect(_on_cmd_set_embedding_config)
	_events.cmd_add_fact.connect(_on_cmd_add_fact)
	_events.cmd_edit_fact.connect(_on_cmd_edit_fact)
	_events.cmd_delete_fact.connect(_on_cmd_delete_fact)
	_events.cmd_save_canon.connect(_on_cmd_save_canon)
	_events.cmd_reset_canon.connect(_on_cmd_reset_canon)
	_events.cmd_settle_exploration.connect(_on_cmd_settle_exploration)
	_events.cmd_start_exploration.connect(_on_cmd_start_exploration)
	# 人物域回声：世界流水合并（渲染与 DM 上下文共用）+ 对话状态跟踪
	_dialogue_events.dialogue_started.connect(_on_dialogue_started)
	_dialogue_events.dialogue_ended.connect(_on_dialogue_ended_signal)
	_dialogue_events.state_changed.connect(_on_dialogue_state_changed)
	_dialogue_events.event_appended.connect(_on_dialogue_event)
	_events.knobs_changed.emit(current_knobs())
	_broadcast_state()
	_broadcast_location()


func _exit_tree() -> void:
	if _shared == self:
		_shared = null
	_audit_log.close()
	if _events != null:
		_events.cmd_submit_input.disconnect(_on_cmd_submit_input)
		_events.cmd_talk_to.disconnect(_on_cmd_talk_to)
		_events.cmd_travel_to.disconnect(_on_cmd_travel_to)
		_events.cmd_get_canon.disconnect(_on_cmd_get_canon)
		_events.cmd_get_state.disconnect(_on_cmd_get_state)
		_events.cmd_set_knobs.disconnect(_on_cmd_set_knobs)
		_events.cmd_get_knobs.disconnect(_on_cmd_get_knobs)
		_events.cmd_set_embedding_config.disconnect(_on_cmd_set_embedding_config)
		_events.cmd_add_fact.disconnect(_on_cmd_add_fact)
		_events.cmd_edit_fact.disconnect(_on_cmd_edit_fact)
		_events.cmd_delete_fact.disconnect(_on_cmd_delete_fact)
		_events.cmd_save_canon.disconnect(_on_cmd_save_canon)
		_events.cmd_reset_canon.disconnect(_on_cmd_reset_canon)
		_events.cmd_settle_exploration.disconnect(_on_cmd_settle_exploration)
		_events.cmd_start_exploration.disconnect(_on_cmd_start_exploration)
	if _dialogue_events != null:
		_dialogue_events.dialogue_started.disconnect(_on_dialogue_started)
		_dialogue_events.dialogue_ended.disconnect(_on_dialogue_ended_signal)
		_dialogue_events.state_changed.disconnect(_on_dialogue_state_changed)
		_dialogue_events.event_appended.disconnect(_on_dialogue_event)
	if _character_events != null:
		_character_events.lore_changed.disconnect(_on_lore_changed)


# ============ 统一入口：DM 裁决主链路 ============


## 处理 cmd_submit_input：统一输入第一站——DM 判路由并分派。
## 门控：自身可输入 且 对话不生成中 且 对话不在结算窗口。
func _on_cmd_submit_input(text: String) -> void:
	if state != State.WAITING_PLAYER or _dialogue_busy or _dialogue_settling:
		return
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	_resolve_with_dm(trimmed)


## DM 裁决：组装材料 → PURPOSE_DM 调用 → validate_dm → 按路由分派。
func _resolve_with_dm(input_text: String) -> void:
	var present := LocationStore.npcs_at(LocationStore.current())
	var present_ids := {}
	for id in present:
		present_ids[id] = true

	# 冻结世界材料：话题栈喂料（扫描输入）→ 融合检索（骨架信号 + 语义层）→ 单一预算
	# 语义层二选一：api 档先嵌查询文本（失败/超时自动回落 BM25），builtin 档直接 BM25
	var history := WorldStream.recent_mixed_lines(DM_HISTORY_WINDOW)
	var qvec := PackedFloat32Array()
	if _embed_cfg.vector_enabled():
		qvec = await _embed_query(input_text, history)
	var pack := DMPackBuilder.build(
		input_text,
		turn_number + 1,
		repository.worldview_text,
		repository.mainline_text,
		LocationStore.current(),
		EntityRegistry.display_name(LocationStore.current()),
		history,
		present,
		_partner_id,
		_topics,
		qvec,
	)
	_events.pack_built.emit(pack)

	var present_rows := _present_npc_rows(present)
	var partner_line := "（没有正在进行的交谈）"
	if not _partner_id.is_empty():
		partner_line = "[%s] %s" % [_partner_id, EntityRegistry.display_name(_partner_id)]
	var sys := prompt_builder.dm_system_prompt(current_knobs())
	var usr := prompt_builder.dm_user_prompt(pack, present_rows, partner_line)
	_events.prompt_built.emit(sys, usr)

	_ensure_audit_log()
	state = State.DM_RESOLVING
	_broadcast_state()
	_events.llm_request.emit("DM 裁决（%s）…" % LLMController.shared().display_name())
	var result: Dictionary = await LLMController.shared().complete_json(sys, usr, LLMClient.PURPOSE_DM)
	if state != State.DM_RESOLVING:
		return  # 防御：期间状态被外部改变
	state = State.WAITING_PLAYER

	if result.get("transport", false):
		# 传输失败：输入退回玩家重试（不落任何世界事件）
		_events.world_input_rejected.emit(input_text, "DM 请求失败：%s" % str(result.get("error", "未知错误")))
		_broadcast_state()
		return
	if not result.get("ok", false):
		# 输出不可解析：按行动注入保底旁白——宁可平淡，不可改写世界
		var fallback := _dm_fallback(input_text, str(result.get("error", "")))
		_events.dm_resolved.emit(fallback)
		_land_action(input_text, fallback.get("narration", ""), str(fallback.get("outcome", "pending")))
		_broadcast_state()
		return

	var parsed: Dictionary = DMParser.validate_dm(result["data"], present_ids, _partner_id)
	parsed["raw"] = str(result.get("raw", ""))
	_events.dm_resolved.emit(parsed)
	var route := str(parsed.get("route", "action"))
	var landed_turn := turn_number
	match route:
		"reject":
			_emit_event({"event": "world_input_rejected", "text": input_text,
				"reason": str(parsed.get("reason", ""))})
			_events.world_input_rejected.emit(input_text, str(parsed.get("reason", "")))
		"action":
			_land_action(input_text, str(parsed.get("narration", "")), str(parsed.get("outcome", "pending")))
			_land_declared_facts(parsed.get("facts", []))
		"speech", "mixed":
			if route == "mixed":
				var action_text := str(parsed.get("action", ""))
				_land_action(action_text if not action_text.is_empty() else input_text,
					str(parsed.get("narration", "")), str(parsed.get("outcome", "pending")))
				_land_declared_facts(parsed.get("facts", []))
			_deliver_speech(parsed, present)
	# 话题栈衰减：仅世界回合落地时推进（纯话语不推进世界，栈不衰减）
	if turn_number > landed_turn:
		_topics.tick()
	_broadcast_state()


## 行动落地：回合号 +1 → player_action（原文）→ narration_turn（DM 叙述）。
func _land_action(action_text: String, narration: String, outcome: String) -> void:
	turn_number += 1
	_emit_event({"event": "player_action", "speaker": "player", "text": action_text})
	_emit_event({"event": "narration_turn", "turn": turn_number,
		"outcome": outcome, "text": narration})


## 落地 DM 申报的持久事实（临时事实通道）：以 PROVISIONAL 状态立即入正典——
## 后续回合的事实检索与对话域学习即刻可及；结算时由整理者逐条复核（confirmed
## 点名才转正，未点名的移除）。与既有事实（或先前申报）精确文本一致时无事发生。
## 确定性闸门：单轮条数与单条长度超限的申报拦截（广播 fact_declare_blocked 留审计）。
## facts：DMParser 校验后的 [{content, weight}] 列表。
func _land_declared_facts(facts: Array) -> void:
	if facts.is_empty():
		return
	var landed := 0
	for raw in facts:
		var f := raw as Dictionary
		var content := str(f.get("content", "")).strip_edges()
		if content.is_empty():
			continue
		if landed >= DECLARE_PER_TURN_CAP:
			_emit_event({"event": "fact_declare_blocked", "content": content.substr(0, 40),
				"reason": "超出单轮申报上限（%d 条），疑似总结式申报" % DECLARE_PER_TURN_CAP})
			continue
		if content.length() > DECLARE_CONTENT_MAX:
			_emit_event({"event": "fact_declare_blocked", "content": content.substr(0, 40),
				"reason": "表述超长（%d 字，上限 %d），疑似叙述摘录" % [
					content.length(), DECLARE_CONTENT_MAX]})
			continue
		if CanonStore.find_by_content(content) > 0:
			continue  # 重复申报或与既有事实逐字一致：无事发生
		var weight_key := str(f.get("weight", "minor"))
		var id := CanonStore.establish(content, "narrator", weight_key,
			_scope_for(content, weight_key), true)
		if id > 0:
			landed += 1
			var fact := CanonStore.entry(id)
			_emit_event({"event": "fact_established", "id": id,
				"source": CanonFact.source_to_key(fact.source),
				"weight": CanonFact.weight_to_key(fact.weight),
				"content": content, "provisional": true})
	if landed > 0:
		CanonStore.save()
		_emit_canon()
		_backfill_embeddings()


## 话语分派：无对话 → 开始并送话；对象相同 → 直接送话；对象不同 → 结算当前再切换。
func _deliver_speech(parsed: Dictionary, present: Array[String]) -> void:
	var npc := str(parsed.get("npc", ""))
	var speech := str(parsed.get("speech", ""))
	if npc.is_empty():
		# 没人可说话：钳制失败（解析器已尽力），按拒绝退回
		_emit_event({"event": "world_input_rejected", "text": speech, "reason": "此处没有可交谈的人。"})
		_events.world_input_rejected.emit(speech, "此处没有可交谈的人。")
		return
	_topics.touch([npc])  # 说话目标入栈/续命（其名下事实随 S4 保持可激活）
	if _partner_id == npc:
		_dialogue_events.cmd_submit.emit(speech)
	elif not _partner_id.is_empty():
		# 自动切换：结算当前对话（学习+记忆落档），完成后开新对话并送出暂存的话
		_pending_switch = {"npc": npc, "speech": speech}
		_dialogue_settling = true
		_dialogue_events.cmd_settle_now.emit()
	else:
		_start_conversation(npc)
		_dialogue_events.cmd_submit.emit(speech)


## 处理 cmd_talk_to：直接与在场人物开始交谈（位置面板捷径，绕过 DM）。
## 对话中点名别人同样走自动切换；点名当前对象则不动作。
func _on_cmd_talk_to(npc_id: String) -> void:
	if state != State.WAITING_PLAYER or _dialogue_busy or _dialogue_settling:
		return
	if npc_id == _partner_id:
		return
	_topics.touch([npc_id])
	if not _partner_id.is_empty():
		_pending_switch = {"npc": npc_id, "speech": ""}
		_dialogue_settling = true
		_dialogue_events.cmd_settle_now.emit()
		return
	_start_conversation(npc_id)


## 开始一段对话：人物域以当前地点为场景（场景解析回退见 DialogueController.start_dialogue）。
func _start_conversation(npc_id: String) -> void:
	_dialogue_events.cmd_start.emit(npc_id, LocationStore.current())


# ============ 人物域回声与状态跟踪 ============


## 人物域广播 lore_changed：设定资料已被编辑（CharacterController 写快照后发出）。
## 重载设定资料并重新导入作者实体与位置图——导入幂等，位置图的 brief/npcs 等
## 运行期状态保留；在场人物行与实体显示名随新规范名生效（进行中的裁决不中断）。
func _on_lore_changed() -> void:
	# 仓库由 Characters 在广播前 reload_shared()——此处重导本域结构层
	EntityRegistry.load_authors(repository)
	LocationStore.load_authors(repository)
	_broadcast_location()


func _on_dialogue_started(npc_id: String, _npc_name: String, _scene_name: String) -> void:
	_partner_id = npc_id


func _on_dialogue_ended_signal(_reason: String) -> void:
	_partner_id = ""
	_dialogue_settling = false
	if not _pending_switch.is_empty():
		var target := str(_pending_switch.get("npc", ""))
		var speech := str(_pending_switch.get("speech", ""))
		_pending_switch = {}
		if not target.is_empty():
			_start_conversation(target)
			if not speech.is_empty():
				_dialogue_events.cmd_submit.emit(speech)


func _on_dialogue_state_changed(_state: String, _turn: int, _turns_left: int, _can_accept: bool, busy: bool) -> void:
	_dialogue_busy = busy


## 对话事件回声：入世界流水（WorldStream；审计已由人物域落档）。
func _on_dialogue_event(event: Dictionary) -> void:
	if str(event.get("event", "")) == "dialogue_ended":
		_dialogue_settling = true  # 引擎事件先于结算完成；信号到达时清除
	WorldStream.append_dialogue_echo(event)


# ============ 移动 / 进场描述 ============


## 处理 cmd_travel_to：移动到相邻地点（无 LLM）。对话进行中不可移动。
func _on_cmd_travel_to(entity_id: String) -> void:
	if state != State.WAITING_PLAYER or _dialogue_busy or _dialogue_settling or not _partner_id.is_empty():
		return
	if not LocationStore.travel_to(entity_id):
		return
	LocationStore.save()
	_emit_event({
		"event": "location_travelled",
		"to": entity_id,
		"name": EntityRegistry.display_name(entity_id),
		"brief": LocationStore.brief(entity_id),
	})
	_broadcast_location()
	if not LocationStore.has_brief(entity_id):
		_describe_location(entity_id)


## 首次进入某地点：组装进场包（场景卡素材 + 该地作用域正典 + 近期流水）→
## 一次生成到达描述 → 冻结为 brief（此后再进零延迟零调用）。
## 生成失败不冻结（下次进入重试），不确立事实（事实只走结算通道）。
func _describe_location(entity_id: String) -> void:
	state = State.DESCRIBING
	_broadcast_state()
	var scene: Location = repository.scenes.get(entity_id)
	var environment := scene.environment if scene != null else ""
	var atmosphere := scene.atmosphere if scene != null else ""
	var fact_lines: Array[String] = []
	for fact in CanonStore.facts_for_location(entity_id):
		fact_lines.append("[%d] %s" % [fact.id, fact.content])
	var prompts := DMPromptBuilder.entry_prompt(
		EntityRegistry.display_name(entity_id), environment, atmosphere,
		fact_lines, WorldStream.recent_mixed_lines(DM_HISTORY_LINES))
	_events.llm_request.emit(LLMController.shared().display_name())
	var result: Dictionary = await LLMController.shared().complete_json(
		str(prompts.get("system", "")), str(prompts.get("user", "")), LLMClient.PURPOSE_ENTRY_DESCRIBE)
	if state != State.DESCRIBING:
		return  # 防御：期间状态被外部改变
	var text := ""
	if result.get("ok", false) and result.get("data") is Dictionary:
		text = str(JsonTool.pick(result["data"], ["narration", "叙述", "描述"], "")).strip_edges()
	if text.is_empty():
		_emit_event({"event": "scene_described", "location": entity_id,
			"name": EntityRegistry.display_name(entity_id),
			"text": "（你对四周匆匆一瞥，没留下太深的印象。）", "frozen": false})
	else:
		if text.length() > ENTRY_BRIEF_MAX:
			text = text.substr(0, ENTRY_BRIEF_MAX) + "……"
		LocationStore.set_brief(entity_id, text)
		LocationStore.save()
		_emit_event({"event": "scene_described", "location": entity_id,
			"name": EntityRegistry.display_name(entity_id), "text": text, "frozen": true})
		_broadcast_location()
	state = State.WAITING_PLAYER
	_broadcast_state()


# ============ 探索结算（事实由独立的整理者 agent 从完整记录中提取） ============


## 处理 cmd_settle_exploration：结束本段探索并结算。对话进行中不可结算。
func _on_cmd_settle_exploration() -> void:
	if state != State.WAITING_PLAYER or _dialogue_busy or _dialogue_settling or not _partner_id.is_empty():
		return
	var log_lines := WorldStream.session_lines()
	if log_lines.is_empty():
		_emit_event({"event": "exploration_settled", "facts": 0, "turns": turn_number})
		state = State.ENDED
		_broadcast_state()
		return
	state = State.EXTRACTING
	_broadcast_state()
	var canon := _extract_canon_entries()
	var pack_ids := {}
	for fact in canon:
		pack_ids[fact.id] = true
	var prompts := DMPromptBuilder.extraction_prompt(canon, log_lines)
	_events.llm_request.emit("事实整理中（%s）…" % LLMController.shared().display_name())
	var result: Dictionary = await LLMController.shared().complete_json(
		str(prompts.get("system", "")), str(prompts.get("user", "")), LLMClient.PURPOSE_FACT_EXTRACT)
	if state != State.EXTRACTING:
		return  # 防御：期间状态被外部改变
	if result.get("transport", false) or not result.get("ok", false):
		_emit_event({"event": "extraction_failed", "error": str(result.get("error", "未知错误"))})
		state = State.WAITING_PLAYER
		_broadcast_state()
		return
	var parsed: Dictionary = DMParser.validate_facts(result["data"], pack_ids,
		current_knobs().get("threshold", "宽松") == "严格")
	var count := _land_extracted_facts(parsed.get("facts", []))
	# 点名制复核：confirmed 里的临时事实转正，其余移除——整理者是永久正典的唯一守门人
	var verdict: Dictionary = CanonStore.settle_provisional(parsed.get("confirmed", []))
	var confirmed := int(verdict.get("confirmed", 0))
	var discarded := int(verdict.get("discarded", 0))
	if discarded > 0:
		_emit_event({"event": "fact_discarded", "count": discarded,
			"note": "结算未被点名的临时申报已移除"})
	CanonStore.save()
	_emit_canon()
	_backfill_embeddings()
	_emit_event({"event": "exploration_settled", "facts": count, "turns": turn_number,
		"confirmed": confirmed, "discarded": discarded, "notes": parsed.get("notes", [])})
	state = State.ENDED
	_broadcast_state()


## 处理 cmd_start_exploration：结算后开始新探索——重置回合与记录（世界正典与位置保留）。
func _on_cmd_start_exploration() -> void:
	if state != State.ENDED:
		return
	turn_number = 0
	WorldStream.clear()
	_topics.clear()
	_pending_switch = {}
	_partner_id = ""
	state = State.WAITING_PLAYER
	_emit_event({"event": "exploration_started"})
	_broadcast_state()


# ============ 事实库编辑 / 保存 / 重置（浏览器；"只追加"哲学的唯一例外入口） ============


## 处理 cmd_add_fact：新增一条事实（作用域为单个实体 id，空 = 全局）。
func _on_cmd_add_fact(payload: Dictionary) -> void:
	var content := str(payload.get("content", "")).strip_edges()
	if content.is_empty():
		return
	var scope_ids: Array = []
	var scope_id := str(payload.get("scope_id", "")).strip_edges()
	if not scope_id.is_empty():
		scope_ids.append(scope_id)
	var id := CanonStore.establish(content,
		str(payload.get("source", "narrator")), str(payload.get("weight", "minor")), scope_ids)
	if id == 0:
		return
	CanonStore.save()
	var fact := CanonStore.entry(id)
	_emit_event({"event": "fact_established", "id": id, "source": fact.source,
		"weight": fact.weight, "content": content, "manual": true})
	_emit_canon()


## 处理 cmd_edit_fact：修改条目的表述与权重（作用域不变）。payload：{id, content, weight}。
func _on_cmd_edit_fact(payload: Dictionary) -> void:
	var fact := CanonStore.entry(int(payload.get("id", 0)))
	if fact == null:
		return
	var content := str(payload.get("content", "")).strip_edges()
	if content.is_empty():
		return
	var old_content := fact.content
	fact.content = content
	var weight := str(payload.get("weight", ""))
	if [CanonFact.WEIGHT_KEYS[0], CanonFact.WEIGHT_KEYS[1]].has(weight):
		fact.weight = CanonFact.weight_from_key(weight)
	CanonStore.save()
	_emit_event({"event": "fact_edited", "id": fact.id,
		"before": old_content, "content": content})
	_emit_canon()


## 处理 cmd_delete_fact：删除条目（取代链置 0，不留悬空引用）。
func _on_cmd_delete_fact(fact_id: int) -> void:
	if not CanonStore.erase(fact_id):
		return
	CanonStore.save()
	_emit_event({"event": "fact_deleted", "id": fact_id})
	_emit_canon()


## 处理 cmd_save_canon：显式保存事实库并广播绝对路径（浏览器保存按钮）。
func _on_cmd_save_canon() -> void:
	CanonStore.save()
	_events.canon_saved.emit(ProjectSettings.globalize_path(CanonStore.PATH))


## 处理 cmd_reset_canon：一键把事实库重置为作者正典（settings/canon.json）。
func _on_cmd_reset_canon() -> void:
	var count := CanonStore.reset_to_authors()
	CanonStore.save()
	_emit_event({"event": "canon_reset", "facts": count})
	_events.canon_reset.emit(count)
	_emit_canon()


# ============ 查询 / 状态 ============


## 处理 cmd_get_canon：重发世界事实快照。
func _on_cmd_get_canon() -> void:
	_emit_canon()


## 处理 cmd_get_state：重发状态机快照与位置快照（UI 晚于控制器就绪时补拉）。
func _on_cmd_get_state() -> void:
	_broadcast_state()
	_broadcast_location()


## 处理 cmd_set_knobs：写入并持久化旁白风格旋钮，清提示词缓存后广播。
func _on_cmd_set_knobs(knobs: Dictionary) -> void:
	for def in GameConfig.KNOB_DEFS:
		if knobs.has(def["key"]):
			_game_config.set("narration_" + def["key"], str(knobs[def["key"]]))
	_game_config.save_to_disk()
	prompt_builder.clear_cache()
	_events.knobs_changed.emit(current_knobs())


## 处理 cmd_get_knobs：重发旋钮快照（设置屏进屏时）。
func _on_cmd_get_knobs() -> void:
	_events.knobs_changed.emit(current_knobs())


## 处理 cmd_set_embedding_config：写入并持久化检索档位配置；换嵌入模型时清空旧向量。
func _on_cmd_set_embedding_config(provider: String, api_key: String, model: String, base_url: String) -> void:
	_embed_cfg.provider = provider
	_embed_cfg.api_key = api_key
	_embed_cfg.model = model
	_embed_cfg.base_url = base_url
	_embed_cfg.save_to_disk()
	if CanonStore.embedding_model() != model:
		CanonStore.clear_embeddings()


## 当前旋钮快照（Dictionary；键来自 GameConfig.KNOB_DEFS——加旋钮不必改这里）。
func current_knobs() -> Dictionary:
	var knobs := {}
	for def in GameConfig.KNOB_DEFS:
		knobs[def["key"]] = str(_game_config.get("narration_" + def["key"]))
	return knobs


## 状态机当前状态的中文显示名（UI 状态栏直接使用）。
func state_name() -> String:
	match state:
		State.WAITING_PLAYER:
			return "等待你的行动"
		State.DM_RESOLVING:
			return "DM 裁决中"
		State.DESCRIBING:
			return "正在打量四周"
		State.EXTRACTING:
			return "整理世界事实中"
		State.ENDED:
			return "探索已结算"
	return "未知"


## 当前是否可接受玩家输入（DM/描述/整理/已结算期间为否；对话生成门控另算）。
func can_accept_input() -> bool:
	return state == State.WAITING_PLAYER


# ============ 内部 ============


## DM 保底（解析失败兜底）：按行动处理，pending、零发现——宁可平淡，不可改写世界。
func _dm_fallback(input_text: String, error_text: String) -> Dictionary:
	return {
		"ok": true,
		"route": "action",
		"npc": "",
		"action": input_text,
		"narration": "你愣了一下，周围的一切没有变化。（DM 暂时失语，稍后再试）",
		"outcome": "pending",
		"speech": "",
		"reason": "",
		"facts": [],
		"notes": ["DM 输出解析失败，已注入保底行动：" + error_text],
	}


# ============ 语义层向量管线（api 档；builtin 档全部跳过） ============


## 查询文本嵌入（每回合一次）：失败/超时返回空向量 → FactRetriever 自动回落 BM25。
func _embed_query(action_text: String, history: Array[String]) -> PackedFloat32Array:
	var client := EmbeddingClient.new()
	client.api_key = _embed_cfg.api_key
	client.model = _embed_cfg.model
	client.base_url = _embed_cfg.base_url
	add_child(client)
	var result: Dictionary = await client.embed_texts([action_text + " " + " ".join(history)])
	client.queue_free()
	if not bool(result.get("ok", false)):
		push_warning("查询嵌入失败，本回合回落 BM25：%s" % str(result.get("error", "")))
		return PackedFloat32Array()
	var vectors: Array = result.get("embeddings", [])
	if vectors.is_empty():
		return PackedFloat32Array()
	return vectors[0]


## 正典模型名与配置不一致（换嵌入模型）→ 清空全部向量等待重嵌。
func _sync_embedding_model() -> void:
	if not _embed_cfg.vector_enabled():
		return
	var recorded := CanonStore.embedding_model()
	if not recorded.is_empty() and recorded != _embed_cfg.model:
		CanonStore.clear_embeddings()


## 后台补齐缺失的事实向量（落地事实/结算后触发；分批 ≤16，失败静默下次再补）。
## 以 fire-and-forget 方式调用（不 await）。
func _backfill_embeddings() -> void:
	if _embed_busy or not _embed_cfg.vector_enabled():
		return
	_embed_busy = true
	var client := EmbeddingClient.new()
	client.api_key = _embed_cfg.api_key
	client.model = _embed_cfg.model
	client.base_url = _embed_cfg.base_url
	add_child(client)
	var changed := false
	if CanonStore.embedding_model() != _embed_cfg.model:
		CanonStore.clear_embeddings()
		CanonStore.note_embedding_model(_embed_cfg.model)
	while true:
		var missing := CanonStore.facts_missing_embeddings()
		if missing.is_empty():
			break
		var batch: Array[String] = []
		for i in mini(EmbeddingClient.MAX_BATCH, missing.size()):
			batch.append((missing[i] as CanonFact).content)
		var result: Dictionary = await client.embed_texts(batch)
		if not bool(result.get("ok", false)):
			break  # 网络失败：静默放弃本批，下次触发再补
		var vectors: Array = result.get("embeddings", [])
		for i in mini(vectors.size(), missing.size()):
			(missing[i] as CanonFact).embedding = vectors[i]
			changed = true
	client.queue_free()
	_embed_busy = false
	if changed:
		CanonStore.save()


## 在场人物行（"[id] 规范名——身份"）：人物域优先（身份完整），注册表兜底（仅名字）。
func _present_npc_rows(present: Array[String]) -> Array[String]:
	var rows: Array[String] = []
	for id in present:
		var person: Person = repository.characters.get(id)
		if person != null:
			rows.append("[%s] %s——%s" % [id, person.canonical_name,
				person.identity if not person.identity.is_empty() else "身份不明"])
		else:
			rows.append("[%s] %s" % [id, EntityRegistry.display_name(id)])
	return rows



## 结算注入的现行正典（id 升序，超上限保最近确立的——取代闭集以此为限）。
## 含临时事实：整理者复核——矛盾走 ref 取代，相符者结算后转正。
func _extract_canon_entries() -> Array[CanonFact]:
	var active: Array[CanonFact] = []
	for fact in CanonStore.all_entries():
		if fact.status != CanonFact.FactStatus.SUPERSEDED:
			active.append(fact)
	active.sort_custom(func(a, b): return a.id < b.id)
	if active.size() > EXTRACT_CANON_CAP:
		active = active.slice(active.size() - EXTRACT_CANON_CAP)
	return active


## 落地提取出的事实：ref>0 走取代（闭集已校验），ref=0 新确立；
## 作用域由引擎分配——表述提及的实体优先，否则 major=全局 / minor=当前地点。
## 返回确立/取代的事实条数。
func _land_extracted_facts(facts: Array) -> int:
	var count := 0
	for raw in facts:
		var f := raw as Dictionary
		var content := str(f.get("content", ""))
		var source_key := str(f.get("source", "narrator"))
		var weight_key := str(f.get("weight", "minor"))
		var ref := int(f.get("ref", 0))
		if ref > 0:
			var change: Dictionary = CanonStore.supersede(ref, content, source_key, weight_key)
			var old_id := int(change.get("old_id", 0))
			var new_id := int(change.get("new_id", 0))
			# new_id == old_id：新表述与被指条目逐字相同（整理者复述了旧事实），无变化不计入
			if old_id > 0 and new_id > 0 and new_id != old_id:
				count += 1
				_emit_event({
					"event": "fact_superseded", "old_id": old_id,
					"new_id": new_id, "content": content,
					"ripples": CharacterController.shared().count_knowledge_refs(old_id),
				})
		else:
			var id := CanonStore.establish(content, source_key, weight_key, _scope_for(content, weight_key))
			if id > 0:
				count += 1
				_emit_event({
					"event": "fact_established", "id": id,
					"source": source_key, "weight": weight_key, "content": content,
				})
	return count


## 提取事实的作用域分配（确定性）：表述提及的实体名下优先（最多 3 个标签）；
## 未提及任何实体时 major=全局、minor=当前地点。返回实体 id 列表。
func _scope_for(content: String, weight: String) -> Array:
	var scope: Array = []
	for mentioned in EntityRegistry.scan_mentioned(content):
		scope.append(str((mentioned as Dictionary).get("id", "")))
		if scope.size() >= 3:
			break
	if scope.is_empty() and weight == "minor":
		var current := LocationStore.current()
		if not current.is_empty():
			scope.append(current)
	return scope


## 首次落地前打开审计日志（懒打开，之后常开）。
func _ensure_audit_log() -> void:
	if _audit_open:
		return
	_audit_open = true
	_audit_log.open(EVENT_LOG_DIR, "narration")


## 追加一条世界事件（叙述域）：入世界流水（WorldStream）→ 落审计 → 广播（副本）。
func _emit_event(event: Dictionary) -> void:
	WorldStream.append_narration(event, turn_number)
	_audit_log.append_line(event)
	_events.event_appended.emit(event.duplicate(true))


## 重发世界事实快照（调试页）。
func _emit_canon() -> void:
	_events.canon_listed.emit(CanonStore.all_entries())


## 广播位置快照：当前位置 + 相邻地点 + 在场 NPC + 冻结的进场描述。
func _broadcast_location() -> void:
	var current_id := LocationStore.current()
	var neighbors: Array = []
	for id in LocationStore.neighbors(current_id):
		neighbors.append({"id": id, "name": EntityRegistry.display_name(id)})
	var npcs: Array = []
	for id in LocationStore.npcs_at(current_id):
		npcs.append({"id": id, "name": EntityRegistry.display_name(id)})
	_events.location_changed.emit(current_id, EntityRegistry.display_name(current_id),
		neighbors, npcs, LocationStore.brief(current_id))


## 广播状态机快照。
func _broadcast_state() -> void:
	_events.state_changed.emit(state_name(), turn_number, can_accept_input())
