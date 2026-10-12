extends Control
## 世界屏（Scripts/UI/）：统一入口的唯一游戏界面——位置面板（当前地点 + 相邻移动 +
## 在场 NPC）、一个输入框（做点什么，或对谁说句话——DM 裁决路由）、世界叙述流
## （旁白与对话气泡混排，SillyTavern 式单一流），以及调试侧栏四页
## （①世界事实 ②材料包 ③完整提示词 ④模型回应——双域共用，最新覆盖）。
## 与逻辑层经 EventBus 集线器中转：NarrationEvents（DM/行动域/事实库）与
## DialogueEvents（人物域）收发。忙时门控合并：DM 裁决中 或 对话生成中 或 结算中。

const COLOR_PLAYER := Color("#7ec8e3")   # 玩家气泡的颜色
const COLOR_NPC := Color("#e9c46a")      # NPC 气泡的昵称色
const COLOR_SILENCE := Color("#a8a29e")  # 沉默气泡的颜色
const COLOR_NARRATOR := Color("#ced4da") # 旁白叙述正文的颜色
const COLOR_OUTCOME := Color("#8d99ae")  # outcome 标签的颜色
const COLOR_SYSTEM := Color("#8d99ae")   # 系统提示行的颜色
const COLOR_ERROR := Color("#e76f51")    # 失败提示的颜色
const COLOR_LOCATION := Color("#e9c46a") # 位置面板文字（金）

# —— 顶栏 ——
@onready var status_label: Label = %StatusLabel
@onready var mode_label: Label = %ModeLabel

# —— 世界区 ——
@onready var scroll: ScrollContainer = %NarrationScroll
@onready var log_box: VBoxContainer = %NarrationLog
@onready var action_input: LineEdit = %ActionInput
@onready var send_btn: Button = %SendBtn
@onready var settle_btn: Button = %SettleBtn
@onready var end_talk_btn: Button = %EndTalkBtn
@onready var reset_mem_btn: Button = %ResetMemBtn

# —— 调试侧栏（默认收起，按钮展开；①页为代码构建的事实库浏览器） ——
@onready var debug_sidebar: Control = %DebugSidebar
@onready var pack_view: RichTextLabel = %PackView
@onready var prompt_full_view: RichTextLabel = %PromptFullView
@onready var response_view: RichTextLabel = %ResponseView

# —— 事件集线器 ——
var _narration: NarrationEvents   # DM / 行动域 / 事实库
var _dialogue: DialogueEvents     # 人物域
var _llm: LlmEvents
var _nav: UiEvents

# —— 状态缓存 ——
var current_full_prompt := ""        # 两层拼合的完整提示词原文（复制按钮用）
var _dm_state_name := ""            # DM 状态机显示名
var _dm_turn := 0
var _dm_ok := false                 # DM 状态机可接受输入
var _dlg_active := false            # 对话进行中
var _dlg_can_accept := false        # 对话轮到玩家
var _dlg_busy := false              # 对话生成中
var _dlg_settling := false          # 对话结算窗口（引擎事件到信号之间）
var _dlg_turn := 0
var _dlg_partner_name := ""
var _location_panel: VBoxContainer  # 位置面板（动态构建）
var _loc_label: Label               # 当前位置名
var _npc_buttons_box: HBoxContainer # 在场 NPC 按钮容器
var _travel_buttons: Array[Button] = []  # 相邻地点移动按钮（忙时统一置灰）


## 取全局事件总线；autoload 未就绪时（理论上仅测试环境）手动创建。
func _bus() -> EventBus:
	return EventBus.shared() if EventBus.shared() != null else EventBus.create_shared()


