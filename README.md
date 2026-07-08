# Termux PATH Bridge

将 Termux 命令无缝桥接到 Android 系统 PATH 的 Magisk 模块。

**前提条件：必须先在手机中安装 Termux 应用，并在 Termux 内使用 pkg install 安装所需程序。本模块仅负责桥接，不包含任何命令。**

安装后，你可以在任何使用系统 PATH 的终端中直接运行 Termux 安装的程序——python、ffmpeg、youtube-dl、vim、git……就像它们原本就是系统命令一样。


## ⚡ 为什么选择它

- 开箱即用：重启手机自动完成扫描，无需任何配置
- Android 10+ 全兼容：动态选择执行方式，普通应用也能调用 Termux 命令
- 多模块友好：自动避开其他 Magisk 模块的命令，防止冲突
- 零冲突设计：自动跳过系统已有命令，不覆盖原生功能
- 实时同步：Termux 安装/卸载程序后，一键扫描即刻更新
- 轻量安全：纯软链接架构，不复制文件，不修改系统分区
- 环境完整继承：保留父 Shell 的别名、函数和自定义变量
- 白名单强制覆盖：指定命令覆盖系统版本


## ✨ 功能全景

| 功能 | 说明 |
|------|------|
| 动态扫描 | 自动发现 Termux 中所有可执行程序 |
| 软链接架构 | 所有命令指向统一主脚本 |
| 完整环境继承 | 保留别名、函数和所有环境变量 |
| 动态执行选择 | Android 10+ 区分 ELF/脚本，智能选择 linker |
| 多模块冲突避免 | 自动跳过其他模块提供的命令 |
| 冲突避免 | 跳过系统/关键/黑名单/其他模块四重保护 |
| 白名单强制覆盖 | 指定命令覆盖系统版本 |
| 自动清理 | 卸载即清理，白名单或其他模块接管后自动让位 |
| 精细化权限修复 | 仅修改必要目录 |
| 用户黑名单 | 自定义屏蔽命令 |
| 音量键交互 | 扫描完成后按音量键选择是否重启 |


## ⚠️ 使用前提

**本模块不包含任何命令。** 你必须先在手机上安装 Termux 应用，并 pkg install 安装所需程序。


## 📦 安装

- 需要 Root + Magisk 20.4+
- 下载 zip → Magisk Manager 本地安装 → 重启


## 🚀 使用

日常：重启后直接使用 Termux 命令

白名单：/data/adb/modules/termux_path/whitelist
黑名单：/data/adb/modules/termux_path/blacklist

手动扫描：Magisk 模块页面「操作」按钮


## 📝 注意事项

- 权限修复仅针对必要目录
- 日志文件 /data/local/tmp/termux_path.log，超过 1MB 自动轮转
- 关键命令即使在白名单中也不会被覆盖
- 仅在使用系统 PATH 的终端中有效


## 🔧 故障排查

提交 Issue 时附上：/data/local/tmp/termux_path.log


## 📄 许可证

MIT License (c) 2026 Klein-ops

GitHub：https://github.com/Klein-ops/termux_path