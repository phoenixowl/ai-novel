# 代码结构与调用链分析

这份文档解释这个项目的代码是怎么组织的、一轮对话和一次人物编辑在程序内部是怎么流转的。
读这份文档不需要预先了解任何设计概念——所有名词在用到的地方都会解释。

---

## 一、命名规则：五个家族

所有类先按"职责"归入一个家族，家族决定后缀、也决定它在调用链上能调用谁：

| 家族 | 后缀 | 判定问题 | 调用许可 |
|---|---|---|---|
| **控制器** | `xxxController` | 它接收 `cmd_*` 命令、推进状态机、向 UI 发事件吗？ | 可调用一切 |
| **处理器** | `Builder` / `Parser` / `Reviewer` / `Summarizer` / `Tool` | 它被控制器调用完成一步加工，自己不拥有世界状态吗？ | 只调用存取器与模型 |
| **存取器** | `Repository` / `Store` / `Log` / `Client` | 它只负责数据进出（文件或外部协议），不含业务规则吗？ | 不反向调用 |
| **模型** | 领域名词（`Card` / `Pack` / `Config`…） | 它主要是数据，方法仅限序列化与简单查询吗？ | 谁都不调用 |
| **契约** | `xxxEvents` / `EventBus` | 它只声明/分发信号，没有任何逻辑吗？ | —— |

每个业务域一个目录，目录内必备 `xxx_controller.gd` + `xxx_events.gd`。
调用链永远读得通：**UI →(cmd 命令) Controller →(加工) Processor →(存取) Store/Repository →(广播) Events → UI**。

---

## 二、项目全貌

这是一个"AI 互动小说"的原型：玩家用文字和 NPC（游戏角色）对话，
NPC 由大语言模型（DeepSeek）扮演。程序的工作不是替 NPC 想话说，
而是**给模型准备好它需要的材料、检查它说的话、记住发生过的事**；
此外提供一套人物编辑界面，玩家可以查看和修改任何人物的设定。

代码分成五个目录，每个目录一个业务域：

```
Scripts/
├─ Common/    跨域基建（事件总线、审计日志、JSON 工具、游戏设置）
├─ LLM/       「模型」域：和 DeepSeek 打交道的一切
├─ Lore/      「设定」域：人物卡、组织、知识日志、人物编辑
├─ Dialogue/  「对话」域：一轮对话的核心流程
└─ UI/        「界面」域：五个屏幕各自的脚本 + 导航信号
```

**依赖方向是单向的**：UI → 总线 → 各域控制器。UI 从不直接调用控制器的函数，
控制器也不知道 UI 的存在——它们只通过"事件总线"交换消息。

---

## 三、程序怎么启动

`project.godot` 里配置了主场景 `Scenes/main.tscn`（把五个屏幕摆好，按导航信号决定哪个可见）
和**四个自动加载（autoload）**——游戏一启动就存在的全局单例：

| 顺序 | 名字 | 脚本 | 家族 | 干什么 |
|---|---|---|---|---|
| 1 | `Events` | `Common/event_bus.gd` | 契约 | 事件总线，所有跨层消息的中转站 |
| 2 | `LLM` | `LLM/llm_controller.gd` | 控制器 | 模型域：管 API Key、创建客户端、发请求 |
| 3 | `Characters` | `Lore/character_controller.gd` | 控制器 | 人物域：卡面/快照、人物编辑、知识日志构建 |
| 4 | `Dialogue` | `Dialogue/dialogue_controller.gd` | 控制器 | 对话域：整段对话流程的指挥官 |

各控制器在所属域的 Events 集线器上连接 `cmd_*` 命令、发射事件信号：
`DialogueEvents` / `LlmEvents` / `CharacterEvents` / `UiEvents`。
看名字就知道方向：`cmd_*` 是 UI 发给控制器的命令，其余是控制器发给 UI 的事件。

---

## 四、数据存在哪里

**res://settings/（作者写的，随游戏发布，运行期只读）**
世界观、15 张 NPC 人物卡、组织、场景卡、玩家默认卡、跨对话背景摘要。

**user://（运行时产生）——「设定集快照」+ 体验数据**

| 文件 | 内容 | 谁写 |
|---|---|---|
| `characters/<id>.json` | **人物运行时快照**：persona 区（称呼/身份/人设）+ journal 区（全量知识、记忆） | CharacterController / DialogueController |
| `affinity/<id>.json` | 该 NPC 对玩家的好感度 | AffinityStore |
| `player.json` | 玩家快照（称呼/身份/外观） | CharacterController |
| `config.cfg` | API Key、模型、审查开关 | LlmConfig / GameConfig |
| `dialogue_logs/*.jsonl` | 每段对话的审计流水（一行一个 JSON） | AuditLog |
| `journals/<id>.json` | 旧版学习日志（仅兼容读取，不再新写） | —— |