## 初始化：构建位置面板、挂载事实库浏览器、连接双域信号、补拉状态。
func _ready() -> void:
	_narration = _bus().hub(NarrationEvents) as NarrationEvents
	_dialogue = _bus().hub(DialogueEvents) as DialogueEvents
	_llm = _bus().hub(LlmEvents) as LlmEvents
	_nav = _bus().hub(UiEvents) as UiEvents
	_build_location_panel()
	_attach_fact_browser()
	# DM / 行动域
	_narration.state_changed.connect(_on_dm_state_changed)
	_narration.location_changed.connect(_on_location_changed)
	_narration.pack_built.connect(_on_pack_built)
	_narration.prompt_built.connect(_on_prompt_built)
	_narration.llm_request.connect(_on_llm_request)
	_narration.event_appended.connect(_on_event_appended)
	_narration.dm_resolved.connect(_on_dm_resolved)
	_narration.world_input_rejected.connect(_on_world_input_rejected)
	# 人物域
	_dialogue.dialogue_started.connect(_on_dialogue_started)
	_dialogue.dialogue_ended.connect(_on_dialogue_ended)
	_dialogue.state_changed.connect(_on_dialogue_state_changed)
	_dialogue.event_appended.connect(_on_event_appended)
	_dialogue.response.connect(_on_dialogue_response)
	_dialogue.pack_built.connect(_on_pack_built)
	_dialogue.prompt_built.connect(_on_prompt_built)
	_dialogue.memory_reset.connect(_on_memory_reset)
	_dialogue.affinity_changed.connect(_on_affinity_changed)
	_llm.mode_changed.connect(_on_llm_mode_changed)
	_nav.navigate_requested.connect(_on_navigate_requested)
	_nav.dialogue_requested.connect(_on_dialogue_requested)
	_narration.cmd_get_state.emit()  # 控制器常驻 WAITING_PLAYER：初始广播早于本屏就绪，补拉


## 挂载事实库浏览器为调试侧栏①页（代码构建；订阅 canon_listed、发编辑命令均自理）。
func _attach_fact_browser() -> void:
	var browser := FactBrowser.new()
	browser.name = "① 世界事实"
	debug_sidebar.add_child(browser)
	debug_sidebar.move_child(browser, 0)


func _build_location_panel() -> void:
	var box: VBoxContainer = %NarrationScroll.get_parent()  # NarrationBox
	_location_panel = VBoxContainer.new()
	_location_panel.add_theme_constant_override("separation", 6)
	var loc_row := HBoxContainer.new()
	loc_row.add_theme_constant_override("separation", 10)
	_loc_label = Label.new()
	_loc_label.add_theme_color_override("font_color", COLOR_LOCATION)
	_loc_label.add_theme_font_size_override("font_size", 16)
	loc_row.add_child(_loc_label)
	loc_row.add_child(_make_spring())
	_location_panel.add_child(loc_row)
	var npc_row := HBoxContainer.new()
	npc_row.add_theme_constant_override("separation", 10)
	var npc_caption := Label.new()
	npc_caption.text = "在场："
	npc_caption.add_theme_color_override("font_color", COLOR_SYSTEM)
	npc_caption.add_theme_font_size_override("font_size", 14)
	npc_row.add_child(npc_caption)
	_npc_buttons_box = HBoxContainer.new()
	_npc_buttons_box.add_theme_constant_override("separation", 10)
	npc_row.add_child(_npc_buttons_box)
	_location_panel.add_child(npc_row)
	var separator := HSeparator.new()
	_location_panel.add_child(separator)
	box.add_child(_location_panel)
	box.move_child(_location_panel, 1)  # HintLabel 之后、叙述流之前


func _make_spring() -> Control:
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spring


# ============================================================
#  门控与状态栏（DM 与对话合成）
# ============================================================


## DM 状态机快照：缓存状态名与回合（状态栏用），更新门控与按钮。
func _on_dm_state_changed(state: String, turn: int, can_accept: bool) -> void:
	_dm_state_name = state
	_dm_turn = turn
	_dm_ok = can_accept
	_refresh_gating()


## 对话状态快照：更新门控、状态栏与「结束交谈」按钮。
## 【可修复】turns_left 参数由信号携带但未使用（状态栏以 MAX_TURNS 常量自算）——接上即可去掉对常量的依赖。
func _on_dialogue_state_changed(state: String, turn: int, _turns_left: int,
		can_accept: bool, busy: bool) -> void:
	_dlg_busy = busy
	_dlg_can_accept = can_accept
	_dlg_turn = turn
	if state == "对话已结束":
		_dlg_active = false
	_refresh_gating()


