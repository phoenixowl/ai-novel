extends Control
## 对话屏（Scripts/UI/）：NPC/场景选择、对话记录、玩家输入，
## 以及「调试侧栏」按钮展开的四页调试面板（设定资料/材料包/提示词/模型回应）。
## 与逻辑层的交互经 EventBus 集线器中转：连接 DialogueEvents 与 LlmEvents 的
## 相关信号、发射命令信号；返回主菜单经 UiEvents.navigate_requested。


const COLOR_PLAYER := Color("#7ec8e3")   # 玩家气泡的昵称色
const COLOR_NPC := Color("#e9c46a")      # NPC 气泡的昵称色
const COLOR_SILENCE := Color("#a8a29e")  # 沉默气泡的颜色
const COLOR_SYSTEM := Color("#8d99ae")   # 系统提示行/标签的颜色
const COLOR_ERROR := Color("#e76f51")    # 错误/拒绝提示的颜色
const COLOR_OK := Color("#90be6d")       # 成功提示的颜色

# —— 顶栏 ——
@onready var npc_option: OptionButton = %NpcOption
@onready var scene_option: OptionButton = %SceneOption
@onready var start_btn: Button = %StartBtn
@onready var mode_label: Label = %ModeLabel
@onready var reset_mem_btn: Button = %ResetMemBtn
@onready var settle_btn: Button = %SettleBtn

# —— 对话区 ——
@onready var scene_label: Label = %SceneLabel
@onready var round_label: Label = %RoundLabel
@onready var dialogue_scroll: ScrollContainer = %DialogueScroll
@onready var dialogue_log: VBoxContainer = %DialogueLog
@onready var player_input: LineEdit = %PlayerInput
@onready var send_btn: Button = %SendBtn

# —— 调试侧栏（默认收起，按钮展开） ——
@onready var debug_sidebar: Control = %DebugSidebar
@onready var settings_view: RichTextLabel = %SettingsView
@onready var pack_view: RichTextLabel = %PackView
@onready var prompt_full_view: RichTextLabel = %PromptFullView
@onready var response_view: RichTextLabel = %ResponseView

# —— 事件集线器 ——
var _dialogue: DialogueEvents  # 对话域（材料包/回应/状态/审查…）
var _llm: LlmEvents            # LLM 域（配置快照与客户端切换）
var _nav: UiEvents             # UI 导航

# —— 状态缓存 ——
var current_system_prompt := ""        # 本轮 System 提示词（复制完整提示词用）
var current_user_prompt := ""          # 本轮 User 提示词（复制完整提示词用）
var current_full_prompt := ""          # 两层拼合的完整提示词原文（复制按钮用）
var _lore_overview := ""               # 设定资料总览文本（侧栏①页）
var _can_accept := false               # 引擎是否可接受玩家输入
var _actions_enabled := false          # 与 _can_accept 同步；动态创建的回滚按钮按此初始化
var _rollback_buttons: Array[Button] = []  # 对话气泡上的「↩」按钮（等待期统一置灰）


## 取全局事件总线；autoload 未就绪时（理论上仅测试环境）手动创建。
func _bus() -> EventBus:
	return EventBus.shared() if EventBus.shared() != null else EventBus.create_shared()


## 初始化：取得集线器、连接事件并拉取设定资料快照。
func _ready() -> void:
	_dialogue = _bus().hub(DialogueEvents) as DialogueEvents
	_llm = _bus().hub(LlmEvents) as LlmEvents
	_nav = _bus().hub(UiEvents) as UiEvents
	_connect_events()


# ============================================================
#  事件连接（对话屏 ← 集线器信号 ← 逻辑层）
# ============================================================


