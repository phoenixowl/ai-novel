class_name DialogueEngine
extends Node
## 对话引擎（Dialogue 层，autoload "Dialogue"）：【流程三：回应生成】的编排器，
## 同时串起流程一、二（设计 4.1 一轮对话的八步中，本阶段实现第 1/2/3/4/5/8 步
## 与最小落地，并在第 1 步之前前置“第 0 步：输入审查”——用 LLM 拦下动作描写
## 与诱导注入，被拒输入不记录、不计轮次；第 6/7 步结构检查与事实审核、
## 以及带反馈重试属后续里程碑 M1.1+/M1.3，代码中已标出挂接位置）。
##
##   输入审查（LLM，拒绝动作/诱导） → 玩家开口（原样入记录，防注入） → 冻结现场组装材料包
##   → 两层拼装提示词 → 模型生成（LLMService：DeepSeek / 离线示例）
##   → 解析（发言 / claim_type / 行动提案 / 内心想法 / learned / belief_updates）
##   → 学习提案延后收集（对话结束时一次性结算） → 落地写入事件流水
##
## 事件流水按统一格式追加记录（设计 4.10 / 5.6 接入点三），是阶段二世界状态的雏形；
## 由 EventJournal 落盘到 user://dialogue_logs/*.jsonl 供排查。
## 模型调用统一走 LLMService（autoload "LLM"）——本类不管理客户端与配置。
##
## 对外交互：UI 经 EventBus（autoload "Events"）中转——本类在 DialogueEvents
## 集线器（Scripts/Dialogue/dialogue_events.gd）上连接 cmd_* 命令信号、
## 发射事件信号；UI 连接同一集线器的事件信号、发射命令信号。

enum State {IDLE, WAITING_PLAYER, REVIEWING, WAITING_NPC, ENDED}

const MAX_TURNS := 12            # 单段对话轮次上限（设计 4.9）
const EVENT_LOG_DIR := "user://dialogue_logs"

var repository: LoreRepository
var prompt_builder := PromptBuilder.new()
var input_reviewer := InputReviewer.new()

var state: State = State.IDLE
var current_npc: CharacterCard
var current_scene: SceneCard
var turn_number := 0
var events: Array = []           # 本段对话的事件流水（统一格式）

var journal := KnowledgeJournal.new()  # 该 NPC 的知识日志（卡片初始 + 运行时习得）
var input_review_enabled := true  # 输入审查（第 0 步）开关：关闭时提交直通对话流程
var _journal_session := 0           # 知识日志会话序号（对话开始时递增）
var _pending_learning: Array[Dictionary] = []  # 延后结算的学习提案

var _journal := EventJournal.new()
var _session := 0                # 会话编号：新开对话后丢弃在途的旧请求
var _events: DialogueEvents      # 事件集线器（_ready 时经总线取得）
var _game_config := GameConfig.new()  # 游戏行为设置（输入审查开关等）
# 设定资料快照（UI 后加入时经 cmd_get_lore 补发）
var _lore_characters: Array = []
var _lore_scenes: Array = []
var _lore_overview := ""


## 取全局事件总线；autoload 未就绪时（仅测试环境）手动创建。
func _bus() -> EventBus:
	return EventBus.shared() if EventBus.shared() != null else EventBus.create_shared()


func _ready() -> void:
	# LLM 服务兜底：正常运行由 autoload "LLM" 提供；独立使用引擎时手动创建
	if LLMService.shared() == null:
		LLMService.create_shared()
	# 事件集线器：UI 与本类经同一实例交互
	_events = _bus().hub(DialogueEvents) as DialogueEvents
	# 流程一：加载设定资料（作者手动放置在 res://settings/ 下）
	repository = LoreRepository.new()
	repository.load_all()
	_build_lore_payload()
	# 连接 UI 命令信号
	_events.cmd_start.connect(_on_cmd_start)
	_events.cmd_submit.connect(_on_cmd_submit)
	_events.cmd_get_lore.connect(_on_cmd_get_lore)
	_events.cmd_set_review.connect(_on_cmd_set_review)
	_events.cmd_get_settings.connect(_on_cmd_get_settings)
	_events.cmd_rollback_to_turn.connect(_on_cmd_rollback_to_turn)
	_events.cmd_reset_memory.connect(_on_cmd_reset_memory)
	_events.cmd_set_player_persona.connect(_on_cmd_set_player_persona)
	# 游戏设置（输入审查开关）
	_game_config.load()
	input_review_enabled = _game_config.input_review_enabled
	_events.lore_loaded.emit(_lore_characters, _lore_scenes, _lore_overview)
	_events.review_enabled_changed.emit(input_review_enabled)
	_events.player_persona_changed.emit(_game_config.player_identity, _game_config.player_speech_style)


