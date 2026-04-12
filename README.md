# Termux PATH Bridge

将 Termux 命令无缝桥接到 Android 系统 PATH 的 Magisk 模块。

安装后，你可以在任何终端（adb shell、MT 管理器、Terminal Emulator 等）中直接运行 Termux 安装的程序——python、ffmpeg、youtube-dl、vim、git……就像它们原本就是系统命令一样。


## ⚡ 为什么选择它

- 开箱即用：重启手机自动完成扫描，无需任何配置
- Android 10+ 全兼容：自动注入 SELinux 规则，普通应用（无 Root）也能调用 Termux 命令
- 零冲突设计：自动跳过系统已有命令，永不覆盖原生功能
- 实时同步：Termux 安装/卸载程序后，一键扫描即刻更新
- 轻量安全：纯软链接架构，不复制文件，不修改系统分区


## ✨ 功能全景

| 功能 | 说明 |
|------|------|
| 动态扫描 | 自动发现 Termux 中所有可执行程序 |
| 软链接架构 | 所有命令指向统一主脚本，更新仅需替换一个文件 |
| SELinux 适配 | Android 10+ 自动写入策略规则，解除普通应用执行限制 |
| 冲突避免 | 跳过系统命令、关键命令、用户黑名单三重保护 |
| 自动清理 | Termux 卸载程序后，对应 wrapper 自动移除 |
| 精细化权限修复 | 仅修改必要目录，不对 Termux 数据目录过度干预 |
| 用户黑名单 | 自定义屏蔽不希望暴露的命令 |
| POSIX 兼容 | 纯 POSIX sh 语法，所有设备通用 |


## 🏗️ 技术架构

### 整体设计

模块采用「软链接 + 统一主脚本」架构：

/system/xbin/
├── wrapper_main.sh      # 统一主脚本（所有调用的真正入口）
├── python -> wrapper_main.sh
├── ffmpeg -> wrapper_main.sh
├── git -> wrapper_main.sh
└── ...

当用户执行 python 时：
1. 系统通过 PATH 定位到 /system/xbin/python（软链接）
2. 软链接指向 wrapper_main.sh
3. 主脚本解析被调用的命令名（python），设置 Termux 环境变量
4. 通过 exec 执行 Termux 中的真实二进制 /data/data/com.termux/files/usr/bin/python

这种设计的优势：
- 空间高效：N 个命令仅占用 N 个软链接（每个约几十字节）
- 维护简单：更新主脚本版本，所有命令行为同步升级
- 挂载友好：相对路径软链接，模块可被 Magisk 挂载到任意位置

### 工作流程

模块的核心逻辑封装在公共函数库中，按以下三个阶段顺序执行：

#### 阶段一：环境初始化

初始化顺序：
1. 获取模块根目录 → 确保路径定位准确
2. 加载用户黑名单 → 读取 /data/adb/modules/termux_path/blacklist
3. 获取纯净系统 PATH → 通过 env -i 避免环境污染
4. 构建系统命令缓存 → 遍历 PATH 目录，存入内存供快速查重
5. SELinux 规则注入 → SDK ≥ 29 时写入 sepolicy.rule
6. 精细化权限修复 → 仅对必要路径设置 755/1777

SELinux 规则详情（Android 10+）：
allow * app_data_file file execute_no_trans
allow * privapp_data_file file execute_no_trans

这两条规则允许任意进程执行 Termux 私有数据目录下的文件，是普通应用能够调用 Termux 命令的关键。

权限修复详情：
chmod 755 /data/data/com.termux
chmod 755 /data/data/com.termux/files
chmod -R 755 /data/data/com.termux/files/usr
chmod 1777 /data/data/com.termux/files/usr/tmp

逐层设置而非递归整个应用目录，避免干扰 Termux 自身权限体系。

#### 阶段二：命令扫描与链接创建

