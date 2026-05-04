# Termux PATH Bridge

将 Termux 命令无缝桥接到 Android 系统 PATH 的 Magisk 模块。

**前提条件：必须先在手机中安装 Termux 应用，并在 Termux 内使用 pkg install 安装所需程序。本模块仅负责桥接，不包含任何命令。**

安装后，你可以在任何使用系统 PATH 的终端中直接运行 Termux 安装的程序——python、ffmpeg、youtube-dl、vim、git……就像它们原本就是系统命令一样。典型场景如 adb shell、Terminal Emulator 等，只要终端遵循系统 PATH 环境变量即可。


## ⚡ 为什么选择它

- 开箱即用：重启手机自动完成扫描，无需任何配置
- Android 10+ 全兼容：动态选择执行方式，普通应用（无 Root）也能调用 Termux 命令
- 多模块友好：自动避开其他 Magisk 模块的命令，防止冲突
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
| 动态执行选择 | Android 10+ 用 dd 读取 ELF 头判断 32/64 位，选择正确 linker |
| 多模块冲突避免 | 自动检测其他 Magisk 模块提供的命令，避免重复和覆盖 |
| 冲突避免 | 跳过系统命令、关键命令、用户黑名单、其他模块命令四重保护 |
| 白名单强制覆盖 | 支持指定命令覆盖系统版本（放置到 /system/bin） |
| 自动清理 | Termux 卸载后自动移除 wrapper；白名单或其他模块接管后自动让位 |
| 精细化权限修复 | 仅修改必要目录，不对 Termux 数据目录过度干预 |
| 用户黑名单 | 自定义屏蔽不希望暴露的命令 |
| 全局错误日志 | 所有系统命令的 stderr 自动记录到日志文件 |
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
1. 终端按系统 PATH 顺序查找：/system/bin 优先于 /system/xbin
2. 白名单命令在 /system/bin 中被找到，优先执行
3. 普通命令在 /system/xbin 中被找到（前提是不与系统命令冲突）
4. 软链接指向同目录的 wrapper_main.sh
5. 主脚本解析命令名，设置 Termux 环境，智能选择执行方式

### 核心设计原则

整个脚本遵循「纯函数 + 数据流水线」设计：

- 无全局状态变量：所有数据通过函数参数传递，消除隐式依赖
- 通用列表抽象：load_list() 将配置文件转换为统一格式，in_list() 进行精确匹配
- 函数无副作用：扫描和清理函数仅依赖输入参数，输出确定结果
- 主流程清晰：sync_all() 按「加载配置 → 构建缓存 → 扫描创建 → 清理失效」顺序编排

### 工作流程

#### 阶段一：环境初始化

1. 创建 /system/xbin 目录并设置权限（bin 目录按需创建）
2. 使用 log_cmd 函数执行所有系统命令，stderr 自动记录到日志
3. 精细化修复 Termux 必要目录权限（755/1777）

#### 阶段二：数据准备

1. 通过 load_list 加载白名单和黑名单，返回格式如 /cmd1//cmd2/
2. 调用 build_system_cmd_cache 扫描系统 PATH，返回同格式的命令缓存
3. 调用 build_foreign_cmd_cache 扫描其他 Magisk 模块的命令，构建外部命令缓存
4. 确保主脚本 wrapper_main.sh 在 xbin 目录存在，若白名单非空则在 bin 目录也创建副本

#### 阶段三：命令扫描与链接创建

遍历 Termux bin 目录下所有可执行文件，按优先级处理：

1. 白名单命中 → 创建到 /system/bin，跳过后续检查
2. 黑名单命中 → 跳过
3. 系统命令冲突 → 跳过
4. 其他模块命令冲突 → 跳过
5. 关键命令黑名单 → 跳过
6. 通过所有检查 → 创建到 /system/xbin

#### 阶段四：失效清理

1. 白名单为空时，直接删除整个 /system/bin 目录
2. 白名单非空时，遍历 /system/bin 清理不在白名单中的 wrapper
3. 遍历 /system/xbin 清理黑名单中的 wrapper、其他模块已接管的命令、以及 Termux 已卸载的命令

### 多模块共存机制详解

build_foreign_cmd_cache 函数负责扫描其他 Magisk 模块的命令：

