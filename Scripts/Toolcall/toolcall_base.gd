class_name ToolcallBase
extends RefCounted
## 工具基类（Toolcall 层）：一个工具 = 一个子类。
## 子类在 _init 里填名片字段（name / title / callers / args_hint / doc），
## 并按需覆盖 validate_args 做参数校验与清洗。
## 设计约定：
##   · 权限（callers）与提示词文档同处一类——权限表即文档来源，模型看到的
##     工具清单永远与解析器承认的一致；
##   · 执行不在本层：validate_args 只产出干净的参数，落地由所属域控制器按
##     解析结果调用引擎函数（硬规则：模型输出永不直接改世界）；
##   · validate_args 返回空 Dictionary = 丢弃该项调用（原因已写入 notes），
##     非空 = 清洗后的参数。


var name := ""                      # 工具名（点分命名空间："域.动作"，如 facts.declare）
var title := ""                     # 中文标题（提示词文档用）
var callers: PackedStringArray = [] # 允许的调用方（ToolcallCatalog.CALLER_*）
var args_hint := ""                 # 参数示例（提示词文档与输出契约共用）
var doc: PackedStringArray = []     # 提示词文档行（何时调用 / 权限边界）


## 调用方是否有权调用本工具。
func is_allowed(caller: String) -> bool:
	return callers.has(caller)


## 校验并清洗参数（子类覆盖；默认无参透传）。
## args：模型给出的参数（可能来自嵌套 args 对象或扁平字段）；
## caller：调用方（CALLER_*）——同一工具对不同调用方可有不同必填项；
## notes：解析过程逐条追加（调试页展示）。
func validate_args(args: Dictionary, _caller: String, _notes: Array[String]) -> Dictionary:
	return args
