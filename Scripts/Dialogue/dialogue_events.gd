class_name DialogueEvents
extends RefCounted
## 对话域事件契约（Dialogue 层）：UI 与 DialogueController 之间的全部交互信号。
## 本文件只声明信号，不含任何逻辑——EventBus（autoload "Events"）按脚本单例化
## 并分发本集线器，自身不感知这些信号的存在。
##
## 约定：cmd_* 为命令（UI → 引擎，期望被执行）；其余为事件（引擎 → UI，告知已发生）。
## 字段可变的负载（解析结果、事件流水、打包结果）保留单 Dictionary 参，不强行拆参。


# —— 命令（UI → 引擎） ——

signal cmd_start(npc_id: String, scene_id: String)  # 开始一段新对话（DM 调度或 UI 捷径）
signal cmd_submit(text: String)                     # 提交玩家发言（DM 拆出的话语直达此处）
signal cmd_settle_now()              # 结算学习提案并直接结束本段对话
signal cmd_reset_memory()                           # 重置当前 NPC 的知识日志与记忆

# —— 事件（引擎 → UI） ——

signal dialogue_started(npc_id: String, npc_name: String, scene_name: String)
signal pack_built(pack: MaterialPack)               # 本轮冻结的材料包
signal prompt_built(system: String, user: String)   # 发给模型的两层提示词
signal llm_request(mode: String)                    # 模型请求开始（mode 为客户端显示名）
signal response(result: Dictionary)                 # 解析结果（含 fallback/raw/notes 等可变字段）
signal event_appended(event: Dictionary)            # 对话事件流水（统一记录格式）
signal state_changed(state: String, turn: int, turns_left: int, can_accept: bool, busy: bool)
## busy：审查/生成在途（UI 据此置灰结算/重置/开始按钮，勿用 state 文案反推）
signal dialogue_ended(reason: String)               # npc_action / turn_limit …
signal memory_reset()
signal affinity_changed(value: int, change: int)
