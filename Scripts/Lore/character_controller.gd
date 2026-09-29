class_name CharacterController
extends Node
## 人物控制器（Lore 层，autoload "Characters"）：人物域的命令接收入口。
## 管理人物运行时快照的一切修改——总览/详情查询、保存（人设/知识/记忆/好感度）、
## 恢复卡面、写回作者卡面、还原设定；对话学习写快照的构建规则也在这里
##（build_journal_for：对话域与编辑域共用的唯一知识日志构建入口）。
##
## 数据模型：user://characters/<id>.json 是单人物的运行时快照（persona 区 + journal 区），
## 一切修改都写快照；res://settings/ 是只读模板，只有「写回」会触碰它。
##
## 对外交互：UI 经 EventBus（autoload "Events"）在 CharacterEvents 集线器上
## 连接 cmd_* 命令信号、接收事件信号；设定变更经 lore_changed 广播，
## 由 DialogueController 重载设定资料并重发对话域快照。

const SnapshotStore := preload("res://Scripts/Lore/snapshot_store.gd")

var repository := LoreRepository.new()

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


## 取全局事件总线；autoload 未就绪时手动创建（兜底）。
func _bus() -> EventBus:
	return EventBus.shared() if EventBus.shared() != null else EventBus.create_shared()


func _ready() -> void:
	_shared = self
	_events = _bus().hub(CharacterEvents) as CharacterEvents
	repository.load_all()
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


# ———— 知识日志构建（对话域与编辑域共用的唯一入口） ————


## 构建某人物的知识日志：人物快照的 journal 区存在则整体接管；
## 否则以卡面初始知识起步 + 旧学习日志（user://journals/，仅兼容读取）。
static func build_journal_for(card: CharacterCard) -> KnowledgeJournal:
	var j := KnowledgeJournal.new()
	if j.load_snapshot(card.id):
		return j
	for entry in card.knowledge:
		var e := entry as Dictionary
		j.add_card_entry(
			str(e.get("content", "")),
			str(e.get("source", "常识")),
			str(e.get("trust", "比较相信")),
		)
	j.load_learned(card.id)
	return j


## 删除某人物的运行时档案（快照 + 旧学习日志）。恢复卡面与重置记忆共用。
static func erase_runtime_state(npc_id: String) -> void:
	SnapshotStore.erase(npc_id)
	DirAccess.remove_absolute("user://journals/%s.json" % npc_id)


# ———— 查询 ————


## 处理 cmd_get_characters：构建人物总览数据（玩家置顶 + 全部 NPC）。
func _on_cmd_get_characters() -> void:
	_events.characters_listed.emit(_character_summary_items())


