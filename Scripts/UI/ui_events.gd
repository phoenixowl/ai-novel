class_name UiEvents
extends RefCounted
## UI 层导航事件契约：各屏幕之间的跳转经 EventBus（autoload "Events"）中转。
## 本文件只声明信号，不含任何逻辑——屏幕脚本在 UiEvents 集线器上发射/连接导航信号，
## 根容器（main_ui.gd）据此切换屏幕可见性。


## 导航请求。screen：目标屏幕标识——"menu"（开始菜单）/ "settings"（设置）/ "dialogue"（对话）
signal navigate_requested(screen: String)
