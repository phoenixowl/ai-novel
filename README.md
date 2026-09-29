# ai-novel · AI 互动小说对话原型（阶段一）

依据 `ai_novel_design.md` 实现阶段一前三个流程：**【设定资料】→【材料包】→【回应生成】**，
并提供一个可玩的单场景对话界面。代码按领域分包（Common / LLM / Lore / Dialogue / UI），
UI 层与逻辑层严格分离，底层能力（JSON 工具、LLM 服务、事件日志）封装在 Common 与 LLM 层，
供未来功能（AI 旁白、道具生成……）直接复用。

## 运行

用 Godot 4.x 打开项目运行即可（主场景 `Scenes/main.tscn`）。

启动后进入**开始菜单**，五个屏幕切换：

- **人物对话**：NPC/场景选择、对话记录、输入框；
  顶栏「调试侧栏」按钮展开右侧四页——① 设定资料 ② 材料包 ③ 完整提示词 ④ 模型回应。
- **人物**：全部人物以卡片墙呈现（姓名/人设预览/好感度/知识/记忆计数），
  点击进入编辑页——可修改人设、好感度、知识日志、记忆（保存即写入运行时快照并刷新）；
  编辑页可直接发起与该人物的对话，或「写回作者卡面」「恢复卡面」；
  总览页「还原设定」一键回到作者卡面。玩家人设也在这一页编辑。
- **设置**：DeepSeek API（Key/模型/测试连接，保存到本机 `user://config.cfg`）与
  **输入审查开关**（立即生效并持久化到 [game] 节；关闭后提交直通对话，不再发起审查请求）。

- **未配置 API Key 时自动使用离线示例模式**：MockClient 输出与真实模型同格式的预制示例。
  模型可选 `deepseek-flash`（默认）或 `deepseek-v4-pro`（旗舰）；官方已停用
  `deepseek-chat` / `deepseek-reasoner`（2026-07-24 下线），残留名自动回落默认。

## 目录结构

```
settings/                     【作者数据】设定资料固定目录（作者手动编写放置，运行期只读）
  worldview.txt                 世界观（纯文本）
  factions.json                 组织（id/名称/介绍/成员列表：名称+职位）
  characters/*.json             人物卡（id/姓名/身份/人设/初始好感度 +
                                knowledge 内联初始知识 [{content, source, trust}] + factions 组织 id 列表）
  scenes/*.json                 场景卡（环境素材/氛围素材/开场情境）
  memory/*.json                 跨对话摘要（可选，npc_id + summary）
Scripts/                        （按域分包；命名规则见 docs/architecture.md 第一节）
  Common/                     跨域基建（与具体业务无关，任何域可复用）
    event_bus.gd                EventBus（autoload "Events"）：主题式发布/订阅中转，
                                不含任何业务信号；cmd/* 命令与 evt/* 事件的唯一通道
    audit_log.gd                AuditLog：jsonl 追加式审计日志（对话流水落档）
    json_tool.gd                JsonTool：围栏剥离 / 括号配平 JSON 提取 / 中英文键名读取
    game_config.gd              GameConfig：游戏设置存取（审查开关）
  LLM/                        「模型」域
    llm_controller.gd           LLMController（autoload "LLM"）：客户端生命周期 + 配置 +
                                complete / complete_json（自动容错解析 JSON）+ purpose 标注
    llm_client.gd               LLMClient 抽象基类（complete(system, user, purpose)）+ 用途常量
    deepseek_client.gd          DeepSeek 实现（chat/completions，OpenAI 兼容协议）
    mock_client.gd              离线示例实现（未配置 Key 时自动启用，按 purpose 挑样本）
    llm_config.gd / llm_events.gd
  Lore/                       「设定」域（人物卡、快照、知识、好感度）
    character_controller.gd     CharacterController（autoload "Characters"）：人物运行时快照的
                                一切修改（总览/详情/保存/恢复卡面/写回/还原）+ 知识日志构建
    character_events.gd         CharacterEvents：人物域信号契约（lore_changed 触发对话域重载）
    lore_repository.gd          LoreRepository：聚合 res://settings/ 全部设定（含快照人设接管）
    snapshot_store.gd           SnapshotStore：user://characters/<id>.json 快照读写
    affinity_store.gd           AffinityStore：好感度档位/增减/存取
    knowledge_journal.gd        KnowledgeJournal：知识日志——信任算术/习得/复活/记忆/快照持久化
    character_card.gd / player_card.gd / faction.gd / scene_card.gd
  Dialogue/                   「对话」域
    dialogue_controller.gd      DialogueController（autoload "Dialogue"）：状态机 + 第 0 步审查 +
                                三个流程 + 学习结算 + 回滚 + 事件流水；经 EventBus 与 UI 中转
    dialogue_events.gd          DialogueEvents：对话域信号契约
    input_reviewer.gd           第 0 步：LLM 输入审查提示词与结论读取（失败开放）
    material_pack_builder.gd    【流程二】冻结现场，组装材料包
    material_pack.gd            MaterialPack：材料包数据模型与调试展示
    prompt_builder.gd           提示词两层拼装：静态规则层（缓存）+ 本轮材料层
    response_parser.gd          【流程三】回应四要素校验 + 自动修复记录
    memory_summarizer.gd        结算时：从对话事件流提取记忆与知识的提示词
  UI/                         「界面」域（只连信号、发命令，不持有逻辑层实例）
    ui_events.gd                UiEvents：导航 + 编辑/对话请求信号
    main_ui.gd                  根容器：五屏切换
    main_menu_screen.gd / characters_screen.gd / character_edit_screen.gd
    dialogue_screen.gd / settings_screen.gd
Scenes/main.tscn               入口场景：根容器 + 实例化五个子场景
tests/                         smoke_test.gd 冒烟测试 / engine_loop_test.gd 引擎回路测试 /
                               test_util.gd 断言辅助
```

