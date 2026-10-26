class_name ToolcallRenderer
extends RefCounted
## 工具调用提示词渲染（Toolcall 层）：把某调用方可用的工具渲染成静态层文档段。
## 权限表即文档来源——渲染的就是 ToolcallCatalog.defs_for(caller)，模型看到的
## 工具清单永远与解析器承认的权限一致；两个提示词组装器（DM / NPC）共用本渲染。


## 渲染"你可用的工具"文档段（嵌入静态规则层）。caller：调用方（CALLER_*）。
static func tools_section(caller: String) -> String:
	var p: PackedStringArray = []
	p.append("## 你可用的工具（tool_calls）")
	p.append("除正文内容外，你可以在输出的 tool_calls 数组里发起工具调用，每个形如")
	p.append("{\"tool\": \"工具名\", \"args\": {…}}；没有需要就省略 tool_calls 或给空数组。")
	for d in ToolcallCatalog.defs_for(caller):
		p.append("- %s %s：args %s" % [d.name, d.title, d.args_hint])
		for line in d.doc:
			p.append("  · " + line)
	var denied := _denied_note(caller)
	if not denied.is_empty():
		p.append(denied)
	return "\n".join(p)


## 越权提示（每个调用方一句——把权限边界也写进提示词，让模型不必试错）。
static func _denied_note(caller: String) -> String:
	match caller:
		ToolcallCatalog.CALLER_NPC:
			return "注意：你不能申报世界事实（facts.declare 是 DM 的权限），也不能替引擎开启对话——想让世界记住什么，把它说给人听。"
		ToolcallCatalog.CALLER_DM:
			return "注意：你不能替 NPC 表态、提案信念或改写好感度——那些属于人物域的权限。"
	return ""
