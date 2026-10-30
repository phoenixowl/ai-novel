extends SceneTree
## 动态生成系统端到端测试（无 UI、无网络，强制离线）：
##   godot --headless -s tests/gen_loop_test.gd
## 覆盖（Mock 样本确定性）：
##   场景一：DM 触发 world.discover → 人物生成（干净路径：构思→审核通过→落地）
##           ——知识闭集（池内引用+主观条目）、快照落盘、存在事实、在场安置
##   场景二：越权草稿 → 引擎丢弃越权知识 + 审核者 revise → 修订循环 → 落地
##   场景三：组织生成（GenController 直连）→ 合并进设定库、成员表可查
##   场景四：地点生成（含 1 链式住户）→ 位置图连边、进场描述冻结、住户正确落位
##   场景五：一键清除 → gen 实体/组织文件/正典 gen 作用域条目全部消失
var _ran := false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	if _ran:
		return
	_ran = true

	var failures := 0
	print("==== 动态生成回路测试 ====")

	# 设定目录确定性：工厂重置 user://settings（从内置模板重新播种）
	TestUtil.reset_runtime()

	EventBus.create_shared()
	LLMController.create_shared()
	LLMController.shared().force_offline = true

	# -s 模式下 autoload 同样会加载：移除 autoload 的 DM 避免重复订阅（Gen 保留使用）
	var autoload_dm := root.get_node_or_null("DM")
	if autoload_dm != null:
		root.remove_child(autoload_dm)
		autoload_dm.free()

	# 干净起步：清内存状态与磁盘残留
	CanonStore.reset_for_test()
	EntityRegistry.reset_for_test()
	LocationStore.reset_for_test()
	WorldStream.reset_for_test()
	GenFactionStore.reset_for_test()
	TestUtil.clear_gen_characters()
	for f in ["world/canon.json", "world/entities.json", "world/locations.json",
			"world/gen_factions.json"]:
		DirAccess.remove_absolute(GamePaths.save_dir() + "/" + f)
	CanonStore.reload_for_test()  # 重新播种作者正典——候选知识池需要 LAW/PUBLIC 层

	var dm := DMController.new()
	root.add_child(dm)  # _ready：加载设定 + 导入作者实体/位置图
	LocationStore.travel_to("fangshi")  # 首个场景是百草堂——把探索起点走到作坊市街

	var ge := EventBus.shared().hub(GenEvents) as GenEvents
	var finishes: Array = []
	ge.generation_finished.connect(func(kind, ok, msg): finishes.append([kind, ok, msg]))

	# —— 场景一：干净路径——DM 触发 → 人物“贺松”落地 ——
	var ne := EventBus.shared().hub(DMEvents) as DMEvents
	ne.cmd_submit_input.emit("我敲了敲巷尾那扇从来没有开过的门")
	failures = await _wait_gen(finishes, failures, "character", "场景一：人物生成完成")
	var repo := LoreRepository.shared()
	var song := _find_gen_char(repo, "贺松")
	failures = TestUtil.check(song != "", "场景一：生成人物“贺松”进入设定库", failures)
	if not song.is_empty():
		var person: Person = repo.characters[song]
		failures = TestUtil.check(person.knowledge.size() == 3,
			"场景一：初始知识 3 条（2 条池内引用 + 1 条主观）", failures)
		failures = TestUtil.check(LocationStore.npcs_at("fangshi").has(song),
			"场景一：新人物安置在作坊市街", failures)
		failures = TestUtil.check(FileAccess.file_exists(
				GamePaths.save_dir() + "/characters/%s.json" % song),
			"场景一：人物快照落盘（user://characters/gen_*.json）", failures)
		failures = TestUtil.check(CanonStore.facts_for_entities([song]).size() >= 1,
			"场景一：存在事实入典（可被后续检索）", failures)
	failures = TestUtil.check(not FileAccess.file_exists(
			ProjectSettings.globalize_path("res://settings/characters/gen_1.json")),
		"场景一：settings/ 未被触碰（生成只写 user://）", failures)

	# —— 场景二：越权草稿——引擎丢弃越权知识，审核者 revise，修订循环后落地 ——
	ne.cmd_submit_input.emit("我盯上了那个探子的住处")
	failures = await _wait_gen(finishes, failures, "character", "场景二：修订循环完成")
	var third := _find_gen_char(repo, "费三")
	failures = TestUtil.check(third != "", "场景二：修订后的人物“费三”落地（初稿贺青被 revise）", failures)
	if not third.is_empty():
		var person3: Person = repo.characters[third]
		var leaked := false
		for entry in person3.knowledge:
			if entry.content.contains("天穹台"):
				leaked = true
		failures = TestUtil.check(person3.knowledge.size() == 3 and not leaked,
			"场景二：越权知识（天穹台）未落库——引擎闭集丢弃", failures)

	# —— 场景三：组织生成（GenController 直连，绕过 DM）——
	var faction_ok: bool = GenController.shared().request("faction", "新出现的互助会", "fangshi")
	failures = TestUtil.check(faction_ok, "场景三：组织生成请求受理", failures)
	failures = await _wait_gen(finishes, failures, "faction", "场景三：组织生成完成")
	var ashes := ""
	for id in repo.factions:
		if (repo.factions[id] as Faction).canonical_name == "灰烬会":
			ashes = str(id)
	failures = TestUtil.check(not ashes.is_empty(), "场景三：组织“灰烬会”合并进设定库", failures)
	if not ashes.is_empty():
		failures = TestUtil.check((repo.factions[ashes] as Faction).position_of("贺松") == "供奉",
			"场景三：成员表按名匹配职位（贺松=供奉）", failures)
		failures = TestUtil.check(ashes.begins_with("gen_"),
			"场景三：动态组织使用 gen_ id", failures)

	# —— 场景四：地点生成 + 链式住户 ——
	# 4a 配额闸门：前三个请求（场景一/二/三）已用满每段探索的 3 次生成配额——
	#    本次 discover 应被引擎拒绝（无生成事件）
	var before_quota := finishes.size()
	ne.cmd_submit_input.emit("我去看看那条新开的窄道")
	await create_timer(1.5).timeout  # 等 DM 裁决完成与配额拒绝留痕
	failures = TestUtil.check(finishes.size() == before_quota,
		"场景四：配额闸门——每段探索第 4 次生成被拒绝", failures)
	# 4b 重置会话配额后重新触发（输入避开相邻地点别名，防止误触发 world.travel）
	GenController.shared().reset_session()
	ne.cmd_submit_input.emit("我去看看那条新开的窄道")
	failures = await _wait_gen(finishes, failures, "location", "场景四：地点生成完成")
	var lane := ""
	for id in LocationStore.neighbors("fangshi"):
		if EntityRegistry.display_name(id) == "断井巷":
			lane = id
	failures = TestUtil.check(not lane.is_empty(), "场景四：新地点“断井巷”与作坊市街连边", failures)
	if not lane.is_empty():
		failures = TestUtil.check(not LocationStore.brief(lane).is_empty(),
			"场景四：进场描述随生成冻结（再进零调用）", failures)
		var liu := _find_gen_char(repo, "柳三变")
		failures = TestUtil.check(liu != "" and LocationStore.npcs_at(lane).has(liu),
			"场景四：链式住户“柳三变”落位在断井巷", failures)
		if liu != "":
			var person_liu: Person = repo.characters[liu]
			failures = TestUtil.check(person_liu.knowledge.size() == 2,
				"场景四：住户知识只剩池内引用（提及秦峙的主观条目被闭集丢弃——他不认识秦峙）", failures)
	failures = TestUtil.check(EntityRegistry.gen_count() == 5,
		"场景四：gen 实体共 5 个（2 人物 + 1 组织 + 1 地点 + 1 住户）", failures)

	# —— 场景五：一键清除（同步完成——事件先于等待入列，显式传起始下标）——
	var before_clear := finishes.size()
	ge.cmd_clear_generated.emit()
	failures = await _wait_gen(finishes, failures, "clear", "场景五：清除完成", before_clear)
	failures = TestUtil.check(EntityRegistry.gen_count() == 0, "场景五：注册表 gen 条目清零", failures)
	failures = TestUtil.check(not FileAccess.file_exists(GamePaths.save_dir() + "/world/gen_factions.json"),
		"场景五：动态组织文件删除", failures)
	failures = TestUtil.check(not LocationStore.neighbors("fangshi").any(
			func(id): return str(id).begins_with("gen_")),
		"场景五：位置图 gen 节点与边清除", failures)
	LoreRepository.reload_shared()
	failures = TestUtil.check(_find_gen_char(LoreRepository.shared(), "贺松") == ""
		and _find_gen_char(LoreRepository.shared(), "柳三变") == "",
		"场景五：重载后生成人物不再出现", failures)

	# —— 清理 ——
	for f in ["world/canon.json", "world/entities.json", "world/locations.json",
			"world/gen_factions.json"]:
		DirAccess.remove_absolute(GamePaths.save_dir() + "/" + f)
	TestUtil.clear_gen_characters()
	CanonStore.reset_for_test()
	EntityRegistry.reset_for_test()
	LocationStore.reset_for_test()
	WorldStream.reset_for_test()
	GenFactionStore.reset_for_test()

	if failures == 0:
		print("==== 全部通过 ====")
		quit(0)
	else:
		print("==== 失败 %d 项 ====" % failures)
		quit(1)


## 等待一次指定 kind 的生成结束（轮询 finishes；20 秒超时记失败）。
## start_index：显式起始下标（同步完成的事件先于本调用入列时传入）；-1 = 从当前末尾起。
func _wait_gen(finishes: Array, failures: int, kind: String, label: String, start_index := -1) -> int:
	var waited := 0.0
	var start := finishes.size() if start_index == -1 else start_index
	while waited < 20.0:
		for i in range(start, finishes.size()):
			if str((finishes[i] as Array)[0]) == kind:
				failures = TestUtil.check(bool((finishes[i] as Array)[1]),
					label + "（ok=%s，%s）" % [str((finishes[i] as Array)[1]), str((finishes[i] as Array)[2])], failures)
				return failures
		await create_timer(0.1).timeout
		waited += 0.1
	failures = TestUtil.check(false, label + "（超时未完成）", failures)
	return failures


## 按名查生成人物的 id（无则空串）。
func _find_gen_char(repo: LoreRepository, name: String) -> String:
	for id in repo.character_ids():
		if id.begins_with("gen_") and (repo.characters[id] as Person).canonical_name == name:
			return id
	return ""