1. 遍历 /data/adb/modules/* 下的所有模块目录
2. 跳过自身模块（$MODDIR）
3. 跳过已禁用或标记删除的模块（存在 disable 或 remove 文件）
4. 对每个活跃模块，检查其 system 目录下是否存在系统 PATH 中的对应路径
5. 收集所有外部命令，构建缓存

这一机制确保了：
- 不会重复创建已被其他模块提供的命令 wrapper
- 如果其他模块新增了同名命令，本模块的旧 wrapper 会被自动清理
- 多个模块可以和平共处，不会相互覆盖

### 统一主脚本详解

所有软链接最终都指向 wrapper_main.sh（内部版本 4.0），其核心执行逻辑：

#!/system/bin/sh
# termux_path Wrapper v4.0

CMD=$(basename "$0")
PREFIX="/data/data/com.termux/files/usr"
TARGET="$PREFIX/bin/$CMD"

# 验证目标文件存在且可执行
if [ ! -f "$TARGET" ]; then
    echo "错误: Termux 中未安装命令 '$CMD'" >&2
    exit 127
fi

if [ ! -x "$TARGET" ]; then
    echo "错误: 权限不足，无法执行 '$CMD'" >&2
    exit 126
fi

# 设置 Termux 运行时环境
export HOME="$PREFIX/home"
export TMPDIR="$PREFIX/tmp"
export PREFIX="$PREFIX"
[ -n "$LD_LIBRARY_PATH" ] && export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH" || export LD_LIBRARY_PATH="$PREFIX/lib"
export PATH="$PREFIX/bin:$PATH"

# 获取 SDK 版本
sdk_version=$(getprop ro.build.version.sdk 2>/dev/null)
[ -z "$sdk_version" ] && sdk_version=0

# Android 10+ 用 dd 读取 ELF 头判断位数
if [ "$sdk_version" -ge 29 ]; then
    elf_class=$(dd if="$TARGET" bs=1 skip=4 count=1 2>/dev/null | od -A n -t d1 | tr -d ' ')
    case "$elf_class" in
        2) linker="linker64" ;;    # 64 位二进制
        1) linker="linker" ;;      # 32 位二进制
        *)  # 非 ELF 文件（脚本等）
            if [ -x "$PREFIX/bin/bash" ]; then
                bash_elf_class=$(dd if="$PREFIX/bin/bash" bs=1 skip=4 count=1 2>/dev/null | od -A n -t d1 | tr -d ' ')
                case "$bash_elf_class" in
                    2) linker="linker64" ;;
                    1) linker="linker" ;;
                    *) "$TARGET" "$@"; exit $? ;;
                esac
                "$linker" "$PREFIX/bin/bash" "$TARGET" "$@"
                exit $?
            else
                "$TARGET" "$@"
                exit $?
            fi
            ;;
    esac
    "$linker" "$TARGET" "$@"
    exit $?
else
    "$TARGET" "$@"
    exit $?
fi

关键设计点：

1. ELF 检测使用 dd 直接读 ELF 头第 5 个字节
   - 值为 1 → 32 位，值为 2 → 64 位
   - 比 file 命令更可靠，不依赖外部工具

2. 脚本类命令的处理
   - 用 Termux 自带的 bash 执行，确保 shebang 正确解析
   - bash 本身也通过 linker 执行，保证在 Android 10+ 的 SELinux 环境下正常运行

3. 错误日志
   所有系统命令的 stderr 通过 log_cmd 函数自动追加到 /data/local/tmp/termux_path.log，排查问题只需这一份日志


## ⚠️ 使用前提

**本模块不包含任何命令。** 你必须先在手机上安装 Termux 应用，并在 Termux 内使用 pkg install 安装你需要的程序（如 pkg install python），本模块才能将这些命令桥接到系统 PATH。


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

重启后模块自动完成扫描，即可在任意使用系统 PATH 的终端中直接使用 Termux 程序。

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
- 仅在使用系统 PATH 的终端中有效，不保证在所有终端应用中可用


## 🔧 故障排查

常见问题：
- command not found：确认 Termux 中已用 pkg install 安装了对应程序，然后手动执行一次扫描
- Permission denied：重启手机或手动执行 restorecon
- 白名单未生效：检查文件路径和内容，确认已触发扫描
- 与其他模块冲突：本模块会自动避让，无需手动干预

提交 Issue 时请附上：/data/local/tmp/termux_path.log
（所有错误已自动记录在内）


## 🔨 编译与打包

git clone https://github.com/Klein-ops/termux_path.git
cd termux_path
chmod 755 service.sh action.sh customize.sh uninstall.sh
zip -r termux_path_v2.3.1.zip ./* -x ".git/*" -x "*.md" -x ".gitignore"


## 📄 许可证

MIT License (c) 2026 Klein-ops


## 📮 反馈与贡献

- 问题报告：请在 GitHub Issues 中提交，附上日志文件
- 功能建议：欢迎在 Issues 中讨论
- 代码贡献：请 Fork 仓库后提交 Pull Request

GitHub 仓库：https://github.com/Klein-ops/termux_path