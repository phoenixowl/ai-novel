extends SceneTree
## UI 冒烟检查（headless 实例化世界屏）：
##   godot --headless -s tests/ui_smoke_check.gd
## 覆盖：场景可加载、调试抽屉为根浮层（展开/收起不挤压世界面板——布局回归防线）、
## ④ 模型回应页的渲染（工具调用明细 / dialogue.end 收场标记 / 好感度变化）。

var _ran := false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	TestUtil.reset_runtime()
	var scene: PackedScene = load("res://Scenes/world_screen.tscn")
	var failures := 0
	failures = TestUtil.check(scene != null, "world_screen.tscn 可加载", failures)
	var ui: Control = scene.instantiate()
	root.add_child(ui)
	await process_frame
	ui._on_sidebar_toggled(true)
	await process_frame
	var sidebar := ui.get_node("%DebugSidebar") as Control
	failures = TestUtil.check(sidebar != null and sidebar.visible, "抽屉展开（visible）", failures)
	failures = TestUtil.check(sidebar.get_parent() == ui, "抽屉为根浮层（不参与 Split 布局）", failures)
	# 布局不受挤压：世界面板宽度应保持接近全宽
	var panel := ui.get_node("%WorldScroll").get_parent() as Control
	failures = TestUtil.check(panel.size.x > 1200.0, "世界面板未被侧栏挤压（宽 %.0f）" % panel.size.x, failures)
	ui._on_sidebar_toggled(false)
	await process_frame
	failures = TestUtil.check(not sidebar.visible, "抽屉收起", failures)

	# —— 玩家状态悬浮窗：默认显示、模板渲染、展开/收起、拖动钳制、显隐开关 ——
	var psw := ui.get_node_or_null("PlayerStateWindow")
	failures = TestUtil.check(psw != null and psw.visible, "玩家状态悬浮窗默认显示", failures)
	if psw != null:
		psw._refresh({"counters": {"crystal": 7}, "collections": {"items": [{"name": "安神灯", "qty": 1}]}})
		await process_frame
		var found_counter := false
		for c in psw._counters_row.get_children():
			if str((c as Label).text).contains("晶石") and str((c as Label).text).contains("7"):
				found_counter = true
		failures = TestUtil.check(found_counter, "悬浮窗：计数器按模板渲染（晶石 7）", failures)
		failures = TestUtil.check(not psw._lists_box.visible, "悬浮窗：默认收起", failures)
		psw._set_expanded(true)
		var found_item := false
		for c in psw._lists_box.get_children():
			if str((c as Label).text).contains("安神灯"):
				found_item = true
		failures = TestUtil.check(psw._lists_box.visible and found_item, "悬浮窗：展开显示条目明细", failures)
		psw.position = Vector2(0, 0)
		psw._drag_move(Vector2(99999, 10))
		failures = TestUtil.check(psw.position.x <= ui.size.x and psw.position.y > 0,
			"悬浮窗：拖动钳制在屏幕内", failures)
		var ps_btn := ui.get_node("%PlayerStateBtn") as Button
		ps_btn.button_pressed = false
		await process_frame
		failures = TestUtil.check(not psw.visible, "悬浮窗：头栏开关隐藏", failures)

	# —— AuthorTool 玩家状态页：结构化增删改（计数器/条目集/字段子表） ——
	var ps_draft := AuthortoolDraft.new()
	ps_draft.load_from_project()
	var ps_page := AuthortoolPlayerStatePage.new()
	root.add_child(ps_page)
	ps_page.setup(ps_draft)
	await process_frame
	var counters_before: int = (ps_draft.player_state.get("counters", []) as Array).size()
	var collections_before: int = (ps_draft.player_state.get("collections", []) as Array).size()
	ps_page._add_counter()
	ps_page._add_collection()
	await process_frame
	failures = TestUtil.check((ps_draft.player_state["counters"] as Array).size() == counters_before + 1
		and (ps_draft.player_state["collections"] as Array).size() == collections_before + 1,
		"状态模板页：结构化新增计数器与条目集", failures)
	var new_col: Dictionary = (ps_draft.player_state["collections"] as Array)[collections_before]
	failures = TestUtil.check(str(new_col.get("key", "")).begins_with("list_")
		and (new_col.get("fields", []) as Array).size() >= 1,
		"状态模板页：新条目集自带默认字段", failures)
	var line_count := _count_line_edits(ps_page)
	failures = TestUtil.check(line_count >= 10, "状态模板页：结构化表单已渲染（%d 个输入框）" % line_count, failures)
	ps_page.queue_free()

	var text: String = ui._format_dm_result({
		"route": "action", "narration": "你做了。", "outcome": "success", "settle": true,
		"tool_calls": [{"tool": "facts.declare", "args": {"content": "x", "weight": "minor"}}],
		"raw": "raw",
	})
	failures = TestUtil.check(text.contains("dialogue.end") and text.contains("工具调用")
		and text.contains("facts.declare") and text.contains("强制收场"), "④页 DM：工具调用与收场标记", failures)
	var text2: String = ui._format_dialogue_response({
		"ok": true, "utterance": "嗯", "claim_type": "猜测", "affinity_change": 3,
		"tool_calls": [{"tool": "affinity.change", "args": {"delta": 3}}],
		"action": {"type": "answer", "name": "答话", "description": ""}, "raw": "raw",
	})
	failures = TestUtil.check(text2.contains("好感度变化") and text2.contains("+3")
		and text2.contains("affinity.change"), "④页 NPC：好感度与工具调用", failures)
	ui.queue_free()
	print("==== UI 冒烟检查：%s ====" % ("全部通过" if failures == 0 else "失败 %d 项" % failures))
	quit(0 if failures == 0 else 1)


## 递归统计节点树里的 LineEdit 数（结构化表单渲染断言用）。
func _count_line_edits(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is LineEdit:
			count += 1
		count += _count_line_edits(child)
	return count
