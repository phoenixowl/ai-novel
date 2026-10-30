class_name DMEvents
extends RefCounted
## 旁白域事件契约（DM 层）：UI 与 DMController 之间的全部交互信号。
## 本文件只声明信号，不含任何逻辑——EventBus（autoload "Events"）按脚本单例化
## 并分发本集线器，自身不感知这些信号的存在。
##
## 约定：cmd_* 为命令（UI → 控制器，期望被执行）；其余为事件（控制器 → UI，告知已发生）。
## 旁白输入与对话输入是两个独立接口（不做输入路由）——本域不经第 0 步审查，
## 防注入由旁白提示词静态层消化。


# —— 命令（UI → 控制器） ——

signal cmd_submit_input(text: String)        # 统一入口：提交玩家输入（行动或话语，由 DM 裁决路由）
signal cmd_talk_to(npc_id: String)           # 直接与在场人物开始交谈（位置面板捷径，绕过 DM）
signal cmd_travel_to(entity_id: String)      # 移动到相邻地点（引擎校验有边；不相邻不可达）
signal cmd_get_canon()                          # 请求世界事实快照（调试侧栏①页）
signal cmd_get_state()                          # 请求重发状态机快照（UI 晚于控制器就绪时拉取）
signal cmd_set_knobs(knobs: Dictionary)         # 设置旁白风格旋钮（即时持久化）
signal cmd_get_knobs()                          # 请求重发旋钮快照（设置屏进屏时）
signal cmd_set_embedding_config(provider: String, api_key: String, model: String, base_url: String)  # 检索档位配置（即时持久化 + 换模型清向量）
signal cmd_add_fact(payload: Dictionary)        # 事实库编辑：新增 {content, weight, source, scope_type, scope_id}
signal cmd_edit_fact(payload: Dictionary)       # 事实库编辑：修改 {id, content, weight}
signal cmd_delete_fact(fact_id: int)            # 事实库编辑：删除条目
signal cmd_save_canon()                         # 显式保存事实库到 saves/world/canon.json
signal cmd_reset_canon()                        # 一键重置事实库为作者正典（清除全部运行期事实）
signal cmd_settle_exploration()                   # 结束本段探索并结算（事实整理者提取世界事实）
signal cmd_start_exploration()                  # 结算后开始新探索（重置回合与记录）
signal player_state_changed(state: Dictionary)     # 玩家状态变更（DM player.state 工具落地后；UI 刷新）

# —— 事件（控制器 → UI） ——

signal state_changed(state: String, turn: int, can_accept: bool)   # 状态机快照（无轮次上限，turn 为回合号）
signal location_changed(current_id: String, current_name: String, neighbors: Array, npcs: Array, brief: String)
## 位置快照：neighbors/npcs 为 Array[Dictionary]{id, name}；brief 为冻结的进场描述（可为空）
signal dm_resolved(result: Dictionary)                             # DM 裁决结果（路由/目标/行动叙述/话语；调试④页）
signal world_input_rejected(text: String, reason: String)          # DM 拒绝输入（注入/元指令；原话退回玩家）
signal pack_built(pack: DMPack)                             # 本轮冻结的世界材料包
signal prompt_built(system: String, user: String)                  # 发给模型的两层提示词
signal llm_request(mode: String)                                   # 模型请求开始（mode 为客户端显示名）
signal event_appended(event: Dictionary)                           # 世界事件流水（player_action/narration_turn/对话回声…）
signal canon_listed(entries: Array)                                # 世界事实全量（含 superseded，UI 折叠渲染）
signal canon_saved(path: String)                                   # 事实库已显式保存（path 为绝对路径）
signal canon_reset(count: int)                                     # 事实库已重置为作者正典（count 为播种条数）
signal knobs_changed(knobs: Dictionary)                            # 旋钮状态（启动/变更/查询时发出）
