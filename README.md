# Termux PATH Bridge

将 Termux 命令无缝桥接到 Android 系统 PATH 的 Magisk 模块。

安装后可以在任何终端直接运行 Termux 里的程序，python、ffmpeg、youtube-dl、vim、git……像系统命令一样用。


## ⚡ 为什么选择它

- 开箱即用：重启自动扫描，无需配置
- Android 10+ 全兼容：动态选择执行方式，普通应用也能调用 Termux 命令
- 多模块友好：自动避开其他 Magisk 模块的命令，防止冲突
- 零冲突设计：跳过系统已有命令，不覆盖原生功能
- 实时同步：Termux 安装/卸载程序后一键扫描即更新
- 轻量安全：纯软链接架构，不复制文件不修改系统分区
- 环境完整继承：保留父 Shell 的别名、函数和自定义变量
- 精确命令匹配：/分隔符消除子串误判
- 白名单强制覆盖：指定命令覆盖系统版本


## ✨ 功能全景

| 功能 | 说明 |
|------|------|
| 动态扫描 | 自动发现 Termux 中所有可执行程序 |
| 软链接架构 | 所有命令指向统一主脚本 |
| 完整环境继承 | 保留别名、函数和所有环境变量 |
| 精确命令匹配 | /cmd/ 格式消除子串误判 |
| 动态执行选择 | ELF/脚本智能选择执行方式 |
| 多模块冲突避免 | 自动跳过其他模块提供的命令 |
| 冲突避免 | 跳过系统/关键/黑名单命令 |
| 白名单强制覆盖 | 指定命令覆盖系统版本 |
| 自动清理 | 卸载即清理，白名单或其他模块接管后自动让位 |
| 精细化权限修复 | 仅修改必要目录 |
| 用户黑名单 | 自定义屏蔽命令 |
| 全局错误日志 | stderr 全量记录便于排查 |
| POSIX 兼容 | 所有设备通用 |


## 🏗️ 技术架构

### 整体设计

「软链接 + 统一主脚本 + 双目录」架构：

/system/bin/      # 白名单目录（优先于系统 PATH）
/system/xbin/      # 普通命令目录

所有软链接指向同目录的 wrapper_main.sh。

### 多模块共存机制

扫描阶段会遍历其他 Magisk 模块的文件，构建"外部命令缓存"。
对于已在其他模块中出现的命令，本模块不会创建 wrapper；
如果之前创建过、现在被其他模块接管了，也会在清理阶段自动移除。

### 主脚本执行逻辑

- 用 dd 读取 ELF 头判断 32/64 位，不再依赖 file 命令
- Android 10+：ELF → linker/linker64；脚本 → Termux bash
- Android 9-：直接执行

### 错误日志

脚本开头 exec 2>>日志文件，所有 stderr 全量记录，
排查问题只需一份 /data/local/tmp/termux_path.log。


## 📦 安装

- 需要 Root + Magisk 20.4+
- 下载 zip → Magisk Manager 本地安装 → 重启


## 🚀 使用

日常：重启后直接使用 Termux 命令

白名单：/data/adb/modules/termux_path/whitelist
黑名单：/data/adb/modules/termux_path/blacklist

手动扫描：Magisk 模块页面「操作」按钮，或 Root 终端执行
. /data/adb/modules/termux_path/termux_path_common.sh && run_scan


## 🔧 故障排查

提交 Issue 时附上：/data/local/tmp/termux_path.log
（所有错误已自动记录在内）


## 📄 许可证

MIT License (c) 2026 Klein-ops


## 📮 反馈

GitHub：https://github.com/Klein-ops/termux_path