## 统一刷新输入可用性与按钮状态（DM 可输入 且 对话不在生成/结算窗口）。
func _refresh_gating() -> void:
	var input_ok := _dm_ok and not _dlg_busy and not _dlg_settling
	action_input.editable = input_ok
	send_btn.disabled = not input_ok
	action_input.placeholder_text = "做点什么，或对谁说句话…" if input_ok \
		else "世界正在回应…"
	for btn in _travel_buttons:
		btn.disabled = not input_ok or _dlg_active
	end_talk_btn.disabled = not (_dlg_active and _dlg_can_accept and not _dlg_busy)
	reset_mem_btn.disabled = end_talk_btn.disabled
	settle_btn.disabled = not _dm_ok or _dlg_active or _dlg_settling
	_refresh_status()


## 合成状态栏：对话进行中显示交谈对象与轮次，否则显示 DM 状态。
func _refresh_status() -> void:
	if _dlg_active:
		status_label.text = "与 %s 交谈中 · 第 %d / %d 轮" % [
			_dlg_partner_name, _dlg_turn, DialogueController.MAX_TURNS]
	else:
		status_label.text = "回合 %d · %s" % [_dm_turn, _dm_state_name]


## 位置快照到达（启动/移动/补拉）：重建移动按钮与在场 NPC 列表。
## 在场 NPC 点击直接开始交谈（cmd_talk_to 捷径，绕过 DM）。
func _on_location_changed(current_id: String, current_name: String, neighbors: Array, npcs: Array, brief: String) -> void:
	_loc_label.text = "位置：%s" % current_name
	var loc_row: HBoxContainer = _loc_label.get_parent()
	for child in loc_row.get_children():
		if child is Button:
			child.queue_free()
	_travel_buttons.clear()
	for raw in neighbors:
		var d := raw as Dictionary
		var btn := Button.new()
		btn.text = "→ %s" % str(d.get("name", ""))
		btn.tooltip_text = "前往 %s" % str(d.get("name", ""))
		var target := str(d.get("id", ""))
		btn.pressed.connect(func(): _narration.cmd_travel_to.emit(target))
		_travel_buttons.append(btn)
		loc_row.add_child(btn)
	for child in _npc_buttons_box.get_children():
		child.queue_free()
	if npcs.is_empty():
		var empty := Label.new()
		empty.text = "（无人在场）"
		empty.add_theme_color_override("font_color", COLOR_SYSTEM)
		_npc_buttons_box.add_child(empty)
	for raw in npcs:
		var d := raw as Dictionary
		var btn := Button.new()
		btn.text = "与 %s 交谈" % str(d.get("name", ""))
		btn.tooltip_text = "与 %s 对话（%s）" % [str(d.get("name", "")), str(d.get("id", ""))]
		var npc_id := str(d.get("id", ""))
		btn.pressed.connect(func(): _narration.cmd_talk_to.emit(npc_id))
		_npc_buttons_box.add_child(btn)
	_refresh_gating()


# ============================================================
#  事件处理（世界屏 ← 集线器信号 ← 控制器）
# ============================================================


## 本轮材料包组装完成（双域共用②页，最新覆盖）：按实际类型渲染到侧栏②页。
func _on_pack_built(pack) -> void:
	if pack is MaterialPack:
		pack_view.text = (pack as MaterialPack).to_display_text()
	elif pack is NarrationPack:
		pack_view.text = (pack as NarrationPack).to_display_text()
	else:
		push_warning("未知材料包类型：%s" % pack.get_class())


