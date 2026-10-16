class_name DialogueController
extends Node
## 人物域引擎（Dialogue 层，autoload "Dialogue"）：由 DM 调度的对话回合编排——
## 玩家话语（DM 已拆出）原样入记录 → 冻结现场组装材料包（含"此刻之前发生了什么"
## 的世界上下文注入）→ 两层提示词 → 生成 → 解析（发言/claim/行动/信念/好感）
## → 学习提案延后收集（对话结束时一次性结算）→ 落地写入事件流水。
## 输入审查（第 0 步）已随统一入口退役（2026-10）：DM 路由取代了"对话只能说话"的边界，
## 注入由 DM 的 reject 路由拦截。
## 事件流水按统一格式追加，由 DM 的世界屏同源渲染；模型调用统一走 LLMController。
## 人物数据模型为 Person（knowledge 承载信念）；12 轮上限；结束后不可续聊。
## 对外交互：DM（DMController）与世界屏经 EventBus 在 DialogueEvents 集线器上交互。

enum State {IDLE, WAITING_PLAYER, WAITING_NPC, ENDED}

const MAX_TURNS := 12            # 单段对话轮次上限
const EVENT_LOG_DIR := GamePaths.EVENT_LOG_DIR
## 叙述域事件注入对话材料包"此刻之前发生了什么"的行数
const WORLD_CONTEXT_LINES := 6

var repository: LoreRepository
var prompt_builder := PromptBuilder.new()

var state: State = State.IDLE
var current_person: Person      # 回应者（Models 层人物对象）
var current_scene: Location     # 对话场景（统一入口下恒为当前位置，可能有回退）
var turn_number := 0
var turn_events: Array = []      # 本段对话的事件流水（统一格式）

var _pending_learning: Array[Dictionary] = []  # 延后结算的信念提案（对话结束时一次性结算）
var current_affinity := 0  # 当前 NPC 对玩家的好感度（对话期间缓存，变更经 AffinityStore 落盘）

var _audit_log := AuditLog.new()   # 本段对话的审计日志（事件流水 + 被拒输入共用）
var _session := 0                # 会话编号：新开对话时递增，用于丢弃在途的旧请求
var _events: DialogueEvents      # 事件集线器（_ready 时经总线取得）

static var _shared: DialogueController


static func shared() -> DialogueController:
	return _shared

## 测试/嵌入式环境兜底：autoload 未就绪时手动创建并注册共享实例（挂到当前场景树）
static func create_shared() -> DialogueController:
	if _shared == null:
		_shared = DialogueController.new()
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			(loop as SceneTree).root.add_child(_shared)
	return _shared

func _ready() -> void:
	# LLM 服务兜底：正常运行由 autoload "LLM" 提供；独立使用引擎时手动创建
	if LLMController.shared() == null:
		LLMController.create_shared()
	_shared = self
	# 事件集线器：UI 与本类经同一实例交互
	_events = EventBus.resolve().hub(DialogueEvents) as DialogueEvents
	# 流程一：加载设定资料（作者手动放置在 res://settings/ 下）
	repository = LoreRepository.shared()  # 统一入口：作者数据全项目一份
	# 连接 UI 命令信号
	_events.cmd_start.connect(_on_cmd_start)
	_events.cmd_submit.connect(_on_cmd_submit)
	_events.cmd_settle_now.connect(_on_cmd_settle_now)
	_events.cmd_reset_memory.connect(_on_cmd_reset_memory)
	# 人物域广播：设定被编辑后重载设定资料（见 _on_lore_changed）
	(EventBus.resolve().hub(CharacterEvents) as CharacterEvents).lore_changed.connect(_on_lore_changed)


func _exit_tree() -> void:
	if _shared == self:
		_shared = null
	_audit_log.close()
	if _events != null:
		_events.cmd_start.disconnect(_on_cmd_start)
		_events.cmd_submit.disconnect(_on_cmd_submit)
		_events.cmd_settle_now.disconnect(_on_cmd_settle_now)
		_events.cmd_reset_memory.disconnect(_on_cmd_reset_memory)
		(EventBus.resolve().hub(CharacterEvents) as CharacterEvents).lore_changed.disconnect(_on_lore_changed)


## 人物域广播 lore_changed：设定资料已被编辑（CharacterController 写快照后发出）。
## 仓库被就地重载（load_all 原地替换 characters 等字典）；进行中的对话不中断——
## 编辑保存路径在 reload 前原地改写同一 Person 对象，下一轮材料包即时生效；
## 删除快照类操作（恢复卡面/还原设定）则另行经 discard_person_runtime 同步本域。
func _on_lore_changed() -> void:
	# 仓库由 Characters 在广播前 reload_shared()——此处只需清本域缓存
	prompt_builder.clear_cache()