## 知识系统：来源锚定的知识日志

每个 NPC 一本**只追加日志**（`KnowledgeJournal`）：条目 = 知识表述（content）+
逐字依据（evidence，习得条目）+ 来源（speaker）+ 信任（trust）。人物卡内联初始知识，
运行时的习得条目与记忆持久化为**人物运行时快照** `user://characters/<npc_id>.json`
（res:// 作者卡面只读；编辑页与对话学习写同一份快照——修改即改快照）。

**运行时零开放生成**——模型输出只有三种形态，引擎全部可确定性校验：

| 形态 | 例子 | 引擎校验 |
|---|---|---|
| 逐字复制 | `learned[].quote`（对方原话节选，作证据） | 子串校验；失败回退整句锚定 |
| 闭集引用 | `belief_updates[].ref`（本轮展示的日志编号） | 集合成员校验 |
| 枚举 | relation（佐证/矛盾）、行动类型 | 枚举校验 |

习得的 `summary`（知识表述）由模型概括，但证据 quote 已锚定真实发言——表述漂移有界、
有日志、可回滚。**信任算术全部确定性**（引擎定事实）：

- 习得默认「怀疑」；独立来源（不同 speaker）佐证 +1 档（上限 绝对可信）
- 矛盾 -1 档（下限 怀疑）；同来源佐证无效
- 「已失效」条目被佐证 → 复活为「怀疑」；玩家言论永不直接产生 绝对可信/已失效

材料包**全量注入**知识日志（NPC 的知识本就全量可及，超过 80 条才压缩佐证链）；
识谎免费：玩家的话与日志矛盾时两条记录同在模型眼前，自然质疑。

## 架构：EventBus 中转

> 详细的代码结构与调用链分析见 [docs/architecture.md](docs/architecture.md)。

UI 层不创建、不持有任何逻辑层实例。各域控制器以 autoload 注册
（`Events` 总线 / `LLM` 模型域 / `Characters` 人物域 / `Dialogue` 对话域），彼此通过主题通信：

- `cmd/…`（UI → 控制器）：如 `DialogueEvents.TOPIC_CMD_SUBMIT`（{text}）、
  `TOPIC_CMD_START`、`LLMController.TOPIC_CMD_SET_CONFIG`、`CharacterEvents.cmd_save_character`。
- `evt/…`（控制器 → UI）：如 `TOPIC_STATE_CHANGED`（{state, turn, can_accept,…}）、
  `TOPIC_PACK_BUILT`（MaterialPack）、`TOPIC_RESPONSE`、`TOPIC_KB_BUILT`。
- 跨域握手只有一个：`CharacterEvents.lore_changed`——人物域改了设定，
  对话域据此重载 LoreRepository 并重发对话域快照。
- 信号契约归属各领域类（集线器文件），总线（EventBus）只做集线器注册与分发，不含业务语义；
  UI 打开晚于逻辑层就绪时，经 `cmd_get_*` 命令拉取快照（设定资料 / LLM 配置 / 设置）。
- UI 内部（屏幕之间）的导航走 `UiEvents.navigate_requested`，根容器据此切换子场景。

未来功能（AI 旁白、道具生成）同样只需：订阅自己的 cmd 主题 + 发布 evt 主题 + 调 LLM 服务。

## 为未来功能预留的接入口

- **LLMController（autoload "LLM"）**：任何新 AI 功能一次调用即得结构化结果——
  `await LLM.complete_json(system, user, purpose)` 返回 `{ok, transport, data, notes, raw, error}`；
  purpose 常量在 `LLMClient` 上登记（如未来的 `PURPOSE_NARRATOR`、`PURPOSE_ITEM_FORGE`），
  离线模式据此挑选对应示例样本。
- **JsonTool**：模型输出的围栏剥离、括号配平提取、中英文键名读取的唯一实现处。
- **AuditLog**：jsonl 事件日志；阶段二世界事件流水（设计 5.6 接入点三）以此为地基。

## 一轮对话在界面上的流转

1. 选 NPC 与场景 → 『开始新对话』（引擎加载人物卡/场景卡/知识清单/跨对话摘要）。
2. 输入一句话回车后，先经**第 0 步：LLM 输入审查**（可在设置中关闭）——括号/星号/空格
   包裹的动作描写、诱导性提问与注入指令会被拒绝：不记录、不计轮次、NPC 听不到，
   原输入退回输入框供修改后重发（审查失败时放行，不阻塞游戏）。离线示例模式由内置近似规则应答。
