class_name GenEvents
extends RefCounted
## 生成域信号契约（Gen 层）：零逻辑，只声明信号。
## UI 经 EventBus 在本集线器上收事件、发命令（与其他域同款约定）。

signal generation_started(kind: String)            # 一次生成开始（kind = location/character/faction）
signal generation_stage(stage: String)             # 阶段推进（"构思中"/"一致性审核中"/"修订中"）
signal generation_finished(kind: String, ok: bool, message: String)  # 一次生成结束（含放弃原因）
signal cmd_clear_generated()                       # 命令：清除全部动态生成内容（调试入口）