## 人物域删除了某 NPC 的运行时档案（恢复卡面/还原设定）后调用：
## 若正与该 NPC 对话，把内存对象切换到重载后的作者卡面并丢弃未结算的信念提案——
## 否则对话结束的结算会把刚删除的旧快照原样写回，恢复操作被静默撤销。
func discard_person_runtime(npc_id: String) -> void:
	if current_person == null or current_person.entity_id != npc_id:
		return
	var fresh: Person = repository.characters.get(npc_id)
	if fresh != null:
		current_person = fresh
		current_affinity = AffinityStore.get_value(npc_id, current_person.affinity)
	_pending_learning.clear()
	prompt_builder.clear_cache()


# ———— 命令处理（UI 经集线器命令信号发来） ————


## 处理 cmd_start：按 NPC/场景 id 开始一段新对话。
## npc_id/scene_id 为设定资料中的实体 id；不存在时静默忽略（返回 false）。
func _on_cmd_start(npc_id: String, scene_id: String) -> void:
	start_dialogue(npc_id, scene_id)


## 处理 cmd_submit：提交玩家发言（DM 已拆出的话语直达此处）。text 为话语原文。
func _on_cmd_submit(text: String) -> void:
	submit_player_input(text)


# ———— 对外接口（逻辑层内部与测试使用；UI 一律走总线） ————


## 开始一段新对话：按 id 取人物；场景解析带回退链（作者场景卡 → 位置图对象 →
## 最小 Location）——统一入口下对话场景恒为当前位置，不能假定有作者场景卡。
## 信念已在 Person.knowledge 上（加载时完成快照接管与正典消解）。
## npc_id/scene_id：实体 id。返回人物 id 是否有效（失败返回 false）。
func start_dialogue(npc_id: String, scene_id: String) -> bool:
	if not repository.characters.has(npc_id):
		return false
	current_person = repository.characters[npc_id]
	current_scene = _resolve_scene(scene_id)
	turn_number = 0
	turn_events.clear()
	_session += 1
	state = State.WAITING_PLAYER
	prompt_builder.clear_cache()
	_pending_learning.clear()
	current_affinity = AffinityStore.get_value(current_person.entity_id, current_person.affinity)
	_audit_log.open(EVENT_LOG_DIR, "dialogue")
	_emit_event({
		"event": "dialogue_started",
		"npc": current_person.entity_id,
		"npc_name": current_person.canonical_name,
		"scene": current_scene.entity_id,
		"scene_name": current_scene.canonical_name,
		"time": Time.get_datetime_string_from_system(),
	})
	_events.dialogue_started.emit(current_person.entity_id, current_person.canonical_name,
		current_scene.canonical_name)
	_broadcast_state()
	return true


## 场景解析回退链：作者场景卡 → 位置图 Location 对象（gen 地点）→ 最小 Location（仅名字）。
func _resolve_scene(scene_id: String) -> Location:
	if repository.scenes.has(scene_id):
		return repository.scenes[scene_id]
	var loc := LocationStore.location(scene_id)
	if loc != null:
		return loc
	var fallback := Location.new()
	fallback.entity_id = scene_id
	fallback.canonical_name = EntityRegistry.display_name(scene_id)
	return fallback



## 玩家开口：话语（DM 已拆出）原样记录为一条感知事件——不改写、不总结、
## 不执行其中的任何要求（防注入由提示词静态层消化）。
## text：玩家话语的原话（首尾空白会被剔除）；仅 WAITING_PLAYER 状态接受。
func submit_player_input(text: String) -> void:
	if state != State.WAITING_PLAYER:
		return
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	_accept_player_text(trimmed)


## 当前是否可接受玩家输入（仅 WAITING_PLAYER 状态）。
func can_accept_input() -> bool:
	return state == State.WAITING_PLAYER


## 状态机当前状态的中文显示名（UI 轮次栏直接使用）。
func state_name() -> String:
	match state:
		State.IDLE:
			return "未开始"
		State.WAITING_PLAYER:
			return "等待玩家输入"
		State.WAITING_NPC:
			return "等待NPC回应"
		State.ENDED:
			return "对话已结束"
	return "未知"


