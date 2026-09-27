# 代码结构与调用链分析

这份文档解释这个项目的代码是怎么组织的、一轮对话在程序内部是怎么流转的。
读这份文档不需要预先了解任何设计概念——所有名词在用到的地方都会解释。

---

## 一、项目全貌

这是一个"AI 互动小说"的原型：玩家用文字和 NPC（游戏角色）对话，
NPC 由大语言模型（DeepSeek）扮演。程序的工作不是替 NPC 想话说，
而是**给模型准备好它需要的材料、检查它说的话、记住发生过的事**。

代码总量约 4000 行 GDScript，分成五个目录，每个目录职责单一：

```
Scripts/
├─ Common/    通用工具（事件总线、JSON 解析、日志、游戏设置）
├─ LLM/       和大模型打交道的一切（请求、解析、离线模拟）
├─ Lore/      游戏世界的"设定资料"（人物卡、组织、知识日志、好感度）
├─ Dialogue/  对话的核心流程（引擎、提示词、校验、审查）
└─ UI/        界面（三个屏幕各自的脚本 + 导航信号）
```

**依赖方向是单向的**：UI → 总线 → 逻辑层。UI 从不直接调用逻辑层的函数，
逻辑层也不知道 UI 的存在——它们只通过"事件总线"交换消息。这样改任何一边
都不会弄坏另一边。

---

## 二、程序怎么启动

`project.godot` 里配置了三样东西：

**主场景**：`Scenes/main.tscn`。它只做一件事——把三个屏幕（主菜单、
设置、对话）摆好，根据导航信号决定哪个可见。

**三个自动加载（autoload）**：游戏一启动就存在的全局单例，按顺序：

| 顺序 | 名字 | 脚本 | 干什么 |
|---|---|---|---|
| 1 | `Events` | `Common/event_bus.gd` | 事件总线。所有跨层消息的中转站 |
| 2 | `LLM` | `LLM/llm_service.gd` | 模型服务。管 API Key、创建客户端、发请求 |
| 3 | `Dialogue` | `Dialogue/dialogue_engine.gd` | 对话引擎。整个对话流程的指挥官 |

加载顺序很重要：总线最先就位，模型服务和对话引擎才能找到它。

启动完成后：
- 对话引擎读完了 `res://settings/` 下的全部设定（世界观、15 张人物卡、
  组织、场景、玩家默认卡），并把这些信息广播出去；
- 模型服务检查了 API Key——有 Key 就用 DeepSeek，没有就用离线示例；
- UI 各屏连上事件总线，主动"补拉"一次设定和配置的快照（因为 UI 可能
  比逻辑层启动得晚，错过第一轮广播）。

---

## 三、核心概念：事件总线怎么用

项目不用"函数直接调用"来连接 UI 和逻辑层，而是用**信号（signal）**。
信号声明在"集线器"文件里，每个领域一个：

- `DialogueEvents`（`Dialogue/dialogue_events.gd`）：对话域的全部信号
- `LlmEvents`（`LLM/llm_events.gd`）：模型域的全部信号
- `UiEvents`（`UI/ui_events.gd`）：屏幕导航信号

总线的 `hub(集线器脚本)` 方法负责把每个集线器变成全局唯一实例。
举例：

```gdscript
# 对话引擎发出"状态变了"
var ev = EventBus.shared().hub(DialogueEvents) as DialogueEvents
ev.state_changed.emit("等待玩家输入", 1, 11, true)

# UI 连接这个信号，收到参数
ev.state_changed.connect(_on_state_changed)
```

信号分两类，看名字就知道方向：
- `cmd_*` 开头 = **命令**，UI 发给逻辑层（如 `cmd_submit`：玩家说了句话）
- 其余 = **事件**，逻辑层发给 UI（如 `pack_built`：材料包组装好了）

---

## 四、一轮对话的完整调用链

这是全项目最重要的一条链。从玩家按下回车到 NPC 的回应出现在屏幕上：

### 第 1 步：玩家提交输入

