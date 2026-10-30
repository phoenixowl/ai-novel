# 代码阅读指南

> 这是**当前代码**（2026-10 统一入口改造后）的阅读地图。
> `docs/` 下其余文档（architecture.md、narration_architecture.md 等）写于改造前，
> 描述的双入口、输入审查、旁白回合等机制已不存在，只作历史参考。
> 行号会漂移，本文一律用「文件 · 函数名」定位。

---

## 0. 这个项目在干什么（三句话）

1. 玩家在世界屏打一句话，**DM**（一次 LLM 调用）裁决它是行动还是说话：
   行动由 DM 叙述后果，说话转交给在场 NPC 当面回应。
2. 引擎自己的工作只有三件——**备料**（把 NPC/DM 需要的材料冻结成"材料包"拼进提示词）、
   **验货**（用闭集/枚举等确定性规则校验模型输出）、**记账**（把发生了什么写进世界流水、
   人物快照与事实正典）。世界内容的创造全部发生在模型输出 + 引擎校验这一步，
   引擎从不自己编剧情。
3. 一切跨层通信走 EventBus 的**契约信号**（cmd_* 命令下行、evt 事件上行），
   UI 不持有任何逻辑层实例。

---

## 1. 心智模型：五个 autoload + 一条总线

`project.godot` 的 autoload 顺序即启动顺序：

| Autoload | 脚本 | 一句话职责 | 它不做什么 |
|---|---|---|---|
| `Events` | `Scripts/Common/event_bus.gd` | 按"契约脚本"单例化并分发信号的总线 | 不感知任何业务信号 |
| `LLM` | `Scripts/LLM/llm_controller.gd` | 唯一的模型入口：`complete` / `complete_json` | 不理解内容，只搬运 |
| `Characters` | `Scripts/Characters/character_controller.gd` | 人物运行时快照的读写入口（cmd_save/reset/write_back…） | 不参与对话流程 |
| `DM` | `Scripts/DM/dm_controller.gd` | **DM**：统一入口裁决、行动叙述、探索结算 | 不读不写 NPC 信念（硬线①） |
| `Dialogue` | `Scripts/Dialogue/dialogue_controller.gd` | NPC 对话回合状态机（12 轮上限） | 对正典只读（硬线②） |
| `Gen` | `Scripts/Gen/gen_controller.gd` | 动态生成编排：三管线 + 审核修订循环（生成期间闸住玩家输入） | 不写 settings/；提示词/契约/落地在各 agent 类 |

三条读代码时最有用的规则：

- **域之间几乎不直连**。唯一例外：DM 通过 DialogueEvents 的 `cmd_start` / `cmd_submit`
  / `cmd_settle_now` 调度对话，以及双方都订阅 `CharacterEvents.lore_changed`
  （人物被编辑 → 两域各自重载设定资料）。
- **静态 Store 是惰性的**。`CanonStore` / `EntityRegistry` / `LocationStore` / `WorldStream`
  （World 层）是静态类，任何公开 API 首次调用时自动读盘
  （`saves/world/*.json`）并播种作者正典——所以 autoload 初始化顺序不影响正确性。
- **模型输出永不直接改世界**。所有写入都收敛到少数几个引擎函数：
  `CanonStore.establish / supersede`、`Person.learn_entry / learn_ref / corroborate /
  contradict`、`AffinityStore.apply_change`。改世界 = 调这些函数，别绕过。

---

## 2. 通信方式：hub 契约信号（五分钟看懂）

每个域一个契约文件（`xxx_events.gd`），**只声明 signal，零逻辑**：

```gdscript
# Scripts/Dialogue/dialogue_events.gd（节选）
signal cmd_start(npc_id: String, scene_id: String)   # 命令：UI/DM → 引擎
signal response(result: Dictionary)                   # 事件：引擎 → UI
```

使用方式（UI 与引擎两侧对称）：