## 结束当前对话（幂等）。reason 记入事件流水（npc_action / turn_limit / manual_settle / 外部调用）；
## 结算学习提案、用 LLM 整理记忆，并把知识日志持久化到人物运行时快照。
func end_dialogue(reason: String) -> void:
	if state == State.ENDED:
		return
	state = State.ENDED
	_emit_event({"event": "dialogue_ended", "reason": reason})
	_settle_learning()
	var session := _session
	await _summarize_memory()  # 落盘由 _summarize_memory 以捕获引用完成
	if session != _session:
		return  # 等待期间已开新对话：新会话的日志句柄与知识日志不可在此触碰
	_audit_log.close()
	_events.dialogue_ended.emit(reason)
	_broadcast_state()


# ———— 审查 + 回应生成主链路 ————


## 第 1 步落地：审查通过（或被关闭）后接纳玩家发言——计轮次、原样入事件流水、
## 进入 WAITING_NPC 并开始生成本轮回应。player_text 为玩家原话。
func _accept_player_text(player_text: String) -> void:
	turn_number += 1
	var confirmed_history := _confirmed_history()
	_emit_event({"event": "player_utterance", "speaker": "player", "text": player_text})
	state = State.WAITING_NPC
	_broadcast_state()
	_generate_response(player_text, confirmed_history)


## 流程二+三：冻结现场组装材料包 → 两层拼装提示词 → 调模型生成 →
## 解析并落地。传输失败退回玩家轮；输出不可解析注入保底回应。
## player_text：玩家原话；confirmed_history：截至上一轮已确认的事件（记忆槽）。
func _generate_response(player_text: String, confirmed_history: Array) -> void:
	var session := _session

	# 流程二：冻结现场，组装材料包（信念层全量 + 检索世界事实 + 世界上下文 + 记忆 + 行动清单）
	var pack := DialoguePackBuilder.build(
		current_person,
		current_scene,
		player_text,
		confirmed_history,
		repository.get_memory(current_person.entity_id),
		current_person.active_knowledge(),
		turn_number,
		MAX_TURNS,
		current_affinity,
		repository.player.to_prompt_dict(),
		_retrieve_world_facts(current_person.entity_id),
		_world_context_lines(),
	)
	pack.session_lines = current_person.memory_lines()
	_events.pack_built.emit(pack)

	# 第 4 步：两层拼装提示词（静态规则层缓存 + 本轮材料层；好感度走材料包 npc_state）
	var sys := prompt_builder.system_prompt(current_person, repository.worldview_text, repository.mainline_text)
	var usr := prompt_builder.user_prompt(pack)
	_events.prompt_built.emit(sys, usr)

	# 流程三：模型生成回应（complete_json 已含容错 JSON 提取）
	_events.llm_request.emit(LLMController.shared().display_name())
	var result: Dictionary = await LLMController.shared().complete_json(sys, usr, LLMClient.PURPOSE_DIALOGUE)
	if session != _session:
		return  # 期间已重新开始对话，丢弃在途回应

	if result.get("transport", false):
		# 传输层失败（网络/鉴权）：不写入世界内事件流水，退回玩家轮，由 UI 提示。
		_events.response.emit({"ok": false, "fallback": false,
			"error": str(result.get("error", "未知错误")), "raw": "",
			"belief_updates": []})
		state = State.WAITING_PLAYER
		_broadcast_state()
		return

	if not result.get("ok", false):
		# 输出不可解析：完整流程中此处以同一份材料包带反馈重试两次（设计 4.6/4.8），
		# 阶段一原型直接注入保底回应——宁可冷淡，不可胡说。
		var fallback := _fallback_response(str(result.get("error", "")))
		fallback["raw"] = str(result.get("raw", ""))
		_events.response.emit(fallback)
		await _land_response(fallback)
		return

	# TODO(里程碑 M1.1/M1.3)：此处依次挂接「结构检查→事实审核→带反馈重试」。
	var parsed := ResponseParser.validate(result["data"], turn_number)
	parsed["raw"] = str(result.get("raw", ""))
	parsed["fallback"] = false
	_collect_learning(parsed, player_text, pack)
	var affinity_delta := int(parsed.get("affinity_change", 0))
	if affinity_delta != 0:
		# 好感度不在静态层（缓存键无关）：新值经下一轮材料包生效，无需清缓存
		current_affinity = AffinityStore.apply_change(current_person.entity_id, affinity_delta, current_affinity)
		_events.affinity_changed.emit(current_affinity, affinity_delta)
	_events.response.emit(parsed)
	await _land_response(parsed)


## 收集本轮学习提案（延后结算——对话期间不写知识日志，保持材料包"冻结现场"一致）。
## 把 parsed 中的 belief_updates 连同本轮闭集存入 _pending_learning，
## 由 end_dialogue → _settle_learning 一次性结算。
## parsed：ResponseParser 校验后的回应；player_text：本轮玩家原话；pack：本轮材料包。
func _collect_learning(parsed: Dictionary, player_text: String, pack: DialoguePack) -> void:
	var updates: Array = parsed.get("belief_updates", [])
	if updates.is_empty():
		return
	var pack_seqs := {}
	for e in pack.knowledge_entries:
		pack_seqs[e.seq] = true
	_pending_learning.append({
		"turn": turn_number,
		"belief_updates": updates,
		"pack_seqs": pack_seqs,
	})


