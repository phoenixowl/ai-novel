class_name EventBus
extends Node
## 全局事件总线（Common 层，autoload "Events"）：逻辑层与 UI 层之间的唯一中转。
##
## 设计约束：总线对业务一无所知——不声明、不感知任何信号。各领域把“事件契约”
## 写在自己的集线器文件里（原生强类型 signal，如 DialogueEvents / LlmEvents），
## 总线只负责按脚本单例化并分发这些集线器：
##   引擎/服务侧：var ev := bus.hub(DialogueEvents) as DialogueEvents; ev.state_changed.emit(...)
##   UI/测试侧：  (bus.hub(DialogueEvents) as DialogueEvents).state_changed.connect(handler)
## 集线器脚本必须无参构造（只声明信号的契约文件天然满足）。
##
## 测试/嵌入式环境可用 create_shared() 兜底（正常运行由 autoload 提供）。


static var _shared: EventBus

var _hubs := {}  # 脚本资源路径(String) -> 集线器实例(RefCounted)


## 取共享总线实例（autoload 未就绪时为 null）。
static func shared() -> EventBus:
	return _shared


## 测试/嵌入式环境兜底：autoload 未就绪时手动创建并注册共享实例
static func create_shared() -> EventBus:
	if _shared == null:
		_shared = EventBus.new()
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			(loop as SceneTree).root.add_child(_shared)
	return _shared


func _ready() -> void:
	_shared = self


func _exit_tree() -> void:
	if _shared == self:
		_shared = null


## 取领域集线器：按脚本资源路径单例化并缓存；脚本必须可无参构造
func hub(script: Script) -> RefCounted:
	var path := script.get_path()
	if not _hubs.has(path):
		var instance: Variant = script.new()
		assert(instance is RefCounted, "事件集线器必须是 RefCounted：%s" % path)
		_hubs[path] = instance
	return _hubs[path]


## 该集线器是否已注册（测试用）。script：契约脚本。
func has_hub(script: Script) -> bool:
	return _hubs.has(script.get_path())
