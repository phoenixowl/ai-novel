class_name CharacterEvents
extends RefCounted
## 人物域事件契约（Lore 层）：UI 与 CharacterController 之间的全部交互信号。
## 本文件只声明信号，不含任何逻辑——EventBus（autoload "Events"）按脚本单例化
## 并分发本集线器，自身不感知这些信号的存在。
##
## 约定：cmd_* 为命令（UI → 控制器，期望被执行）；其余为事件（控制器 → UI，告知已发生）。


# —— 命令（UI → 控制器）——

signal cmd_get_characters()                         # 请求人物总览（卡片墙数据）
signal cmd_get_character(npc_id: String)            # 请求单个人物详情（编辑页；"player" 为玩家）
signal cmd_save_character(payload: Dictionary)      # 保存人物编辑（全量期望状态）
signal cmd_reset_character(npc_id: String)          # 恢复卡面：删除该 NPC 的运行时快照
signal cmd_write_back_character(npc_id: String)     # 写回作者卡面：快照反向写入 res://
signal cmd_restore_lore()                           # 还原设定：删除全部人物快照

# —— 事件（控制器 → UI）——

signal characters_listed(items: Array)              # 人物总览数据（玩家 + 全部 NPC 卡片）
signal character_loaded(detail: Dictionary)         # 编辑页详情（kind=player/npc）
signal character_saved(id: String)                  # 保存完成（UI 重拉详情刷新）
signal character_action_result(id: String, ok: bool, message: String)  # 写回/还原/恢复等操作结果
signal lore_changed()                               # 人物设定已变更（其他域据此重载设定资料）
