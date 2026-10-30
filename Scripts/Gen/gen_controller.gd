class_name GenController
extends Node
## 生成控制器（Gen 层，autoload "Gen"）：三条生成管线（地点/人物/组织，各一个
## agent 类）与共用审核者的编排宿主。职责边界——本类只做：
##   请求门控（每段探索上限 / gen 实体总量上限 / 忙碌互斥）
##   冻结生成上下文（GenContext + GenKnowledgePool）
##   多轮管线编排：构思 → 引擎校验 → 审核 → 修订（≤2 轮）→ 落地 → 链式后续
##   阶段广播（GenEvents）与结束后的设定重载握手（lore_changed）
## 提示词、契约校验、落地细节全部内聚在各 agent 类（GenAgentBase 子类）里。
## 生成期间 busy=true：DM 域据此闸住玩家输入（一致性优先于时间成本）。
## 全部产物只写 saves/（快照/位置图/注册表/gen_factions/正典），settings/ 零触碰。


## 每段探索允许的生成次数（超出由 DM 侧落地时拦截）
const DISCOVER_PER_EXPLORATION := 3
## 动态生成实体总量软上限（防长期游玩膨胀）
const GEN_ENTITY_CAP := 50
## 修订轮数预算（初稿之外最多修订 2 轮）
const MAX_REVISIONS := 2
## 注入生成上下文的近期流水行数
const HISTORY_LINES := 8

var busy := false

var _events: GenEvents
var _audit := GenAuditAgent.new()
var _agents := {}  # kind(String) -> GenAgentBase
var _session_requests := 0

static var _shared: GenController


static func shared() -> GenController:
	return _shared


## 测试/嵌入式环境兜底：autoload 未就绪时手动创建并注册共享实例。
static func create_shared() -> GenController:
	if _shared == null:
		_shared = GenController.new()
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			(loop as SceneTree).root.add_child(_shared)
	return _shared


func _ready() -> void:
	_shared = self
	_events = EventBus.resolve().hub(GenEvents) as GenEvents
	_events.cmd_clear_generated.connect(_on_cmd_clear_generated)
	for agent in [GenAgentLocation.new(), GenAgentCharacter.new(), GenAgentFaction.new()]:
		_agents[agent.kind] = agent


func _exit_tree() -> void:
	if _shared == self:
		_shared = null
	if _events != null:
		_events.cmd_clear_generated.disconnect(_on_cmd_clear_generated)


## 新探索开始：重置本段探索的生成计数（DM 域在 cmd_start_exploration 时调用）。
func reset_session() -> void:
	_session_requests = 0


## 发起一次生成（fire-and-forget：内部异步推进，调用方不等待）。
## kind：location/character/faction；brief：DM 的一句话意图；origin：发起地点 id。
## 返回 false = 被门控拒绝（忙碌/超额），原因由调用方（DM）记录。
func request(kind: String, brief: String, origin: String) -> bool:
	if busy or not _agents.has(kind):
		return false
	if _session_requests >= DISCOVER_PER_EXPLORATION:
		return false
	if EntityRegistry.gen_count() >= GEN_ENTITY_CAP:
		return false
	_session_requests += 1
	busy = true
	_events.generation_started.emit(kind)
	_run(kind, brief, origin)
	return true


func _run(kind: String, brief: String, origin: String) -> void:
	var landed_ids: Array = []
	var messages: Array[String] = []
	var ok := await _pipeline(kind, brief, origin, false, landed_ids, messages)
	# 链式后续全部完成后一次性重载设定并广播——各域一次性看到完整的新实体
	if not landed_ids.is_empty():
		LoreRepository.reload_shared()
		(EventBus.resolve().hub(CharacterEvents) as CharacterEvents).lore_changed.emit()
	busy = false
	_events.generation_finished.emit(kind, ok, "；".join(messages))


## 一条管线的完整执行（含链式后续的递归排队）。返回整体是否至少落地了一个实体。
func _pipeline(kind: String, brief: String, origin: String, chained: bool,
		landed_ids: Array, messages: Array) -> bool:
	var ctx := _build_context(kind, brief, origin)
	ctx.chained = chained
	var outcome := await _generate_with_agent(_agents[kind] as GenAgentBase, ctx)
	messages.append(str(outcome.get("message", "")))
	if not bool(outcome.get("ok", false)):
		return false
	landed_ids.append_array(outcome.get("ids", []))
	# 链式后续（如新地点的住户）：顺序执行，先落地者已进入后继者的世界
	var any_ok := true
	for followup in outcome.get("followups", []):
		var f: Dictionary = followup
		var sub_ok := await _pipeline(str(f.get("kind", "")), str(f.get("brief", "")),
			str(f.get("home", origin)), true, landed_ids, messages)
		any_ok = any_ok and sub_ok
	return any_ok