## 提示词拼装完成（双域共用③页）：缓存原文并展示两层全文。
func _on_prompt_built(system_prompt: String, user_prompt: String) -> void:
	current_full_prompt = "【System · 静态规则层】\n%s\n\n【User · 本轮材料层】\n%s" % [system_prompt, user_prompt]
	prompt_full_view.text = "[color=#e0b36a][b]■ System · 静态规则层[/b][/color]\n%s\n\n[color=#e0b36a][b]■ User · 本轮材料层[/b][/color]\n%s" % [
		_bb_escape(system_prompt), _bb_escape(user_prompt),
	]


## 模型请求开始：顶栏显示"请求中"。
func _on_llm_request(mode: String) -> void:
	mode_label.text = "请求中（%s）…" % mode


## 模型客户端切换：更新顶栏显示。
func _on_llm_mode_changed(name: String) -> void:
	mode_label.text = "模型：" + name


## DM 裁决结果（④页展示路由详情：路由/目标/行动叙述/话语/修复 notes）。
func _on_dm_resolved(result: Dictionary) -> void:
	response_view.text = _format_dm_result(result)


## 对话回应到达（④页展示解析详情）。
func _on_dialogue_response(result: Dictionary) -> void:
	response_view.text = _format_dialogue_response(result)


## DM 拒绝输入（注入/元指令）：红色提示气泡 + 原输入退回输入框。
func _on_world_input_rejected(text: String, reason: String) -> void:
	_append_rejection_bubble(reason)
	response_view.text = "[color=#e76f51][b]【输入被 DM 拒绝】[/b][/color]\n· 理由：" + _bb_escape(reason) \
		+ "\n· 原输入：" + _bb_escape(text)
	action_input.text = text
	action_input.grab_focus()


## 对话开始：记录对象名（状态栏用）并聚焦输入框。
func _on_dialogue_started(_npc_id: String, npc_name: String, _scene_name: String) -> void:
	_dlg_active = true
	_dlg_partner_name = npc_name
	_refresh_gating()
	action_input.grab_focus()


## 对话结束：结算窗口关闭，回到 DM 状态栏。
func _on_dialogue_ended(_reason: String) -> void:
	_dlg_settling = false
	_refresh_gating()


## 记忆重置完成。
func _on_memory_reset() -> void:
	status_label.text = "记忆已重置（恢复为人物卡初始状态）"


## 好感度变化：状态栏短暂显示。
func _on_affinity_changed(value: int, change: int) -> void:
	var sign_text := "+" if change > 0 else ""
	status_label.text = "好感度 %s%d（%s）" % [sign_text, change, AffinityStore.tier_label(value)]


## 导航事件：进入本屏时聚焦输入框并重拉状态。
func _on_navigate_requested(screen: String) -> void:
	if screen == "narration":
		action_input.grab_focus()
		_narration.cmd_get_state.emit()


## 人物编辑页请求与某人对话：直接开始交谈（当前位置为场景）。
func _on_dialogue_requested(npc_id: String) -> void:
	_narration.cmd_talk_to.emit(npc_id)


# ============================================================
#  玩家操作（信号已在场景 [connection] 中接线）
# ============================================================


## 「← 菜单」：请求导航回开始菜单。
func _on_back_pressed() -> void:
	_nav.navigate_requested.emit("menu")


## 输入框回车提交：等价于点击「发送」。
func _on_input_submitted(text: String) -> void:
	_send(text)


## 「发送」按钮：提交输入框当前内容（统一入口——DM 裁决路由）。
func _on_send_pressed() -> void:
	_send(action_input.text)


## 提交玩家输入：门控通过时发射 cmd_submit_input 并清空输入框。
func _send(text: String) -> void:
	if not (action_input.editable and not send_btn.disabled):
		return
	_narration.cmd_submit_input.emit(text)
	action_input.clear()


## 「结算探索」/「开始新探索」按钮（事实整理者提取世界事实 / 重置回合）。
func _on_settle_pressed() -> void:
	if settle_btn.text == "开始新探索":
		_narration.cmd_start_exploration.emit()
	else:
		_narration.cmd_settle_narration.emit()


## 「结束交谈」按钮：结算当前对话（学习与记忆落档）回到行动域。
func _on_end_talk_pressed() -> void:
	_dialogue.cmd_settle_now.emit()