```gdscript
var ev := EventBus.shared().hub(DialogueEvents) as DialogueEvents
ev.cmd_start.emit("shen_moyan", "teahouse")            # 发命令
ev.response.connect(_on_dialogue_response)             # 收事件
```

命名约定：`cmd_*` = 请求引擎做某事；其余 = 引擎宣布某事已发生。
UI 内部的屏幕切换走 `Scripts/UI/ui_events.gd`（navigate_requested 等三个信号）。

---

## 3. 核心名词（用到时回来查）

| 名词 | 是什么 | 定义处 |
|---|---|---|
| 正典 | 世界客观事实库，只追加、可取代 | `CanonStore`（条目是 `CanonFact`） |
| supersede | 事实被新表述取代：旧条目标记指向新条目，不删除 | `CanonStore.supersede` |
| 信念 | 某 NPC 私有的知识日志；三形态：CARD（作者卡）/ SUBJECTIVE（主观）/ REF（指向正典的引用） | `KnowledgeEntry` |
| 信任算术 | 佐证 +1 档 / 矛盾 −1 档 / 已失效可复活，全确定性 | `KnowledgeEntry.apply_*` |
| 材料包 | 一轮请求的全部输入，组装后**冻结不变** | `DialoguePack`（对话）/ `DMPack`（DM） |
| 世界流水 | 叙述事件 + 对话回声的单一混排数组，DM 上下文 / 屏幕渲染 / 结算提取三处共用 | `DMController.events` |
| 闭集 | 模型只能引用"本轮展示过的编号"，越界即钳制/丢弃 | `DMParser` / `DialogueController._settle_learning` |
| brief | 首次进场的描述，生成一次后冻结，重进零调用 | `LocationStore.set_brief` |
| 快照 | `saves/characters/<id>.json`，persona 区 + journal 区，一切人物修改落这里 | `SnapshotStore` |

---

## 4. 主线：一条输入的完整旅程

以玩家输入 **"白芷若，麻烦你给我瞧瞧这条胳膊"**（对话进行中，点名了别人）为例。
这是全项目最重要的一条路径，把下面 8 步对着源码走一遍，代码就读通了大半。

```
世界屏输入框
   │ DMEvents.cmd_submit_input
   ▼
DMController._on_cmd_submit_input ──门控：WAITING_PLAYER 且对话不忙
   ▼ _resolve_with_dm
组装 DM 材料（DMPackBuilder.build：地点事实+全局提要+提及实体扫描+全量探索流水）
拼两层提示词（DMPromptBuilder.dm_system_prompt / dm_user_prompt）
   │ LLM.complete_json(…, PURPOSE_DM)          ← 全程唯一一次 DM 调用
   ▼
DMParser.validate_dm：route 枚举 / npc 在场闭集钳制 / outcome 回落
   ▼ match route
   ├─ reject  → world_input_rejected：理由广播，原话退回输入框
   ├─ action  → _land_action：流水 += player_action + narration_turn
   ├─ mixed   → 先 _land_action（行动部分），再往下走说话分支
   └─ speech/mixed 的说话部分 → _deliver_speech：
        无对话      → cmd_start（开新对话）→ cmd_submit（送话）
        对象相同    → cmd_submit 直送
        对象不同    → 存 _pending_switch → cmd_settle_now（自动结算旧对话，
                      结束信号到达后续送暂存的话）★本例走这里
   ▼
DialogueController.start_dialogue（同步：状态→WAITING_PLAYER，发 dialogue_started）
   ▼ submit_player_input → _accept_player_text：轮次+1，玩家原话入流水
_generate_response：
   DialoguePackBuilder.build（冻结现场：信念+检索正典+世界上下文+记忆+行动清单）
   PromptBuilder.system_prompt（按 NPC 缓存）+ user_prompt（材料包直渲染）
   │ LLM.complete_json(…, PURPOSE_DIALOGUE)
   ▼
ResponseParser.validate：发言/claim_type/行动/信念提案/好感度，非法字段安全回落
   ▼
_land_response：answer/silence 入流水；end_dialogue → end_dialogue()
   ▼ end_dialogue（结算窗口，期间 UI 输入闸住）
_settle_learning：攒了一路的 belief_updates 逐条过闭集 → 信任算术
_summarize_memory：LLM 提取记忆与知识（PURPOSE_MEMORY）→ 写 Person → save_journal 落盘
   ▼ dialogue_ended 信号
DMController._on_dialogue_ended_signal：清结算窗口 → 续送 _pending_switch
```

