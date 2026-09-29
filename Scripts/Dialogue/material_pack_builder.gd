class_name MaterialPackBuilder
extends RefCounted
## 【流程二：材料包】
## 引擎冻结现场，收集 NPC 此刻的全部相关情况，组装材料包（设计 4.1 第3步、4.3/4.4）：
##   素材包 = 场景素材 + 玩家原话 + 相关知识 + 记忆 + 自身状态
##   行动清单 = 阶段一仅三项对话行动
## 行动提案的数据格式从第一天就统一为“类型 + 目标 + 说明”（设计 5.6 接入点一），
## 阶段二扩充世界行动类型时只增清单，不改对话流程。


## 阶段一行动清单（设计 4.4）：只有三项，它们的裁决不需要游戏逻辑。
static func dialogue_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	actions.append({
		"type": "answer",
		"name": "答话",
		"target": "玩家",
		"description": "默认选项。发言写入对话记录。",
	})
	actions.append({
		"type": "silence",
		"name": "沉默",
		"target": "玩家",
		"description": "永远可选。明示的冷处理（如：不置可否地看着你）。冷淡、戒备、不想搭理都是合法的人设表现。",
	})
	actions.append({
		"type": "end_dialogue",
		"name": "结束对话",
		"target": "本段对话",
		"description": "永远可选。必须附带离开的动作描述（如：转身回了柜台），不允许凭空消失。",
	})
	return actions

## 接近轮次上限时的收尾提示（设计 4.9）
const NEAR_LIMIT_HINT := "（提示：话题开始重复时，用符合性格的收尾话结束。）"


## 冻结现场组装材料包：知识日志全量注入 + 记忆 + 自身状态 + 行动清单。
## npc/scene：角色与场景卡；player_utterance：玩家原话；confirmed_history：已确认事件；
## cross_summary：背景摘要；knowledge_entries：本轮展示的知识日志条目；turn_number/max_turns：轮次。
static func build(
		npc: CharacterCard,
		scene: SceneCard,
		player_utterance: String,
		confirmed_history: Array,
		cross_summary: String,
		knowledge_entries: Array[Dictionary],
		turn_number: int,
		max_turns: int,
		affinity := 0,
		player_info := {},
) -> MaterialPack:
	var pack := MaterialPack.new()
	pack.turn_number = turn_number
	pack.max_turns = max_turns
	pack.npc = npc
	pack.scene = scene

	# 素材包·场景素材：静态场景卡 + 开场情境说明（阶段一形态）
	pack.scene_materials = {
		"environment": scene.environment,
		"atmosphere": scene.atmosphere,
		"opening_situation": scene.opening_situation,
	}

	# 素材包·玩家这句话：原样引用
	pack.player_utterance = player_utterance

	# 素材包·知识日志：全量注入（引擎侧由 KnowledgeJournal.entries_for_pack() 给出）
	pack.knowledge_entries = knowledge_entries.duplicate(true)

	# 素材包·玩家信息（末尾强调段用）
	pack.player_info = player_info.duplicate(true)

	# 素材包·记忆：本段对话已确认的历史 + 跨对话摘要
	pack.cross_dialogue_summary = cross_summary
	pack.dialogue_history = confirmed_history.duplicate(true)

	# 素材包·自身状态：阶段一用心情基准；由近期对话结果推导属阶段二
	pack.npc_state = {
		"mood": AffinityStore.tier_label(affinity),
		"tone": npc.profile,
		"affinity": affinity,
	}

	# 行动清单
	pack.action_list = dialogue_actions()

	pack.assembled_at = Time.get_time_string_from_system()
	return pack
