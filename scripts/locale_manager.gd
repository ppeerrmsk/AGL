extends Node

## 本地化管理器（AutoLoad）
##
## 职责：
## 1. 启动时从 user://locale.cfg 读取用户选择的 locale（默认 zh）
## 2. 提供 set_locale_persistent(code)：切换语言 + 持久化 + 重载当前场景刷新
## 3. 提供 trm(key)：多行文本翻译（还原 CSV 里的 \n 转义为真实换行）
##
## UI 入口：主菜单底部的语言切换按钮（中 / EN / 日）调 set_locale_persistent。
## 不使用 F8 等功能键（F8 是 Godot 编辑器"停止运行"快捷键，会与游戏内热键冲突）。
##
## 新增 UI 文本流程：
##   1. 在 i18n/translations.csv 加一行 `KEY,中文,English,日本語`
##   2. 代码里用 tr("KEY") 或 tr("KEY_FMT") % [...]
##   3. 编辑器重新导入（Godot 自动触发）

const SUPPORTED_LOCALES := ["zh", "en", "ja"]
const DEFAULT_LOCALE := "zh"
const CONFIG_PATH := "user://locale.cfg"

func _ready() -> void:
	# 优先级：持久化配置 > 系统 locale（若在支持列表）> DEFAULT_LOCALE
	var saved := _load_saved_locale()
	if saved != "":
		TranslationServer.set_locale(saved)
		return
	var current := TranslationServer.get_locale().split("_")[0]
	if not SUPPORTED_LOCALES.has(current):
		TranslationServer.set_locale(DEFAULT_LOCALE)

## 翻译多行文本：CSV 里写 `\n`，这里还原为真实换行。
## 用于 BBCode 战术提示等含换行的文本。
func trm(key: String) -> String:
	return TranslationServer.translate(key).replace("\\n", "\n")

## 切换 locale 并持久化，随后重载当前场景刷新所有 tr() 文本。
## 由主菜单语言按钮调用。
func set_locale_persistent(code: String) -> void:
	if not SUPPORTED_LOCALES.has(code):
		push_warning("LocaleManager: unsupported locale '%s'" % code)
		return
	if TranslationServer.get_locale().split("_")[0] == code:
		return  # 已经是该 locale，不重载
	TranslationServer.set_locale(code)
	_save_locale(code)
	get_tree().reload_current_scene()

## 返回当前 locale 的基础代码（zh/en/ja）
func get_current_locale() -> String:
	return TranslationServer.get_locale().split("_")[0]

func _load_saved_locale() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return ""
	var code: String = cfg.get_value("locale", "code", "")
	if SUPPORTED_LOCALES.has(code):
		return code
	return ""

func _save_locale(code: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("locale", "code", code)
	cfg.save(CONFIG_PATH)