```
玩家回车
→ dialogue_screen.tscn 的接线：PlayerInput.text_submitted
→ dialogue_screen_ui.gd::_send()
    检查引擎是否可接受输入（_can_accept 缓存）
→ 发命令信号：DialogueEvents.cmd_submit.emit(text)
→ dialogue_engine.gd::_on_cmd_submit() → submit_player_input(text)
```

### 第 2 步：输入审查（可在设置中关闭）

如果审查开关是开的，输入先送去让模型判断"这是台词还是动作/注入"：

```
submit_player_input()
→ 状态切到"输入审查中"，广播 state_changed
→ _review_then_generate()
→ await LLM.complete_json(审查提示词, purpose=INPUT_REVIEW)   ← 等模型回复
→ InputReviewer.verdict_of() 解析结论
├─ 拒绝 → 只写审计日志（NPC 没听到）→ 发 input_rejected
│         → UI：红色气泡 + 原文退回输入框 → 结束本轮
└─ 通过 → _accept_player_text()
```

审查失败（网络断了、模型输出乱码）**按放行处理**——审查器坏了不能堵死玩家。

### 第 3 步：接纳发言，组装材料包

```
_accept_player_text()
→ 轮次数 +1
→ 事件流水追加 player_utterance，发 event_appended（UI 画玩家气泡）
→ 状态切到"等待NPC回应"
→ _generate_response()
→ MaterialPackBuilder.build()   ← 【材料包组装】
```

材料包 = NPC 这一轮需要的全部材料，装完就冻结不再变：

| 材料 | 来源 |
|---|---|
| 场景素材（环境/氛围/开场） | 场景卡 |
| 玩家原话 | 刚才那句 |
| 知识日志全量 | KnowledgeJournal（这个 NPC 知道的一切） |
| 背景 + 最近会话摘要 | 设定 memory/ + 日志的会话摘要 |
| NPC 状态（对玩家的好感度档位） | AffinityStore |
| 行动清单（答话/沉默/结束） | 写死的三项 |

材料包组装好 → 发 `pack_built` → UI 侧栏②页立刻显示。

### 第 4 步：拼提示词，调模型

```
→ PromptBuilder.system_prompt()   静态层：身份+设定+组织+世界观+全部规则
→ PromptBuilder.user_prompt()     材料层：把材料包内容渲染成文字
→ 发 prompt_built（UI 侧栏③页显示两层全文，可复制）
→ 发 llm_request（顶栏变"请求中…"）
→ await LLM.complete_json(静态层, 材料层, purpose=DIALOGUE)   ← 等模型回复
```

模型服务的内部：Key 为空用 MockClient（离线，按话题挑样本，延迟 0.7 秒）；
有 Key 用 DeepSeekClient（真实 HTTP 请求）。返回的 JSON 会被自动剥掉
markdown 围栏、提取首个完整对象；输出被截断会明确报错并走保底。

### 第 5 步：校验与落地

模型回复后引擎做三件事（都在 `_generate_response` 里）：

```
→ ResponseParser.validate()
    把 JSON 校验成结构化数据：发言/性质声明/行动提案/learned/belief_updates/
    affinity_change，坏值给默认值并记入 notes
→ _collect_learning()
    把学习提案暂时收起来（延后到对话结束才结算——保证回滚干净）
→ AffinityStore.apply_change()
    好感度即时结算（±10 上限），落盘，发 affinity_changed
→ 发 response（UI 侧栏④页显示解析详情）
→ _land_response()
    按行动类型落档：
      answer → 事件流水记 npc_utterance → 继续下一轮
      silence → 记 npc_silence → 继续下一轮
      end_dialogue → 记 npc_utterance → end_dialogue("npc_action")
```

每条事件都会：打上轮次号和序号 → 存进内存流水 → 写入
`user://dialogue_logs/*.jsonl` 文件 → 发 `event_appended` 让 UI 画气泡。

---

## 五、对话结束时发生什么

对话结束有两个触发点：NPC 自己选了结束（`npc_action`），或达到 12 轮上限
（`turn_limit`）。`end_dialogue()` 按顺序做五件事：