遍历 /data/data/com.termux/files/usr/bin/* 下的每个可执行文件，执行四重检查：

检查一：系统命令冲突
通过 case " $SYSTEM_CMDS_CACHE " in *" $cmd "*) 语法检查命令名是否已存在于系统命令缓存中。若存在则跳过，避免覆盖系统原生命令。

检查二：关键命令黑名单
内置黑名单包含：su、mount、umount、reboot、shutdown、magisk、magiskpolicy、resetprop。这些命令即使存在于 Termux 中也不会被链接，以保障系统安全。

检查三：用户黑名单
检查命令是否存在于用户自定义黑名单中。若存在则跳过，给予用户完全的控制权。

检查四：Termux 源有效性
确认 Termux 中的对应文件确实存在且可执行。

通过所有检查后，在模块的 /system/xbin 目录下创建软链接，使用相对路径指向同目录的 wrapper_main.sh。

#### 阶段三：失效清理

遍历模块 xbin 目录下的所有软链接，执行两类清理：

清理一：黑名单清理
如果命令已被加入用户黑名单，删除其 wrapper。

清理二：有效性清理
如果 Termux 中对应的源命令已不存在，删除其 wrapper。

这实现了「加入黑名单即清理」和「卸载即清理」的自动维护机制。

### 统一主脚本详解

所有软链接最终都指向 wrapper_main.sh，其完整代码如下：

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

执行流程逐行解析：

1. CMD=$(basename "$0")
   获取用户调用的命令名，即软链接的名称。例如用户执行 python，则 CMD=python。

2. TARGET="$PREFIX/bin/$CMD"
   拼接 Termux 中对应二进制文件的完整路径：/data/data/com.termux/files/usr/bin/python。

3. 文件存在性与权限检查
   验证目标文件存在且可执行，若失败则返回标准错误码（127=命令未找到，126=权限不足）。

4. 环境变量设置
   - HOME：Termux 用户主目录，部分程序依赖此变量定位配置文件
   - TMPDIR：临时文件目录，使用 Termux 的 tmp 而非系统 /tmp
   - PREFIX：Termux 安装前缀，部分程序需要此变量
   - LD_LIBRARY_PATH：动态链接库搜索路径，确保 Termux 程序能找到其依赖的 .so 文件
   - PATH：将 Termux bin 目录前置，确保脚本内部调用其他命令时优先使用 Termux 版本

5. exec "$TARGET" "$@"
   使用 exec 执行目标程序并传递所有参数。exec 会替换当前 Shell 进程而非创建子进程，确保信号传递正确且避免进程层级冗余。


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

如果你不希望某些 Termux 命令被暴露到系统 PATH，可以通过黑名单文件进行控制。

1. 在模块根目录下创建或编辑 blacklist 文件：
   /data/adb/modules/termux_path/blacklist

2. 每行写入一个需要屏蔽的命令名，例如：
   # 这是注释，会被忽略
   awk
   sed
   grep

3. 保存文件后，触发一次手动扫描，被列入黑名单的命令对应的 wrapper 将被自动清理，且后续扫描不会再创建。

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

1. SELinux 策略说明
   在 Android 10 及以上系统中，本模块会自动生成 sepolicy.rule 文件，允许普通应用执行 Termux 数据目录下的二进制文件。该规则由 Magisk 在启动时加载，无需用户操作。

2. 权限修改说明
   本模块在开机时会执行精细化的权限修复：仅针对 Termux 的必要目录设置权限，不递归修改整个应用数据目录，从而在保障外部调用可用性的同时，最大程度减少对 Termux 自身文件权限的干扰。

3. 日志文件
   所有操作（扫描、创建、清理）都会写入日志文件 /data/local/tmp/termux_path.log。遇到问题时，请优先查看此文件获取详细错误信息。日志格式示例：

   04-11 10:23:45 - ========== 开始同步 ==========
   04-11 10:23:45 - SELinux 规则已写入 (SDK 33)
   04-11 10:23:45 - 系统命令缓存已建立
   04-11 10:23:46 - 创建 wrapper 链接: python
   04-11 10:23:46 - 主脚本已生成/更新到 v2.0
   04-11 10:23:47 - 清理黑名单 wrapper: awk
   04-11 10:23:47 - 清理失效 wrapper: old-command
   04-11 10:23:47 - 同步完成 - 总计:452 新增:3 跳过:55 清理:2
   04-11 10:23:47 - ========== 同步结束 ==========

4. 与系统命令的关系
   本模块不会覆盖任何系统已有命令。如果希望优先使用 Termux 版本的某个命令（例如 Termux 中的 awk 比系统自带的版本更新），可以手动删除对应的软链接，重新创建同名的独立脚本文件，自行控制 PATH 顺序，或在 Shell 配置文件中调整 PATH 环境变量的顺序。


## 🔧 故障排查

### 问题：命令在终端中无法执行，提示 "command not found"

可能原因及解决方法：

1. 命令尚未被扫描
   - 解决方法：手动执行一次扫描

2. Termux 中未安装该命令
   - 检查方法：在 Termux 中执行 pkg list-installed | grep 命令名
   - 解决方法：在 Termux 中使用 pkg install 安装所需包

3. 模块未正确加载
   - 检查方法：在 Magisk Manager 中确认模块状态为「已启用」
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

3. SELinux 规则未生效（Android 10+）
   - 检查方法：查看模块目录下是否存在 sepolicy.rule 文件
   - 解决方法：重启手机以重新加载 Magisk 规则

4. 手动修复
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

1. 该命令与系统命令同名 → 预期行为，模块主动跳过
2. 该命令在关键命令列表中 → 安全设计，防止覆盖关键系统工具
3. 该命令在用户黑名单中 → 检查 blacklist 文件
4. 该命令在 Termux 中不可执行 → 在 Termux 中执行 ls -la 确认权限

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


## 📄 许可证

MIT License

版权所有 (c) 2026 Klein-ops

特此免费授予任何获得本软件及相关文档文件副本的人不受限制地处置本软件的权利，包括但不限于使用、复制、修改、合并、发布、分发、再许可和/或销售本软件副本的权利，以及允许获得本软件的人如此做的权利，但须符合以下条件：

上述版权声明和本许可声明应包含在本软件的所有副本或实质部分中。

本软件按「原样」提供，不作任何明示或默示的保证。

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