对话期间，每条对话事件经 `DialogueEvents.event_appended` 双路广播：
世界屏画气泡（`world_screen._append_bubble`），DM 域打上 `domain="dialogue"`
副本并入世界流水（`_on_dialogue_event`）——所以屏幕、DM 上下文、结算提取看到的
是同一条流。

探索的终点是**结算**（`cmd_settle_exploration`）：整理者 agent 通读整段世界流水
（PURPOSE_FACT_EXTRACT），`DMParser.validate_facts` 过闭集后
`establish` / `supersede` 落进正典——这是事实入库的唯一通道。

---

## 5. 文件地图（★ = 建议第一遍精读）

第一次读按编号顺序：① ② ③ → 主线四件套 → 其余按需。

```
Scripts/
├─ Common/
│     event_bus.gd            ★ 总线：hub() 按契约脚本单例化；resolve() 是取总线的唯一入口
│     json_tool.gd            ★ 围栏剥离/括号配平提取/宽容键名读取（全项目唯一实现处）
│     audit_log.gd              jsonl 追加日志（saves/dialogue_logs/）
│     game_config.gd            DM 风格四旋钮的持久化（[game] 节；KNOB_DEFS 是旋钮定义唯一来源）
│     game_paths.gd             便携目录布局（settings/saves/export 三目录锚定运行根）的唯一登记处
├─ Toolcall/                   工具调用命名空间：模型输出的操作契约——一个工具一个类，
│                               全部继承 ToolcallBase（定义+权限+参数校验内聚）；
│                               DM 与 NPC 的 tool_calls 都经此校验——执行仍落在各域控制器
│     toolcall_base.gd        ★ 工具基类：名片字段 + is_allowed + validate_args（子类覆盖）
│     toolcall_facts_declare.gd      facts.declare（仅 DM：申报持久事实）
│     toolcall_dialogue_start.gd     dialogue.start（仅 DM：递话/开启对话）
│     toolcall_dialogue_end.gd       dialogue.end（DM 强制收场 / NPC 自己收场）
│     toolcall_affinity_change.gd    affinity.change（仅 NPC：好感度）
│     toolcall_belief_propose.gd     belief.propose（仅 NPC：信念提案）
│     toolcall_world_travel.gd       world.travel（仅 DM：切换到相邻场景，邻接闭集在解析期校验）
│     toolcall_catalog.gd      目录与注册处（实例化全部工具；def/is_allowed/defs_for）
│     toolcall_parser.gd         tool_calls → 权限/结构校验（委托工具实例；越权丢弃记 notes；上限 8/回合）
│     toolcall_renderer.gd       按调用方渲染静态层工具清单（权限表即文档来源）
│     toolcall_world_discover.gd world.discover（仅 DM：请求动态生成；设计见 docs/gen_design.md）
│     toolcall_player_state.gd    player.state（仅 DM：玩家状态变更；三级闭集来自 PlayerStateSchema）
├─ Player/                     玩家状态域：模板驱动（引擎不含世界观词汇——计数器/条目集
│                               的键、名称、上限全部由 settings/player_state.json 声明）
│     player_state_schema.gd   ★ 状态模板：加载/校验/内置默认 + 字段规则（validate_entry/match）
│     player_state_store.gd       saves/world/player_state.json 唯一写入口（apply 增删改+钳制+渲染行）
├─ Gen/                        动态生成域（autoload "Gen"）：DM 发现新事物 → 独立 agent 编写，
│                               多轮"构思→审核→修订"，产物只写 saves/（一个 agent 一个类）
│     gen_controller.gd       ★ 编排：门控/冻结上下文/多轮循环/链式后续/清除命令（零业务细节）
│     gen_agent_base.gd          生成 agent 基类：提示词+契约校验+落地的统一形态
│     gen_agent_location.gd      地点 agent（进场描述直接冻结；住户简报链式触发人物生成）
│     gen_agent_character.gd     人物 agent（知识双通道：池内引用 + 主观条目知情集闭集）
│     gen_agent_faction.gd       组织 agent（gen_factions.json 唯一写入口）
│     gen_agent_audit.gd         审核者 agent（三管线共用的第二视角：语义一致性检查单）
│     gen_context.gd             冻结生成上下文（与材料包冻结同一哲学）
│     gen_knowledge_pool.gd      候选知识池（"小市民不知道高层秘密"的物理边界）
│     gen_faction_store.gd       saves/world/gen_factions.json 唯一读写
│     gen_cleaner.gd             一键清除全部 gen 内容（快照/节点/注册/组织/正典作用域）
│     gen_events.gd              契约（started/stage/finished + cmd_clear_generated）
├─ LLM/
│     llm_client.gd             抽象基类 + PURPOSE_* 用途常量 + retire 防悬挂机制
│     llm_controller.gd       ★ autoload "LLM"：complete_json 容错解析 {ok,transport,data,raw}
│     deepseek_client.gd        OpenAI 兼容协议实现（每请求新建短命连接节点 + 看门狗竞速，
│                               防网络异常后 HTTPRequest 永久卡死；含截断检测 truncated 标志）
│     mock_client.gd            离线样本（按 purpose / 玩家话题挑样本）
│     llm_config.gd             Key/模型/max_tokens 存取（[deepseek] 节）
├─ Models/                      纯数据 + JSON 边界，无业务规则
│     entity.gd                 基类：id/名/别名/type/source/status
│     person.gd               ★ 人物：信念列表持有者，learn_*/corroborate/信任档
│     knowledge_entry.gd      ★ 信念条目 + 确定性信任算术
│     canon_fact.gd             事实条目（source/weight/status/scope）
│     location.gd / faction.gd  地点（含运行期 brief/npcs）/ 组织
│     material_pack.gd / narration_pack.gd    两种冻结材料包（含调试页渲染）
├─ Characters/                 人物域（与 autoload "Characters" 对齐）
│     character_controller.gd   autoload "Characters"：保存/恢复/写回/还原 + 启动 relink
│     lore_repository.gd        作者数据统一入口 shared()/reload_shared()：聚合 res://settings/ → 模型
│     snapshot_store.gd         saves/characters/<id>.json 双区读写（class_name 静态存取器）
│     affinity_store.gd         好感度 −100..100 与档位文案
│     character_events.gd       契约（lore_changed 是唯一跨域握手）
├─ DM/                          裁决层：统一入口的裁判（DM）
│     dm_controller.gd       ★ autoload "DM"：状态机五态 + 裁决分派 + 落地 + 结算
│     world_stream.gd          世界流水唯一数据源（叙述+对话回声混排；DM 上下文/渲染/结算共用）
├─ World/                      世界状态层
│     canon_store.gd          ★ 静态正典：establish/supersede/作用域检索/惰性播种
│     entity_registry.gd        静态实体注册表：resolve 别名解析 / scan_mentioned 提及扫描
│     location_store.gd         静态位置图：邻接表 + 当前位置 + brief/npcs
│     dm_pack_builder.gd       DM 材料包组装（§6.2 配方①②③④）
│     dm_prompt_builder.gd      DM 两层提示词 + 进场描述 + 事实提取提示词
│     dm_parser.gd              DM 裁决 / 事实提取 两种契约校验
├─ Dialogue/                    人物域
│     dialogue_controller.gd  ★ autoload "Dialogue"：状态机 + 生成主链 + 延后学习结算
│     dialogue_pack_builder.gd  对话材料包组装
│     prompt_builder.gd         NPC 两层提示词（静态层按 NPC 缓存；好感度经材料包走材料层）
│     response_parser.gd        回应四要素校验（坏字段安全回落并记 notes）
│     memory_summarizer.gd      结算时提取记忆/知识的提示词
│     dialogue_events.gd        契约
├─ Authortool/                   作者工具（架构豁免：作者侧工具，无 autoload/集线器，
│                                草稿+导出在 RefCounted 模型层，页面直接操作草稿）
│     authortool_draft.gd        草稿模型：res://settings + 运行时正典 + 风格旋钮 → 内存编辑对象
│     authortool_exporter.gd     一键导出：export/<时间戳>/ 完整作者数据包
│     authortool_screen.gd       外壳屏：六子页导航 + 重新载入/一键导出
│     authortool_page.gd        子页基类：setup/apply_draft 统一形态（外壳静态分发）
│     authortool_list_page.gd    列表型子页基座（左列表增删 + 右表单，选中即编辑）
│     authortool_world_page.gd / authortool_style_page.gd     世界观主线 / DM 风格四旋钮
│     authortool_player_state_page.gd  玩家状态模板（JSON 编辑 + 结构校验；导出 player_state.json）
│     authortool_factions_page.gd / authortool_characters_page.gd
│     authortool_scenes_page.gd / authortool_facts_page.gd    组织 / 人物 / 场景 / 事实库
│     authortool_widgets.gd      共享控件构建器（暗色样式，各页复用）
└─ UI/                          只发 cmd、只收 evt
      main_ui.gd                五屏切换
      world_screen.gd        ★ 世界屏：门控合成、气泡渲染、调试侧栏四页、玩家状态悬浮窗
      player_state_window.gd    玩家状态悬浮窗（可拖动/可展开；模板渲染；清空入口）
      fact_browser.gd           侧栏①事实库（增删改/保存/重置）
      characters_screen.gd / character_edit_screen.gd   人物卡片墙 / 编辑表单
      settings_screen.gd        API 配置 + 风格旋钮（即选即存）
      main_menu_screen.gd       菜单
Scenes/main.tscn                 唯一入口场景（实例化五个子屏）
tests/                           三个 headless 测试：smoke / engine_loop / dm_loop（见 §7）
```

