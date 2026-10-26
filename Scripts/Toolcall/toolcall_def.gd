class_name ToolcallDef
extends RefCounted
## 工具定义（Toolcall 层，契约）：模型可调用操作的一张名片——名称、标题、
## 允许的调用方（权限的唯一来源）、参数说明与提示词文档行。
## 纯数据零逻辑：结构校验在 ToolcallParser，执行落在各域控制器的落地函数
## （硬规则不变——模型输出永不直接改世界，工具层只负责契约）。


var name := ""                      # 工具名（点分命名空间："域.动作"，如 facts.declare）
var title := ""                     # 中文标题（提示词文档用）
var callers: PackedStringArray = [] # 允许的调用方（ToolcallCatalog.CALLER_*）
var args_hint := ""                 # 参数示例（提示词文档与输出契约共用）
var doc: PackedStringArray = []     # 提示词文档行（何时调用 / 权限边界）
