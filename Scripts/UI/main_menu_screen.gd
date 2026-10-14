extends Control
## 开始菜单屏（Scripts/UI/）：应用启动首页，提供「探索世界」「人物」「设置」三个入口。
## 跳转经 UiEvents 集线器的 navigate_requested 信号发出，由根容器切换屏幕。


## 导航集线器（_ready 时经总线取得）。
var _nav: UiEvents


## 取全局事件总线；autoload 未就绪时（理论上仅测试环境）手动创建。
func _bus() -> EventBus:
	return EventBus.shared() if EventBus.shared() != null else EventBus.create_shared()


## 初始化：取得导航集线器（按钮信号已在场景 [connection] 中接线）。
func _ready() -> void:
	_nav = _bus().hub(UiEvents) as UiEvents


## 「探索世界」：请求导航到探索屏（旁白域——行动裁决与世界叙述）。
func _on_menu_narration_pressed() -> void:
	_nav.navigate_requested.emit("narration")


## 「人物」：请求导航到人物总览。
func _on_menu_characters_pressed() -> void:
	_nav.navigate_requested.emit("characters")


## 「设置」：请求导航到设置屏。
func _on_menu_settings_pressed() -> void:
	_nav.navigate_requested.emit("settings")


## 「设定编辑（AuthorTool）」：请求导航到设定编辑屏（多子页编辑 + 一键导出作者数据包）。
func _on_menu_authortool_pressed() -> void:
	_nav.navigate_requested.emit("authortool")