## 「重置记忆」按钮：清空当前交谈对象的知识日志与记忆（回落卡面初始状态）。
## 引擎侧要求对话进行中（current_person 存在），门控与「结束交谈」一致。
func _on_reset_memory_pressed() -> void:
	if reset_mem_btn.disabled:
		return
	_dialogue.cmd_reset_memory.emit()


## 「调试侧栏」：按按钮按下状态展开/收起右侧四页调试面板。
func _on_sidebar_toggled(pressed: bool) -> void:
	debug_sidebar.visible = pressed


## 「复制完整提示词」（两层原文，未转义）到系统剪贴板。
func _copy_prompt() -> void:
	DisplayServer.clipboard_set(current_full_prompt)


# ============================================================
#  世界叙述流渲染（旁白与对话气泡混排；动态内容，运行期创建）
# ============================================================


## 一条世界事件落档（双域同源）：向叙述流追加对应气泡。
func _on_event_appended(event: Dictionary) -> void:
	_append_bubble(event)
	var kind := str((event as Dictionary).get("event", ""))
	if kind == "dialogue_ended":
		_dlg_settling = true  # 引擎事件先于结算完成；dialogue_ended 信号到达时清除
		_refresh_gating()


## 按事件类型追加气泡（旁白/对话/位置/事实/系统横幅）。
func _append_bubble(event: Dictionary) -> void:
	var e := event as Dictionary
	var view := _new_bubble()

	match str(e.get("event", "")):
		"player_action":
			view.push_color(COLOR_PLAYER)
			view.push_bold()
			view.add_text("你（行动）：")
			view.pop()
			view.pop()
			view.add_text(" " + str(e.get("text", "")))
		"narration_turn":
			var outcome := str(e.get("outcome", ""))
			view.push_color(COLOR_OUTCOME)
			view.add_text("〔%s〕 " % outcome)
			view.pop()
			view.push_color(COLOR_NARRATOR)
			view.add_text(str(e.get("text", "")))
			view.pop()
		"player_utterance":
			view.push_color(COLOR_PLAYER)
			view.push_bold()
			view.add_text("你：")
			view.pop()
			view.pop()
			view.add_text(" " + str(e.get("text", "")))
		"npc_utterance":
			view.push_color(COLOR_NPC)
			view.push_bold()
			view.add_text("%s：" % str(e.get("npc_name", "NPC")))
			view.pop()
			view.pop()
			view.add_text(" " + str(e.get("text", "")))
			_push_claim_tag(view, str(e.get("claim_type", "猜测")))
			if str(e.get("action", "")) == "end_dialogue" and not str(e.get("action_description", "")).is_empty():
				view.add_text("  ")
				_push_italic(view, "（%s）" % str(e.get("action_description", "")), COLOR_SYSTEM)
		"npc_silence":
			view.push_color(COLOR_SILENCE)
			view.push_bold()
			view.add_text("%s（沉默）" % str(e.get("npc_name", "NPC")))
			view.pop()
			view.pop()
			view.add_text(" " + str(e.get("description", "")))
		"dialogue_started":
			_system_line(view, "—— 开始与 %s 交谈 ——" % str(e.get("npc_name", "")))
		"dialogue_ended":
			var reason := str(e.get("reason", ""))
			var reason_text := str({"npc_action": "%s 结束了对话" % str(e.get("npc_name", "")),
				"turn_limit": "达到轮次上限", "manual_settle": "交谈结束"}.get(reason, "交谈结束"))
			_system_line(view, "—— %s，回到行动 ——" % reason_text)
		"belief_updated":
			_system_line(view, "（%s对此事的想法变了：%s → %s）" % [
				str(e.get("npc_name", "")), str(e.get("before", "")), str(e.get("after", "")),
			])
		"location_travelled":
			# 【可修复】事件的 to 字段（目标地点 id）未展示，渲染用的是 name——展示 id 可辅助调试
			var brief := str(e.get("brief", ""))
			if brief.is_empty():
				_system_line(view, "—— 你来到了%s ——" % str(e.get("name", "")))
			else:
				_system_line(view, "—— 你再次回到%s：%s ——" % [str(e.get("name", "")), brief])
		"scene_described":
			# 【可修复】事件的 frozen 字段（描述是否已冻结为 brief）未展示——接上可区分"临时一瞥/已冻结"
			view.push_color(COLOR_LOCATION)
			view.add_text("【%s · 初见】" % str(e.get("name", "")))
			view.pop()
			view.push_color(COLOR_NARRATOR)
			view.add_text(str(e.get("text", "")))
			view.pop()
		"fact_established":
			_system_line(view, "（世界多了一条事实 [%d]：%s）" % [int(e.get("id", 0)), str(e.get("content", ""))])
		"fact_superseded":
			# 【可修复】事件的 new_id 字段（取代者的编号）未展示——接上可从气泡直接跳到新事实
			var ripple := int(e.get("ripples", 0))
			var ripple_text := "（%d 条信念过时）" % ripple if ripple > 0 else ""
			_system_line(view, "（事实 [%d] 被改写：%s）%s" % [
				int(e.get("old_id", 0)), str(e.get("content", "")), ripple_text])
		"fact_edited":
			_system_line(view, "（事实 [%d] 被手动修改：%s）" % [int(e.get("id", 0)), str(e.get("content", ""))])
		"fact_deleted":
			_system_line(view, "（事实 [%d] 已被移除）" % int(e.get("id", 0)))
		"canon_reset":
			_system_line(view, "—— 事实库已重置为作者正典（共 %d 条事实） ——" % int(e.get("facts", 0)))
		"exploration_settled":
			# 【可修复】事件的 notes 字段（提取器的丢弃/降级明细）未展示——调试④页有全量，此处可补一行
			_system_line(view, "—— 探索已结算：整理者收录/更新了 %d 条世界事实（共 %d 回合），此后不能继续行动 ——" % [
				int(e.get("facts", 0)), int(e.get("turns", 0))])
			settle_btn.text = "开始新探索"
		"extraction_failed":
			view.push_color(COLOR_ERROR)
			view.add_text("（事实整理失败：%s——探索继续，可再次结算）" % str(e.get("error", "")))
			view.pop()
		"exploration_started":
			_system_line(view, "—— 新的探索开始了 ——")
			settle_btn.text = "结算探索"
			_clear_log()
		"world_input_rejected":
			view.push_color(COLOR_ERROR)
			view.add_text("（DM 拒绝了这条输入）")
			view.pop()
			view.add_text(" " + str(e.get("reason", "")))
		"fallback_used":
			_system_line(view, "（保底回应触发：%s）" % str(e.get("reason", "")))

	log_box.add_child(view)
	_scroll_to_bottom.call_deferred()


