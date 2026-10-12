class_name MaterialPackBuilder
extends RefCounted
## 【流程二：材料包】
## 引擎冻结现场，收集 NPC 此刻的全部相关情况，组装材料包（设计 4.1 第3步、4.3/4.4）：
##   素材包 = 场景素材 + 玩家原话 + 信念层 + 检索世界事实 + 记忆 + 自身状态
##   行动清单 = 三项对话行动
## 行动提案的数据格式从第一天就统一为"类型 + 目标 + 说明"（设计 5.6 接入点一），
## 阶段二扩充世界行动类型时只增清单，不改对话流程。


## 三项对话行动（设计 4.4）：它们的裁决不需要游戏逻辑。
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


## 冻结现场组装材料包：信念层全量 + 检索世界事实 + 记忆 + 自身状态 + 行动清单。
## npc/scene：人物与场景模型；player_utterance：玩家话语（DM 已拆出）；
## confirmed_history：已确认事件；cross_summary：背景摘要；
## knowledge_entries：信念层条目（含 stale 由渲染层现算）；
## world_facts：检索到的世界事实（NPC 所在地作用域 + 全局提要，均 major 全量 minor 封顶，硬线②只读）；
## world_context：叙述域近期事件行（"此刻之前发生了什么"；DM 世界屏的共享上下文）；
## turn_number/max_turns：轮次。
static func build(
		npc: Person,
		scene: Location,
		player_utterance: String,
		confirmed_history: Array,
		cross_summary: String,
		knowledge_entries: Array[KnowledgeEntry],
		turn_number: int,
		max_turns: int,
		affinity := 0,
		player_info := {},
		world_facts: Array[CanonFact] = [],
		world_context: Array[String] = [],
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

	# 素材包·信念层：全量注入（引擎侧由 Person.active_knowledge() 给出）
	pack.knowledge_entries = knowledge_entries.duplicate()

	# 素材包·世界事实：检索注入（§6.3 配方，调用方从 CanonStore 取好传入）
	pack.world_facts = world_facts.duplicate()

	# 素材包·玩家信息（末尾强调段用）
	pack.player_info = player_info.duplicate(true)

	# 素材包·记忆：本段对话已确认的历史 + 跨对话摘要 + 世界上下文（共享经历）
	pack.cross_dialogue_summary = cross_summary
	pack.world_context = world_context.duplicate()
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