**快照语义**：一切修改（对话学习、编辑页保存）都写快照；`res://settings/` 是只读模板。
「恢复卡面」删单人快照、「还原设定」删全部快照，回落作者卡面；
「写回作者卡面」把快照反向写入 res://（仅 Godot 编辑器环境可行）。
好感度与对话日志是体验数据，不属于快照，还原时保留。

---

## 五、一轮对话的完整调用链

```
玩家回车
→ dialogue_screen.gd 发命令：DialogueEvents.cmd_submit
→ DialogueController::submit_player_input()
   状态切到"输入审查中"（等待期 UI 置灰回滚/结算按钮）
→ 第 0 步：InputReviewer[处理器] 组装审查提示词
   → await LLMController.complete_json()          ← 等模型回复
   ├─ 拒绝 → 只写 AuditLog（NPC 没听到）→ input_rejected → 原文退回输入框
   └─ 通过 → 轮次 +1，玩家原话入事件流水 → 状态切到"等待NPC回应"
→ 流程二：MaterialPackBuilder.build()[处理器]
   场景素材 + 玩家原话 + 知识日志全量（CharacterController.build_journal_for 构建）
   + 记忆 + 好感度档位 + 三选一行动清单 —— 组装后冻结 → pack_built
→ PromptBuilder[处理器] 两层拼装（静态层按 NPC 缓存 / 本轮材料层）→ prompt_built
→ 流程三：await LLMController.complete_json()
   ├─ 传输失败 → 退回玩家轮，不写事件
   ├─ 不可解析 → _fallback_response 保底沉默（宁可冷淡，不可胡说）
   └─ 成功 → ResponseParser.validate()[处理器] 四要素校验
      → 信念提案延后收集（_pending_learning）
      → 好感度即时结算（AffinityStore，每轮 ±10）→ affinity_changed
      → _land_response 落档：答话入记录 / 沉默记冷处理 / 结束则收尾
```

每条事件：打轮次号与序号 → 进 `turn_events` 流水 → AuditLog 落盘 → `event_appended` 让 UI 画气泡。

**对话结束**（NPC 选择 / 12 轮上限 / 手动结算）时 `end_dialogue()`：
结算全部延后的信念提案（闭集校验 + 确定性信任算术）→ LLM 整理记忆与新知识 →
写入人物快照 → 关日志。学习延后到结束才结算，保证回滚（丢弃在途请求 + 删提案）始终干净。

---

## 六、一次人物编辑的调用链

```
主菜单「人物」→ characters_screen 卡片墙（cmd_get_characters → characters_listed）
→ 点卡片 → character_edit_screen（cmd_get_character → character_loaded）
→ 改表单 →「保存并刷新」cmd_save_character
→ CharacterController：
   人设 → SnapshotStore.write_persona（快照 persona 区）
   知识 → KnowledgeJournal 整表更新（未列出的 seq 即删除）→ 快照 journal 区
   记忆 → set_memories；好感度 → AffinityStore.set_value
   → characters_listed + character_saved + lore_changed
→ DialogueController 监听 lore_changed：重载 LoreRepository、清提示词缓存、重发 lore_loaded
→ 编辑页收到 character_saved 重拉详情（表单回到引擎侧真值）
```

「对话」按钮 → UiEvents.dialogue_requested → 对话屏预选该 NPC 并自动开始。
**两域只通过 `lore_changed` 一个信号握手**——人物域改了世界，对话域重读世界，互不知晓内部细节。

---

## 七、知识系统：来源锚定的知识日志

每个 NPC 一本**只追加日志**（`KnowledgeJournal`[模型]）：条目 = 知识表述 + 逐字依据（习得条目）
+ 来源 + 信任。信任梯 `怀疑 → 比较相信 → 绝对可信`，算术全部确定性：

- 独立来源佐证 +1 档（同来源无效）；矛盾 -1 档（下限怀疑）；已失效被佐证 → 复活为怀疑
- 模型输出只有三种形态：逐字复制、闭集引用（材料包展示过的编号）、枚举——引擎全部可校验

材料包**全量注入**知识日志（超过 80 条才压缩佐证链）；识谎免费——玩家的话与日志矛盾时
两条记录同在模型眼前。