## 连接本屏关心的全部事件信号；随后主动拉取设定资料快照
##（本屏可能晚于逻辑层就绪，错过其启动时的首次广播）。
func _connect_events() -> void:
	_dialogue.lore_loaded.connect(_on_lore_loaded)
	_dialogue.dialogue_started.connect(_on_dialogue_started)
	_dialogue.pack_built.connect(_on_pack_built)
	_dialogue.prompt_built.connect(_on_prompt_built)
	_dialogue.llm_request.connect(_on_llm_request)
	_dialogue.response.connect(_on_response)
	_dialogue.event_appended.connect(_on_event_appended)
	_dialogue.state_changed.connect(_on_state_changed)
	_dialogue.dialogue_ended.connect(_on_dialogue_ended)
	_dialogue.input_rejected.connect(_on_input_rejected)
	_dialogue.rolled_back.connect(_on_rolled_back)
	_dialogue.memory_reset.connect(_on_memory_reset)
	_dialogue.affinity_changed.connect(_on_affinity_changed)
	_llm.config.connect(_on_llm_config)
	_llm.mode_changed.connect(_on_llm_mode_changed)
	_nav.navigate_requested.connect(_on_navigate_requested)
	_nav.dialogue_requested.connect(_on_dialogue_requested)
	_dialogue.cmd_get_lore.emit()


## 设定资料快照到达：填充侧栏①页与 NPC/场景下拉。
## characters/scenes：Array[Dictionary]{id, label}；overview：总览文本。
func _on_lore_loaded(characters: Array, scenes: Array, overview: String) -> void:
	_lore_overview = overview
	settings_view.text = _lore_overview
	npc_option.clear()
	for item in characters:
		npc_option.add_item(str((item as Dictionary).get("label", "")))
		npc_option.set_item_metadata(npc_option.item_count - 1, (item as Dictionary).get("id", ""))
	scene_option.clear()
	for item in scenes:
		scene_option.add_item(str((item as Dictionary).get("label", "")))
		scene_option.set_item_metadata(scene_option.item_count - 1, (item as Dictionary).get("id", ""))
	if npc_option.item_count > 0:
		npc_option.selected = 0
	if scene_option.item_count > 0:
		scene_option.selected = 0
	if npc_option.item_count == 0 or scene_option.item_count == 0:
		round_label.text = "设定资料加载失败：请检查 res://settings/ 目录（详见①设定资料页）"
		start_btn.disabled = true


## 对话开始：更新本屏标题（场景 · NPC）并聚焦输入框。
func _on_dialogue_started(npc_name: String, scene_name: String) -> void:
	scene_label.text = "%s · %s" % [scene_name, npc_name]
	player_input.grab_focus()


## 本轮材料包组装完成：渲染到侧栏②页。
## pack：冻结后的 MaterialPack（含常识/检索知识、记忆、行动清单）。
func _on_pack_built(pack) -> void:
	pack_view.text = (pack as MaterialPack).to_display_text()


## 本轮提示词拼装完成：缓存原文并在侧栏③页展示完整提示词（System + User 一页）。
## system_prompt/user_prompt：静态规则层与本轮材料层全文。
func _on_prompt_built(system_prompt: String, user_prompt: String) -> void:
	current_system_prompt = system_prompt
	current_user_prompt = user_prompt
	current_full_prompt = "【System · 静态规则层】\n%s\n\n【User · 本轮材料层】\n%s" % [system_prompt, user_prompt]
	prompt_full_view.text = "[color=#e0b36a][b]■ System · 静态规则层[/b][/color]\n%s\n\n[color=#e0b36a][b]■ User · 本轮材料层[/b][/color]\n%s" % [
		_bb_escape(system_prompt), _bb_escape(user_prompt),
	]


## 模型请求开始：顶栏显示“请求中”状态。mode：客户端显示名（如 DeepSeek · deepseek-flash）。
## 回滚完成：清空对话区。
func _on_rolled_back(turn: int) -> void:
	_clear_dialogue_log()
	response_view.text = "（已回滚到第 %d 轮之前，请重新发言）" % turn


## 记忆重置完成。
func _on_memory_reset() -> void:
	round_label.text = "记忆已重置（恢复为人物卡初始状态）"


## 好感度变化：在轮次栏显示。
func _on_affinity_changed(value: int, change: int) -> void:
	var sign_text := "+" if change > 0 else ""
	round_label.text = "好感度 %s%d（%s）" % [sign_text, change, AffinityStore.tier_label(value)]