## 结算信念提案（对话结束时调用）：遍历全部延后的信念提案，执行闭集校验并应用信任算术。
## belief_updates 的 ref 限该轮材料包展示过的编号（闭集校验）。
func _settle_learning() -> void:
	if _pending_learning.is_empty():
		return
	for proposal in _pending_learning:
		var p := proposal as Dictionary
		var pack_seqs: Dictionary = p.get("pack_seqs", {})
		for item in p.get("belief_updates", []):
			var d := item as Dictionary
			var ref := int(d.get("ref", 0))
			if not pack_seqs.has(ref):
				continue
			var change: Dictionary
			if str(d.get("relation", "")) == "矛盾":
				change = current_person.contradict(ref)
			else:
				change = current_person.corroborate(ref, repository.player.canonical_name)
			if bool(change.get("changed", false)):
				_emit_event({
					"event": "belief_updated",
					"ref": ref,
					"before": str(change.get("before", "")),
					"after": str(change.get("after", "")),
					"cause": str(change.get("cause", "")),
					"npc_name": current_person.canonical_name,
				})
	_pending_learning.clear()


## 检索该 NPC 可及的世界事实（world_model_design §6.3：对话域对正典只读——硬线②）。
## NPC 所在地点作用域 + 全局提要（两处均 major 全量、minor 封顶保最近）；
## 不站任何地方的 NPC 只看得到全局提要。
func _retrieve_world_facts(npc_id: String) -> Array[CanonFact]:
	var facts: Array[CanonFact] = []
	var loc := LocationStore.location_of_npc(npc_id)
	if not loc.is_empty():
		facts.append_array(CanonStore.facts_for_location(loc))
	facts.append_array(CanonStore.global_digest())
	return facts


## 统一入口的共享上下文：叙述域近期事件（"此刻之前发生了什么"）——
## 经 WorldStream 全局入口只读（硬线②）；不含对话回声（对话自身的记录另有槽位，避免重复）。
func _world_context_lines() -> Array[String]:
	return WorldStream.recent_narration_only_lines(WORLD_CONTEXT_LINES)


## 记忆整理：对话结算后用 LLM 从完整事件流归纳一段记忆写入日志。
## LLM 失败时静默跳过（记忆为空不影响其他功能），但仍落盘一次以保住已结算的信念更新。
## 等待期间即使开了新对话（current_person 可能已换对象），全部写入与落盘都走
## 捕获的旧引用、存旧 NPC——不触碰新会话的日志实例。
func _summarize_memory() -> void:
	if current_person == null or turn_events.is_empty():
		return
	var session := _session
	var npc_id := current_person.entity_id
	var person_ref := current_person
	var player_name := repository.player.canonical_name  # 习得来源缺省：以捕获时的玩家名为准
	var prompts := MemorySummarizer.build_prompts(turn_events, current_person.canonical_name)
	_events.llm_request.emit("记忆与知识整理中…")
	var result: Dictionary = await LLMController.shared().complete_json(
		str(prompts.get("system", "")), str(prompts.get("user", "")), LLMClient.PURPOSE_MEMORY,
	)
	if not result.get("ok", false):
		CharacterController.shared().save_journal(person_ref, npc_id)
		return
	var data: Dictionary = result.get("data", {})
	var memory_text := MemorySummarizer.extract(str(data.get("memory", "")))
	if not memory_text.is_empty():
		person_ref.add_memory(memory_text)
	for item in data.get("knowledge", []):
		if not (item is Dictionary):
			continue
		var d: Dictionary = item
		var content := str(d.get("content", "")).strip_edges()
		if content.is_empty():
			continue
		# 学习路径实体消解（§5.4）：内容与某条现行正典精确一致 → 记信念引用（不是复制品）；
		# 匹配不到 → 主观条目。引擎确定性匹配，零开放生成。
		var fact_id := CanonStore.find_by_content(content)
		if fact_id > 0:
			person_ref.learn_ref(fact_id, content, str(d.get("evidence", "")),
				str(d.get("speaker", player_name)), int(d.get("turn", 0)), session, str(d.get("note", "")))
		else:
			person_ref.learn_entry(content, str(d.get("evidence", "")), str(d.get("speaker", player_name)),
				int(d.get("turn", 0)), session, str(d.get("note", "")))
	CharacterController.shared().save_journal(person_ref, npc_id)