func _exit_tree() -> void:
	_journal.close()
	if _events != null:
		_events.cmd_start.disconnect(_on_cmd_start)
		_events.cmd_submit.disconnect(_on_cmd_submit)
		_events.cmd_get_lore.disconnect(_on_cmd_get_lore)
		_events.cmd_set_review.disconnect(_on_cmd_set_review)
		_events.cmd_get_settings.disconnect(_on_cmd_get_settings)
		_events.cmd_rollback_to_turn.disconnect(_on_cmd_rollback_to_turn)
		_events.cmd_reset_memory.disconnect(_on_cmd_reset_memory)
		_events.cmd_set_player_persona.disconnect(_on_cmd_set_player_persona)


# ———— 命令处理（UI 经集线器命令信号发来） ————


## 处理 cmd_start：按 NPC/场景 id 开始一段新对话。
## npc_id/scene_id 为设定资料中的实体 id；不存在时静默忽略（返回 false）。
func _on_cmd_start(npc_id: String, scene_id: String) -> void:
	start_dialogue(npc_id, scene_id)


## 处理 cmd_submit：提交玩家输入（可能先经第 0 步审查）。
## text 为玩家原话。
func _on_cmd_submit(text: String) -> void:
	submit_player_input(text)


## 处理 cmd_set_review：开启/关闭输入审查并持久化，随后广播新状态。
## enabled=true 提交前经 LLM 审查；false 直通对话流程（不再发起审查请求）。
func _on_cmd_set_review(enabled: bool) -> void:
	input_review_enabled = enabled
	_game_config.input_review_enabled = enabled
	_game_config.save()
	_events.review_enabled_changed.emit(input_review_enabled)
	_events.player_persona_changed.emit(_game_config.player_identity, _game_config.player_speech_style)


## 处理 cmd_get_settings：重发设置快照（当前审查开关状态）。
func _on_cmd_get_settings() -> void:
	_events.review_enabled_changed.emit(input_review_enabled)
	_events.player_persona_changed.emit(_game_config.player_identity, _game_config.player_speech_style)
	_events.player_persona_changed.emit(_game_config.player_identity, _game_config.player_speech_style)


## 处理 cmd_get_lore：重发设定资料快照（人物/场景列表、总览文本）。
func _on_cmd_get_lore() -> void:
	_events.lore_loaded.emit(_lore_characters, _lore_scenes, _lore_overview)


# ———— 对外接口（逻辑层内部与测试使用；UI 一律走总线） ————


## 开始一段新对话：按 id 取人物卡与场景卡，重置状态与事件流水，
## 准备该角色的知识日志（卡片初始 + 运行时习得），开启事件日志并广播开始事件。
## npc_id/scene_id：设定资料中的实体 id。返回 id 是否有效（失败返回 false）。
func start_dialogue(npc_id: String, scene_id: String) -> bool:
	if not repository.characters.has(npc_id) or not repository.scenes.has(scene_id):
		return false
	current_npc = repository.characters[npc_id]
	current_scene = repository.scenes[scene_id]
	turn_number = 0
	events.clear()
	_session += 1
	state = State.WAITING_PLAYER
	prompt_builder.clear_cache()
	_prepare_journal(current_npc)
	_pending_learning.clear()
	_journal.open(EVENT_LOG_DIR, "dialogue")
	_emit_event({
		"event": "dialogue_started",
		"npc": current_npc.id,
		"npc_name": current_npc.display_name,
		"scene": current_scene.id,
		"scene_name": current_scene.scene_name,
		"time": Time.get_datetime_string_from_system(),
	})
	_events.dialogue_started.emit(current_npc.display_name, current_scene.scene_name)
	_broadcast_state()
	return true


## 对话开始：准备该角色的知识日志——人物卡初始知识逐条入日志（顺序分配 seq 1..N），
## 再从 user://journals/ 读回运行时习得的条目与会话摘要（卡片每次重建，作者改卡不被遮蔽）。
## card：本次对话的 NPC 人物卡。
func _prepare_journal(card: CharacterCard) -> void:
	journal = KnowledgeJournal.new()
	for entry in card.knowledge:
		var e := entry as Dictionary
		journal.add_card_entry(
			str(e.get("content", "")),
			str(e.get("source", "常识")),
			str(e.get("trust", "比较相信")),
		)
	journal.load_learned(card.id)
	_journal_session = journal.session_count() + 1