## 结算对话按钮：引擎侧结算并直接结束本段对话。
func _on_settle_pressed() -> void:
	_dialogue.cmd_settle_now.emit()


## 重置记忆按钮。
func _on_reset_memory_pressed() -> void:
	_dialogue.cmd_reset_memory.emit()


func _on_llm_request(mode: String) -> void:
	mode_label.text = "请求中（%s）…" % mode


## 模型回应到达（解析成功/保底/失败）：渲染到侧栏④页。
## result：引擎发布的回应 Dictionary（fallback/ok/error/raw/notes 等可变字段）。
func _on_response(result) -> void:
	response_view.text = _format_response(result)


## 一条对话事件落档：向对话记录追加对应气泡。
## event：统一记录格式（player_utterance/npc_utterance/npc_silence/dialogue_ended…）。
func _on_event_appended(event) -> void:
	_append_bubble(event)


## 引擎状态变化：更新轮次栏、输入可用性与按钮状态。
## 等待模型（审查中/生成中）期间置灰全部状态变更入口：
## 气泡「↩」回滚、结算、重置记忆与开始新对话。
## state：状态中文名；turn：当前轮次；can_accept：是否可接受玩家输入。
func _on_state_changed(state: String, turn: int, _turns_left: int, can_accept: bool) -> void:
	round_label.text = "第 %d / %d 轮 · %s" % [turn, DialogueController.MAX_TURNS, state]
	_can_accept = can_accept
	_actions_enabled = can_accept
	_set_input_enabled(_can_accept)
	var busy := state == "等待NPC回应" or state == "输入审查中"
	for btn in _rollback_buttons:
		btn.disabled = not _actions_enabled
	settle_btn.disabled = not _actions_enabled
	reset_mem_btn.disabled = busy
	start_btn.disabled = busy


## 对话结束：输入框占位文案提示重新开始。
func _on_dialogue_ended(_reason: String) -> void:
	player_input.placeholder_text = "对话已结束，点击『开始新对话』重新开始"


## 输入被审查拒绝：追加红色提示气泡、侧栏④页展示详情、原输入退回输入框。
## text：被拒的玩家原话；reason：审查给出的拒绝理由。
func _on_input_rejected(text: String, reason: String) -> void:
	_append_rejection_bubble(reason)
	response_view.text = _format_rejection(text, reason)
	player_input.text = text  # 原输入退回输入框，供修改后重发
	player_input.grab_focus()


## LLM 配置快照到达：更新顶栏模型显示（Key/模型缓存归设置屏管理，此处忽略）。
## mode：当前客户端显示名。
func _on_llm_config(_api_key: String, _model: String, mode: String) -> void:
	mode_label.text = "模型：" + mode


## 模型客户端切换（配置变更后）：更新顶栏模型显示。name：新客户端显示名。
func _on_llm_mode_changed(name: String) -> void:
	mode_label.text = "模型：" + name


## 导航事件：进入本屏时聚焦输入框（对话状态由引擎事件驱动，无需其它初始化）。
## screen：目标屏幕标识（"dialogue" 时处理）。
func _on_navigate_requested(screen: String) -> void:
	if screen == "dialogue":
		player_input.grab_focus()


# ============================================================
#  玩家操作（信号已在场景 [connection] 中接线；动作经集线器命令信号发往逻辑层）
# ============================================================


## 「← 菜单」：请求导航回开始菜单。
func _on_back_pressed() -> void:
	_nav.navigate_requested.emit("menu")


## 「开始新对话」按钮：以当前下拉选择开始。
func _on_start_pressed() -> void:
	_start_current()


## 以当前 NPC/场景下拉选择开始新对话（清空对话区与侧栏②③④页）。
func _start_current() -> void:
	if npc_option.selected == -1 or scene_option.selected == -1:
		return
	_clear_dialogue_log()
	pack_view.text = "（发送一句话后，这里显示本轮组装的材料包）"
	prompt_full_view.text = "（等待对话开始）"
	response_view.text = "（等待模型回应）"
	player_input.placeholder_text = "说一句话，回车发送…"
	_dialogue.cmd_start.emit(
		str(npc_option.get_item_metadata(npc_option.selected)),
		str(scene_option.get_item_metadata(scene_option.selected)),
	)