---

## 6. 数据落盘地图

```
<运行根>/                  导出版=exe 同目录；开发/测试=项目根（OS.has_feature 判定）
  settings/                 初始世界观（玩家放置；"重置"类操作以此为准——引擎只读）
  export/                   AuthorTool 导出的作者数据包（覆盖 settings/ 即换世界观）
  saves/                    全部运行期数据（删掉整个文件夹即回到初始世界观）
  worldview.txt / mainline.txt     世界观全文 / 主线基调（注入静态层）
  canon.json                       作者正典（启动播种，删除后重启会回来——锚语义）
  player.json / characters/*.json  玩家默认卡 / 人物卡（内联初始知识）
  factions.json / scenes/*.json / player_state.json / memory/*.json

user://                    运行期状态（Windows: %APPDATA%\Godot\app_userdata\ai_novel）
  config.cfg                    [deepseek] Key/模型/上限 + [game] 四旋钮
  player.json                   玩家编辑后的称呼/身份/外观
  characters/<id>.json          人物快照：persona 区（name/identity/profile）
                                + journal 区（knowledge/memories/next_seq）
  affinity/<id>.json            好感度
  world/canon.json              正典全量（含 superseded 链）+ next_id
  world/entities.json           注册表投影（六公共字段；brief/npcs 不在此，防双写）
  world/locations.json          位置图节点（brief/npcs）+ 邻接边 + 当前位置
  dialogue_logs/*.jsonl         世界流水审计（narration_* / dialogue_* 两前缀）
```

