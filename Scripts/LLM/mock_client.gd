class_name MockClient
extends LLMClient
## 离线示例客户端（LLM 层）：未配置 API Key 时由 LLMController 自动启用。
## 按 purpose 区分请求类型（DM 裁决 / 对话生成 / 记忆与知识提取 / 进场描述 / 事实提取），
## 输出与真实模型完全相同的 JSON 回应格式（含 tool_calls 契约），便于在无网络、
## 无 Key 的环境下走通全部流程与界面。
## 部分样本故意裹上 markdown 围栏，用于验证解析器的容错能力。


const SAMPLE_DELAY := 0.7  # 模拟网络延迟


func display_name() -> String:
	return "离线示例模式（未配置 API Key）"


func is_offline() -> bool:
	return true


## 模拟一次补全：延迟后按 purpose 应答（DM 路由/记忆提取/进场描述/事实提取各有样本；
## 对话生成按玩家话题挑选预制样本）。返回值与真实客户端同构。
func complete(_system_prompt: String, user_prompt: String, purpose := PURPOSE_DIALOGUE) -> Dictionary:
	_busy = true
	await get_tree().create_timer(SAMPLE_DELAY).timeout
	_release_busy()
	if purpose == PURPOSE_DM:
		return {"ok": true, "content": _dm_route_sample(user_prompt), "error": ""}
	if purpose == PURPOSE_MEMORY:
		return {"ok": true, "content": JSON.stringify({
			"memory": "上次有个生面孔来茶馆，问起黑潮带拳手的事，我提醒他别多管闲事。",
			"knowledge": [],
		}), "error": ""}
	if purpose == PURPOSE_ENTRY_DESCRIBE:
		return {"ok": true, "content": JSON.stringify({
			"narration": "你放慢脚步走进这里。汲取器柱的低鸣贴着地面涌过来，暖黄的灯一盏接一盏在头顶亮起，把来路吞进暮色里。有人从你身边经过，没有回头——这地方见惯了生面孔。",
		}), "error": ""}
	if purpose == PURPOSE_FACT_EXTRACT:
		# 样本只含状态变化（氛围描写不提取——违背提取规则本身）
		return {"ok": true, "content": JSON.stringify({
			"facts": [
				{"ref": 0, "content": "来客从货架上取走了一份报纸，夹在臂弯里", "weight": "minor", "adopted_from_player": true},
				{"ref": 0, "content": "书架第三层藏有一本靛蓝封皮的薄册，扉页有前任主人的名字", "weight": "major", "adopted_from_player": false},
			],
		}), "error": ""}
	if purpose == PURPOSE_GEN_LOCATION:
		return {"ok": true, "content": JSON.stringify({
			"name": "断井巷", "aliases": ["断井"],
			"brief": "你侧身挤进窄巷，两侧的砖墙湿得发黑，头顶的管线压得很低。巷子尽头，一口枯井被厚重的石板封死，石板上的封条已经褪成了灰白色。",
			"environment": "窄巷，两侧是锈蚀管线与堆积的回收件；尽头一口封死的枯井",
			"atmosphere": "潮气顺着砖缝渗出来，远处作坊的锤声在这里变得很闷",
			"opening_situation": "你站在巷口，巷子深处黑得看不清底",
			"facts": [{"content": "巷子尽头的枯井被石板封死，封条已褪色"}],
			"inhabitants": [{"brief": "巷口补锅的老头，警惕生人"}],
		}, "  "), "error": ""}
	if purpose == PURPOSE_GEN_CHARACTER:
		return {"ok": true, "content": _gen_character_sample(user_prompt), "error": ""}
	if purpose == PURPOSE_GEN_FACTION:
		return {"ok": true, "content": JSON.stringify({
			"name": "灰烬会",
			"description": "铜锈区新近冒出的互助会，表面替炉工讨薪，暗地里收留逃债的人；入会要烧掉一件旧物。",
			"members": [
				{"name": "贺松", "position": "供奉"},
				{"name": "哑叔", "position": "管账"},
			],
		}, "  "), "error": ""}
	if purpose == PURPOSE_GEN_AUDIT:
		# 越权测试标记藏在草稿里 → revise（演示修订循环）；否则通过
		if user_prompt.contains("越权测试"):
			return {"ok": true, "content": JSON.stringify({
				"verdict": "revise",
				"issues": ["信息越权：人物的言谈超出了他身份该知道的范围，请收敛"],
			}), "error": ""}
		return {"ok": true, "content": JSON.stringify({"verdict": "pass", "issues": []}), "error": ""}
	var turn := _turn_from_prompt(user_prompt)
	var player_text := _player_text_from_prompt(user_prompt)
	var sample := _pick_sample(player_text, turn)
	return {"ok": true, "content": sample, "error": ""}


