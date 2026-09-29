class_name UiEvents
extends RefCounted
## UI 层导航事件契约：各屏幕之间的跳转经 EventBus（autoload "Events"）中转。
## 本文件只声明信号，不含任何逻辑——屏幕脚本在 UiEvents 集线器上发射/连接导航信号，
## 根容器（main_ui.gd）据此切换屏幕可见性。


## 导航请求。screen：目标屏幕标识——"menu"（开始菜单）/ "characters"（人物总览）/
## "character_edit"（人物编辑）/ "dialogue"（对话）/ "settings"（设置）
signal navigate_requested(screen: String)


## 请求编辑某个人物（人物卡片点击 → 编辑页）。npc_id 为人物卡 id 或 "player"。
signal character_edit_requested(npc_id: String)


## 请求与某个人物对话（编辑页 → 对话屏：预选该 NPC 并自动开始）。
signal dialogue_requested(npc_id: String)
