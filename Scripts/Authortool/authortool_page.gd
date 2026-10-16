class_name AuthortoolPage
extends VBoxContainer
## AuthorTool 子页基类（Scripts/Authortool/）：统一子页对外形态——
## setup（构建 UI + 首次注入草稿）与 apply_draft（重新载入草稿时刷新）。
## 外壳屏据此静态分发，不做字符串 call。各子页（世界/风格/列表型）皆派生自本类。


## 构建本页 UI 并注入草稿（每个页面实例只调一次；子类必须实现）。
func setup(_draft: AuthortoolDraft) -> void:
	pass


## 重新载入草稿：刷新本页展示（默认无动作——纯展示页可不变）。
func apply_draft(_draft: AuthortoolDraft) -> void:
	pass
