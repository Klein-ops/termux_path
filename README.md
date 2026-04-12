# Termux PATH Bridge

将 Termux 环境中的可执行命令桥接到 Android 系统 PATH 的 Magisk 模块。

在任意终端（adb shell、MT 管理器终端、Terminal Emulator 等）中直接调用你在 Termux 里用 pkg 安装的程序（如 python、ffmpeg、youtube-dl、vim 等），无需输入完整路径或先进入 Termux 环境。


## ✨ 核心特性

- 动态扫描与自动发现
  每次启动或手动触发时，自动扫描 Termux 的 bin 目录，无需手动编写命令列表。

- 软链接 + 统一主脚本架构
  所有命令 wrapper 均以软链接形式指向同一个主脚本 wrapper_main.sh。版本更新时只需替换该脚本，所有链接自动生效，极大降低维护成本。

- 智能冲突避免
  自动跳过所有 Android 系统原生已有的命令（如 sh、ls、pm），并内置关键命令黑名单（su、mount、reboot 等），防止覆盖系统核心工具。

- 用户自定义黑名单
  支持通过模块根目录下的 blacklist 文件自定义需要跳过的命令，每行一个命令名。被列入黑名单的命令不会被创建 wrapper，已存在的 wrapper 也会在下次扫描时自动清理。

- 零残留自动清理
  当你在 Termux 中卸载某个程序后，下次扫描会自动清理其对应的失效 wrapper 软链接，保持系统 xbin 目录整洁。

- 开机权限自动修复
  在开机 late_start 阶段自动修复 Termux 私有数据目录的必要权限和 SELinux 上下文，确保命令可被普通用户执行，同时避免过度修改。

- POSIX sh 完全兼容
  脚本严格遵守 POSIX 标准，不依赖 Bash 扩展，在所有 Android 设备的 /system/bin/sh 下均可运行。


## ⚙️ 技术实现与工作流程

本模块的核心工作由位于模块根目录的公共函数库脚本完成，该脚本负责以下三个主要阶段：

### 第一阶段：环境初始化与缓存构建

模块启动时首先执行以下步骤：

