# ai-novel · AI 互动小说对话原型（阶段一）

依据 `ai_novel_design.md` 实现阶段一前三个流程：**【设定资料】→【材料包】→【回应生成】**，
并提供一个可玩的单场景对话界面。代码按领域分包（Common / LLM / Lore / Dialogue / UI），
UI 层与逻辑层严格分离，底层能力（JSON 工具、LLM 服务、事件日志）封装在 Common 与 LLM 层，
供未来功能（AI 旁白、道具生成……）直接复用。

## 运行

用 Godot 4.x 打开项目运行即可（主场景 `Scenes/main.tscn`）。

启动后进入**开始菜单**，三个屏幕切换：

- **人物对话**：与之前一致的对话体验（NPC/场景选择、对话记录、输入框）；
  顶栏「调试侧栏」按钮展开右侧四页——① 设定资料 ② 材料包 ③ 提示词 ④ 模型回应。
- **设置**：DeepSeek API（Key/模型/测试连接，保存到本机 `user://config.cfg`）与
  **输入审查开关**（立即生效并持久化到 [game] 节；关闭后提交直通对话，不再发起审查请求）。

- **未配置 API Key 时自动使用离线示例模式**：MockClient 输出与真实模型同格式的预制示例。
  模型可选 `deepseek-flash`（默认）或 `deepseek-v4-pro`（旗舰）；官方已停用
  `deepseek-chat` / `deepseek-reasoner`（2026-07-24 下线），残留名自动回落默认。

## 目录结构

```
settings/                     【流程一】设定资料固定目录（作者手动编写放置，运行期只读）
  worldview.txt                 世界观（纯文本）
  factions.json                 组织（id/名称/介绍/成员列表：名称+职位）
  characters/*.json             人物卡（id/姓名/身份/性格/说话方式/心情基准 +
                                knowledge 内联初始知识 [{content, source, trust}] + factions 组织 id 列表）
  scenes/*.json                 场景卡（环境素材/氛围素材/开场情境）
  memory/*.json                 跨对话摘要（可选，npc_id + summary）
Scripts/
  Common/                     通用底层（与游戏逻辑无关，任何功能可复用）
    event_bus.gd                EventBus（autoload "Events"）：主题式发布/订阅中转，
                                不含任何业务信号；cmd/* 命令与 evt/* 事件的唯一通道
    json_util.gd                JsonUtil：围栏剥离 / 括号配平 JSON 提取 / 中英文键名读取
    event_journal.gd            EventJournal：jsonl 追加式事件日志（阶段二事件流水的地基）
  LLM/                        LLM 基础设施（未来 AI 功能的统一接入口）
    llm_service.gd              LLMService（autoload "LLM"）：客户端生命周期 + 配置 +
                                complete / complete_json（自动容错解析 JSON）+ purpose 标注
    llm_client.gd               LLMClient 抽象基类（complete(system, user, purpose)）+ 用途常量
    deepseek_client.gd          DeepSeek 实现（chat/completions，OpenAI 兼容协议）
    mock_client.gd              离线示例实现（未配置 Key 时自动启用，按 purpose 挑样本）
    llm_config.gd               LlmConfig：Key/模型的本机存取
  Lore/                       设定资料域（加载 res://settings/ 的代码；数据目录本身别改这里）
    lore_repository.gd          LoreRepository：【流程一】设定资料扫描与加载（含信念解析与悬空校验）
    knowledge_entry.gd          全局知识条目（数字id/内容/依赖项id）
    knowledge_belief.gd         知识信念：角色对知识的持有状态（来源 + 可信度）
    knowledge_journal.gd        KnowledgeJournal：来源锚定的知识日志——习得/佐证/矛盾
                                信任算术、失效复活、会话摘要、user://journals 持久化
    character_card.gd           人物卡 / scene_card.gd 场景卡
  Dialogue/                   对话域（阶段一核心流程）
    dialogue_engine.gd          编排器（autoload "Dialogue"）：第 0 步审查 + 三个流程 +
                                学习处理（子串锚定/闭集校验） + 对话状态机 + 事件流水落档；经 EventBus 与 UI 中转
    input_reviewer.gd           第 0 步：LLM 输入审查提示词与结论读取（失败开放）
    material_pack_builder.gd    【流程二】冻结现场，组装材料包（知识日志全量 + 记忆 + 行动清单）
    material_pack.gd            MaterialPack：材料包数据模型与调试展示
    prompt_builder.gd           提示词两层拼装：静态规则层（缓存）+ 本轮材料层
    response_parser.gd          【流程三】回应四要素校验 + 自动修复记录
  UI/
    ui_events.gd                UiEvents：UI 导航事件契约（navigate_requested 信号集线器）
    main_ui.gd                  UI 根容器：只做三屏切换（订阅 UiEvents，切换子场景可见性）
    main_menu_ui.gd             开始菜单屏：人物对话/设置入口
    settings_screen_ui.gd       设置屏：DeepSeek API（Key/模型/测试/保存）+ 输入审查开关
    dialogue_screen_ui.gd       对话屏：对话记录/输入/调试侧栏（四页调试面板）
Scenes/main.tscn               入口场景：根容器 + 实例化三个子场景
Scenes/main_menu.tscn          开始菜单屏（配 main_menu_ui.gd，自带信号接线）
Scenes/settings_screen.tscn    设置屏（配 settings_screen_ui.gd）
Scenes/dialogue_screen.tscn    对话屏（配 dialogue_screen_ui.gd）
tests/                         smoke_test.gd 冒烟测试 / engine_loop_test.gd 引擎回路测试 /
                               test_util.gd 断言辅助
```

