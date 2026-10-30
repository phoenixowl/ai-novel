class_name GamePaths
extends RefCounted
## 目录布局（Common 层）：便携式三目录，全部锚定**运行根目录**——
##   导出版（打包 exe）＝ exe 同目录；开发/测试（编辑器环境）＝ 项目根。
##   settings/   初始世界观（作者或玩家放置；"重置"类操作以此为准——引擎只读）
##   saves/      全部运行期数据（正典/实体/位置图/人物快照/好感度/玩家状态/
##               模型与风格配置/审计日志）——删掉整个文件夹即回到初始世界观
##   export/     AuthorTool 导出的作者数据包（覆盖 settings/ 即换世界观）
## 路径拼接统一用 "/"（Windows 亦接受）。res://settings 不再被引擎读取。


static var _base := ""


## 运行根目录（惰性缓存）：编辑器环境取项目根；导出版取 exe 所在目录。
static func base_dir() -> String:
	if _base.is_empty():
		if OS.has_feature("editor"):
			_base = ProjectSettings.globalize_path("res://").rstrip("/\\")
		else:
			_base = OS.get_executable_path().get_base_dir()
	return _base


# ———— 三大目录 ————


static func settings_dir() -> String:
	return base_dir() + "/settings"


static func save_dir() -> String:
	return base_dir() + "/saves"


static func export_dir() -> String:
	return base_dir() + "/export"


# ———— saves 子目录与文件 ————


static func world_dir() -> String:
	return save_dir() + "/world"


static func canon_path() -> String:
	return world_dir() + "/canon.json"


static func entities_path() -> String:
	return world_dir() + "/entities.json"


static func locations_path() -> String:
	return world_dir() + "/locations.json"


static func gen_factions_path() -> String:
	return world_dir() + "/gen_factions.json"


static func player_state_path() -> String:
	return world_dir() + "/player_state.json"


static func characters_dir() -> String:
	return save_dir() + "/characters"


static func affinity_dir() -> String:
	return save_dir() + "/affinity"


static func player_card_path() -> String:
	return save_dir() + "/player.json"


static func config_path() -> String:
	return save_dir() + "/config.cfg"


static func event_log_dir() -> String:
	return save_dir() + "/dialogue_logs"


# ———— settings 内的文件 ————


static func author_canon_path() -> String:
	return settings_dir() + "/canon.json"


static func author_player_state_path() -> String:
	return settings_dir() + "/player_state.json"