## 追加一条 DM 拒绝的红色提示气泡（世界外提示）。
func _append_rejection_bubble(reason: String) -> void:
	var view := _new_bubble()
	view.push_color(COLOR_ERROR)
	view.push_bold()
	view.add_text("（输入被拒绝）")
	view.pop()
	view.pop()
	view.add_text(" " + reason)
	view.push_color(COLOR_SYSTEM)
	view.add_text(" 只接受世界内的行动与话语。")
	view.pop()
	log_box.add_child(view)
	_scroll_to_bottom.call_deferred()


func _new_bubble() -> RichTextLabel:
	var view := RichTextLabel.new()
	view.bbcode_enabled = true
	view.fit_content = true
	view.scroll_active = false
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return view


## NPC 发言末尾的 claim 标签：非"确知"一律记作"声称（…）"。
func _push_claim_tag(view: RichTextLabel, claim: String) -> void:
	var tag := "确知" if claim == "确知" else "声称（%s）" % claim
	view.push_color(COLOR_SYSTEM)
	view.add_text("  〔%s〕" % tag)
	view.pop()


## 写入一段彩色斜体文本并闭合样式。
func _push_italic(view: RichTextLabel, text: String, color: Color) -> void:
	view.push_color(color)
	view.push_italics()
	view.add_text(text)
	view.pop()
	view.pop()