## 知识系统：来源锚定的知识日志

每个 NPC 一本**只追加日志**（`KnowledgeJournal`）：条目 = 知识表述（content）+
逐字依据（evidence，习得条目）+ 来源（speaker）+ 信任（trust）。人物卡内联初始知识，
对话开始时逐条入日志；运行时习得的条目与会话摘要持久化在 `user://journals/<npc_id>.json`
（卡片每次重建，作者改卡不被运行时遮蔽）。

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

UI 层不创建、不持有任何逻辑层实例。逻辑层服务以 autoload 注册
（`Events` 总线 / `LLM` 模型服务 / `Dialogue` 对话引擎），彼此通过主题通信：

- `cmd/…`（UI → 逻辑）：如 `DialogueEngine.TOPIC_CMD_SUBMIT`（{text}）、
  `TOPIC_CMD_START`、`LLMService.TOPIC_CMD_SET_CONFIG`、`TOPIC_CMD_BUILD_KB`。
- `evt/…`（逻辑 → UI）：如 `TOPIC_STATE_CHANGED`（{state, turn, can_accept,…}）、
  `TOPIC_PACK_BUILT`（MaterialPack）、`TOPIC_RESPONSE`、`TOPIC_KB_BUILT`。
- 信号契约归属各领域类（集线器文件），总线（EventBus）只做集线器注册与分发，不含业务语义；
  UI 打开晚于逻辑层就绪时，经 `cmd_get_*` 命令拉取快照（设定资料 / LLM 配置 / 设置）。
- UI 内部（屏幕之间）的导航走 `UiEvents.navigate_requested`，根容器据此切换子场景。

未来功能（AI 旁白、道具生成）同样只需：订阅自己的 cmd 主题 + 发布 evt 主题 + 调 LLM 服务。

## 为未来功能预留的接入口

- **LLMService（autoload "LLM"）**：任何新 AI 功能一次调用即得结构化结果——
  `await LLM.complete_json(system, user, purpose)` 返回 `{ok, transport, data, notes, raw, error}`；
  purpose 常量在 `LLMClient` 上登记（如未来的 `PURPOSE_NARRATOR`、`PURPOSE_ITEM_FORGE`），
  离线模式据此挑选对应示例样本。
- **JsonUtil**：模型输出的围栏剥离、括号配平提取、中英文键名读取的唯一实现处。
- **EventJournal**：jsonl 事件日志；阶段二世界事件流水（设计 5.6 接入点三）以此为地基。

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
| 输入审查（前置第 0 步，扩展需求） | `InputReviewer` + `DialogueEngine._review_then_generate`（被拒输入不入流水；失败开放） |
| 4.1 第1步 玩家开口/防注入 | `DialogueEngine.submit_player_input`（原样入记录）+ `PromptBuilder._build_system` 防注入条款 |
| 4.1 第3步 冻结现场 | `MaterialPackBuilder.build`（组装后不变） |
| 4.1 第4步 两层提示词 | `PromptBuilder.system_prompt`（按 NPC 缓存）/ `user_prompt` |
| 4.3 素材包五要素 | `MaterialPack` 字段 |
| 4.4 行动清单（仅对话行动） | `MaterialPackBuilder.dialogue_actions()`（统一“类型+目标+说明”格式） |
| 4.5 回应四要素 | `ResponseParser.validate`（JSON 提取由 `LLMService.complete_json`/`JsonUtil` 完成） |
| 4.9 状态机与轮次上限 | `DialogueEngine`（State 枚举 / MAX_TURNS / 近上限提示） |
| 4.10 记录与跨对话记忆 | `DialogueEngine._emit_event` → `EventJournal` 落档 + `settings/memory/*.json` 摘要注入 |
| 5.6 接入点 | 行动格式统一①、落地即裁决②、事件流水③、claim_type 落档④、知识检索入口⑤ |
| 知识习得与信念变化 | `KnowledgeJournal` + `DialogueEngine._process_learning`（子串锚定/闭集校验/确定性信任算术） |
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
# 逻辑层冒烟测试（JsonUtil / 设定加载 / 检索 / 材料包 / 提示词 / 校验 / 审查，无 UI 无网络）
godot --headless -s tests/smoke_test.gd

# 引擎回路端到端测试（经 EventBus 集线器：cmd 信号 → 审查拒绝 → 两轮生成落地 → 结束对话，强制离线）
godot --headless -s tests/engine_loop_test.gd
```