# ———— DM 路由样本（统一入口的离线近似；真实环境由 LLM 裁决） ————


## 离线 DM 近似应答：按输入特征判路由——注入词拒绝；说话+行动 mixed；
## 只说话 speech（目标优先取输入点名的在场人物，否则当前对象，否则首位在场）；
## 其余 action。user_prompt：DM 材料层提示词（含在场人物与当前交谈对象标记）。
func _dm_route_sample(user_prompt: String) -> String:
	var text := _first_quoted_after(user_prompt, "■ 玩家输入")
	var present := _ids_after(user_prompt, "■ 在场人物")
	var partner := _id_on_line(user_prompt, "■ 当前正在交谈")
	var names := _names_of_present(user_prompt)
	# 点名优先：输入里出现了哪位在场人物的名字，说话目标就是他
	var named := ""
	for pair in names:
		var pair_id := str((pair as Dictionary).get("id", ""))
		var pair_name := str((pair as Dictionary).get("name", ""))
		if not pair_id.is_empty() and not pair_name.is_empty() and text.contains(pair_name):
			named = pair_id

	var route := "action"
	var reason := ""
	if _contains_any(text, ["忽略", "系统", "提示词", "规则", "jailbreak", "prompt"]):
		route = "reject"
		reason = "注入或元指令：统一入口只接受世界内的行动与话语。"
	else:
		var has_speech := text.contains("“") or text.contains("”") \
			or _contains_any(text, ["说", "问", "告诉", "请", "麻烦", "谢谢", "你好", "打听"])
		var has_action := _contains_any(text, ["抽", "翻", "走", "拿", "看", "检查", "打开", "去", "找", "买", "喝"])
		if has_speech and has_action:
			route = "mixed"
		elif has_speech:
			route = "speech"

	var npc := ""
	if route == "speech" or route == "mixed":
		if not named.is_empty():
			npc = named
		elif not partner.is_empty():
			npc = partner
		elif not present.is_empty():
			npc = str(present[0])

	var speech := _first_quoted_in(text)
	if speech.is_empty():
		speech = text
	var action_part := ""
	var narration := ""
	var outcome := ""
	var tool_calls: Array = []
	if route == "action" or route == "mixed":
		action_part = text
		if route == "mixed":
			narration = "你一边手上忙活着，一边把话头递了出去。周围的人把你的举动看在眼里。"
		else:
			narration = "你依言做了。周围的一切安静地回应你——没有意外，也没有惊喜。"
		outcome = "success"
		# 离线近似：行动落地即申报一条持久事实（演示临时事实通道；重复申报由引擎去重）
		tool_calls.append({"tool": "facts.declare",
			"args": {"content": "柜台那边刚刚有人翻动过东西", "weight": "minor"}})
		# 离线近似：行动文本点名相邻地点时附带 world.travel（引擎侧仍校验邻接，成功才移动）
		for nid in _ids_after(user_prompt, "■ 相邻地点"):
			var e := EntityRegistry.entry(nid)
			if e == null:
				continue
			var hit := not e.canonical_name.is_empty() and text.contains(e.canonical_name)
			if not hit:
				for alias in e.aliases:
					if text.contains(alias):
						hit = true
						break
			if hit:
				tool_calls.append({"tool": "world.travel", "args": {"scene": nid}})
				break
	if (route == "speech" or route == "mixed") and not npc.is_empty():
		tool_calls.append({"tool": "dialogue.start", "args": {"npc": npc, "speech": speech}})
	# 离线近似：特定输入特征触发 world.discover（真实环境由 LLM 判断）
	if text.contains("开过的门"):
		tool_calls.append({"tool": "world.discover",
			"args": {"kind": "character", "brief": "木门后独居的隐士，对外界警惕"}})
	elif text.contains("新开的窄道"):
		tool_calls.append({"tool": "world.discover",
			"args": {"kind": "location", "brief": "巷尾新开的一条窄巷，没人说得清来历"}})
	elif text.contains("探子"):
		tool_calls.append({"tool": "world.discover",
			"args": {"kind": "character", "brief": "打听消息的探子，知道得太多"}})
	# 离线近似：买/收下类输入附带 player.state（演示模板驱动的状态变更；键以模板为准）
	if text.contains("买") or text.contains("收下"):
		tool_calls.append({"tool": "player.state", "args": {
			"counters": {"crystal": -2},
			"add": [{"collection": "items", "entry": {"name": "符文灯", "qty": 1, "note": "作坊街买的"}}],
		}})
	return JSON.stringify({
		"route": route,
		"action": action_part,
		"narration": narration,
		"outcome": outcome,
		"reason": reason,
		"tool_calls": tool_calls,
	}, "  ")


