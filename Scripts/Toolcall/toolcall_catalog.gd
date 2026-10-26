class_name ToolcallCatalog
extends RefCounted
## 工具目录（Toolcall 层）：全部工具的登记处与权限表——"谁能调用什么"的唯一来源。
## 调用方（caller）与域的对应：
##   dm  —— 裁判层（DMController）：世界侧操作（申报事实、开启/结束对话）
##   npc —— 人物域（DialogueController）：自身状态操作（好感度、信念提案、结束自己的对话）
## 权限设计（与各域硬线一一对应）：
##   facts.declare   仅 dm  —— NPC 不能主动写入世界事实；NPC 想让世界记住一件事，
##                     只能说给人听，由 DM 下回合申报、或结算时由整理者提取
##   dialogue.start  仅 dm  —— 对话的调度权在裁判层（统一入口裁决的结果）
##   dialogue.end    dm+npc —— DM 可强制结算一场对话；NPC 只能结束自己参与的这一场
##   affinity.change 仅 npc —— 好感度是 NPC 自己的心，DM 不能代写
##   belief.propose  仅 npc —— 信念是 NPC 的私产（硬线①：DM 不读不写 NPC 信念）
## 加工具三步：在此登记（权限+文档）→ ToolcallParser 补参数校验 → 所属控制器补落地。
## 提示词文档（ToolcallRenderer）按 defs_for(caller) 渲染——模型看到的工具清单
## 永远与解析器承认的权限一致。


const CALLER_DM := "dm"
const CALLER_NPC := "npc"

const FACT_DECLARE := "facts.declare"
const DIALOGUE_START := "dialogue.start"
const DIALOGUE_END := "dialogue.end"
const AFFINITY_CHANGE := "affinity.change"
const BELIEF_PROPOSE := "belief.propose"

static var _defs: Array[ToolcallDef] = []


## 全部工具定义（首次调用时惰性构建）。
static func defs() -> Array[ToolcallDef]:
	if _defs.is_empty():
		_build()
	return _defs


## 按工具名取定义（未知工具返回 null）。
static func def(tool_name: String) -> ToolcallDef:
	for d in defs():
		if d.name == tool_name:
			return d
	return null


## 调用方是否有权调用该工具（权限判断的唯一入口）。
static func is_allowed(tool_name: String, caller: String) -> bool:
	var d := def(tool_name)
	return d != null and d.callers.has(caller)


## 某调用方可用的全部工具（提示词文档与权限审计共用）。
static func defs_for(caller: String) -> Array[ToolcallDef]:
	var out: Array[ToolcallDef] = []
	for d in defs():
		if d.callers.has(caller):
			out.append(d)
	return out


static func _build() -> void:
	var declare := ToolcallDef.new()
	declare.name = FACT_DECLARE
	declare.title = "申报持久事实"
	declare.callers = PackedStringArray([CALLER_DM])
	declare.args_hint = "{\"content\": \"简短的状态陈述\", \"weight\": \"major / minor\"}"
	declare.doc = PackedStringArray([
		"只有本回合的行动确实确立了持久状态变化才调用（申报标准见事实纪律）；拿不准就不调。",
		"只能新增：你没有改写或推翻既有事实（[编号] 条目）的权力。",
	])
	_defs.append(declare)

	var start := ToolcallDef.new()
	start.name = DIALOGUE_START
	start.title = "开启对话 / 递话"
	start.callers = PackedStringArray([CALLER_DM])
	start.args_hint = "{\"npc\": \"在场人物 id\", \"speech\": \"要交给这位 NPC 的话\"}"
	start.doc = PackedStringArray([
		"route 为 speech / mixed 时必须调用一次，把玩家要说的话原样或轻度整理后交给 NPC，不改写意思。",
		"npc 只能填在场清单里的 [id]；对话进行中没点名对象时，默认交给当前交谈对象。",
	])
	_defs.append(start)

	var end := ToolcallDef.new()
	end.name = DIALOGUE_END
	end.title = "结束当前对话"
	end.callers = PackedStringArray([CALLER_DM, CALLER_NPC])
	end.args_hint = "DM：{\"reason\": \"一句话理由\"}；NPC：{\"departure\": \"离开的动作描述\"}"
	end.doc = PackedStringArray([
		"结束当前正在进行的对话。DM 用于世界层面的强制结算（NPC 的学习与记忆照常落档）。",
		"NPC 用于自己收场：必须写明离开的动作（departure），不允许凭空消失。",
	])
	_defs.append(end)

	var affinity := ToolcallDef.new()
	affinity.name = AFFINITY_CHANGE
	affinity.title = "好感度变化"
	affinity.callers = PackedStringArray([CALLER_NPC])
	affinity.args_hint = "{\"delta\": -10 到 10 的整数}"
	affinity.doc = PackedStringArray([
		"对方的言行让你对此人的观感发生变化时调用；平淡交流不要调用。",
		"数值只在这里给，不要在发言中直接提及。",
	])
	_defs.append(affinity)

	var belief := ToolcallDef.new()
	belief.name = BELIEF_PROPOSE
	belief.title = "信念提案"
	belief.callers = PackedStringArray([CALLER_NPC])
	belief.args_hint = "{\"ref\": 知识日志编号, \"relation\": \"佐证 或 矛盾\", \"note\": \"一句理由\"}"
	belief.doc = PackedStringArray([
		"对方的话佐证或动摇了你知识日志里某条记录时调用；ref 只能引用本轮材料包展示过的编号。",
		"提案在对话结束结算时才生效——日志当下不会变。",
	])
	_defs.append(belief)
