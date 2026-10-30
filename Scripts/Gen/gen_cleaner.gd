class_name GenCleaner
extends RefCounted
## 动态生成内容清除器（Gen 层）：一键清除全部 gen_ 实体——人物快照、位置图节点、
## 注册表条目、动态组织文件、作用域指向 gen 实体的正典条目。只动 saves/ 下的
## 运行期数据，作者数据（settings/）不受影响。


## 执行清除。返回被移除的实体数。
static func clear() -> int:
	# 1. 人物快照（saves/characters/gen_*.json）
	var removed := 0
	var dir := DirAccess.open(SnapshotStore.dir())
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir() and file_name.begins_with(EntityRegistry.PREFIX_GEN) \
					and file_name.ends_with(".json"):
				DirAccess.remove_absolute("%s/%s" % [SnapshotStore.dir(), file_name])
				removed += 1
			file_name = dir.get_next()
		dir.list_dir_end()
	# 2. 注册表与位置图
	removed += EntityRegistry.remove_gen_entries()
	LocationStore.remove_gen_locations()
	# 3. 动态组织
	GenFactionStore.erase_all()
	# 4. 正典：作用域指向 gen 实体的条目（存在事实、本地事实、取代链置零由 erase 处理）
	for fact in CanonStore.all_entries().duplicate():
		var touches_gen := false
		for sid in fact.scope:
			if str(sid).begins_with(EntityRegistry.PREFIX_GEN):
				touches_gen = true
				break
		if touches_gen:
			CanonStore.erase(fact.id)
	CanonStore.save()
	return removed