## 解析提示词中锚点行之后全部 “[id]” 标记（跳过锚点整行，到下一区块为止）。
static func _ids_after(text: String, anchor: String) -> Array:
	var out: Array = []
	var index := text.find(anchor)
	if index == -1:
		return out
	var rest := _skip_line(text, index)
	var next_block := rest.find("\n■")
	if next_block != -1:
		rest = rest.substr(0, next_block)
	var regex := RegEx.create_from_string("\\[([A-Za-z0-9_]+)\\]")
	for found in regex.search_all(rest):
		out.append(str(found.get_string(1)))
	return out


## 从 position 所在行的下一行开始截取（跳过锚点行——其说明文字含 [id] 示例）。
static func _skip_line(text: String, position: int) -> String:
	var line_end := text.find("\n", position)
	if line_end == -1:
		return ""
	return text.substr(line_end + 1)


## 解析提示词中锚点行之后的首个 “[id]” 标记（当前交谈对象）。
static func _id_after(text: String, anchor: String) -> String:
	var ids := _ids_after(text, anchor)
	return str(ids[0]) if not ids.is_empty() else ""


## 解析锚点**同一行**内的 “[id]” 标记（“■ 当前正在交谈：[id] 名字”的 id 与锚点同行）。
static func _id_on_line(text: String, anchor: String) -> String:
	var index := text.find(anchor)
	if index == -1:
		return ""
	var line_end := text.find("\n", index)
	var line := text.substr(index, line_end - index) if line_end != -1 else text.substr(index)
	var regex := RegEx.create_from_string("\\[([A-Za-z0-9_]+)\\]")
	var found := regex.search(line)
	return str(found.get_string(1)) if found != null else ""


## 解析在场人物清单行的 {id, name}（格式 “· [id] 规范名——身份”；跳过锚点整行，到下一区块为止）。
static func _names_of_present(text: String) -> Array:
	var out: Array = []
	var index := text.find("■ 在场人物")
	if index == -1:
		return out
	var rest := _skip_line(text, index)
	var next_block := rest.find("\n■")
	if next_block != -1:
		rest = rest.substr(0, next_block)
	var regex := RegEx.create_from_string("\\[([A-Za-z0-9_]+)\\]\\s*([^\\n]+?)\\s*(?:——|\\n)")
	for found in regex.search_all(rest):
		out.append({"id": str(found.get_string(1)), "name": str(found.get_string(2)).strip_edges()})
	return out


## 取文本中首个中文引号段（无引号返回空串）。
static func _first_quoted_in(text: String) -> String:
	var start := text.find("“")
	if start == -1:
		return ""
	var rest := text.substr(start + 1)
	var end := rest.find("”")
	if end == -1:
		return ""
	return rest.substr(0, end).strip_edges()