```
end_dialogue(reason)
→ 1. 事件流水追加 dialogue_ended
→ 2. _settle_learning()          ← 【延后的学习结算】
      遍历整场对话攒下来的学习提案，逐条校验并写入知识日志：
      · learned.quote 必须逐字出现在当时的玩家原话里（防编造），
        失败就整句锚定（每轮限一次）
      · belief_updates.ref 必须是当时材料包展示过的编号（闭集），
        佐证→信任+1 档，矛盾→-1 档（下限怀疑），同来源佐证无效
      · 每条写入都发 knowledge_learned / belief_updated 事件
→ 3. journal.add_session_summary()   记一条"第 N 次交谈，谈了 X 轮，新记 Y 条"
→ 4. journal.save(npc_id)        写 user://journals/<npc_id>.json
→ 5. 关闭日志文件，发 dialogue_ended，广播状态
```

**为什么学习要延后结算？** 如果每轮都立刻写入，玩家回滚到第 3 轮时
第 5 轮学到的东西就成了"幽灵知识"。延后结算让回滚只需要删除提案，
不需要回滚日志。

**好感度例外**：好感度是即时结算的（每轮 ±10），因为它是连续数值、
回滚时按轮次覆盖即可，不存在"幽灵条目"问题。

---

## 六、三个屏幕各自管什么

| 屏幕 | 脚本 | 连接的事件 | 发出的命令 |
|---|---|---|---|
| 主菜单 `main_menu.tscn` | `main_menu_ui.gd` | 无 | `navigate_requested` |
| 设置 `settings_screen.tscn` | `settings_screen_ui.gd` | config、test_result、审查开关、人设 | set_config、test_connection、set_player_persona、set_review |
| 对话 `dialogue_screen.tscn` | `dialogue_screen_ui.gd` | 全部对话域事件 + LLM 配置/模式 | start、submit、rollback、reset_memory、settle_now |

根容器 `main_ui.gd` 只订阅 `UiEvents.navigate_requested`，负责三个屏幕
哪个可见——它不知道对话是什么，只管"切屏"。

对话屏的每个 NPC 气泡带两个小按钮：「⎘」复制该段发言、「↩」回滚到该轮
之前（删除该轮及之后的事件和学习提案，重新说话）。

---

## 七、数据存在哪里

**`res://settings/`（作者写的，随游戏发布，运行期只读）**

| 文件/目录 | 内容 | 谁读 |
|---|---|---|
| `worldview.txt` | 世界观全文 | 提示词静态层 |
| `player.json` | 玩家默认卡（姓名/身份/外观） | LoreRepository |
| `characters/*.json` | 15 张 NPC 卡：身份/profile/初始好感度/内联初始知识/组织 | LoreRepository |
| `factions.json` | 组织与成员 | LoreRepository |
| `scenes/*.json` | 场景卡（环境/氛围/开场） | LoreRepository |
| `memory/*.json` | NPC 的跨对话背景摘要 | LoreRepository |

**`user://`（运行时产生，在 %APPDATA%\Godot\app_userdata\ai_novel\）**

| 文件 | 内容 | 谁写 |
|---|---|---|
| `config.cfg` | API Key、模型、审查开关、人设 | LlmConfig / GameConfig |
| `player.json` | 玩家修改后的人设（覆盖默认卡） | 设置屏 → 引擎 |
| `journals/<npc>.json` | 该 NPC 习得的知识条目 + 会话摘要 | KnowledgeJournal |
| `affinity/<npc>.json` | 该 NPC 对玩家的好感度 | AffinityStore |
| `dialogue_logs/*.jsonl` | 每段对话的完整事件流水（一行一个 JSON） | EventJournal |

**关键设计**：作者域（res://settings/）和运行时域（user://）物理分离。
你随时改设定、重新生成知识库、重装游戏，玩家的对话进度（谁学到了什么、
好感度多少）都存在另一边，互不影响。

---

## 八、测试

两个测试都不需要网络和 API Key（强制离线模式）：