## 结算对话：仅玩家回合可用——结算学习提案并整理记忆后，直接结束本段对话，
## 结束后状态机拒绝续聊。
func _on_cmd_settle_now() -> void:
	if state != State.WAITING_PLAYER:
		return
	end_dialogue("manual_settle")


## 重置当前 NPC 的知识日志与记忆：删除运行时快照与旧学习日志并重建（回落卡面初始知识）。
func _on_cmd_reset_memory() -> void:
	if current_person == null:
		return
	CharacterController.shared().erase_runtime_state(current_person.entity_id)
	current_person.reset_knowledge_to_author()  # 快照已删：信念回落作者卡消解结果
	current_person.memories = []
	_pending_learning.clear()
	_events.memory_reset.emit()


## 第 8 步落地：按行动提案类型落档——结束对话则收尾、沉默记态度、答话入记录
##（阶段一只有对话行动，其“裁决”就是对话状态机自身的处理，设计 4.1 / 5.6 接入点二）。
## parsed：ResponseParser 校验后的回应 Dictionary（utterance/claim_type/action…）。
func _land_response(parsed: Dictionary) -> void:
	var action: Dictionary = parsed.get("action", {})
	var action_type := str(action.get("type", "answer"))
	match action_type:
		"end_dialogue":
			_emit_event({
				"event": "npc_utterance",
				"speaker": current_person.entity_id,
				"npc_name": current_person.canonical_name,
				"text": str(parsed.get("utterance", "")),
				"claim_type": str(parsed.get("claim_type", "猜测")),
				"action": "end_dialogue",
				"action_description": str(action.get("description", "")),
			})
			end_dialogue("npc_action")
		"silence":
			_emit_event({
				"event": "npc_silence",
				"speaker": current_person.entity_id,
				"npc_name": current_person.canonical_name,
				"description": str(action.get("description", "沉默")),
				"claim_type": str(parsed.get("claim_type", "猜测")),
				"action": "silence",
			})
			_after_turn()
		_:
			_emit_event({
				"event": "npc_utterance",
				"speaker": current_person.entity_id,
				"npc_name": current_person.canonical_name,
				"text": str(parsed.get("utterance", "")),
				"claim_type": str(parsed.get("claim_type", "猜测")),
				"action": "answer",
			})
			_after_turn()


## 单轮收尾：达到轮次上限则结束对话，否则回到 WAITING_PLAYER。
func _after_turn() -> void:
	if turn_number >= MAX_TURNS:
		end_dialogue("turn_limit")
		return
	state = State.WAITING_PLAYER
	_broadcast_state()


## 保底回应（设计 4.1 兜底）：重试耗尽/输出不可用时注入冷淡沉默——
## 不报错、不重问。error_text 记入事件流水与返回值供调试展示。
func _fallback_response(error_text: String) -> Dictionary:
	_emit_event({"event": "fallback_used", "reason": error_text})
	return {
		"ok": true,
		"fallback": true,
		"error": error_text,
		"turn_id": turn_number,
		"expected_turn": turn_number,
		"inner_thought": "（兜底回应：模型输出不可用）",
		"utterance": "",
		"claim_type": "猜测",
		"action": {"type": "silence", "name": "沉默", "description": "他抬头看了你一眼，没说话。"},
		"belief_updates": [],
		"notes": ["模型输出解析失败，已注入保底回应：" + error_text],
	}


# ———— 内部 ————


## 供素材包「记忆」槽使用的已确认轮次（仅玩家/NPC 发言与沉默事件，不含过程事件）。
func _confirmed_history() -> Array:
	var out: Array = []
	for event in turn_events:
		var kind := str(event.get("event", ""))
		if kind == "player_utterance" or kind == "npc_utterance" or kind == "npc_silence":
			out.append(event)
	return out


## 追加一条对话事件：打上 turn/seq → 入事件流水 → 落盘审计日志 → 广播（副本）。
## event：统一记录格式的 Dictionary（event 键必需）。
func _emit_event(event: Dictionary) -> void:
	event["turn"] = turn_number
	event["seq"] = turn_events.size() + 1
	turn_events.append(event)
	_audit_log.append_line(event)
	_events.event_appended.emit(event.duplicate(true))


## 广播状态机快照（状态名、轮次、剩余轮次、是否可输入、是否有在途请求）。
func _broadcast_state() -> void:
	var busy := state == State.WAITING_NPC
	_events.state_changed.emit(state_name(), turn_number, maxi(0, MAX_TURNS - turn_number), can_accept_input(), busy)