1. 动态获取模块根目录
   使用 ${0%/*} 语法获取脚本所在目录，确保在 service.sh 和手动执行两种模式下都能准确定位模块路径。

2. 加载用户黑名单
   读取模块根目录下的 blacklist 文件（如果存在），忽略空行和以 # 开头的注释行，将每行内容作为命令名存入黑名单缓存。

3. 获取纯净系统 PATH
   通过 env -i /system/bin/sh -c 'echo $PATH' 命令获取 Android 系统的原始、未受污染的 PATH 变量。这避免了当前 Shell 环境变量可能已被 Termux 或其他模块修改的问题。

4. 构建系统命令缓存
   遍历系统 PATH 下的所有目录（/system/bin、/vendor/bin、/product/bin、/system/xbin 等），将其中存在的所有文件名一次性读入内存缓存变量 SYSTEM_CMDS_CACHE。这个缓存用于后续阶段的高速冲突检测，避免每次检查都重新扫描文件系统。

5. 精细化修复 Termux 目录权限
   执行 restorecon -R 恢复 SELinux 上下文。随后仅对必要路径设置权限：
   - /data/data/com.termux 自身设为 755
   - /data/data/com.termux/files 设为 755
   - /data/data/com.termux/files/usr 目录递归设为 755
   - 临时目录 /data/data/com.termux/files/usr/tmp 设为 1777（粘滞位）
   这种逐层设置的方式仅影响 Termux 执行程序所需的最小范围，避免递归修改整个应用数据目录可能带来的潜在问题。

### 第二阶段：扫描 Termux 并创建软链接

遍历 Termux 二进制目录 /data/data/com.termux/files/usr/bin 下的每一个文件：

1. 过滤条件
   - 只处理普通文件或软链接
   - 必须具有可执行权限

2. 四重检查
   对每个命令依次执行以下检查，任一条件满足则跳过：

   a) 系统命令冲突检查
      通过 case " $SYSTEM_CMDS_CACHE " in *" $cmd "*) 语法检查命令名是否已存在于系统命令缓存中。若存在则跳过，避免覆盖系统原生命令。

   b) 关键命令检查
      内置关键命令列表包含：su、mount、umount、reboot、shutdown、init、kernel、recovery、magisk、magiskpolicy、resetprop。这些命令即使存在于 Termux 中也不会被链接，以保障系统安全。

   c) 用户黑名单检查
      检查命令是否存在于用户自定义黑名单中。若存在则跳过，给予用户完全的控制权。

   d) Termux 源命令有效性检查
      确认 Termux 中的对应文件确实存在且可执行。

3. 创建软链接
   通过检查后，在模块的 /system/xbin 目录下创建软链接，使用相对路径指向同目录的 wrapper_main.sh。相对路径设计确保了模块可以被安全地挂载到任意位置而不破坏链接有效性。

### 第三阶段：失效清理

本阶段负责自动清理不再需要的 wrapper 软链接：

1. 遍历模块 xbin 目录下的所有条目
2. 跳过主脚本 wrapper_main.sh
3. 判断该条目是否为本模块创建的 wrapper（通过检查软链接目标是否为 wrapper_main.sh）
4. 对每个 wrapper 执行两类清理检查：
   a) 黑名单清理：如果命令已被加入用户黑名单，删除其 wrapper
   b) 有效性清理：如果 Termux 中对应的源命令已不存在，删除其 wrapper

这实现了“加入黑名单即清理”和“卸载即清理”的自动维护机制。

### 统一主脚本的工作原理 (wrapper_main.sh)

所有软链接最终都指向 wrapper_main.sh，该脚本的代码如下：

#!/system/bin/sh
# termux_path Wrapper v2.0

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

exec "$TARGET" "$@"

工作流程说明：
1. 通过 basename "$0" 获取用户调用的命令名（即软链接的名称）
2. 拼接 Termux 中对应二进制文件的完整路径
3. 验证目标文件存在且可执行
4. 设置 Termux 运行时所需的环境变量：
   - HOME：Termux 用户主目录
   - TMPDIR：临时文件目录
   - PREFIX：Termux 安装前缀
   - LD_LIBRARY_PATH：动态链接库搜索路径，确保 Termux 程序能找到其依赖的 .so 文件
   - PATH：将 Termux bin 目录前置，确保脚本内部调用其他命令时优先使用 Termux 版本
5. 使用 exec 执行目标程序并传递所有参数。exec 会替换当前 Shell 进程，避免产生多余的进程层级


## 📦 安装与要求

系统要求：
- Android 设备已获取 Root 权限
- 已安装 Magisk（20.4+）
- 已安装 Termux 并在其中使用 pkg 安装过至少一个程序

安装步骤：
1. 下载本模块的 .zip 压缩包
2. 打开 Magisk Manager 应用
3. 进入「模块」页面
4. 点击「从本地安装」
5. 选择下载的压缩包文件
6. 等待刷入过程自动完成
7. 根据提示重启手机

重启后模块即会生效，无需额外配置。


## 🚀 使用方法

### 日常使用（自动生效）

重启后，模块已在后台完成初始扫描。你可以直接在任意终端 App 中执行 Termux 程序：

# 在 adb shell 中直接使用
adb shell
python --version
ffmpeg -i input.mp4 output.avi
youtube-dl "https://www.youtube.com/watch?v=..."

# 在 MT 管理器终端中使用
vim /sdcard/notes.txt
nano /data/local/tmp/config.conf

# 在 Terminal Emulator 等本地终端中使用
git clone https://github.com/example/repo.git
node script.js

### 用户自定义黑名单

如果你不希望某些 Termux 命令被暴露到系统 PATH（例如可能与系统命令产生混淆，或你仅希望在 Termux 内部使用），可以通过黑名单文件进行控制。

1. 在模块根目录下创建或编辑 blacklist 文件：
   /data/adb/modules/termux_path/blacklist

2. 每行写入一个需要屏蔽的命令名，例如：
   # 这是注释，会被忽略
   awk
   sed
   grep

3. 保存文件后，触发一次手动扫描（见下方说明），被列入黑名单的命令对应的 wrapper 将被自动清理，且后续扫描不会再创建。

### 安装新命令后（手动触发扫描）

当你在 Termux 中通过 pkg install 安装新程序后，需要让模块感知到这一变化。

方法一：通过 Magisk Manager 一键执行

1. 打开 Magisk Manager
2. 进入「模块」页面
3. 找到名为「Termux PATH Bridge」的模块
4. 点击模块底部的「操作」按钮
5. 在弹出的终端窗口中，模块会自动执行扫描并输出详细统计信息
6. 等待输出完成，新命令立即可用

扫描输出示例：

termux_path - 手动扫描
====================
Termux 目录: /data/data/com.termux/files/usr/bin
Wrapper 目录: /data/adb/modules/termux_path/system/xbin
黑名单文件: /data/adb/modules/termux_path/blacklist

正在加载黑名单...
正在扫描系统命令缓存...
正在扫描 Termux 命令...
  创建 wrapper: python
  创建 wrapper: ffmpeg
  跳过系统命令: sh
  跳过关键命令: su
  跳过黑名单命令: awk
...

====================
扫描完成!
====================
总计 Termux 命令: 452
新增 wrapper: 3
跳过 (系统/关键/黑名单): 55
清理失效 wrapper: 2

日志文件: /data/local/tmp/termux_path.log

方法二：在 Root 终端中手动执行

# 获取 Root 权限
su

# 执行模块提供的扫描函数
. /data/adb/modules/termux_path/termux_path_common.sh && run_scan


## 📝 注意事项

1. 权限修改说明
   本模块在开机时会执行精细化的权限修复：仅针对 Termux 的 /data/data/com.termux、/data/data/com.termux/files 以及 /data/data/com.termux/files/usr 目录设置 755 权限，并将临时目录设为 1777。这一过程不递归修改整个应用数据目录，从而在保障外部调用可用性的同时，最大程度减少对 Termux 自身文件权限的干扰。

2. 日志文件
   所有操作（扫描、创建、清理）都会写入日志文件 /data/local/tmp/termux_path.log。遇到问题时，请优先查看此文件获取详细错误信息。日志格式示例：

   04-11 10:23:45 - ========== 开始同步 ==========
   04-11 10:23:45 - 系统命令缓存已建立
   04-11 10:23:46 - 创建 wrapper 链接: python
   04-11 10:23:46 - 主脚本已生成/更新到 v2.0
   04-11 10:23:47 - 清理黑名单 wrapper: awk
   04-11 10:23:47 - 清理失效 wrapper: old-command
   04-11 10:23:47 - 同步完成 - 总计:452 新增:3 跳过:55 清理:2
   04-11 10:23:47 - ========== 同步结束 ==========

3. 普通应用调用说明
   普通应用（无 Root 权限）能否调用 Termux 命令取决于 SELinux 策略和 Termux 文件的权限设置。如果遇到普通应用无法调用的情况，可尝试在开发者选项中为 Termux 开启“可调试”选项，但这并非必需步骤，且效果因设备 ROM 而异。

4. 与系统命令的关系
   本模块不会覆盖任何系统已有命令。如果希望优先使用 Termux 版本的某个命令（例如 Termux 中的 awk 比系统自带的版本更新），可以手动删除对应的软链接，重新创建同名的独立脚本文件，自行控制 PATH 顺序，或在 Shell 配置文件（如 .bashrc）中调整 PATH 环境变量的顺序。


## 🔧 故障排查

### 问题：命令在终端中无法执行，提示 "command not found"

可能原因及解决方法：

1. 命令尚未被扫描
   - 解决方法：手动执行一次扫描（参考上文“使用方法”部分）

2. Termux 中未安装该命令
   - 检查方法：在 Termux 中执行 pkg list-installed | grep 命令名
   - 解决方法：在 Termux 中使用 pkg install 安装所需包

3. 模块未正确加载
   - 检查方法：在 Magisk Manager 中确认模块状态为“已启用”
   - 检查方法：执行 ls -la /system/xbin/ | grep wrapper_main.sh 查看模块文件是否存在
   - 解决方法：尝试禁用后重新启用模块，或重新安装模块后重启

4. 命令被加入黑名单
   - 检查方法：查看模块目录下的 blacklist 文件内容
   - 解决方法：从 blacklist 中移除对应命令行，然后手动执行扫描

### 问题：执行命令时报 "Permission denied"

可能原因及解决方法：

1. Termux 文件权限异常
   - 解决方法：重启手机以触发模块的权限修复流程

2. SELinux 上下文问题
   - 检查方法：执行 ls -lZ /data/data/com.termux/files/usr/bin/命令名
   - 解决方法：重启手机，模块会在开机时执行 restorecon 修复

3. 手动修复
   - 在 Root 终端执行：
     chmod 755 /data/data/com.termux/files/usr/bin/*
     restorecon -R /data/data/com.termux

### 问题：执行命令时报 "错误: Termux 中未安装命令"

可能原因及解决方法：

1. wrapper 软链接存在但其对应的 Termux 源命令已被卸载
   - 解决方法：手动执行一次扫描，模块会自动清理失效链接

2. 软链接目标损坏
   - 检查方法：在 /system/xbin 目录中执行 ls -la 命令名
   - 解决方法：删除损坏的软链接后重新扫描

### 问题：某些 Termux 命令没有被创建 wrapper

可能原因：

1. 该命令与系统命令同名
   - 这是预期行为，模块会主动跳过以防止冲突

2. 该命令在关键命令列表中
   - 这是安全设计，防止覆盖 su、mount 等关键系统工具

3. 该命令在用户黑名单中
   - 检查 blacklist 文件，如确需暴露则移除对应行

4. 该命令在 Termux 中不可执行
   - 检查方法：在 Termux 中执行 ls -la /data/data/com.termux/files/usr/bin/命令名

### 问题：查看详细日志

所有操作日志位于：/data/local/tmp/termux_path.log

查看命令：
cat /data/local/tmp/termux_path.log

或者实时监控：
tail -f /data/local/tmp/termux_path.log


## 🔨 编译与打包

如果你需要自行打包模块：

1. 克隆仓库
   git clone https://github.com/Klein-ops/termux_path.git
   cd termux_path

2. 确保所有脚本具有正确的 shebang 和权限
   chmod 755 service.sh action.sh customize.sh uninstall.sh
   chmod 644 module.prop

3. （可选）创建默认黑名单文件
   touch blacklist

4. 打包为 zip
   zip -r termux_path_vX.X.X.zip ./* -x ".git/*" -x "*.md" -x ".gitignore"

5. 签名（可选）
   使用 Magisk 管理器安装时无需签名


## 📄 许可证

MIT License

版权所有 (c) 2026 Klein-ops

特此免费授予任何获得本软件及相关文档文件（下称“软件”）副本的人不受限制地处置本软件的权利，包括但不限于使用、复制、修改、合并、发布、分发、再许可和/或销售本软件副本的权利，以及允许获得本软件的人如此做的权利，但须符合以下条件：

上述版权声明和本许可声明应包含在本软件的所有副本或实质部分中。

本软件按“原样”提供，不作任何明示或默示的保证，包括但不限于对适销性、特定用途的适用性和非侵权性的保证。在任何情况下，作者或版权持有人均不对因本软件或本软件的使用或其他交易而引起的、与之相关的任何索赔、损害赔偿或其他责任承担责任，无论是合同诉讼、侵权行为还是其他。

完整许可证文本请查看仓库中的 LICENSE 文件。


## 🙏 致谢

- Magisk 团队提供的模块开发框架
- Termux 项目提供的强大终端环境
- 所有测试和反馈问题的用户


## 📮 反馈与贡献

- 问题报告：请在 GitHub Issues 中提交，附上 /data/local/tmp/termux_path.log 日志文件内容
- 功能建议：欢迎在 Issues 中讨论
- 代码贡献：请 Fork 仓库后提交 Pull Request

GitHub 仓库：https://github.com/Klein-ops/termux_path