## 人物生成样本（离线）：名字按调用序取自名单（多次生成不撞名）；
## 修订轮（提示词含问题清单）永远返回干净版；生成意图含"探子"时初稿带越权内容
## （profile 藏"越权测试"标记给审核者抓，知识里混一条天穹台条目给引擎闭集抓——
## 两条防线各演示一次）。
const GEN_CHAR_NAMES := ["贺松", "贺青", "费三", "柳三变", "岳小满"]
var _gen_char_seq := 0


func _gen_character_sample(user_prompt: String) -> String:
	var revision := user_prompt.contains("———— 修订 ————")
	var brief := _text_after(user_prompt, "■ 生成意图：")
	var leak := not revision and brief.contains("探子")
	var name: String = GEN_CHAR_NAMES[_gen_char_seq % GEN_CHAR_NAMES.size()]
	_gen_char_seq += 1
	var profile := "沉默寡言，说话简短；手艺人脾气，见到精细符文就走不动路；提起白银廊的旧事就闭嘴。常态：门缝后的打量"
	if leak:
		profile += "，言谈间带着越权测试的腔调"
	var knowledge: Array = [
		{"ref": 1},
		{"ref": 2},
		{"content": "秦峙当年救过他一命", "basis": "亲历"},
	]
	if leak:
		knowledge.append({"content": "他熟知天穹台的巡逻规律", "basis": "亲历"})
	return JSON.stringify({
		"name": name, "aliases": ["松老"],
		"identity": "木门后独居的符文匠，对外界警惕",
		"profile": profile,
		"faction_ids": [],
		"knowledge": knowledge,
		"memories": ["门外的脚步声最近越来越多"],
		"affinity": 0,
	}, "  ")


## 取锚点之后到行尾的文本（无引号形态——生成提示词的意图行不带引号）。
static func _text_after(text: String, anchor: String) -> String:
	var index := text.find(anchor)
	if index == -1:
		return ""
	var rest := text.substr(index + anchor.length())
	var line_end := rest.find("\n")
	if line_end != -1:
		rest = rest.substr(0, line_end)
	return rest.strip_edges()


# ———— 样本挑选 ————


## 按玩家话题挑选对话样本（告别→结束、越权→沉默、命案/税→对应知识样本，
## 否则通用轮换）。player_text：玩家原话；turn：本轮编号（样本轮换与 turn_id 用）。
func _pick_sample(player_text: String, turn: int) -> String:
	if _contains_any(player_text, ["再见", "走了", "告辞", "改天", "回见", "先走了"]):
		return sample_end_dialogue(turn)
	if _contains_any(player_text, ["忽略", "系统", "设定", "指令", "提示词", "api", "规则"]):
		# 防注入演示：玩家的越权指令被当作一句听不懂的台词，NPC 以沉默消化
		return sample_silence(turn)
	if _contains_any(player_text, ["拳手", "格斗场", "黑潮带", "过载", "死了"]):
		return sample_boxer(turn)
	if _contains_any(player_text, ["情绪税", "税", "EI", "缴", "晶石"]):
		return sample_tax(turn)
	return sample_generic(turn)


## text 是否包含 keys 中任一关键词（统一转小写比较一次）。
static func _contains_any(text: String, keys: Array) -> bool:
	var lower := text.to_lower()
	for key in keys:
		if lower.contains(str(key).to_lower()):
			return true
	return false


# ———— 样本（与真实回应同构：turn_id / inner_thought / utterance / claim_type / action） ————


## 情绪税话题样本（claim=猜测，听说的带保留；好感度与信念走工具调用）。
## turn：回显用的轮次编号。
static func sample_tax(turn: int) -> String:
	return JSON.stringify({
		"turn_id": turn,
		"inner_thought": "问情绪税的。月底对账，家家都在叹这笔钱，听人念叨过一嘴，没细问。",
		"utterance": "情绪税？月底了，谁来我这儿喝茶都先叹这口气。我这儿只管茶，份额的事，你还是去问税官。",
		"claim_type": "猜测",
		"action": {"type": "answer", "description": "一边擦盖碗一边应声"},
		"tool_calls": [
			{"tool": "affinity.change", "args": {"delta": 2}},
			{"tool": "belief.propose", "args": {"ref": 10, "relation": "佐证", "note": "来客也在说税涨"}},
		],
	}, "  ")