## 单个 agent 的多轮循环：构思 → 引擎校验 → 审核 → 修订。
## 引擎契约不合格与审核 revise 都进入修订循环（问题清单即修订指令）；
## 预算耗尽仍不合格 → 放弃（世界无事发生，宁缺毋滥）。
func _generate_with_agent(agent: GenAgentBase, ctx: GenContext) -> Dictionary:
	var issues: Array = []
	var draft := {}
	for round in MAX_REVISIONS + 1:
		_events.generation_stage.emit("构思中" if round == 0 else "修订中")
		var prompts: Dictionary = agent.build_draft_prompt(ctx) if round == 0 \
			else agent.build_revision_prompt(ctx, draft, issues)
		var result: Dictionary = await LLMController.shared().complete_json(
			str(prompts.get("system", "")), str(prompts.get("user", "")), agent.purpose)
		if not bool(result.get("ok", false)):
			issues = ["上一稿的输出无法解析为 JSON，请重新输出完整的 JSON 对象。"]
			continue
		var round_notes: Array[String] = []
		draft = agent.validate_draft(result["data"], ctx, round_notes)
		if draft.is_empty():
			issues = round_notes.duplicate()
			continue
		_events.generation_stage.emit("一致性审核中")
		var verdict := await _audit_round(ctx, agent.render_for_audit(draft))
		if str(verdict.get("verdict", "pass")) == "pass":
			var notes: Array[String] = []
			var landed := agent.land(draft, ctx, notes)
			if not bool(landed.get("ok", false)):
				landed["message"] = "；".join(notes)
				return landed
			return landed
		issues = verdict.get("issues", [])
	_events.generation_stage.emit("即将完成")
	return {"ok": false, "ids": [], "message": "（构思了几番，世界没有回应——本次生成放弃）", "followups": []}


## 审核一轮。审核输出异常（不可解析）按 pass 处理——漏报由引擎硬门兜底，
## 且避免审核者自身故障卡死整个生成。
func _audit_round(ctx: GenContext, draft_text: String) -> Dictionary:
	var prompts := _audit.build_prompt(ctx, draft_text)
	var result: Dictionary = await LLMController.shared().complete_json(
		str(prompts.get("system", "")), str(prompts.get("user", "")), LLMClient.PURPOSE_GEN_AUDIT)
	var notes: Array[String] = []
	if not bool(result.get("ok", false)):
		notes.append("审核输出无法解析，按通过处理。")
		return {"verdict": "pass", "issues": []}
	return _audit.validate(result["data"], notes)


## 冻结生成上下文：agent 与审核者看到的全部材料在此定死（材料包冻结的同一哲学）。
func _build_context(kind: String, brief: String, origin: String) -> GenContext:
	var ctx := GenContext.new()
	ctx.kind = kind
	ctx.brief = brief
	ctx.origin = origin
	var repo := LoreRepository.shared()
	ctx.worldview = repo.worldview_text
	ctx.mainline = repo.mainline_text
	ctx.history_lines = WorldStream.recent_mixed_lines(HISTORY_LINES)
	ctx.origin_facts = CanonStore.facts_for_location(origin)
	# 名字闭集：全部实体的规范名与别名（撞名即修订）
	var names: Array[String] = []
	for type in [Entity.EntityType.PERSON, Entity.EntityType.LOCATION, Entity.EntityType.FACTION]:
		for e in EntityRegistry.entities_of_type(type):
			names.append(e.canonical_name)
			for alias in e.aliases:
				names.append(alias)
	ctx.known_names = names
	if kind == "character":
		# 知情集：同地点在场 NPC + 玩家（brief 无法结构化指定相识，v1 不做）
		var acquaintance: Array = ["player"]
		var acquaintance_names: Array[String] = [repo.player.canonical_name]
		for npc_id in LocationStore.npcs_at(origin):
			acquaintance.append(npc_id)
			acquaintance_names.append(EntityRegistry.display_name(npc_id))
		ctx.acquaintance = acquaintance
		ctx.acquaintance_names = acquaintance_names
		ctx.pool = GenKnowledgePool.build(origin, acquaintance)
	return ctx


## 处理 cmd_clear_generated：一键清除全部动态生成内容并广播设定重载。
func _on_cmd_clear_generated() -> void:
	if busy:
		return  # 生成中不清理（防半成品状态被撕裂）
	var removed := GenCleaner.clear()
	LoreRepository.reload_shared()
	(EventBus.resolve().hub(CharacterEvents) as CharacterEvents).lore_changed.emit()
	_events.generation_finished.emit("clear", true, "已清除全部动态生成内容（%d 个实体）" % removed)
