class_name CharacterController
extends Node
## 人物控制器（Characters 层，autoload "Characters"）：人物域的命令接收入口。
## 管理人物运行时快照的一切修改——总览/详情查询、保存（人设/知识/记忆/好感度）、
## 恢复卡面、写回作者卡面、还原设定。人物数据模型为 Models 层的 Person
## （knowledge: Array[KnowledgeEntry] 承载信念，确定性算术在 KnowledgeEntry 上）。
##
## 数据模型：user://characters/<id>.json 是单人物的运行时快照（persona 区 + journal 区），
## 一切修改都写快照；res://settings/ 是只读模板，只有「写回」会触碰它。
##
## 对外交互：UI 经 EventBus（autoload "Events"）在 CharacterEvents 集线器上
## 连接 cmd_* 命令信号、接收事件信号；设定变更经 lore_changed 广播，
## 由 DialogueController 重载设定资料并重发对话域快照。

var repository: LoreRepository  # 统一入口 LoreRepository.shared()——作者数据全项目一份

static var _shared: CharacterController

var _events: CharacterEvents  # 事件集线器（_ready 时经总线取得）


static func shared() -> CharacterController:
	return _shared


## 测试/嵌入式环境兜底：autoload 未就绪时手动创建并注册共享实例（挂到当前场景树）
static func create_shared() -> CharacterController:
	if _shared == null:
		_shared = CharacterController.new()
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			(loop as SceneTree).root.add_child(_shared)
	return _shared



func _ready() -> void:
	_shared = self
	_events = EventBus.resolve().hub(CharacterEvents) as CharacterEvents
	relink_runtime_journals()  # 启动维护：旧形态知识与正典对齐（在加载/接管前完成文件级转换）
	repository = LoreRepository.shared()  # 统一入口：作者数据全项目一份（含快照接管）
	_events.cmd_get_characters.connect(_on_cmd_get_characters)
	_events.cmd_get_character.connect(_on_cmd_get_character)
	_events.cmd_save_character.connect(_on_cmd_save_character)
	_events.cmd_reset_character.connect(_on_cmd_reset_character)
	_events.cmd_write_back_character.connect(_on_cmd_write_back_character)
	_events.cmd_restore_lore.connect(_on_cmd_restore_lore)


func _exit_tree() -> void:
	if _shared == self:
		_shared = null
	if _events != null:
		_events.cmd_get_characters.disconnect(_on_cmd_get_characters)
		_events.cmd_get_character.disconnect(_on_cmd_get_character)
		_events.cmd_save_character.disconnect(_on_cmd_save_character)
		_events.cmd_reset_character.disconnect(_on_cmd_reset_character)
		_events.cmd_write_back_character.disconnect(_on_cmd_write_back_character)
		_events.cmd_restore_lore.disconnect(_on_cmd_restore_lore)


# ———— 启动维护与持久化 ————


