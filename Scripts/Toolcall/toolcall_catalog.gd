class_name ToolcallCatalog
extends RefCounted
## 工具目录（Toolcall 层）：全部工具的注册处——一个工具 = 一个 ToolcallBase 子类实例。
## 加新工具三步：
##   1. 新建 ToolcallXxx extends ToolcallBase（_init 填名片 + validate_args 做参数校验）；
##   2. 在本类登记工具名常量，并在 _build_tools() 里追加实例；
##   3. 所属域控制器补落地（硬规则：模型输出永不直接改世界）。
## 调用方（caller）与域的对应：
##   dm  —— 裁判层（DMController）：世界侧操作（申报事实、递话、强制收场、相邻移动）
##   npc —— 人物域（DialogueController）：自身状态操作（好感度、信念提案、结束自己这场）
## 权限边界与各域硬线一一对应（详见各工具类的 doc）。


const CALLER_DM := "dm"
const CALLER_NPC := "npc"

const FACT_DECLARE := "facts.declare"
const DIALOGUE_START := "dialogue.start"
const DIALOGUE_END := "dialogue.end"
const AFFINITY_CHANGE := "affinity.change"
const BELIEF_PROPOSE := "belief.propose"
const WORLD_TRAVEL := "world.travel"
const WORLD_DISCOVER := "world.discover"
const PLAYER_STATE := "player.state"

static var _tools: Array[ToolcallBase] = []


## 全部工具实例（首次调用时惰性构建；加工具在 _build_tools 登记）。
static func tools() -> Array[ToolcallBase]:
	if _tools.is_empty():
		_build_tools()
	return _tools


## 按工具名取工具实例（未知工具返回 null）。
static func def(tool_name: String) -> ToolcallBase:
	for t in tools():
		if t.name == tool_name:
			return t
	return null


## 调用方是否有权调用该工具（权限判断的唯一入口）。
static func is_allowed(tool_name: String, caller: String) -> bool:
	var t := def(tool_name)
	return t != null and t.is_allowed(caller)


## 某调用方可用的全部工具（提示词文档渲染用——权限表即文档来源）。
static func defs_for(caller: String) -> Array[ToolcallBase]:
	var out: Array[ToolcallBase] = []
	for t in tools():
		if t.callers.has(caller):
			out.append(t)
	return out


static func _build_tools() -> void:
	_tools = [
		ToolcallFactsDeclare.new(),
		ToolcallDialogueStart.new(),
		ToolcallDialogueEnd.new(),
		ToolcallAffinityChange.new(),
		ToolcallBeliefPropose.new(),
		ToolcallWorldTravel.new(),
		ToolcallWorldDiscover.new(),
		ToolcallPlayerState.new(),
	]