## 人物总览卡片数据。knowledge/memory 计数 -1 表示"不适用"（玩家）。
func _character_summary_items() -> Array:
	var items: Array = []
	items.append({
		"kind": "player", "id": "player",
		"name": repository.player_card.display_name,
		"identity": repository.player_card.identity,
		"profile": repository.player_card.appearance,
		"affinity": 0, "affinity_label": "",
		"knowledge_count": -1, "memory_count": -1,
	})
	for id in repository.character_ids():
		var card: CharacterCard = repository.characters[id]
		var j := build_journal_for(card)
		var affinity := AffinityStore.get_value(id, card.affinity)
		items.append({
			"kind": "npc", "id": id,
			"name": card.display_name,
			"identity": card.identity,
			"profile": card.profile,
			"affinity": affinity,
			"affinity_label": AffinityStore.tier_label(affinity),
			"knowledge_count": j.size(),
			"memory_count": j.memory_count(),
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
			"name": repository.player_card.display_name,
			"identity": repository.player_card.identity,
			"profile": repository.player_card.appearance,
			"profile_label": "外观（NPC 看到的样子）",
			"affinity": 0, "has_snapshot": false,
			"knowledge": [], "memories": [],
		}
	if not repository.characters.has(npc_id):
		return {}
	var card: CharacterCard = repository.characters[npc_id]
	var j := build_journal_for(card)
	var knowledge: Array = []
	for e in j.entries_all():
		var d := (e as Dictionary).duplicate()
		d["trust_view"] = ("已失效" if str(d.get("status", "")) == KnowledgeJournal.STATUS_VOIDED
			else str(d.get("trust", "")))
		knowledge.append(d)
	return {
		"kind": "npc", "id": npc_id,
		"name": card.display_name,
		"identity": card.identity,
		"profile": card.profile,
		"profile_label": "人设",
		"affinity": AffinityStore.get_value(npc_id, card.affinity),
		"has_snapshot": SnapshotStore.exists(npc_id),
		"knowledge": knowledge,
		"memories": j.memory_texts(),
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
	repository.load_all()
	_events.characters_listed.emit(_character_summary_items())
	_events.character_saved.emit(id)
	_events.lore_changed.emit()


## NPC 保存：人设 → 快照 persona 区；知识/记忆 → 快照 journal 区；好感度 → AffinityStore。
func _save_npc(id: String, payload: Dictionary) -> void:
	var card: CharacterCard = repository.characters[id]
	SnapshotStore.write_persona(id, {
		"name": str(payload.get("name", card.display_name)),
		"identity": str(payload.get("identity", card.identity)),
		"profile": str(payload.get("profile", card.profile)),
	})
	var j := build_journal_for(card)
	var kept := {}
	for raw in payload.get("knowledge", []):
		if not (raw is Dictionary):
			continue
		var item := raw as Dictionary
		var content := str(item.get("content", "")).strip_edges()
		if content.is_empty():
			continue
		var seq := int(item.get("seq", 0))
		if seq > 0 and j.has_seq(seq):
			j.update_entry(seq, content, str(item.get("speaker", "")), str(item.get("trust", "")))
		else:
			seq = j.learn(content, "", str(item.get("speaker", "手动")), 0, 0, "编辑页手动添加")
		kept[seq] = true
	j.retain_seqs(kept)
	j.set_memories(payload.get("memories", []))
	j.save(id)
	AffinityStore.set_value(id, int(payload.get("affinity", card.affinity)))


## 玩家保存：user://player.json（含称呼，覆盖作者默认卡）。
func _save_player(payload: Dictionary) -> void:
	repository.player_card.display_name = str(payload.get("name", repository.player_card.display_name))
	repository.player_card.identity = str(payload.get("identity", repository.player_card.identity))
	repository.player_card.appearance = str(payload.get("profile", repository.player_card.appearance))
	DirAccess.make_dir_recursive_absolute("user://")
	var file := FileAccess.open("user://player.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({
			"name": repository.player_card.display_name,
			"identity": repository.player_card.identity,
			"appearance": repository.player_card.appearance,
		}, "  "))
		file.close()


## 处理 cmd_reset_character：恢复卡面——删除该 NPC 的运行时快照与旧学习日志（好感度保留）。
func _on_cmd_reset_character(npc_id: String) -> void:
	if not repository.characters.has(npc_id):
		return
	erase_runtime_state(npc_id)
	repository.load_all()
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
			"name": repository.player_card.display_name,
			"identity": repository.player_card.identity,
			"appearance": repository.player_card.appearance,
		}
		path = "res://settings/player.json"
	elif repository.characters.has(npc_id):
		var card: CharacterCard = repository.characters[npc_id]
		var j := build_journal_for(card)
		var knowledge: Array = []
		for e in j.entries_all():
			var d := e as Dictionary
			var trust := ("已失效" if str(d.get("status", "")) == KnowledgeJournal.STATUS_VOIDED
				else str(d.get("trust", "")))
			knowledge.append({
				"content": str(d.get("content", "")),
				"source": str(d.get("speaker", "常识")),
				"trust": trust,
			})
		data = {
			"id": npc_id,
			"name": card.display_name,
			"identity": card.identity,
			"profile": card.profile,
			"knowledge": knowledge,
		}
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


## 处理 cmd_restore_lore：还原设定——删除全部人物快照与旧学习日志，回到作者卡面。
## 好感度（user://affinity/）与对话审计日志（user://dialogue_logs/）保留。
func _on_cmd_restore_lore() -> void:
	SnapshotStore.erase_all()
	SnapshotStore.wipe_json_dir("user://journals")
	repository.load_all()
	_events.characters_listed.emit(_character_summary_items())
	_events.character_action_result.emit("", true, "已还原全部人物设定（好感度与对话日志保留）")
	_events.lore_changed.emit()
