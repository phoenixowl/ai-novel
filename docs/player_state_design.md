# 玩家状态记录系统设计方案 v2

> 状态：**已实施**（含可拖动/可展开的玩家状态悬浮窗；实现见 Scripts/Player/ 与
> Scripts/UI/player_state_window.gd）。离线测试：smoke（模板/闭集/钳位）、
> dm_loop 场景十（canon_sync 全链路）、ui_smoke_check（悬浮窗交互）。
> 问题：目前玩家在世界里是"透明"的——买了什么、身上有什么、欠了谁的人情、
> 答应过什么事、身体有没有受伤，全都只存在于叙述文字和正典条目里，没有结构化
> 记录。本方案给玩家加一份**随剧情成长的状态档案**。
>
> 设计原则（按优先级）：
> 1. **引擎与世界解耦**：引擎不知道"晶石""货币""物品"这些词——它们是本世界观
>    （欲望之都）的概念。引擎只提供通用机制：**计数器**（数值资源）与**条目集**
>    （清单）。具体有哪些计数器、哪些清单、叫什么名字、上限多少，全部由创作者
>    在**状态模板**里声明。武侠世界可以有"银两/内伤/门派任务"，克苏鲁世界可以
>    有"理智/线索/创伤"，引擎一行不改。
> 2. **模型提案、引擎落地、闭集校验**（与 Toolcall/Gen 同款）：只有 DM 能提案
>    状态变更，引擎按模板校验后落盘；模板之外的键一律丢弃。
> 3. **只写 saves/**：运行期数值存 `user://`；模板是作者数据（settings/），运行期只读。

---

## 0. 先看这里：名词解释

| 名词 | 意思 |
|---|---|
| **状态模板（schema）** | 创作者写的一份声明文件：这个世界观里玩家的状态由哪些**计数器**和**条目集**组成。引擎的全部行为（工具校验、界面渲染、提示词注入）都由它驱动。 |
| **计数器（counter）** | 一个有名字的数值资源，有上下限。例：晶石、银两、理智值、声望。 |
| **条目集（collection）** | 一个有名字的清单，每条是几个字段组成的记录。例：随身物品（名称/数量/备注）、未了之约（内容/是否完成）。 |
| **落地** | 校验通过后真正写入存档文件的动作。 |

---

## 1. 状态模板：创作者声明"玩家有什么状态"

模板文件 `settings/player_state.json`（作者数据，可选——不提供时引擎用内置的
通用默认模板，见 §2 末尾）。以欲望之都为例：

```json
{
  "counters": [
    {"key": "crystal", "label": "晶石", "min": 0, "max": 999, "initial": 0,
     "hint": "把魔力封入晶格的硬通货"}
  ],
  "collections": [
    {"key": "items", "label": "随身物品", "cap": 20, "canon_sync": true, "npc_visible": false,
     "fields": [
       {"key": "name",  "label": "名称", "required": true, "max": 40},
       {"key": "qty",   "label": "数量", "type": "int", "min": 1, "max": 99, "default": 1},
       {"key": "note",  "label": "备注", "max": 60}
     ]},
    {"key": "conditions", "label": "身体状态", "cap": 10, "canon_sync": false, "npc_visible": false,
     "fields": [
       {"key": "name", "label": "状况", "required": true, "max": 40},
       {"key": "note", "label": "说明", "max": 60}
     ]},
    {"key": "bonds", "label": "未了之约", "cap": 20, "canon_sync": false, "npc_visible": false,
     "fields": [
       {"key": "text", "label": "内容", "required": true, "max": 80},
       {"key": "done", "label": "已完成", "type": "bool", "default": false}
     ]},
    {"key": "clues", "label": "线索备注", "cap": 30, "canon_sync": false, "npc_visible": false,
     "fields": [
       {"key": "text",   "label": "内容", "required": true, "max": 80},
       {"key": "source", "label": "来源", "max": 20}
     ]}
  ]
}
```

**每个声明的含义**：

- `key`：引擎与工具调用使用的内部名（英文，稳定不变）；`label`：界面与提示词
  里的显示名（中文随世界观）。
- 计数器：`min/max` 钳制范围、`initial` 开场值（缺省 0）、`hint` 注入提示词的
  一句说明（让 DM 知道这资源在世界里意味着什么）。
- 条目集：`cap` 条数上限（超出丢弃记 notes）；`fields` 声明每条记录的字段
  （`required` 必填、`type` int/bool/string 缺省 string、`max` 字长、`default`）。
- **两个引擎级开关（每个条目集独立）**：
  - `canon_sync`：条目增删时是否自动同步一条正典事实（"来客获得了安神汤"，
    LOCAL 挂玩家，精确去重）——背包类开、备注类关；
  - `npc_visible`：是否注入 NPC 材料层——默认全部 false（玩家的牌面是玩家
    的）；创作者可以声明公开状态（如武侠世界的"悬赏令"、声望）为 true。

**其他世界观的例子**（说明自由度，不是引擎内容）：

- 武侠：计数器 `silver 银两`、`internal_energy 内力`；条目集 `items 药材/暗器`、
  `grudges 恩怨`、`tasks 门派任务`（`npc_visible: true`——师父看得到你接了什么活）。
- 克苏鲁：计数器 `sanity 理智`（min 0 max 99）；条目集 `clues 线索`、
  `wounds 创伤`、`debts 债务`。
- 科幻：计数器 `oxygen 氧气`、`credits 信用点`；条目集 `parts 部件`、
  `contacts 联络人`。

**内置默认模板**（作者没写模板文件时）：一个计数器 `money 货币` + 四个条目集
`items 随身物品 / conditions 状态 / bonds 未了之约 / notes 备注`（字段同上例、
全部 `canon_sync: false, npc_visible: false`）——保证开箱可用，且不含任何
特定世界观的词汇。

---

## 2. 数据结构与生命周期

运行期数值存 `saves/world/player_state.json`（`PlayerStateStore` 唯一写入口），
**结构与模板同构**（模板变了，旧数值按 key 对号入座；模板里删掉的键自然失效）：

```json
{
  "counters": {"crystal": 12},
  "collections": {
    "items":      [{"name": "安神汤", "qty": 1, "note": "百草堂抓的"}],
    "conditions": [{"name": "右手轻微手抖", "note": "过载发作的后遗症"}],
    "bonds":      [{"text": "欠唐枢一袋碎魔晶的余款，明晚取货", "done": false}],
    "clues":      [{"text": "拳手的保单受益人是空的", "source": "崔胜"}]
  }
}
```

- 引擎侧上限即模板声明值（cap/min/max），另有硬顶兜底（计数器 ±999/轮、
  条目集 ≤40），防模板本身写飞。
- **生命周期**：跨探索、跨重启保留（它是"存档"的一部分）。"还原设定"、
  "一键重置事实库"、"清除动态生成内容"**都不动它**；设置屏提供独立的
  "清空玩家状态"（二次确认）。
- 模板损坏（非法 JSON/类型错）→ 记入 load_report 并回落内置默认模板，
  旧数值文件保留不丢。

---

## 3. 写入路径：DM 的 `player.state` 工具（模板驱动）

新工具类 `ToolcallPlayerState extends ToolcallBase`，**仅 DM 可调**，一次调用
携带本回合全部变更（原子提交）。参数的合法键**由模板决定**——这就是"不硬编码"
的落点：工具校验器手里只有模板，模板里没有的东西它一概不认识：

```json
{"tool": "player.state", "args": {
  "counters": {"crystal": -3},
  "add":    [{"collection": "items", "entry": {"name": "安神汤", "qty": 1, "note": "百草堂抓的"}}],
  "remove": [{"collection": "items", "match": {"name": "报纸"}}],
  "update": [{"collection": "bonds", "match": {"text": "答应明晚去唐枢铺子取货"}, "set": {"done": true}}]
}}
```

三类操作（引擎固定，与世界观无关）：

- `counters`：key 必须在模板的计数器声明里（闭集），值为**增量**（正负），
  引擎按 min/max 钳位（钳位发生记 notes，如"晶石不足，余额保持 0"）；
- `add`：collection 必须在模板的条目集声明里（闭集）；entry 字段按模板
  `fields` 校验（未知字段丢弃记 notes、必填缺失丢弃、超长截断、int/bool
  类型检查、cap 滴满拒绝并记 notes）；
- `remove` / `update`：`match` 按**模板声明的字段**做第一条精确匹配
  （匹配不到记 notes——模型记错了名字不静默失败）；`update` 的 `set` 同样
  按模板字段校验（改 `done` 勾销之约就靠它）。

**落地**（`DMController._apply_player_state` → `PlayerStateStore`）：

- `canon_sync: true` 的条目集，add/remove 自动 establish 正典事实（LOCAL、
  作用域挂玩家、精确去重防灌水）——NPC 侧的世界认知与玩家档案同步；
  其余条目集与计数器不进正典（操作数据；DM 觉得叙事上重要可再 `facts.declare`）。
- 每次落地广播 `player_state_changed`（进世界流水留痕，界面实时刷新）。
- 空调用（无任何有效变更）直接丢弃记 notes。
- 防刷：与 facts.declare 共享提示词纪律（只记玩家行动确实造成的变更）；
  引擎钳制兜底。

**提示词注入（模板渲染）**：

- DM 材料层尾部新增"■ 玩家状态（此刻随身与未了之事）"段：逐计数器
  `label：当前值（hint）`、逐条目集 `label：条目列表`。按模板声明渲染，
  模板没有的段落不出现。
- NPC 材料层：只注入 `npc_visible: true` 的条目集（默认一个都没有）。

## 4. 读取路径（谁在什么时候看到什么）

| 消费方 | 看到什么 | 时机 |
|---|---|---|
| DM 材料层 | 全部计数器与条目集（模板渲染） | 每回合 |
| 世界屏状态面板 | 全部（折叠：计数器一行 + 各条目集计数；点开明细） | 实时（player_state_changed 刷新） |
| NPC 材料层 | 仅 `npc_visible: true` 的条目集 | 每轮 |
| 人物编辑页玩家卡 | 全部，可手动增删改校正（二期） | 进页拉取 |

## 5. 硬线与既有约定核对

| 约定 | 本方案 |
|---|---|
| 引擎与世界解耦 | 引擎只认"计数器/条目集/字段"三个抽象概念；一切专名在模板里 |
| 模型输出永不直接改世界 | 工具只提案；落地走 `PlayerStateStore` 唯一入口 |
| 闭集即安全 | 计数器键/条目集键/字段名三级闭集（全部来自模板）；长度/数量/上下限引擎钳制；匹配不到记 notes |
| 材料包冻结 | 状态随 DM 材料包冻结（构建时快照） |
| 一切修改必须落盘 | `saves/world/player_state.json` 唯一写入口 |
| NPC 信念不变量 | NPC 只见 `npc_visible` 条目集（默认没有）；信息传播仍走正典可见性与叙述 |

## 6. 改动清单

**新增**：`Scripts/Player/player_state_schema.gd`（模板加载与校验，含内置
默认模板）、`Scripts/Player/player_state_store.gd`（存取器：计数器增减、
条目集 add/remove/update，全部按 schema 校验）、
`Scripts/Toolcall/toolcall_player_state.gd`、`tests/player_state_test.gd`
（或并入 smoke）。

**修改**：`ToolcallCatalog`（登记）、`DMController`（`_apply_player_state`
落地转发）、`DMPack`/`DMPackBuilder`（携带模板渲染的状态段 + NPC 侧
npc_visible 段）、`DMEvents`（`player_state_changed`）、`world_screen`
（折叠状态面板）、`MockClient`（"买/拿/给"类输入附带 player.state 样本）、
`manual_api_tests.md`（T24 买药闭环等 2–3 条）。
二期：玩家卡校正 UI、结算整理者对账、时钟/日程。

**规模估计**：约 800–1000 行 GDScript（模板层比 v1 多约 200 行，换来的
是世界观自由度）。

## 7. 测试计划

- smoke：模板加载（合法/损坏回落默认）、Store 增删改查与钳制、工具三级
  闭集校验（未知计数器/未知条目集/未知字段丢弃记 notes）、canon_sync 开关、
  DM/NPC 材料层按模板渲染；
- dm_loop 补场景：行动输入触发 mock 附带 player.state → 断言计数器与条目
  落地、正典同步事实存在、`player_state_changed` 落档；
- 真实 API 手动用例（manual_api_tests.md 追加）：T24 买药闭环（行动→申报→
  面板变化→"我喝掉安神汤"被允许且条目消失）；T25 跨世界观冒烟（临时换一份
  武侠模板，验证工具与面板随模板变化）。
