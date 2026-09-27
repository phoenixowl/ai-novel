class_name LlmEvents
extends RefCounted
## LLM 域事件契约（LLM 层）：UI 与 LLMService 之间的全部交互信号。
## 本文件只声明信号，不含任何逻辑——EventBus（autoload "Events"）按脚本单例化
## 并分发本集线器，自身不感知这些信号的存在。


# —— 命令（UI → 服务） ——

signal cmd_set_config(api_key: String, model: String)     # 保存并应用 Key/模型
signal cmd_test_connection(api_key: String, model: String)  # 临时值连通性测试（可为编辑中未保存的值）
signal cmd_get_config()                                   # 请求重发配置快照

# —— 事件（服务 → UI） ——

signal config(api_key: String, model: String, mode: String)  # 配置快照（mode 为客户端显示名）
signal mode_changed(name: String)                            # 客户端切换（在线/离线、模型变更）
signal test_result(ok: bool, message: String)                # 连通性测试结果
