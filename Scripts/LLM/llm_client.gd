class_name LLMClient
extends Node
## LLM 客户端抽象（LLM 层）。
## 统一接口：await complete(system_prompt, user_prompt, purpose) -> Dictionary
##   { "ok": bool, "content": String, "error": String,
##     "truncated": bool（可选，输出被 max_tokens 截断时为 true） }
## purpose 标注本次请求的业务用途（见 PURPOSE_* 常量）：真实客户端可忽略，
## 离线示例客户端（MockClient）据此挑选应答样本。
## 实现：DeepSeekClient（真实 API）、MockClient（离线示例）。
## 换供应商（OpenAI 兼容协议）时只需再派生一个子类，服务与调用方不变。


## 请求用途常量（未来功能在此追加：PURPOSE_ITEM_FORGE …）
const PURPOSE_DIALOGUE := "dialogue"          ## NPC 对话生成
const PURPOSE_MEMORY := "memory"              ## 对话结算后的记忆与知识提取
const PURPOSE_ENTRY_DESCRIBE := "entry_describe"  ## 首次进场描述（一次性生成后冻结）
const PURPOSE_FACT_EXTRACT := "fact_extract"  ## 探索结算后的世界事实提取（独立整理者）
const PURPOSE_DM := "dm"                      ## DM 裁决（统一入口：路由 + 行动后果叙述）


# ———— 退役机制（换配置时防悬挂 await） ————

var _busy := false       # 是否有在途请求
var _retired := false    # 已被新客户端取代：当前请求结束后自行释放


## 标记退役（被新配置的客户端取代）：空闲立即释放；在途则等请求结束后由
## _release_busy 自毁——直接 queue_free 会让等待回应的协程永远无法恢复，调用方卡死。
func retire() -> void:
	_retired = true
	if not _busy:
		queue_free()


## 子类 complete() 在请求收尾处调用：清除在途标记并按需自毁。
func _release_busy() -> void:
	_busy = false
	if _retired:
		queue_free()


## 请求一次补全。system_prompt/user_prompt：系统与用户提示词；purpose：业务用途
##（真实客户端可忽略，离线示例客户端据此挑选样本）。
## 返回 {ok: bool, content: String, error: String}。
func complete(_system_prompt: String, _user_prompt: String, _purpose := PURPOSE_DIALOGUE) -> Dictionary:
	return {"ok": false, "content": "", "error": "LLMClient 为抽象基类，未实现 complete()"}


## 客户端显示名（顶栏状态用，如 “DeepSeek · deepseek-flash”）。
func display_name() -> String:
	return "未配置的 LLM 客户端"


## 是否为离线示例客户端（UI 提示与测试环境判断用）。
func is_offline() -> bool:
	return true
