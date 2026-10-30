class_name GenContext
extends RefCounted
## 冻结生成上下文（Gen 层，数据容器）：一次生成请求的全部参考材料，构建后不再变化
## （与材料包冻结同一哲学——生成结果必须对应一个确定的瞬间）。由 GenController 构建，
## 各 agent 只读取自己需要的字段。


var kind := ""            # location / character / faction
var brief := ""           # DM 的一句话意图（≤60 字）
var origin := ""          # 发起地点 id：location 用它连边；character 用它当 home
var worldview := ""
var mainline := ""
var history_lines: Array[String] = []  # 近期世界流水（渲染好的行）
var pool: GenKnowledgePool = null      # character：候选知识池（构建后冻结）
var acquaintance: Array = []           # character：知情集实体 id（同地点 NPC + 玩家）
var acquaintance_names: Array[String] = []  # 知情集的显示名（提示词与校验共用）
var known_names: Array[String] = []    # 全部现存实体名（防撞名闭集：规范名+别名）
var origin_facts: Array[CanonFact] = []     # 发起地的作用域正典（location/character 背景）
var chained := false      # 链式生成（如新地点的住户）：不重复发起存在事实以外的仪式


## 知情集渲染行（提示词用："你可能认识的人"）。
func acquaintance_lines() -> Array[String]:
	return acquaintance_names.duplicate()


## 名字是否与现存实体冲突（撞名闭集）。
func name_conflicts(name: String) -> bool:
	return known_names.has(name.strip_edges())