---

## 7. 测试与调试

```
godot --headless -s tests/smoke_test.gd          # 纯逻辑：JSON 工具/设定加载/信任算术/
                                                  # 材料包/提示词/两个 Parser/Toolcall/Gen 池/正典语义
godot --headless -s tests/engine_loop_test.gd    # 对话域端到端（经总线，强制离线）
godot --headless -s tests/dm_loop_test.gd       # DM 统一入口端到端（三条路由→结算全链路）
godot --headless -s tests/gen_loop_test.gd      # 动态生成端到端（三管线/修订循环/链式/配额/清除）
godot --headless -s tests/ui_smoke_check.gd     # UI 冒烟：世界屏加载/调试抽屉布局/④页渲染
```

两个回路测试的模式：`EventBus.create_shared()` + `LLMController.create_shared()`
强制离线，把 autoload 的对应节点摘掉再挂测试实例，避免重复订阅。
Mock 客户端按 PURPOSE 与玩家话题挑预制样本，所以测试断言是确定性的。

调试侧栏四页与信号的对应：①事实库 = `FactBrowser`（订阅 canon_listed）；
②材料包 / ③提示词 = 两域共用的 `pack_built` / `prompt_built`（最新覆盖）；
④模型回应 = `dm_resolved` / `response`（含解析 notes 与原始输出）。

