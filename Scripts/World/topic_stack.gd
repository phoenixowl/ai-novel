class_name TopicStack
extends RefCounted
## 话题栈（World 层）：最近被提及实体的带衰减队列——DM 材料包骨架层 S4 信号的来源。
## 解决代词/称谓漏配：玩家上回合说"秦峙的账"，这回合说"他继续"，秦峙仍在栈内，
## 其名下事实照常激活。纯内存、确定性，随探索重置；DMController 持有实例。
##
## 寿命语义（无歧义定义）：touch 置剩余寿命为 LIFETIME + 1；每个世界回合落地时 tick -1；
## 剩余 > 0 即存活。效果 = 实体最后一次被提及后，还能连续 LIFETIME 个回合激活其名下事实。


const CAPACITY := 8   # 容量上限：满时新实体顶掉剩余寿命最小的（同分先入者）
const LIFETIME := 3   # 提及后存活的后续回合数

var _remaining := {}  # entity_id(String) -> 剩余寿命(int)


## 提及/续命：寿命重置；容量满时淘汰剩余寿命最小者。
func touch(entity_ids: Array) -> void:
	for raw in entity_ids:
		var id := str(raw)
		if id.is_empty():
			continue
		_remaining[id] = LIFETIME + 1
		_evict_if_full()


## 世界回合落地时衰减：寿命 -1，归零出栈。
func tick() -> void:
	var expired: Array[String] = []
	for id in _remaining:
		_remaining[id] = int(_remaining[id]) - 1
		if int(_remaining[id]) <= 0:
			expired.append(id)
	for id in expired:
		_remaining.erase(id)


## 当前存活的实体 id（顺序不保证；消费方只做集合判断）。
func alive_ids() -> Array[String]:
	var out: Array[String] = []
	for id in _remaining:
		out.append(id)
	return out


func clear() -> void:
	_remaining.clear()


func _evict_if_full() -> void:
	while _remaining.size() > CAPACITY:
		var victim := ""
		var best := -1
		for id in _remaining:
			var r := int(_remaining[id])
			if best == -1 or r < best:
				best = r
				victim = id
		if victim.is_empty():
			return
		_remaining.erase(victim)