---

## 八、每个文件一览（按域，附行数）

```
Scripts/Common/                          跨域基建
  event_bus.gd             (57)  契约·总线：集线器注册与分发
  audit_log.gd             (37)  存取器·审计日志：jsonl 的打开/追加/关闭
  json_tool.gd             (91)  处理器·JSON 剥围栏/提取/键名兼容
  game_config.gd           (30)  模型·游戏设置（审查开关）

Scripts/LLM/                             「模型」域
  llm_controller.gd      (176)  控制器：配置/客户端生命周期/complete_json
  llm_events.gd            (18)  契约：模型域信号
  llm_client.gd            (31)  存取器·客户端抽象基类 + purpose 常量
  deepseek_client.gd      (133)  存取器·真实请求（含截断检测）
  mock_client.gd          (198)  存取器·离线示例（按话题/用途挑样本）
  llm_config.gd            (37)  模型·Key/模型的本机存取

Scripts/Lore/                            「设定」域
  character_controller.gd (302)  控制器：人物快照的一切修改 + 知识日志构建
  character_events.gd      (24)  契约：人物域信号
  lore_repository.gd      (334)  存取器·聚合 res://settings/ 全部设定
  snapshot_store.gd        (85)  存取器·user://characters/ 快照读写
  affinity_store.gd        (71)  存取器·好感度档位/增减/存取
  knowledge_journal.gd    (378)  模型·知识日志：信任算术/习得/复活/记忆
  character_card.gd / player_card.gd / faction.gd / scene_card.gd   模型·卡片

Scripts/Dialogue/                        「对话」域
  dialogue_controller.gd (603)  控制器：状态机/审查/生成/落地/结算/回滚
  dialogue_events.gd       (35)  契约：对话域信号
  input_reviewer.gd        (61)  处理器·第 0 步输入审查
  material_pack_builder.gd (90)  处理器·冻结现场组装材料包
  material_pack.gd         (99)  模型·材料包数据与调试展示
  prompt_builder.gd       (178)  处理器·两层提示词拼装
  response_parser.gd      (111)  处理器·回应四要素校验
  memory_summarizer.gd     (46)  处理器·结算时记忆/知识提取提示词

Scripts/UI/                              「界面」域
  ui_events.gd             (16)  契约·导航（navigate/编辑/对话请求）
  main_ui.gd               (46)  根容器：五屏切换
  main_menu_screen.gd      (30)  开始菜单
  characters_screen.gd    (139)  人物总览：卡片墙 + 还原设定
  character_edit_screen.gd(312)  人物编辑：人设/好感度/知识/记忆
  dialogue_screen.gd      (530)  对话屏：气泡/输入/四页调试侧栏
  settings_screen.gd      (115)  设置屏：API + 审查开关

tests/
  smoke_test.gd           (196)  分层单元测试
  engine_loop_test.gd     (218)  端到端回路测试（含人物编辑链路）
  test_util.gd             (11)  断言辅助
```

---

## 九、测试

两个测试都不需要网络和 API Key（强制离线模式）：

```
godot --headless -s tests/smoke_test.gd        # 分层单元测试
godot --headless -s tests/engine_loop_test.gd  # 端到端回路
```

- **smoke_test**：JsonTool、设定加载、知识日志信任算术、快照往返（update_entry/set_memories/retain_seqs）、材料包、提示词、回应校验、审查规则。
- **engine_loop_test**：与 UI 相同的总线路径驱动——开始、审查拒绝、两轮生成、回滚丢弃在途请求、结算即结束、人物编辑（保存/恢复卡面/好感度保留）、结束后不可续聊。

---

## 十、想加新功能时从哪里下手

| 想做的事 | 改哪里 |
|---|---|
| 加新的 NPC 可选行动 | `material_pack_builder.gd` 行动清单 + 控制器 `_land_response` 加分支 |
| 加新 AI 功能（旁白/道具） | `LLMClient` 加 purpose 常量，新域建 `xxx_controller.gd + xxx_events.gd` |
| 给人物卡加字段 | 卡模型加解析 → `CharacterEvents` 详情/保存 payload 加键 → 编辑屏加控件 |
| NPC 之间传话 | 复制 KnowledgeJournal 条目到对方快照（经 SnapshotStore） |
| 换模型供应商 | `Scripts/LLM/` 派生一个 `LLMClient` 子类 |

原则不变：**控制器收命令、发事件；处理器只加工；存取器只进出数据；UI 只连信号、发命令；总线不认识任何业务**。