## 编辑页请求与某人物对话：预选该 NPC 并以默认场景自动开始。
## npc_id：人物卡 id。
func _on_dialogue_requested(npc_id: String) -> void:
	for i in npc_option.item_count:
		if str(npc_option.get_item_metadata(i)) == npc_id:
			npc_option.selected = i
			break
	_start_current()


## 输入框回车提交：等价于点击「发送」。text：玩家输入原话。
func _on_input_submitted(text: String) -> void:
	_send(text)


## 「发送」按钮：提交输入框当前内容。
func _on_send_pressed() -> void:
	_send(player_input.text)


## 提交玩家输入：引擎可接受时发射 cmd_submit 并清空输入框。
## text：玩家输入原话（首尾空白由引擎剔除）。
func _send(text: String) -> void:
	if not _can_accept:
		return
	_dialogue.cmd_submit.emit(text)
	player_input.clear()


## 「调试侧栏」：按按钮按下状态展开/收起右侧四页调试面板。
## pressed：true=展开侧栏，false=收起。
func _on_sidebar_toggled(pressed: bool) -> void:
	debug_sidebar.visible = pressed


## 「复制完整提示词」（两层原文，未转义）到系统剪贴板。
func _copy_prompt() -> void:
	DisplayServer.clipboard_set(current_full_prompt)


# ============================================================
#  对话记录渲染（气泡为动态内容，运行期创建）
# ============================================================


## 按事件类型向对话记录追加一条气泡（玩家/NPC/沉默/开始/结束/兜底）。
## event：统一记录格式的 Dictionary（event 键决定分支）。
func _append_bubble(event) -> void:
	var e := event as Dictionary
	var view := _new_bubble()

	match str(e.get("event", "")):
		"dialogue_started":
			_add_system_line(view, "—— 对话开始 · %s · %s ——" % [e.get("scene_name", ""), e.get("npc_name", "")])
		"player_utterance":
			_push_pair(view, "你：", COLOR_PLAYER)
			view.add_text(" " + str(e.get("text", "")))
			var pcopy := Button.new()
			pcopy.text = "⎘"
			pcopy.custom_minimum_size = Vector2(26, 20)
			pcopy.tooltip_text = "复制"
			pcopy.pressed.connect(func(): DisplayServer.clipboard_set(str(e.get("text", ""))))
			view.add_text("  ")
			view.add_child(pcopy)
		"npc_utterance":
			_push_pair(view, "%s：" % str(e.get("npc_name", "NPC")), COLOR_NPC)
			view.add_text(" " + str(e.get("text", "")))
			_push_claim_tag(view, str(e.get("claim_type", "猜测")))
			if str(e.get("action", "")) == "end_dialogue" and not str(e.get("action_description", "")).is_empty():
				view.add_text("  ")
				_push_italic(view, "（%s）" % str(e.get("action_description", "")), COLOR_SYSTEM)
			var turn := int(e.get("turn", 0))
			var copy_btn := Button.new()
			copy_btn.text = "⎘"
			copy_btn.custom_minimum_size = Vector2(26, 20)
			copy_btn.tooltip_text = "复制这段发言"
			copy_btn.pressed.connect(func(): DisplayServer.clipboard_set(str(e.get("text", ""))))
			var rollback_btn := Button.new()
			rollback_btn.text = "↩"
			rollback_btn.custom_minimum_size = Vector2(26, 20)
			rollback_btn.tooltip_text = "回滚到第 %d 轮之前" % turn
			rollback_btn.disabled = not _actions_enabled
			rollback_btn.pressed.connect(func(): _dialogue.cmd_rollback_to_turn.emit(turn))
			_rollback_buttons.append(rollback_btn)
			view.add_text("  ")
			view.add_child(copy_btn)
			view.add_child(rollback_btn)
		"npc_silence":
			_push_pair(view, "%s（沉默）" % str(e.get("npc_name", "NPC")), COLOR_SILENCE)
			view.add_text(" " + str(e.get("description", "")))
		"dialogue_ended":
			var reason := str(e.get("reason", ""))
			var reason_text := str({"npc_action": "NPC 结束了对话", "turn_limit": "达到轮次上限", "manual_settle": "手动结算结束"}.get(reason, reason))
			_add_system_line(view, "—— %s，此后不能续聊 ——" % reason_text)
		"fallback_used":
			_add_system_line(view, "（保底回应触发：%s）" % str(e.get("reason", "")))
		"knowledge_learned":
			_add_system_line(view, "（%s默默记下了：%s）" % [str(e.get("npc_name", "")), str(e.get("content", ""))])
		"belief_updated":
			_add_system_line(view, "（%s对此事的想法变了：%s → %s）" % [
				str(e.get("npc_name", "")), str(e.get("before", "")), str(e.get("after", "")),
			])

	dialogue_log.add_child(view)
	_scroll_to_bottom.call_deferred()