## 第 0 步：输入审查（LLM，可经设置关闭）。动作描写（括号/星号/空格包裹）、
## 诱导性提问、注入指令等被拒绝——不记录、不计轮次、NPC 听不到，原输入退回玩家修改。
## 第 1 步：玩家开口。审查通过（或关闭审查）后，原话原样记录为一条感知事件——
## 不改写、不总结、不执行其中的任何要求（防注入由提示词静态层消化，见设计 4.2）。
## text：玩家输入的原话（首尾空白会被剔除）；仅 WAITING_PLAYER 状态接受。
func submit_player_input(text: String) -> void:
	if state != State.WAITING_PLAYER:
		return
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	if input_review_enabled:
		state = State.REVIEWING
		_broadcast_state()
		_review_then_generate(trimmed)
	else:
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
		State.REVIEWING:
			return "输入审查中"
		State.WAITING_NPC:
			return "等待NPC回应"
		State.ENDED:
			return "对话已结束"
	return "未知"


## 结束当前对话（幂等）。reason 记入事件流水（npc_action / turn_limit / 外部调用）；
## 追加会话摘要（轮数/新记条数/结束原因）并把知识日志持久化到 user://journals/。
func end_dialogue(reason: String) -> void:
	if state == State.ENDED:
		return
	state = State.ENDED
	_emit_event({"event": "dialogue_ended", "reason": reason})
	_settle_learning()
	journal.add_session_summary(_journal_session, turn_number, journal.gained_in_session(_journal_session), reason)
	journal.save(current_npc.id)
	_journal.close()
	_events.dialogue_ended.emit(reason)
	_broadcast_state()


# ———— 审查 + 回应生成主链路 ————


## 第 0 步主链路：发起 LLM 输入审查（失败开放——审查器故障不阻塞游戏），
## 通过则进入 _accept_player_text，被拒则广播 input_rejected 并退回玩家。
## player_text：玩家原话。
func _review_then_generate(player_text: String) -> void:
	var session := _session

	# 第 0 步：输入审查（失败开放——审查器故障不阻塞游戏）
	_events.review_started.emit()
	var review: Dictionary = await LLMService.shared().complete_json(
		input_reviewer.system_prompt(),
		input_reviewer.user_prompt(player_text),
		LLMClient.PURPOSE_INPUT_REVIEW,
	)
	if session != _session:
		return
	var verdict: Dictionary
	if review.get("ok", false) and review.get("data") is Dictionary:
		verdict = InputReviewer.verdict_of(review["data"])
	else:
		verdict = {
			"approved": true,
			"reason": "",
			"notes": ["审查请求失败或不可解析，按放行处理（失败开放）"],
			"error": str(review.get("error", "")),
		}
	verdict["raw"] = str(review.get("raw", ""))
	_events.review_finished.emit(
		bool(verdict.get("approved", true)),
		str(verdict.get("reason", "")),
		verdict.get("notes", []),
		str(verdict.get("raw", "")),
		str(verdict.get("error", "")),
	)

	if not verdict.get("approved", true):
		# 拒绝：世界内什么都没发生——不进事件流水（NPC 没听到），仅写审计日志
		_journal.append_line({
			"event": "input_rejected",
			"turn": turn_number,
			"text": player_text,
			"reason": str(verdict.get("reason", "")),
		})
		_events.input_rejected.emit(player_text, str(verdict.get("reason", "")))
		state = State.WAITING_PLAYER
		_broadcast_state()
		return

	_accept_player_text(player_text)


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

	# 流程二：冻结现场，组装材料包（知识日志全量 + 记忆 + 行动清单）
	var pack := MaterialPackBuilder.build(
		current_npc,
		current_scene,
		player_text,
		confirmed_history,
		repository.get_memory(current_npc.id),
		journal.entries_for_pack(),
		turn_number,
		MAX_TURNS,
	)
	pack.session_lines = journal.session_lines()
	_events.pack_built.emit(pack)

	# 第 4 步：两层拼装提示词（静态规则层缓存 + 本轮材料层）
	var sys := prompt_builder.system_prompt(current_npc, repository.worldview_text, _game_config.player_identity, _game_config.player_speech_style)
	var usr := prompt_builder.user_prompt(pack)
	_events.prompt_built.emit(sys, usr)

	# 流程三：模型生成回应（complete_json 已含容错 JSON 提取）
	_events.llm_request.emit(LLMService.shared().display_name())
	var result: Dictionary = await LLMService.shared().complete_json(sys, usr, LLMClient.PURPOSE_DIALOGUE)
	if session != _session:
		return  # 期间已重新开始对话，丢弃在途回应

	if result.get("transport", false):
		# 传输层失败（网络/鉴权）：不写入世界内事件流水，退回玩家轮，由 UI 提示。
		_events.response.emit({"ok": false, "fallback": false,
			"error": str(result.get("error", "未知错误")), "raw": "",
			"learned": [], "belief_updates": []})
		state = State.WAITING_PLAYER
		_broadcast_state()
		return

	if not result.get("ok", false):
		# 输出不可解析：完整流程中此处以同一份材料包带反馈重试两次（设计 4.6/4.8），
		# 阶段一原型直接注入保底回应——宁可冷淡，不可胡说。
		var fallback := _fallback_response(str(result.get("error", "")))
		fallback["raw"] = str(result.get("raw", ""))
		_events.response.emit(fallback)
		_land_response(fallback)
		return

	# TODO(里程碑 M1.1/M1.3)：此处依次挂接「结构检查→事实审核→带反馈重试」。
	var parsed := ResponseParser.validate(result["data"], turn_number)
	parsed["raw"] = str(result.get("raw", ""))
	parsed["fallback"] = false
	_collect_learning(parsed, player_text, pack)
	_events.response.emit(parsed)
	_land_response(parsed)


