extends SceneTree
## DM 统一入口端到端回路测试（无 UI、无网络，强制离线）：
##   godot --headless -s tests/narration_loop_test.gd
## 交互全部经 EventBus 集线器（与 UI 同一路径）。验证统一输入的三条路由与完整体验：
##   行动路由（DM 叙述后果） → 说话路由（自动开始对话，世界流混排对话回声）
##   → 混合路由（行动落地 + 话送当前对象，边聊边做） → 点名切换对话（自动结算旧对话）
##   → 结束交谈 → 移动与进场描述冻结 → 结算探索（事实整理者提取） → 开始新探索。
## 人物域由 autoload Dialogue 承担（与正常运行同构）；DM 为本测试自建实例。

var _ran := false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	if _ran:
		return
	_ran = true

	var failures := 0
	print("==== DM 统一入口回路测试 ====")

	EventBus.create_shared()
	var bus := EventBus.shared()
	LLMController.create_shared()
	LLMController.shared().force_offline = true

	# -s 模式下 autoload 同样会加载：移除自建实例避免重复订阅
	var autoload_narration := root.get_node_or_null("Narration")
	if autoload_narration != null:
		root.remove_child(autoload_narration)
		autoload_narration.free()

	# 干净起步：清内存状态与磁盘测试残留
	CanonStore.reset_for_test()
	EntityRegistry.reset_for_test()
	LocationStore.reset_for_test()
	TestUtil.clear_gen_characters()
	for f in ["world/canon.json", "world/entities.json", "world/locations.json",
			"characters/ma_kui.json", "characters/bai_zhiruo.json",
			"affinity/ma_kui.json", "affinity/bai_zhiruo.json"]:
		DirAccess.remove_absolute(OS.get_user_data_dir() + "/" + f)

	var dm := NarrationController.new()
	root.add_child(dm)

	var ne := bus.hub(NarrationEvents) as NarrationEvents
	var de := bus.hub(DialogueEvents) as DialogueEvents
	# 世界流 = dm.events（合并流：叙述事件 + 对话回声副本，屏幕与 DM 上下文同源）
	var seen := {"world": dm.events, "dms": [], "starts": [], "ends": [], "packs": 0, "prompts": []}
	ne.dm_resolved.connect(func(r): (seen["dms"] as Array).append(r))
	ne.pack_built.connect(func(_p): seen["packs"] = seen["packs"] + 1)
	ne.prompt_built.connect(func(sys, usr): (seen["prompts"] as Array).append([sys, usr]))
	de.dialogue_started.connect(func(npc_id, _n, _s): (seen["starts"] as Array).append(npc_id))
	de.dialogue_ended.connect(func(reason): (seen["ends"] as Array).append(reason))

	# —— 场景一：行动路由——DM 直接叙述后果，不进对话 ——
	ne.cmd_submit_input.emit("我从货架上取一份报纸")
	await _wait_dm(dm, 10.0)
	failures = TestUtil.check(dm.turn_number == 1, "行动路由：回合 1 落地", failures)
	failures = TestUtil.check(_kinds(seen["world"]).has("player_action")
		and _kinds(seen["world"]).has("narration_turn"), "行动路由：行动与叙述落档", failures)
	failures = TestUtil.check((seen["starts"] as Array).is_empty(), "行动路由：不进入对话", failures)
	var dm1: Dictionary = seen["dms"][0]
	failures = TestUtil.check(str(dm1.get("route", "")) == "action", "行动路由：DM 判 route=action", failures)
	failures = TestUtil.check(seen["packs"] == 1 and (seen["prompts"] as Array).size() == 1,
		"行动路由：材料包与提示词各广播 1 次", failures)
	var usr1: String = (seen["prompts"] as Array)[0][1]
	failures = TestUtil.check(usr1.contains("[ma_kui]") and usr1.contains("白芷若"),
		"DM 材料层含在场人物闭集（fangshi 四人）", failures)
	failures = TestUtil.check(usr1.contains("我从货架上取一份报纸"), "DM 材料层原样携带输入", failures)

	# —— 场景二：说话路由——自动与首位在场者（马魁）开始对话 ——
	ne.cmd_submit_input.emit("请问这里最近安全吗？")
	await _wait_until_func(func() -> bool:
		return _count(seen["world"], "npc_utterance") >= 1, 10.0)
	failures = TestUtil.check((seen["starts"] as Array).size() == 1
		and str((seen["starts"] as Array)[0]) == "ma_kui", "说话路由：自动与马魁开始对话", failures)
	var dm2: Dictionary = seen["dms"][1]
	failures = TestUtil.check(str(dm2.get("route", "")) == "speech"
		and str(dm2.get("npc", "")) == "ma_kui", "说话路由：DM 判 speech → ma_kui", failures)
	failures = TestUtil.check(_kinds(seen["world"]).has("player_utterance")
		and _kinds(seen["world"]).has("npc_utterance"), "对话回声混排进世界流", failures)

	# —— 场景三：混合路由——行动落地 + 话送当前对象（边聊边做） ——
	ne.cmd_submit_input.emit("我翻一翻柜台上的账本，顺便问一句，最近有什么生面孔吗？")
	await _wait_until_func(func() -> bool:
		return _count(seen["world"], "npc_utterance") >= 2, 10.0)
	failures = TestUtil.check(dm.turn_number == 2, "混合路由：世界回合 2 落地", failures)
	var dm3: Dictionary = seen["dms"][2]
	failures = TestUtil.check(str(dm3.get("route", "")) == "mixed"
		and str(dm3.get("npc", "")) == "ma_kui"
		and not str(dm3.get("narration", "")).is_empty(), "混合路由：DM 拆分行动+话语（送当前对象）", failures)
	failures = TestUtil.check(_count(seen["world"], "narration_turn") == 2,
		"混合路由：行动后果已叙述", failures)
	failures = TestUtil.check((seen["starts"] as Array).size() == 1, "混合路由：不重开对话", failures)

	# —— 场景四：点名切换对话——自动结算马魁，转向白芷若 ——
	ne.cmd_submit_input.emit("白芷若，麻烦你给我瞧瞧这条胳膊")
	await _wait_until_func(func() -> bool:
		return (seen["ends"] as Array).size() == 1 and (seen["starts"] as Array).size() == 2, 10.0)
	await _wait_until_func(func() -> bool:
		return _count(seen["world"], "npc_utterance") >= 3, 10.0)
	failures = TestUtil.check((seen["ends"] as Array).size() >= 1
		and str((seen["ends"] as Array)[0]) == "manual_settle", "切换对话：旧对话自动结算", failures)
	failures = TestUtil.check(str((seen["starts"] as Array)[1]) == "bai_zhiruo",
		"切换对话：新对话与白芷若开始", failures)
	for _i in range(30):
		if FileAccess.file_exists(OS.get_user_data_dir() + "/characters/ma_kui.json"):
			break
		await create_timer(0.3).timeout
	failures = TestUtil.check(FileAccess.file_exists(OS.get_user_data_dir() + "/characters/ma_kui.json"),
		"切换对话：马魁快照落盘（记忆与学习结算）", failures)

	# —— 场景五：结束交谈——回到行动域 ——
	de.cmd_settle_now.emit()
	await _wait_until_func(func() -> bool:
		return (seen["ends"] as Array).size() == 2, 10.0)
	failures = TestUtil.check(str((seen["ends"] as Array)[1]) == "manual_settle", "结束交谈：手动结算生效", failures)

	# —— 场景六：移动 + 首次进场描述冻结 ——
	ne.cmd_travel_to.emit("teahouse")
	await _wait_until_func(func() -> bool:
		return LocationStore.has_brief("teahouse"), 10.0)
	failures = TestUtil.check(LocationStore.current() == "teahouse", "移动成功（相邻校验通过）", failures)
	failures = TestUtil.check(_count(seen["world"], "scene_described") == 1, "进场描述生成并落档", failures)

	# —— 场景七：结算探索——整理者通读混排记录提取事实 ——
	ne.cmd_settle_narration.emit()
	await _wait_dm_state(dm, "探索已结算", 10.0)
	var settled := _events_of(seen["world"], "exploration_settled")
	failures = TestUtil.check(settled.size() == 1 and int((settled[0] as Dictionary).get("facts", 0)) == 2,
		"结算提取 2 条事实（整理者样本）", failures)
	failures = TestUtil.check(CanonStore.active_count() >= 2, "提取事实入典", failures)
	failures = TestUtil.check(FileAccess.file_exists(OS.get_user_data_dir() + "/world/canon.json"),
		"正典结算后持久化", failures)

	# —— 场景八：开始新探索——回合与记录重置，世界保留 ——
	ne.cmd_start_exploration.emit()
	failures = TestUtil.check(dm.state_name() == "等待你的行动" and dm.turn_number == 0,
		"新探索重置回合与状态", failures)
	failures = TestUtil.check(_count(seen["world"], "exploration_started") == 1, "新探索事件落档", failures)
	failures = TestUtil.check(CanonStore.active_count() >= 2 and LocationStore.current() == "teahouse",
		"新探索保留世界（正典与位置）", failures)

	# —— 清理测试产生的运行时档案 ——
	for f in ["world/canon.json", "world/entities.json", "world/locations.json",
			"characters/ma_kui.json", "characters/bai_zhiruo.json",
			"affinity/ma_kui.json", "affinity/bai_zhiruo.json"]:
		DirAccess.remove_absolute(OS.get_user_data_dir() + "/" + f)
	TestUtil.clear_gen_characters()
	CanonStore.reset_for_test()
	EntityRegistry.reset_for_test()
	LocationStore.reset_for_test()

	if failures == 0:
		print("==== 全部通过 ====")
		quit(0)
	else:
		print("==== 失败 %d 项 ====" % failures)
		quit(1)


func _wait_dm(dm: NarrationController, seconds: float) -> void:
	await _wait_dm_state(dm, "等待你的行动", seconds)


func _wait_dm_state(dm: NarrationController, target: String, seconds: float) -> void:
	var waited := 0.0
	while waited < seconds:
		if dm.state_name() == target:
			return
		await create_timer(0.1).timeout
		waited += 0.1



func _wait_until_func(predicate: Callable, seconds: float) -> void:
	var waited := 0.0
	while waited < seconds:
		if predicate.call():
			return
		await create_timer(0.1).timeout
		waited += 0.1


func _kinds(events: Array) -> Dictionary:
	var kinds := {}
	for e in events:
		kinds[str((e as Dictionary).get("event", ""))] = true
	return kinds


func _count(events: Array, kind: String) -> int:
	return _events_of(events, kind).size()


func _events_of(events: Array, kind: String) -> Array:
	var out: Array = []
	for event in events:
		if str((event as Dictionary).get("event", "")) == kind:
			out.append(event)
	return out