## 追加一条输入被拒的红色提示气泡（世界外提示，非对话事件）。
## reason：审查给出的拒绝理由。
func _append_rejection_bubble(reason: String) -> void:
	var view := _new_bubble()
	view.push_color(COLOR_ERROR)
	view.push_bold()
	view.add_text("（输入被拒绝）")
	view.pop()
	view.pop()
	view.add_text(" " + reason)
	view.push_color(COLOR_SYSTEM)
	view.add_text(" 只输入你角色说出的话；动作与指令不通过输入框执行。")
	view.pop()
	dialogue_log.add_child(view)
	_scroll_to_bottom.call_deferred()


## 新建一条对话气泡（自适应高度、禁用内部滚动、随容器拉伸宽度）。
func _new_bubble() -> RichTextLabel:
	var view := RichTextLabel.new()
	view.bbcode_enabled = true
	view.fit_content = true
	view.scroll_active = false
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return view


## 写入气泡开头的彩色加粗昵称前缀（如“你：”）并闭合样式。
## prefix：昵称前缀文本；color：昵称颜色。
func _push_pair(view: RichTextLabel, prefix: String, color: Color) -> void:
	view.push_color(color)
	view.push_bold()
	view.add_text(prefix)
	view.pop()
	view.pop()


## 在 NPC 发言气泡末尾追加 claim 标签：非“确知”一律记作“声称（…）”（设计 4.5 落档措辞）。
## claim：发言性质声明（确知/猜测/虚张声势）。
func _push_claim_tag(view: RichTextLabel, claim: String) -> void:
	var tag := "确知" if claim == "确知" else "声称（%s）" % claim
	view.push_color(COLOR_SYSTEM)
	view.add_text("  〔%s〕" % tag)
	view.pop()


## 写入一段彩色斜体文本（如结束对话的离开动作描述）并闭合样式。
## text：文本内容；color：颜色。
func _push_italic(view: RichTextLabel, text: String, color: Color) -> void:
	view.push_color(color)
	view.push_italics()
	view.add_text(text)
	view.pop()
	view.pop()


## 写入一行系统灰色文本（对话开始/结束等横幅提示）并闭合样式。
func _add_system_line(view: RichTextLabel, text: String) -> void:
	view.push_color(COLOR_SYSTEM)
	view.add_text(text)
	view.pop()


## 清空对话记录（开始新对话时；queue_free 让出余帧安全释放）。
func _clear_dialogue_log() -> void:
	_rollback_buttons.clear()
	for child in dialogue_log.get_children():
		child.queue_free()


## 把对话记录滚动到底部（延迟到帧末，等气泡完成布局）。
func _scroll_to_bottom() -> void:
	dialogue_scroll.scroll_vertical = 100000000


# ============================================================
#  审查拒绝 / ④ 模型回应页渲染
# ============================================================


## 组装侧栏④页「输入被拒绝」的说明文本。
## text：被拒的玩家原话；reason：拒绝理由。
func _format_rejection(text: String, reason: String) -> String:
	var p: Array[String] = []
	p.append("[color=#e76f51][b]【输入被拒绝，未进入对话】[/b][/color]")
	p.append("· 理由：" + _bb_escape(reason))
	p.append("· 原输入：" + _bb_escape(text))
	p.append("")
	p.append("[color=#8d99ae]审查标准：只接受你角色“说出口的话”。括号/星号/空格包裹的动作、")
	p.append("诱导性提问与注入指令都会被拒绝。原输入已退回输入框，修改后可重新发送。[/color]")
	return "\n".join(p)