func _system_line(view: RichTextLabel, text: String) -> void:
	view.push_color(COLOR_SYSTEM)
	view.add_text(text)
	view.pop()


## 清空世界叙述流（开始新探索时；queue_free 让出余帧安全释放）。
func _clear_log() -> void:
	for child in log_box.get_children():
		child.queue_free()


func _scroll_to_bottom() -> void:
	scroll.scroll_vertical = 100000000


# ============================================================
#  ④ 模型回应页渲染（DM 裁决 / 对话回应）
# ============================================================


## 组装④页「DM 裁决」详情：路由/目标/行动叙述/话语/notes/原始输出。
func _format_dm_result(r: Dictionary) -> String:
	var p: Array[String] = []
	p.append("[color=#90be6d][b]■ DM 裁决[/b][/color]")
	var npc_id := str(r.get("npc", ""))
	p.append("· 路由：[color=#90be6d]%s[/color]%s" % [
		str(r.get("route", "")),
		"  → [%s] %s" % [npc_id, EntityRegistry.display_name(npc_id)] if not npc_id.is_empty() else ""])
	p.append("")
	if not str(r.get("action", "")).is_empty():
		p.append("[b]行动部分[/b]")
		p.append(_bb_escape(str(r.get("action", ""))))
	if not str(r.get("narration", "")).is_empty():
		p.append("")
		p.append("[b]行动后果（%s）[/b]" % str(r.get("outcome", "")))
		p.append(_bb_escape(str(r.get("narration", ""))))
	if not str(r.get("speech", "")).is_empty():
		p.append("")
		p.append("[b]交给 NPC 的话[/b]")
		p.append(_bb_escape(str(r.get("speech", ""))))
	if not str(r.get("reason", "")).is_empty():
		p.append("")
		p.append("[color=#e76f51][b]拒绝理由[/b][/color]：" + _bb_escape(str(r.get("reason", ""))))
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


## 组装④页「对话回应」解析详情（成功/保底/失败三分支，末尾附原始输出）。
func _format_dialogue_response(r: Dictionary) -> String:
	var p: Array[String] = []
	if r.get("fallback", false):
		p.append("[color=#e76f51][b]（保底回应已触发：%s）[/b][/color]" % _bb_escape(str(r.get("error", ""))))
	elif not r.get("ok", true):
		p.append("[color=#e76f51][b]请求失败：%s[/b][/color]" % _bb_escape(str(r.get("error", ""))))
		p.append("此失败不写入对话记录。")
		p.append("")
		p.append("[color=#8d99ae]———— 模型原始输出 ————[/color]")
		p.append(_bb_escape(str(r.get("raw", "（无）"))))
		return "\n".join(p)
	else:
		p.append("[color=#90be6d][b]对话回应解析成功[/b][/color]")
		p.append("")
		p.append("[b]■ 行动提案[/b]")
		var action: Dictionary = r.get("action", {})
		p.append("· 类型：[color=#90be6d]%s[/color]（%s）" % [action.get("type", ""), action.get("name", "")])
		if not str(action.get("description", "")).is_empty():
			p.append("· 描述：%s" % _bb_escape(str(action.get("description", ""))))
		p.append("")
		p.append("[b]■ 发言性质（claim_type）[/b]")
		var claim := str(r.get("claim_type", ""))
		p.append("· %s%s" % [claim, "  ——落档将记作“某人声称”" if claim != "确知" else ""])
		p.append("")
		p.append("[b]■ 发言[/b]")
		var utterance := str(r.get("utterance", ""))
		p.append(_bb_escape(utterance) if not utterance.is_empty() else "[i]（空：选择了沉默）[/i]")
		p.append("")
		p.append("[b]■ 内心想法（仅调试，不入记录）[/b]")
		var inner := str(r.get("inner_thought", ""))
		p.append(_bb_escape(inner) if not inner.is_empty() else "[i]（模型未提供）[/i]")
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