## 启动维护：把运行时快照里仍以旧形态（card/subjective）存放、但内容已与正典
## 逐字一致的知识转换为信念引用（kind=ref，fact_id 指向正典）——作者正典播种后
## 的一次性对齐。幂等（已是引用或无匹配的条目不动），已失效传闻不转换。
func relink_runtime_journals() -> void:
	var dir := DirAccess.open(SnapshotStore.DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var path := "%s/%s" % [SnapshotStore.DIR, file_name]
			var data := JsonTool.read_json_file(path)
			var changed := false
			for raw in data.get("knowledge", []):
				if not (raw is Dictionary):
					continue
				var e := raw as Dictionary
				if str(e.get("kind", "")) == "ref":
					continue
				if str(e.get("status", "")) == "voided":
					continue
				var fact_id := CanonStore.find_by_content(str(e.get("content", "")))
				if fact_id > 0 and int(e.get("fact_id", 0)) != fact_id:
					e["kind"] = "ref"
					e["fact_id"] = fact_id
					changed = true
			if changed:
				JsonTool.write_json_file(path, data)
		file_name = dir.get_next()
	dir.list_dir_end()


## 人物信念/记忆落盘到运行时快照（对话结算与编辑保存的统一写路径）。
func save_journal(person: Person, npc_id: String) -> void:
	SnapshotStore.write_journal(npc_id, person.knowledge_dicts(), person.memories, person.next_seq_value())


## 涟漪计数：某正典条目被取代时，全部人物快照里指向它的信念引用数。
## 扫描 user://characters/*.json（取代是罕见事件，文件量小，确定性可接受）。
func count_knowledge_refs(fact_id: int) -> int:
	var dir := DirAccess.open(SnapshotStore.DIR)
	if dir == null:
		return 0
	var count := 0
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var data := JsonTool.read_json_file(SnapshotStore.DIR + "/" + file_name)
			for raw in data.get("knowledge", []):
				if raw is Dictionary \
						and str((raw as Dictionary).get("kind", "")) == "ref" \
						and int((raw as Dictionary).get("fact_id", 0)) == fact_id:
					count += 1
		file_name = dir.get_next()
	dir.list_dir_end()
	return count


## 删除某人物的运行时档案（快照）。恢复卡面与重置记忆共用。
func erase_runtime_state(npc_id: String) -> void:
	SnapshotStore.erase(npc_id)


# ———— 查询 ————


## 处理 cmd_get_characters：构建人物总览数据（玩家置顶 + 全部 NPC）。
func _on_cmd_get_characters() -> void:
	_events.characters_listed.emit(_character_summary_items())


## 人物总览卡片数据。knowledge/memory 计数 -1 表示"不适用"（玩家）。
func _character_summary_items() -> Array:
	var items: Array = []
	items.append({
		"kind": "player", "id": "player",
		"name": repository.player.canonical_name,
		"identity": repository.player.identity,
		"profile": repository.player.appearance,
		"affinity": 0, "affinity_label": "",
		"knowledge_count": -1, "memory_count": -1,
	})
	for id in repository.character_ids():
		var person: Person = repository.characters[id]
		var affinity := AffinityStore.get_value(id, person.affinity)
		items.append({
			"kind": "npc", "id": id,
			"name": person.canonical_name,
			"identity": person.identity,
			"profile": person.profile,
			"affinity": affinity,
			"affinity_label": AffinityStore.tier_label(affinity),
			"knowledge_count": person.knowledge.size(),
			"memory_count": person.memory_count(),
		})
	return items


## 处理 cmd_get_character：编辑页详情（玩家或 NPC；未知 id 发空 Dictionary）。
func _on_cmd_get_character(npc_id: String) -> void:
	_events.character_loaded.emit(_character_detail(npc_id))


## 编辑页详情：玩家 = 人设三字段；NPC = 人设 + 好感度 + 全量知识条目 + 记忆。
## trust_view 供编辑页信任下拉显示（voided 条目显示为"已失效"）。
func _character_detail(npc_id: String) -> Dictionary:
	if npc_id == "player":
		return {
			"kind": "player", "id": "player",
			"name": repository.player.canonical_name,
			"identity": repository.player.identity,
			"profile": repository.player.appearance,
			"profile_label": "外观（NPC 看到的样子）",
			"affinity": 0, "has_snapshot": false,
			"knowledge": [], "memories": [],
		}
	if not repository.characters.has(npc_id):
		return {}
	var person: Person = repository.characters[npc_id]
	var knowledge: Array = []
	for e in person.knowledge:
		knowledge.append({
			"seq": e.seq,
			"content": e.content,
			"speaker": e.speaker,
			"trust_view": KnowledgeEntry.TRUST_VOID_KEY if e.status == KnowledgeEntry.EntryStatus.VOIDED
				else KnowledgeEntry.trust_to_key(e.trust),
		})
	return {
		"kind": "npc", "id": npc_id,
		"name": person.canonical_name,
		"identity": person.identity,
		"profile": person.profile,
		"profile_label": "人设",
		"affinity": AffinityStore.get_value(npc_id, person.affinity),
		"has_snapshot": SnapshotStore.exists(npc_id),
		"knowledge": knowledge,
		"memories": person.memory_texts(),
	}


# ———— 保存 / 恢复 / 写回 ————


## 处理 cmd_save_character：UI 传全量期望状态，控制器写快照并广播变更。
## NPC payload：{id, name, identity, profile, affinity, knowledge: [{seq, content, speaker, trust}], memories: [String]}
## —— knowledge 未列出的 seq 即删除；seq=0 的新增为"手动添加"条目。
## 玩家 payload：{id: "player", name, identity, profile(=外观)}。
func _on_cmd_save_character(payload: Dictionary) -> void:
	var id := str(payload.get("id", ""))
	if id == "player":
		_save_player(payload)
	elif repository.characters.has(id):
		_save_npc(id, payload)
	else:
		return
	LoreRepository.reload_shared()
	_events.characters_listed.emit(_character_summary_items())
	_events.character_saved.emit(id)
	_events.lore_changed.emit()


## NPC 保存：人设 → 快照 persona 区；知识/记忆 → 快照 journal 区；好感度 → AffinityStore。
func _save_npc(id: String, payload: Dictionary) -> void:
	var person: Person = repository.characters[id]
	SnapshotStore.write_persona(id, {
		"name": str(payload.get("name", person.canonical_name)),
		"identity": str(payload.get("identity", person.identity)),
		"profile": str(payload.get("profile", person.profile)),
	})
	var kept := {}
	for raw in payload.get("knowledge", []):
		if not (raw is Dictionary):
			continue
		var item := raw as Dictionary
		var content := str(item.get("content", "")).strip_edges()
		if content.is_empty():
			continue
		var seq := int(item.get("seq", 0))
		if seq > 0 and person.has_seq(seq):
			person.update_entry(seq, content, str(item.get("speaker", "")), str(item.get("trust", "")))
		else:
			seq = person.learn_entry(content, "", str(item.get("speaker", "手动")), 0, 0, "编辑页手动添加")
		kept[seq] = true
	person.retain_seqs(kept)
	person.set_memories(payload.get("memories", []))
	save_journal(person, id)
	AffinityStore.set_value(id, int(payload.get("affinity", person.affinity)))


## 玩家保存：user://player.json（含称呼，覆盖作者默认卡）。
func _save_player(payload: Dictionary) -> void:
	repository.player.canonical_name = str(payload.get("name", repository.player.canonical_name))
	repository.player.identity = str(payload.get("identity", repository.player.identity))
	repository.player.appearance = str(payload.get("profile", repository.player.appearance))
	JsonTool.write_json_file("user://player.json", {
		"name": repository.player.canonical_name,
		"identity": repository.player.identity,
		"appearance": repository.player.appearance,
	})


## 处理 cmd_reset_character：恢复卡面——删除该 NPC 的运行时快照（好感度保留）。
func _on_cmd_reset_character(npc_id: String) -> void:
	if not repository.characters.has(npc_id):
		return
	erase_runtime_state(npc_id)
	LoreRepository.reload_shared()  # 重建 Person：回落作者卡面（快照已删，接管为空）
	if DialogueController.shared() != null:
		# 对话进行中恢复卡面：同步对话域内存对象，防止结算把旧快照写回（恢复被撤销）
		DialogueController.shared().discard_person_runtime(npc_id)
	_events.characters_listed.emit(_character_summary_items())
	_events.character_loaded.emit(_character_detail(npc_id))
	_events.character_action_result.emit(npc_id, true, "已恢复卡面（好感度保留）")
	_events.lore_changed.emit()


## 处理 cmd_write_back_character：把当前运行时状态反向写入 res:// 作者卡面。
## 写回 = 人设 + 全部知识条目（卡面格式，voided 记作"已失效"）；记忆/好感度是体验数据不写回。
## 仅 Godot 编辑器环境可行——导出版的 res:// 只读，写入失败并反馈。
func _on_cmd_write_back_character(npc_id: String) -> void:
	var data: Dictionary
	var path: String
	if npc_id == "player":
		data = {
			"name": repository.player.canonical_name,
			"identity": repository.player.identity,
			"appearance": repository.player.appearance,
		}
		path = "res://settings/player.json"
	elif repository.characters.has(npc_id):
		data = (repository.characters[npc_id] as Person).to_author_dict()
		path = "res://settings/characters/%s.json" % npc_id
	else:
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_events.character_action_result.emit(npc_id, false,
			"写入失败：%s（导出版的 res:// 只读，仅 Godot 编辑器环境可写回）" % path)
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	_events.character_action_result.emit(npc_id, true, "已写回 %s" % path)


## 处理 cmd_restore_lore：还原设定——删除全部人物快照，回到作者卡面。
## 好感度（user://affinity/）与对话审计日志（user://dialogue_logs/）保留。
func _on_cmd_restore_lore() -> void:
	SnapshotStore.erase_all()
	LoreRepository.reload_shared()
	if DialogueController.shared() != null:
		# 对话进行中还原设定：同步对话域内存对象，防止结算把旧快照写回（还原被撤销）
		for id in repository.character_ids():
			DialogueController.shared().discard_person_runtime(id)
	_events.characters_listed.emit(_character_summary_items())
	_events.character_action_result.emit("", true, "已还原全部人物设定（好感度与对话日志保留）")
	_events.lore_changed.emit()
