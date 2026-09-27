class_name LLMClient
extends Node
## LLM 客户端抽象（LLM 层）。
## 统一接口：await complete(system_prompt, user_prompt, purpose) -> Dictionary
##   { "ok": bool, "content": String, "error": String }
## purpose 标注本次请求的业务用途（见 PURPOSE_* 常量）：真实客户端可忽略，
## 离线示例客户端（MockClient）据此挑选应答样本。
## 实现：DeepSeekClient（真实 API）、MockClient（离线示例）。
## 换供应商（OpenAI 兼容协议）时只需再派生一个子类，服务与调用方不变。


## 请求用途常量（未来功能在此追加：PURPOSE_NARRATOR、PURPOSE_ITEM_FORGE …）
const PURPOSE_DIALOGUE := "dialogue"          ## NPC 对话生成
const PURPOSE_INPUT_REVIEW := "input_review"  ## 玩家输入审查


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
