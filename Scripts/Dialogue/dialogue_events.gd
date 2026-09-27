class_name DialogueEvents
extends RefCounted
## 对话域事件契约（Dialogue 层）：UI 与 DialogueEngine 之间的全部交互信号。
## 本文件只声明信号，不含任何逻辑——EventBus（autoload "Events"）按脚本单例化
## 并分发本集线器，自身不感知这些信号的存在。
##
## 约定：cmd_* 为命令（UI → 引擎，期望被执行）；其余为事件（引擎 → UI，告知已发生）。
## 字段可变的负载（解析结果、事件流水、打包结果）保留单 Dictionary 参，不强行拆参。


# —— 命令（UI → 引擎） ——

signal cmd_start(npc_id: String, scene_id: String)  # 开始一段新对话
signal cmd_submit(text: String)                     # 提交玩家输入（先经第 0 步审查）
signal cmd_get_lore()                               # 请求重发设定资料快照
signal cmd_rollback_to_turn(turn: int)              # 回滚到指定轮次之前（删除该轮及之后的事件）
signal cmd_reset_memory()                           # 重置当前 NPC 的知识日志与记忆
signal cmd_set_review(enabled: bool)                # 开启/关闭输入审查（持久化）
signal cmd_set_player_persona(identity: String, speech_style: String)  # 设置玩家人设（持久化）
signal cmd_get_settings()                           # 请求重发游戏设置快照（审查开关）

# —— 事件（引擎 → UI） ——

signal lore_loaded(characters: Array, scenes: Array, overview: String)
## characters/scenes: Array[Dictionary]{id: String, label: String}
signal review_started()                             # 第 0 步：输入审查开始
signal review_finished(approved: bool, reason: String, notes: Array, raw: String, error: String)
signal input_rejected(text: String, reason: String) # 输入被拒绝：不记录、不计轮次
signal dialogue_started(npc_name: String, scene_name: String)
signal pack_built(pack: MaterialPack)               # 本轮冻结的材料包
signal prompt_built(system: String, user: String)   # 发给模型的两层提示词
signal llm_request(mode: String)                    # 模型请求开始（mode 为客户端显示名）
signal response(result: Dictionary)                 # 解析结果（含 fallback/raw/notes 等可变字段）
signal event_appended(event: Dictionary)            # 对话事件流水（统一记录格式）
signal state_changed(state: String, turn: int, turns_left: int, can_accept: bool)
signal dialogue_ended(reason: String)               # npc_action / turn_limit …
signal review_enabled_changed(enabled: bool)        # 输入审查开关状态（启动/变更/查询时发出）
signal player_persona_changed(identity: String, speech_style: String)  # 玩家人设状态
signal rolled_back(turn: int)                       # 回滚完成（UI 重建对话区）
signal memory_reset()                               # 记忆已重置
