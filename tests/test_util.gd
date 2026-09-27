class_name TestUtil
extends RefCounted
## 测试辅助（tests/ 专用）：两个 SceneTree 测试脚本共用的断言输出。


static func check(condition: bool, label: String, failures: int) -> int:
	if condition:
		print("  [通过] " + label)
		return failures
	print("  [失败] " + label)
	return failures + 1