---

## 8. 常见修改路标

| 想做的事 | 动哪里 |
|---|---|
| 给 DM 加一种路由 | `DMParser.ROUTES` + `_build_dm_system` 路由规则 + `_resolve_with_dm` 的 match + `MockClient._dm_route_sample`（离线样本） |
| 加一种 NPC 行动类型 | `DialoguePackBuilder.dialogue_actions()` + `ResponseParser.ACTION_TYPES` + `DialogueController._land_response` |
| 换/加模型供应商 | 派生 `LLMClient` 子类实现 `complete()`，`LLMController._apply_config` 挂上；purpose 常量在 `llm_client.gd` |
| 新增一种 AI 功能 | 订阅自己的 cmd + 发自己的 evt + `await LLM.complete_json(sys, usr, PURPOSE_你新加的)`——参考事实整理者的接线 |
| 调 NPC 说话风格 | `PromptBuilder._build_system`（静态层）；调 DM 文风 → 设置屏四旋钮（只改措辞不改结构） |
| 给模型加一个操作（工具） | 新建 `ToolcallXxx extends ToolcallBase`（_init 填名片 + validate_args 做参数校验）→ `ToolcallCatalog._build_tools` 登记实例 → 所属控制器补落地（参考 world.travel 的接线） |
| 改知识/信任规则 | `KnowledgeEntry.apply_*`（算术全在这里，改完跑 smoke_test） |

## 9. 改代码前的四条硬规则

1. **材料包冻结**：`build()` 返回后不得再改——模型回应必须对应一个确定的瞬间。
2. **闭集即安全**：模型给的任何"编号引用"（belief_updates.ref、取代 ref、npc 目标）
   必须过闭集校验才能落引擎；越界一律钳制或丢弃，不报错中断。
3. **对话域对正典只读**；DM 域不碰 NPC 信念。跨域写数据只有
   `lore_changed`（广播）和 DM 调度对话（cmd_*）两个口。
4. **一切人物/世界修改必须落盘**：走 `SnapshotStore.write_journal` /
   `CanonStore.save` / `AffinityStore.set_value`，别只改内存对象。
5. **三个全局入口，别绕**：作者数据只取 `LoreRepository.shared()`（重载只在 Characters 写完快照后
   调 `reload_shared()` 再广播 lore_changed）；世界流水只经 `WorldStream`（对话域只读）；
   人物域服务（save_journal 等）经 `CharacterController.shared()` 实例调用。
