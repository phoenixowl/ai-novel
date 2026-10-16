class_name GamePaths
extends RefCounted
## user:// 目录布局常量（Common 层）：运行期数据的落盘位置的唯一登记处。
## 只放"代码写死的路径"；会被玩家修改的设置属于 GameConfig，不在这里。


## 事件审计日志目录（dialogue_* / narration_* 两前缀的 jsonl，双域共用）
const EVENT_LOG_DIR := "user://dialogue_logs"