3. **① 设定资料**页常驻展示全部设定；**② 材料包**页实时展示本轮冻结的材料包
   （场景素材、玩家原话、限量检索的知识、记忆、自身状态、行动清单）。
4. **③ 提示词**页展示发给模型的两层提示词（System 静态规则层 / User 本轮材料层，可复制）。
5. **④ 模型回应**页展示模型原始输出与解析结果（发言、claim_type、行动提案、
   内心想法、自动修复提示）。左侧对话区同步渲染发言；内心想法仅在此调试页可见，
   不入对话记录（设计 4.5）。
6. 行动落地：答话入记录（非“确知”的发言标注“声称”）；沉默记为冷处理；
   结束对话则收尾且不可续聊；轮次上限 12 轮，接近上限时提示模型自然收尾。
7. 每条对话事件按统一格式追加到 `user://dialogue_logs/*.jsonl`（阶段二世界状态的雏形）；
   被拒绝的输入只写审计日志，不进入事件流水。

## 与设计文档的对应

| 设计条目 | 实现位置 |
|---|---|
| 输入审查（前置第 0 步，扩展需求） | `InputReviewer` + `DialogueController._review_then_generate`（被拒输入不入流水；失败开放） |
| 4.1 第1步 玩家开口/防注入 | `DialogueController.submit_player_input`（原样入记录）+ `PromptBuilder._build_system` 防注入条款 |
| 4.1 第3步 冻结现场 | `MaterialPackBuilder.build`（组装后不变） |
| 4.1 第4步 两层提示词 | `PromptBuilder.system_prompt`（按 NPC 缓存）/ `user_prompt` |
| 4.3 素材包五要素 | `MaterialPack` 字段 |
| 4.4 行动清单（仅对话行动） | `MaterialPackBuilder.dialogue_actions()`（统一“类型+目标+说明”格式） |
| 4.5 回应四要素 | `ResponseParser.validate`（JSON 提取由 `LLMController.complete_json`/`JsonTool` 完成） |
| 4.9 状态机与轮次上限 | `DialogueController`（State 枚举 / MAX_TURNS / 近上限提示） |
| 4.10 记录与跨对话记忆 | `DialogueController._emit_event` → `AuditLog` 落档 + `settings/memory/*.json` 摘要注入 |
| 5.6 接入点 | 行动格式统一①、落地即裁决②、事件流水③、claim_type 落档④、知识检索入口⑤ |
| 知识习得与信念变化 | `KnowledgeJournal` + `DialogueController._process_learning`（子串锚定/闭集校验/确定性信任算术） |
| 4.1 兜底 | 解析失败注入保底沉默（`_fallback_response`）——宁可冷淡，不可胡说 |

**暂未实现（属后续里程碑）**：结构检查的反馈重试（M1.1）、事实审核模型三问（M1.3）、
跨对话摘要的自动整理（M1.4，当前摘要由 `settings/memory/` 提供）。
代码中以 TODO 标出了挂接位置。

## 设定文件格式

人物卡 `settings/characters/<id>.json`（中英文键名均可）：

```json
{
  "id": "shen_moyan", "name": "沈墨言",
  "identity": "…", "personality": "…", "speech_style": "…", "mood_baseline": "平和"
}
```

角色卡的内联初始知识（`knowledge` 数组，即该 NPC 知识日志的初始部分）：
来源自由填写（常识 / 目睹 / 听说：来源者……），信任常用：绝对可信 / 比较相信 / 怀疑 / 已失效：

```json
{
  "factions": ["jadelight_guild"],
  "knowledge": [
    {"content": "茶馆后巷的仓库上个月换了新的黄铜锁", "source": "目睹", "trust": "绝对可信"},
    {"content": "城里米价最近涨了两三成", "source": "听说：粮行掌柜", "trust": "比较相信"}
  ]
}
```

组织 `settings/factions.json`（成员可含没有人物卡的配角；角色卡的 factions 列表
引用组织 id，职位以成员表按姓名匹配，所属组织与介绍注入提示词静态层）：

```json
{
  "factions": [
    {"id": "jadelight_guild", "name": "翡翠市商会",
     "description": "……",
     "members": [{"name": "沈墨言", "position": "理事"}]}
  ]
}
```

场景卡 `settings/scenes/<id>.json`：

```json
{
  "id": "teahouse", "name": "顺水居茶馆",
  "environment": "…", "atmosphere": "…", "opening_situation": "…"
}
```

## 测试

```
# 逻辑层冒烟测试（JsonTool / 设定加载 / 检索 / 材料包 / 提示词 / 校验 / 审查，无 UI 无网络）
godot --headless -s tests/smoke_test.gd

# 引擎回路端到端测试（经 EventBus 集线器：cmd 信号 → 审查拒绝 → 两轮生成落地 → 结束对话，强制离线）
godot --headless -s tests/engine_loop_test.gd
```