## 收集本轮学习提案（延后结算——对话期间不写知识日志，保持材料包"冻结现场"一致）。
## 把 parsed 中的 learned/belief_updates 连同本轮玩家原话与闭集存入 _pending_learning，
## 由 end_dialogue → _settle_learning 一次性结算。
## parsed：ResponseParser 校验后的回应；player_text：本轮玩家原话；pack：本轮材料包。
func _collect_learning(parsed: Dictionary, player_text: String, pack: MaterialPack) -> void:
	var learned: Array = parsed.get("learned", [])
	var updates: Array = parsed.get("belief_updates", [])
	if learned.is_empty() and updates.is_empty():
		return
	var pack_seqs := {}
	for e in pack.knowledge_entries:
		pack_seqs[int((e as Dictionary).get("seq", 0))] = true
	_pending_learning.append({
		"turn": turn_number,
		"learned": learned,
		"belief_updates": updates,
		"player_text": player_text,
		"pack_seqs": pack_seqs,
	})


## 结算学习（对话结束时调用）：遍历全部延后提案，执行确定性校验并写入知识日志。
## \t learned：quote 逐字子串校验（防编造），失败回退整句锚定（每轮至多一条）。
## \t belief_updates：ref 闭集校验（限该轮材料包展示过的编号）。
func _settle_learning() -> void:
	if _pending_learning.is_empty():
		return
	var anchored_turns := {}
	for proposal in _pending_learning:
		var p := proposal as Dictionary
		var player_text := str(p.get("player_text", ""))
		var pack_seqs: Dictionary = p.get("pack_seqs", {})
		var turn := int(p.get("turn", 0))

		for item in p.get("learned", []):
			var d := item as Dictionary
			var quote := str(d.get("quote", ""))
			var evidence := quote
			if not player_text.contains(quote):
				if anchored_turns.has(turn) or player_text.is_empty():
					continue
				evidence = player_text
				anchored_turns[turn] = true
			var seq := journal.learn(
				str(d.get("summary", quote)),
				evidence,
				"来客",
				turn,
				_journal_session,
				str(d.get("note", "")),
			)
			_emit_event({
				"event": "knowledge_learned",
				"journal_seq": seq,
				"content": str(d.get("summary", quote)),
				"evidence": evidence,
				"npc_name": current_npc.display_name,
			})

		for item in p.get("belief_updates", []):
			var d := item as Dictionary
			var ref := int(d.get("ref", 0))
			if not pack_seqs.has(ref):
				continue
			var change: Dictionary
			if str(d.get("relation", "")) == "矛盾":
				change = journal.contradict(ref)
			else:
				change = journal.corroborate(ref, "来客")
			if bool(change.get("changed", false)):
				_emit_event({
					"event": "belief_updated",
					"ref": ref,
					"before": str(change.get("before", "")),
					"after": str(change.get("after", "")),
					"cause": str(change.get("cause", "")),
					"npc_name": current_npc.display_name,
				})
	_pending_learning.clear()


## 回滚到指定轮次之前：删除该轮及之后的所有事件、恢复轮次、清除对应学习提案。
## turn：要回滚到的轮次（该轮本身的 NPC 回应会被删除，玩家可以重新说这一轮）。
func _on_cmd_rollback_to_turn(turn: int) -> void:
	if state == State.ENDED or state == State.IDLE:
		return
	if turn < 1 or turn > turn_number:
		return
	var i := events.size() - 1
	while i >= 0:
		var e := events[i] as Dictionary
		if int(e.get("turn", 0)) >= turn:
			events.remove_at(i)
		i -= 1
	var kept: Array[Dictionary] = []
	for proposal in _pending_learning:
		if int((proposal as Dictionary).get("turn", 0)) < turn:
			kept.append(proposal)
	_pending_learning = kept
	turn_number = turn - 1
	state = State.WAITING_PLAYER
	_broadcast_state()
	_events.rolled_back.emit(turn)