## 组装侧栏④页「模型回应」的解析详情（保底/失败/成功三分支，末尾附原始输出）。
## result：引擎发布的回应 Dictionary（fallback/ok/error/raw/action/claim_type…）。
func _format_response(result) -> String:
	var r := result as Dictionary
	var p: Array[String] = []
	if r.get("fallback", false):
		p.append("[color=#e76f51][b]（保底回应已触发：%s）[/b][/color]" % _bb_escape(str(r.get("error", ""))))
	elif not r.get("ok", true):
		p.append("[color=#e76f51][b]请求失败：%s[/b][/color]" % _bb_escape(str(r.get("error", ""))))
		p.append("可在『设置』中检查 Key 与网络后重试；此失败不写入对话记录。")
		p.append("")
		p.append("[color=#8d99ae]———— 模型原始输出 ————[/color]")
		p.append(_bb_escape(str(r.get("raw", "（无）"))))
		return "\n".join(p)
	else:
		p.append("[color=#90be6d][b]解析成功[/b][/color]")
		p.append("")
		p.append("[b]■ 行动提案[/b]")
		var action: Dictionary = r.get("action", {})
		p.append("· 类型：[color=#90be6d]%s[/color]（%s）" % [action.get("type", ""), action.get("name", "")])
		if not str(action.get("description", "")).is_empty():
			p.append("· 描述：%s" % _bb_escape(str(action.get("description", ""))))
		p.append("")
		p.append("[b]■ 发言性质声明（claim_type）[/b]")
		var claim := str(r.get("claim_type", ""))
		p.append("· %s%s" % [claim, "  ——落档将记作“某人声称”" if claim != "确知" else ""])
		p.append("")
		p.append("[b]■ 发言文本[/b]")
		var utterance := str(r.get("utterance", ""))
		p.append(_bb_escape(utterance) if not utterance.is_empty() else "[i]（空：选择了沉默）[/i]")
		p.append("")
		p.append("[b]■ 内心想法（仅调试用，不入记录、不入记忆、玩家不可见）[/b]")
		var inner := str(r.get("inner_thought", ""))
		p.append(_bb_escape(inner) if not inner.is_empty() else "[i]（模型未提供）[/i]")
		var learned: Array = r.get("learned", [])
		if not learned.is_empty():
			p.append("")
			p.append("[b]■ 习得（quote 依据 / summary 表述）[/b]")
			for item in learned:
				var d := item as Dictionary
				p.append("· 表述：" + _bb_escape(str(d.get("summary", ""))))
				p.append("  依据：“%s”" % _bb_escape(str(d.get("quote", ""))))
		var updates: Array = r.get("belief_updates", [])
		if not updates.is_empty():
			p.append("")
			p.append("[b]■ 信念变化提案[/b]")
			for item in updates:
				var d := item as Dictionary
				p.append("· [%d] %s：%s" % [int(d.get("ref", 0)), str(d.get("relation", "")), _bb_escape(str(d.get("note", "")))])
		var notes: Array = r.get("notes", [])
		if not notes.is_empty():
			p.append("")
			p.append("[b]■ 解析提示与自动修复[/b]")
			for note in notes:
				p.append("· " + _bb_escape(str(note)))
	p.append("")
	p.append("[color=#8d99ae]———— 模型原始输出 ————[/color]")
	p.append(_bb_escape(str(r.get("raw", "（无）"))))
	return "\n".join(p)


# ============================================================
#  小工具
# ============================================================


## BBCode 字面转义：模型输出中的 [ ] 不应被当作标签解析。
func _bb_escape(text: String) -> String:
	return text.replace("[", "[lb]")


## 设置输入框与发送按钮的可用性。enabled：true=可输入。
func _set_input_enabled(enabled: bool) -> void:
	player_input.editable = enabled
	send_btn.disabled = not enabled
