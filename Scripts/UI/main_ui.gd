extends Control
## UI 根容器（Scripts/UI/）：只负责屏幕切换与全局外观，不含任何业务逻辑。
## 五个子场景（各自独立的 tscn + UI 脚本）以实例形式挂在本场景下：
##   Scenes/main_menu.tscn          开始菜单（main_menu_screen.gd）
##   Scenes/characters_screen.tscn  人物总览（characters_screen.gd）
##   Scenes/character_edit_screen.tscn 人物编辑（character_edit_screen.gd）
##   Scenes/settings_screen.tscn    设置（settings_screen.gd）
##   Scenes/dialogue_screen.tscn    对话 + 调试侧栏（dialogue_screen.gd）
## 屏幕间跳转经 UiEvents 集线器（EventBus 中转）：子屏幕发射 navigate_requested，
## 本脚本订阅后切换五个子场景的可见性。


# —— 五个子场景实例（@onready 场景唯一名引用） ——
@onready var menu_screen: Control = %MainMenu
@onready var characters_screen: Control = %CharactersScreen
@onready var character_edit_screen: Control = %CharacterEditScreen
@onready var settings_screen: Control = %SettingsScreen
@onready var dialogue_screen: Control = %DialogueScreen


## 取全局事件总线；autoload 未就绪时（理论上仅测试环境）手动创建。
func _bus() -> EventBus:
	return EventBus.shared() if EventBus.shared() != null else EventBus.create_shared()


## 初始化：设置窗口底色、订阅导航信号、显示开始菜单。
func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#191a21"))
	(_bus().hub(UiEvents) as UiEvents).navigate_requested.connect(_on_navigate_requested)
	_show_screen(menu_screen)


## 导航事件处理：切换到目标屏幕（其余屏隐藏）。
## screen：目标屏幕标识——"menu" / "characters" / "character_edit" / "settings" / "dialogue"；
## 未知标识忽略。
func _on_navigate_requested(screen: String) -> void:
	match screen:
		"menu":
			_show_screen(menu_screen)
		"characters":
			_show_screen(characters_screen)
		"character_edit":
			_show_screen(character_edit_screen)
		"settings":
			_show_screen(settings_screen)
		"dialogue":
			_show_screen(dialogue_screen)


## 显示指定子场景并隐藏其余各屏。screen：五个子场景实例之一。
func _show_screen(screen: Control) -> void:
	menu_screen.visible = screen == menu_screen
	characters_screen.visible = screen == characters_screen
	character_edit_screen.visible = screen == character_edit_screen
	settings_screen.visible = screen == settings_screen
	dialogue_screen.visible = screen == dialogue_screen
