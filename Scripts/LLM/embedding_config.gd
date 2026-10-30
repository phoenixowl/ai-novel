class_name EmbeddingConfig
extends RefCounted
## 语义检索向量档配置（LLM 层）：持久化到 saves/config.cfg 的 [embedding] 节。
## provider 三档（与 FactRetriever/DMController 的回落链对应）：
##   builtin（默认）—— 本地 BM25，零配置；
##   api           —— 向量检索（OpenAI 兼容 /embeddings，第二家供应商；失败自动回落 builtin）；
##   off           —— 只用骨架层信号。


static func config_path() -> String:
	return GamePaths.config_path()

const SECTION := "embedding"

const PROVIDER_BUILTIN := "builtin"
const PROVIDER_API := "api"
const PROVIDER_OFF := "off"

const DEFAULT_BASE_URL := "https://api.siliconflow.cn/v1"
const DEFAULT_MODEL := "BAAI/bge-m3"


var provider := PROVIDER_BUILTIN
var api_key := ""
var model := DEFAULT_MODEL
var base_url := DEFAULT_BASE_URL


## 档位下拉用：显示名 -> provider 键。
const PROVIDER_CHOICES := [
	{"label": "内置 BM25（无需配置）", "key": PROVIDER_BUILTIN},
	{"label": "向量检索（需 API Key）", "key": PROVIDER_API},
	{"label": "关闭（仅骨架信号）", "key": PROVIDER_OFF},
]


## provider 键是否合法。
static func is_valid_provider(key: String) -> bool:
	for c in PROVIDER_CHOICES:
		if str(c["key"]) == key:
			return true
	return false


func load_from_disk() -> void:
	var config := ConfigFile.new()
	if config.load(config_path()) != OK:
		return
	var p := str(config.get_value(SECTION, "provider", PROVIDER_BUILTIN))
	if is_valid_provider(p):
		provider = p
	api_key = str(config.get_value(SECTION, "api_key", ""))
	model = str(config.get_value(SECTION, "model", DEFAULT_MODEL))
	base_url = str(config.get_value(SECTION, "base_url", DEFAULT_BASE_URL))


func save_to_disk() -> void:
	var config := ConfigFile.new()
	config.load(config_path())  # 无文件时忽略，保留其它节
	config.set_value(SECTION, "provider", provider)
	config.set_value(SECTION, "api_key", api_key)
	config.set_value(SECTION, "model", model)
	config.set_value(SECTION, "base_url", base_url)
	config.save(config_path())


## 是否应使用向量档（api 档且 Key 非空）。
func vector_enabled() -> bool:
	return provider == PROVIDER_API and not api_key.strip_edges().is_empty()
