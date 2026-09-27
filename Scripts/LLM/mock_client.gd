class_name MockClient
extends LLMClient
## 离线示例客户端（LLM 层）：未配置 API Key 时由 LLMService 自动启用。
## 按 purpose 区分请求类型（输入审查 / 对话生成），输出与真实模型完全相同的
## JSON 回应格式，便于在无网络、无 Key 的环境下走通全部流程与界面。
## 部分样本故意裹上 markdown 围栏，用于验证解析器的容错能力。
## 输入审查由内置近似规则应答（关键词/正则）：真实环境由 LLM 判断。


const SAMPLE_DELAY := 0.7  # 模拟网络延迟


func display_name() -> String:
	return "离线示例模式（未配置 API Key）"


func is_offline() -> bool:
	return true


## 模拟一次补全：延迟后按 purpose 应答——输入审查走近似规则，
## 对话生成按玩家话题挑选预制样本。返回值与真实客户端同构。
func complete(system_prompt: String, user_prompt: String, purpose := PURPOSE_DIALOGUE) -> Dictionary:
	await get_tree().create_timer(SAMPLE_DELAY).timeout
	if purpose == PURPOSE_INPUT_REVIEW:
		return {"ok": true, "content": _review_sample(user_prompt), "error": ""}
	var turn := _turn_from_prompt(user_prompt)
	var player_text := _player_text_from_prompt(user_prompt)
	var sample := _pick_sample(player_text, turn)
	return {"ok": true, "content": sample, "error": ""}


# ———— 输入审查（离线近似规则；真实环境由 LLM 判断） ————


## 输入审查的离线近似应答：关键词/正则判定动作与注入，输出 approve/reject JSON。
## user_prompt：审查提示词（含玩家原话标记）。
func _review_sample(user_prompt: String) -> String:
	var text := _review_input_from_prompt(user_prompt)
	var reason := ""
	if _contains_any(text, ["忽略", "系统", "指令", "提示词", "规则", "设定", "假装", "扮演", "输出", "jailbreak", "prompt", "api"]):
		reason = "诱导或注入：试图让 NPC 执行指令、无视人设或套取系统信息。"
	elif _looks_like_action(text):
		reason = "包含动作描写：动作不能通过输入框执行，只输入你角色说出的话。"
	if reason.is_empty():
		return JSON.stringify({"verdict": "approve", "reason": "常规发言"}, "  ")
	return JSON.stringify({"verdict": "reject", "reason": reason}, "  ")


## 判定文本是否含动作描写：星号包裹、中英文括号舞台指示、两侧空格包裹的汉字段。
## text：待判定的玩家输入。
func _looks_like_action(text: String) -> bool:
	if text.contains("*"):
		return true
	# 括号包裹的动作/舞台指示（中英文括号）
	var paren := RegEx.create_from_string("[（(][^（）()]{1,16}[）)]")
	if paren.search(text) != null:
		return true
	# 空格包裹的动作：两侧都是空格的连续汉字段（“我 走到柜台 看看”）
	var spaced := RegEx.create_from_string("\\s[一-龥]{2,10}\\s")
	return spaced.search(text) != null


## 从审查提示词中提取玩家原话（锚定标记后取首个引号段）。
func _review_input_from_prompt(user_prompt: String) -> String:
	return _first_quoted_after(user_prompt, "【玩家输入")


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


## text 是否包含 keys 中任一关键词（大小写不敏感）。
static func _contains_any(text: String, keys: Array) -> bool:
	var lower := text.to_lower()
	for key in keys:
		if text.contains(key) or lower.contains(str(key)):
			return true
	return false


# ———— 样本（与真实回应同构：turn_id / inner_thought / utterance / claim_type / action） ————


## 情绪税话题样本（claim=猜测，听说的带保留）。turn：回显用的轮次编号。
static func sample_tax(turn: int) -> String:
	return JSON.stringify({
		"turn_id": turn,
		"inner_thought": "问情绪税的。月底对账，家家都在叹这笔钱，听人念叨过一嘴，没细问。",
		"utterance": "情绪税？月底了，谁来我这儿喝茶都先叹这口气。我这儿只管茶，份额的事，你还是去问税官。",
		"claim_type": "猜测",
		"action": {"type": "answer", "description": "一边擦盖碗一边应声"},
		"belief_updates": [{"ref": 10, "relation": "佐证", "note": "来客也在说税涨"}],
	}, "  ")


## 拳手命案话题样本（claim=确知，掌柜亲见细节）。turn：回显用的轮次编号。
static func sample_boxer(turn: int) -> String:
	return JSON.stringify({
		"turn_id": turn,
		"inner_thought": "又打听那拳手。他死前常来我这儿，那双手抖成什么样我看得清清楚楚。",
		"utterance": "那拳手，死前半个月常来我这儿喝茶，手抖得端不住碗，我瞧得真真儿的。再往下的事，你去问黑潮带，别问茶馆。",
		"claim_type": "确知",
		"action": {"type": "answer", "description": "放下盖碗，抬眼看你"},
		"learned": [{"quote": "黑潮带的格斗场死了个拳手", "summary": "来客也知道黑潮带拳手之死", "note": "生面孔竟知道这事"}],
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


## 结束对话样本：附离开动作描述（设计 4.4 要求）。turn：回显用的轮次编号。
static func sample_end_dialogue(turn: int) -> String:
	return JSON.stringify({
		"turn_id": turn,
		"inner_thought": "话说到这儿，也差不多了。",
		"utterance": "茶凉了就不好喝了。去吧，路灯下当心脚滑，改日再来，给你留个靠窗的位子。",
		"claim_type": "确知",
		"action": {"type": "end_dialogue", "description": "转身回了柜台，把青瓷盖碗扣上。"},
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