## 重置当前 NPC 的知识日志与记忆：删除 user://journals/<npc_id>.json 并重建。
func _on_cmd_reset_memory() -> void:
	if current_npc == null:
		return
	DirAccess.remove_absolute("user://journals/%s.json" % current_npc.id)
	_prepare_journal(current_npc)
	_pending_learning.clear()
	_events.memory_reset.emit()


## 设置玩家人设（持久化到 GameConfig 并广播；清缓存让静态层重建）。
func _on_cmd_set_player_persona(identity: String, speech_style: String) -> void:
	_game_config.player_identity = identity
	_game_config.player_speech_style = speech_style
	_game_config.save()
	prompt_builder.clear_cache()
	_events.player_persona_changed.emit(identity, speech_style)


## 第 8 步：落地。阶段一的行动只可能是对话行动，其“裁决”就是对话状态机自身的
## 处理（设计 4.1 / 5.6 接入点二）：结束对话则收尾，沉默则记录态度，答话则入记录。
## 第 8 步落地：按行动提案类型落档（结束对话则收尾、沉默记态度、答话入记录）。
## parsed：ResponseParser 校验后的回应 Dictionary（utterance/claim_type/action…）。
func _land_response(parsed: Dictionary) -> void:
	var action: Dictionary = parsed.get("action", {})
	var action_type := str(action.get("type", "answer"))
	match action_type:
		"end_dialogue":
			_emit_event({
				"event": "npc_utterance",
				"speaker": current_npc.id,
				"npc_name": current_npc.display_name,
				"text": str(parsed.get("utterance", "")),
				"claim_type": str(parsed.get("claim_type", "猜测")),
				"action": "end_dialogue",
				"action_description": str(action.get("description", "")),
			})
			end_dialogue("npc_action")
		"silence":
			_emit_event({
				"event": "npc_silence",
				"speaker": current_npc.id,
				"npc_name": current_npc.display_name,
				"description": str(action.get("description", "沉默")),
				"claim_type": str(parsed.get("claim_type", "猜测")),
				"action": "silence",
			})
			_after_turn()
		_:
			_emit_event({
				"event": "npc_utterance",
				"speaker": current_npc.id,
				"npc_name": current_npc.display_name,
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


## 保底回应（设计 4.1 兜底）：不报错、不重问，注入冷淡回应。
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
		"learned": [],
		"belief_updates": [],
		"notes": ["模型输出解析失败，已注入保底回应：" + error_text],
	}


# ———— 内部 ————


## 构建设定资料快照（人物/场景下拉数据、总览文本），供启动时与 cmd_get_lore 补发。
func _build_lore_payload() -> void:
	_lore_characters = []
	for id in repository.character_ids():
		var card: CharacterCard = repository.characters[id]
		_lore_characters.append({"id": id, "label": "%s（%s）" % [card.display_name, id]})
	_lore_scenes = []
	for id in repository.scene_ids():
		var scene: SceneCard = repository.scenes[id]
		_lore_scenes.append({"id": id, "label": scene.scene_name})
	_lore_overview = repository.overview_text()


## 供素材包「记忆」槽使用的已确认轮次（不含引擎过程事件）
## 供素材包「记忆」槽使用的已确认轮次（仅玩家/NPC 发言与沉默事件，不含过程事件）。
func _confirmed_history() -> Array:
	var out: Array = []
	for event in events:
		var kind := str(event.get("event", ""))
		if kind == "player_utterance" or kind == "npc_utterance" or kind == "npc_silence":
			out.append(event)
	return out


## 追加一条对话事件：打上 turn/seq → 入事件流水 → 落盘审计日志 → 广播（副本）。
## event：统一记录格式的 Dictionary（event 键必需）。
func _emit_event(event: Dictionary) -> void:
	event["turn"] = turn_number
	event["seq"] = events.size() + 1
	events.append(event)
	_journal.append_line(event)
	_events.event_appended.emit(event.duplicate(true))


## 广播状态机快照（状态名、轮次、剩余轮次、是否可输入）。
func _broadcast_state() -> void:
	_events.state_changed.emit(state_name(), turn_number, maxi(0, MAX_TURNS - turn_number), can_accept_input())