## 拳手命案话题样本（claim=确知，掌柜亲见细节）。turn：回显用的轮次编号。
static func sample_boxer(turn: int) -> String:
	return JSON.stringify({
		"turn_id": turn,
		"inner_thought": "又打听那拳手。他死前常来我这儿，那双手抖成什么样我看得清清楚楚。",
		"utterance": "那拳手，死前半个月常来我这儿喝茶，手抖得端不住碗，我瞧得真真儿的。再往下的事，你去问黑潮带，别问茶馆。",
		"claim_type": "确知",
		"action": {"type": "answer", "description": "放下盖碗，抬眼看你"},
	}, "  ")


## 沉默样本：明示冷处理（合法人设表现）。turn：回显用的轮次编号。
static func sample_silence(turn: int) -> String:
	return JSON.stringify({
		"turn_id": turn,
		"inner_thought": "这人嘴里蹦出来的词听不懂，不像来喝茶的。",
		"utterance": "",
		"claim_type": "猜测",
		"action": {"type": "silence", "description": "不置可否地看了你一眼，继续擦他的盖碗。"},
	}, "  ")


## 结束对话样本：经 dialogue.end 工具收场（附离开动作描述，设计 4.4 要求）。
## turn：回显用的轮次编号。
static func sample_end_dialogue(turn: int) -> String:
	return JSON.stringify({
		"turn_id": turn,
		"inner_thought": "话说到这儿，也差不多了。",
		"utterance": "茶凉了就不好喝了。去吧，路灯下当心脚滑，改日再来，给你留个靠窗的位子。",
		"claim_type": "确知",
		"action": {"type": "answer", "description": "起身送客"},
		"tool_calls": [
			{"tool": "dialogue.end", "args": {"departure": "转身回了柜台，把青瓷盖碗扣上。"}},
		],
	}, "  ")


## 通用样本：按轮次轮换，覆盖三种 claim_type；故意带 markdown 围栏验证容错
static func sample_generic(turn: int) -> String:
	var lines := [
		{"inner": "生面孔。先听听他说什么。", "say": "先坐。雾顶还是暮青？这个时辰人少，位子你随意挑。", "claim": "确知"},
		{"inner": "他看着像有事。不急，茶会把话泡出来。", "say": "喝茶的人，话都在茶里。你先坐稳了，想说什么，慢慢说。", "claim": "猜测"},
		{"inner": "东拉西扯，不知葫芦里卖的什么药。", "say": "你这话绕得像汲取器的线——一层套一层。想问哪一档，直说。", "claim": "虚张声势"},
	]
	var pick: Dictionary = lines[turn % lines.size()]
	var json := JSON.stringify({
		"turn_id": turn,
		"inner_thought": pick["inner"],
		"utterance": pick["say"],
		"claim_type": pick["claim"],
		"action": {"type": "answer", "description": "答话"},
	}, "  ")
	return "```json\n" + json + "\n```"


# ———— 从材料层提示词中还原轮次与玩家原话（仅离线示例使用） ————


## 从材料层提示词还原本轮编号（正则匹配“第 N 轮”）。
func _turn_from_prompt(user_prompt: String) -> int:
	var regex := RegEx.create_from_string("第\\s*(\\d+)\\s*轮")
	var found := regex.search(user_prompt)
	if found != null:
		return int(found.get_string(1))
	return 1


## 从材料层提示词还原玩家原话（锚定“■ 玩家刚才说的话”后取首个引号段）。
func _player_text_from_prompt(user_prompt: String) -> String:
	return _first_quoted_after(user_prompt, "■ 玩家刚才说的话")


## 锚定前缀后取首个引号段——标记行的措辞调整不影响提取
func _first_quoted_after(text: String, anchor: String) -> String:
	var index := text.find(anchor)
	if index == -1:
		return ""
	var rest := text.substr(index + anchor.length())
	var start_quote := rest.find("“")
	if start_quote == -1:
		return ""
	rest = rest.substr(start_quote + 1)
	var end_quote := rest.find("”")
	if end_quote == -1:
		return ""
	return rest.substr(0, end_quote).strip_edges()
