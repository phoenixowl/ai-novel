class_name GenAgentBase
extends RefCounted
## 生成 agent 基类（Gen 层）：一种生成（地点/人物/组织）= 一个子类。
## 子类职责（全部内聚在类里，控制器只编排不插手细节）：
##   build_draft_prompt —— 构思提示词（按冻结上下文拼装）
##   validate_draft     —— 引擎侧契约校验（闭集/上限/撞名），返回规范化草稿；空 = 不合格
##   land               —— 落地（注册、挂图、写快照、存在事实入典），返回结果与链式后续
##   build_revision_prompt / render_for_audit —— 修订与审核的默认形态（子类可覆盖）
## 硬规则不变：agent 不直接改对话状态、不写作者数据；一切落盘走各存取器唯一入口。


var kind := ""     # location / character / faction（子类钉死）
var purpose := ""  # LLMClient.PURPOSE_GEN_*（子类钉死）


## 构思提示词（子类必须覆盖）。
func build_draft_prompt(_ctx: GenContext) -> Dictionary:
	return {"system": "", "user": ""}


## 引擎侧契约校验（子类必须覆盖）。data：complete_json 提取的 Dictionary；
## 返回规范化草稿（Dictionary）；空 Dictionary = 不合格（原因已记入 notes，
## 控制器将其作为问题清单进入修订循环）。
func validate_draft(_data: Dictionary, _ctx: GenContext, _notes: Array[String]) -> Dictionary:
	return {}


## 落地（子类必须覆盖）。draft：校验后的草稿。返回
## {ok: bool, ids: [实体id], message: String, followups: [{kind, brief, home}]}。
func land(_draft: Dictionary, _ctx: GenContext, _notes: Array[String]) -> Dictionary:
	return {"ok": false, "ids": [], "message": "", "followups": []}


## 修订提示词：默认 = 构思提示词 + 上一稿 + 问题清单（子类可覆盖）。
func build_revision_prompt(ctx: GenContext, draft: Dictionary, issues: Array) -> Dictionary:
	var prompts := build_draft_prompt(ctx)
	var p: Array[String] = ["", "———— 修订 ————"]
	p.append("下面是上一稿未通过检查的问题。只针对这些问题修改，重新输出完整的 JSON：")
	for issue in issues:
		p.append("· " + str(issue))
	p.append("")
	p.append("【上一稿】")
	p.append(JSON.stringify(draft, "  "))
	prompts["user"] = str(prompts.get("user", "")) + "\n" + "\n".join(p)
	return prompts


## 交给审核者的草稿文本（默认 JSON 全文；子类可覆盖为更贴切的形态）。
func render_for_audit(draft: Dictionary) -> String:
	return JSON.stringify(draft, "  ")


# ———— 共享小工具 ————


## 截断到 max 字（超长加省略号）。
static func _cap(text: String, max_len: int) -> String:
	var t := text.strip_edges()
	if t.length() > max_len:
		return t.substr(0, max_len) + "……"
	return t


## 清洗别名列：去空白、去重、限条数与长度。返回 Array[String]。
static func _clean_aliases(raw: Variant, max_count: int, max_len: int) -> Array[String]:
	var out: Array[String] = []
	if not (raw is Array):
		return out
	for item in raw:
		var alias := str(item).strip_edges()
		if alias.is_empty() or alias.length() > max_len or out.has(alias):
			continue
		out.append(alias)
		if out.size() >= max_count:
			break
	return out
