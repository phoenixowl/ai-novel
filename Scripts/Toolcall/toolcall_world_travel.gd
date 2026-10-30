class_name ToolcallWorldTravel
extends ToolcallBase
## world.travel（仅 DM）：把玩家切换到相邻场景——引擎确定性执行（邻接校验、落盘、
## 首次进场描述都不需要模型参与第二次）。参数校验含邻接闭集：目标必须经注册表
## 解析为已知地点、且与当前位置相邻。落地：DMController._apply_travel
## （对话进行中不可移动，与 cmd_travel_to 同一门控）。


func _init() -> void:
	name = ToolcallCatalog.WORLD_TRAVEL
	title = "切换场景（仅相邻）"
	callers = PackedStringArray([ToolcallCatalog.CALLER_DM])
	args_hint = "{\"scene\": \"相邻地点 id\"}"
	doc = PackedStringArray([
		"玩家声明移动、或行动后果改变了所在位置时调用；只能移动到材料层“相邻地点”清单里的场景。",
		"移动由引擎确定性执行：邻接校验、落盘与首次进场描述都不需要你再叙述第二次。",
		"对话进行中不可移动——先 dialogue.end 收场，下一回合再移动。",
	])


func validate_args(args: Dictionary, _caller: String, notes: Array[String]) -> Dictionary:
	var scene := str(JsonTool.pick(args, ["scene", "to", "target", "地点"], "")).strip_edges()
	if scene.is_empty():
		notes.append("world.travel 缺少目标场景，已丢弃。")
		return {}
	var resolved := EntityRegistry.resolve(scene)
	if not resolved.is_empty():
		scene = resolved  # 给了名字也给一次解析兜底（规范名/别名 → 实体 id）
	if not LocationStore.has(scene):
		notes.append("world.travel 目标「%s」不是已知地点，已丢弃。" % scene)
		return {}
	if scene == LocationStore.current():
		notes.append("world.travel 目标就是当前地点，已丢弃。")
		return {}
	if not LocationStore.neighbors(LocationStore.current()).has(scene):
		notes.append("world.travel 目标「%s」与当前位置不相邻，已丢弃（只能移动到相邻场景）。" % EntityRegistry.display_name(scene))
		return {}
	return {"scene": scene}
