# Termux PATH Bridge

将 Termux 命令无缝桥接到 Android 系统 PATH 的 Magisk 模块。

安装后，你可以在任何终端（adb shell、MT 管理器、Terminal Emulator 等）中直接运行 Termux 安装的程序——python、ffmpeg、youtube-dl、vim、git……就像它们原本就是系统命令一样。


## ⚡ 为什么选择它

- 开箱即用：重启手机自动完成扫描，无需任何配置
- Android 10+ 全兼容：动态选择 linker，普通应用（无 Root）也能调用 Termux 命令
- 零冲突设计：自动跳过系统已有命令，永不覆盖原生功能（除非你主动加入白名单）
- 实时同步：Termux 安装/卸载程序后，一键扫描即刻更新
- 轻量安全：纯软链接架构，不复制文件，不修改系统分区
- 环境完整继承：保留父 Shell 的别名、函数和自定义变量
- 精确命令匹配：使用 / 分隔符，消除子串误判和空格问题
- 白名单强制覆盖：支持指定命令覆盖系统版本（放置到 /system/bin）
- 架构清晰：纯函数 + 数据流水线，稳定可靠


## ✨ 功能全景

| 功能 | 说明 |
|------|------|
| 动态扫描 | 自动发现 Termux 中所有可执行程序 |
| 软链接架构 | 所有命令指向统一主脚本，更新仅需替换一个文件 |
| 完整环境继承 | 保留父 Shell 的别名、函数和所有环境变量 |
| 精确命令匹配 | 缓存使用 /cmd/ 格式，彻底消除子串误判 |
| 动态 linker 选择 | Android 10+ 自动检测 32/64 位并选择正确 linker |
| 冲突避免 | 跳过系统命令、关键命令、用户黑名单三重保护 |
| 白名单强制覆盖 | 支持指定命令覆盖系统版本（放置到 /system/bin） |
| 自动清理 | Termux 卸载程序后，对应 wrapper 自动移除；白名单移除后也自动清理 |
| 精细化权限修复 | 仅修改必要目录，不对 Termux 数据目录过度干预 |
| 用户黑名单 | 自定义屏蔽不希望暴露的命令 |
| POSIX 兼容 | 纯 POSIX sh 语法，所有设备通用 |


## 🏗️ 技术架构

### 整体设计

模块采用「软链接 + 统一主脚本 + 双目录」架构：

/system/bin/               # 白名单命令目录（优先于系统 PATH）
├── wrapper_main.sh         # 主脚本副本
├── awk -> wrapper_main.sh  # 强制覆盖系统的 awk
└── grep -> wrapper_main.sh # 强制覆盖系统的 grep

/system/xbin/               # 普通命令目录（跳过系统命令）
├── wrapper_main.sh         # 统一主脚本
├── python -> wrapper_main.sh
├── ffmpeg -> wrapper_main.sh
└── git -> wrapper_main.sh

当用户执行命令时：
1. 系统按 PATH 顺序查找：/system/bin 优先于 /system/xbin
2. 白名单命令在 /system/bin 中被找到，优先执行
3. 普通命令在 /system/xbin 中被找到（前提是不与系统命令冲突）
4. 软链接指向同目录的 wrapper_main.sh
5. 主脚本解析命令名，设置 Termux 环境，动态选择 linker 执行

### 核心设计原则

整个脚本遵循「纯函数 + 数据流水线」设计：

- 无全局状态变量：所有数据通过函数参数传递，消除隐式依赖
- 通用列表抽象：load_list() 将配置文件转换为统一格式，in_list() 进行精确匹配
- 函数无副作用：扫描和清理函数仅依赖输入参数，输出确定结果
- 主流程清晰：sync_all() 按「加载配置 → 构建缓存 → 扫描创建 → 清理失效」顺序编排

### 工作流程

#### 阶段一：环境初始化

1. 创建 /system/xbin 目录并设置权限（bin 目录按需创建）
2. 精细化修复 Termux 必要目录权限（755/1777）

#### 阶段二：数据准备

1. 通过 load_list 加载白名单和黑名单，返回格式如 /cmd1//cmd2/
2. 调用 build_system_cmd_cache 扫描系统 PATH，返回同格式的命令缓存
3. 确保主脚本 wrapper_main.sh 在 xbin 目录存在，若白名单非空则在 bin 目录也创建副本

#### 阶段三：命令扫描与链接创建

遍历 Termux bin 目录下所有可执行文件，按优先级处理：

1. 白名单命中 → 创建到 /system/bin，跳过后续检查
2. 黑名单命中 → 跳过
3. 系统命令冲突 → 跳过
4. 关键命令黑名单 → 跳过
5. 通过所有检查 → 创建到 /system/xbin

#### 阶段四：失效清理