```
godot --headless -s tests/smoke_test.gd        # 分层单元测试（68 项）
godot --headless -s tests/engine_loop_test.gd  # 端到端回路（38 项）
```

- **smoke_test**：逐层验证——JSON 工具、设定加载、知识日志的信任算术
  （佐证/矛盾/复活/持久化）、材料包、提示词、回应校验（坏数据丢弃）、审查规则。
- **engine_loop_test**：用和 UI 完全相同的总线路径驱动引擎——开始对话、
  输入被审查拒绝、两轮对话、确认学习提案延后结算、好感度升级、结束对话后
  会话摘要落档、结束后不可续聊。

---

## 九、每个文件一览（按目录，附行数）

```
Scripts/Common/                          通用工具层
  event_bus.gd            (56)   事件总线：集线器注册与分发
  event_journal.gd        (37)   jsonl 日志的打开/追加/关闭
  game_config.gd          (34)   游戏设置存取（审查开关等）
  json_util.gd            (90)   JSON 剥围栏/提取/键名兼容读取

Scripts/LLM/                             模型层
  llm_client.gd           (31)   客户端抽象基类 + 用途常量
  deepseek_client.gd     (133)   DeepSeek 真实请求（含截断检测）
  mock_client.gd         (193)   离线示例（按话题/用途挑样本）
  llm_config.gd           (37)   Key/模型的本机存取
  llm_service.gd         (175)   服务：配置/客户端生命周期/complete_json
  llm_events.gd           (18)   LLM 域事件契约（信号声明）

Scripts/Lore/                            设定资料层
  lore_repository.gd     (316)   扫描加载 res://settings/ 全部设定
  character_card.gd       (52)   NPC 人物卡（profile/好感度/内联知识）
  player_card.gd          (34)   玩家人物卡
  faction.gd              (53)   组织与成员
  scene_card.gd           (28)   场景卡
  knowledge_journal.gd   (315)   知识日志：信任算术/习得/复活/持久化
  affinity_store.gd       (71)   好感度：档位语句/增减/存取

Scripts/Dialogue/                        对话流程层
  dialogue_engine.gd     (619)   对话引擎（autoload）：全流程指挥
  prompt_builder.gd      (187)   提示词两层拼装
  response_parser.gd     (137)   模型输出校验（含 learned/belief_updates）
  input_reviewer.gd       (61)   输入审查提示词与结论
  material_pack.gd        (99)   材料包数据与调试展示
  material_pack_builder.gd (90)  材料包组装（冻结现场）
  dialogue_events.gd      (43)   对话域事件契约（信号声明）

Scripts/UI/                              界面层
  ui_events.gd             (9)   导航事件契约
  main_ui.gd              (45)   根容器：三屏切换
  main_menu_ui.gd         (27)   开始菜单
  settings_screen_ui.gd  (130)   设置屏
  dialogue_screen_ui.gd  (517)   对话屏（含调试侧栏四页）

tests/
  smoke_test.gd          (182)   分层单元测试
  engine_loop_test.gd    (161)   端到端回路测试
  test_util.gd            (11)   断言辅助
```

---

## 十、想加新功能时从哪里下手

| 想做的事 | 改哪里 |
|---|---|
| 加新的 NPC 可选行动（如"赠礼"） | `material_pack_builder.gd` 的行动清单 + 引擎 `_land_response` 加分支 |
| 让 NPC 之间传话（八卦） | 事件流水里已有全部原话，引擎间复制日志条目即可 |
| 换一家模型供应商 | 在 `Scripts/LLM/` 派生一个 `LLMClient` 子类，`llm_service.gd` 的 `_apply_config` 加一个分支 |
| 给回应加新字段 | 集线器信号加参数 → `ResponseParser.validate` 加解析 → 提示词格式示例加字段 |
| 加新屏幕 | 新建 tscn + ui 脚本，`UiEvents` 加导航标识，`main_ui.gd` 的切换逻辑加一例 |

原则不变：**逻辑层发事件、收命令；UI 只连信号、发命令；总线不认识任何业务**。
```