1. 白名单为空时，直接删除整个 /system/bin 目录
2. 白名单非空时，遍历 /system/bin 清理不在白名单中的 wrapper
3. 遍历 /system/xbin 清理黑名单中的 wrapper 和 Termux 已卸载的命令

### 统一主脚本详解

所有软链接最终都指向 wrapper_main.sh（内部版本 3.0）：

#!/system/bin/sh
# termux_path Wrapper v3.0

CMD=$(basename "$0")
PREFIX="/data/data/com.termux/files/usr"
TARGET="$PREFIX/bin/$CMD"

if [ ! -f "$TARGET" ]; then
    echo "错误: Termux 中未安装命令 '$CMD'" >&2
    exit 127
fi

if [ ! -x "$TARGET" ]; then
    echo "错误: 权限不足，无法执行 '$CMD'" >&2
    exit 126
fi

export HOME="$PREFIX/home"
export TMPDIR="$PREFIX/tmp"
export PREFIX="$PREFIX"
[ -n "$LD_LIBRARY_PATH" ] && export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH" || export LD_LIBRARY_PATH="$PREFIX/lib"
export PATH="$PREFIX/bin:$PATH"

[ ! -d "$PREFIX/tmp" ] && mkdir -p "$PREFIX/tmp" 2>/dev/null

sdk_version=$(getprop ro.build.version.sdk 2>/dev/null)
if [ -z "$sdk_version" ]; then
    sdk_version=0
fi

if [ "$sdk_version" -ge 29 ]; then
    file_output=$(file "$TARGET" 2>/dev/null)
    case "$file_output" in
        *"64-bit"*)
            linker="linker64"
            ;;
        *"32-bit"*)
            linker="linker"
            ;;
        *)
            exec "$TARGET" "$@"
            ;;
    esac
    exec "$linker" "$TARGET" "$@"
else
    exec "$TARGET" "$@"
fi

关键设计点：
- Android 9 及以下：直接 exec 执行
- Android 10+：通过 file 命令检测二进制位数，选择 linker 或 linker64 执行
- 使用 exec 替换当前进程，确保信号传递正确


## 📦 安装与要求

系统要求：
- Android 设备已获取 Root 权限
- 已安装 Magisk（20.4+）
- 已安装 Termux 并在其中使用 pkg 安装过至少一个程序

安装步骤：
1. 下载本模块的 .zip 压缩包
2. 打开 Magisk Manager，进入「模块」页面
3. 点击「从本地安装」选择压缩包
4. 等待刷入完成，根据提示重启手机


## 🚀 使用方法

### 日常使用

重启后模块自动完成扫描，即可在任意终端直接使用 Termux 程序。

### 白名单强制覆盖

如果需要 Termux 版本的命令覆盖系统同名命令（如 awk、grep、sed）：

1. 创建或编辑 /data/adb/modules/termux_path/whitelist
2. 每行写入一个命令名，支持 # 注释
3. 保存后手动执行一次扫描

白名单中的命令将被创建到 /system/bin，优先级高于系统原生命令。

### 黑名单屏蔽

如果不想暴露某些 Termux 命令：

1. 创建或编辑 /data/adb/modules/termux_path/blacklist
2. 每行写入一个命令名
3. 保存后手动执行一次扫描

### 手动触发扫描

安装新命令或修改黑白名单后，通过 Magisk Manager 模块页面的「操作」按钮执行扫描，或在 Root 终端执行：

su
. /data/adb/modules/termux_path/termux_path_common.sh && run_scan


## 📝 注意事项

- 权限修复仅针对必要目录，不影响 Termux 自身
- 日志文件位于 /data/local/tmp/termux_path.log，超过 1MB 自动轮转
- 关键命令（su、mount 等）即使在白名单中也不会被覆盖


## 🔧 故障排查

常见问题：
- command not found：手动扫描或检查 Termux 是否安装
- Permission denied：重启手机或手动执行 restorecon
- 白名单未生效：检查文件路径和内容，确认已触发扫描
- 白名单命令残留：升级后扫描一次即可自动清理

提交 Issue 时请启用调试模式：
1. touch /data/adb/modules/termux_path/debug
2. 手动执行一次扫描
3. 上传以下两个文件：
   - /data/local/tmp/termux_path.log
   - /data/local/tmp/termux_path-debug.log


## 🔨 编译与打包

git clone https://github.com/Klein-ops/termux_path.git
cd termux_path
chmod 755 service.sh action.sh customize.sh uninstall.sh
zip -r termux_path_v2.2.0.zip ./* -x ".git/*" -x "*.md" -x ".gitignore"


## 📄 许可证

MIT License (c) 2026 Klein-ops


## 📮 反馈与贡献

GitHub 仓库：https://github.com/Klein-ops/termux_path
问题报告请按照故障排查章节启用调试模式并上传两份日志。
