#!/system/bin/sh

MODDIR="$(readlink -f "${0%/*}")"
[ -z "$MODDIR" ] && MODDIR="."

exec 2>>"/data/local/tmp/termux_path.log"

# === 常量 ===
TERMUX_BIN_DIR="/data/data/com.termux/files/usr/bin"
MODULE_BIN_DIR="$MODDIR/system/xbin"
MODULE_BIN_DIR_OVERRIDE="$MODDIR/system/bin"
LOG_FILE="/data/local/tmp/termux_path.log"
WRAPPER_VERSION="4.0"
CRITICAL_CMDS="su mount umount reboot shutdown magisk magiskpolicy resetprop"
BLACKLIST_FILE="$MODDIR/blacklist"
WHITELIST_FILE="$MODDIR/whitelist"

WRAPPER_MAIN_NAME="wrapper_main.sh"

# === 初始化环境 ===
init_env() {
    mkdir -p "$MODULE_BIN_DIR"
    chmod 755 "$MODDIR" "$MODDIR/system" "$MODULE_BIN_DIR"
    chown -R root:root "$MODDIR"

    if [ -d "/data/data/com.termux" ]; then
        restorecon -R /data/data/com.termux
        chmod 755 /data/data/com.termux
        chmod 755 /data/data/com.termux/files
        chmod -R 755 /data/data/com.termux/files/usr
        mkdir -p /data/data/com.termux/files/usr/tmp
        chmod 1777 /data/data/com.termux/files/usr/tmp
        log "Termux 权限已精细修复"
    fi
}

# === 日志（带轮转，上限 1MB）===
log() {
    if [ -f "$LOG_FILE" ]; then
        size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt 1048576 ]; then
            rm -f "$LOG_FILE"
        fi
    fi
    echo "$(date '+%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
    chmod 644 "$LOG_FILE"
}

# === 获取系统 PATH ===
get_system_path() {
    sys_path="$(env -i /system/bin/sh -c 'echo $PATH' 2>/dev/null)"
    if [ -n "$sys_path" ]; then
        echo "$sys_path"
    else
        echo "/sbin:/system/sbin:/system/bin:/system/xbin:/vendor/bin:/vendor/xbin"
    fi
}

# === 加载列表文件 ===
load_list() {
    file="$1"
    result=""
    if [ -f "$file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            [ -z "$line" ] && continue
            echo "$line" | grep -q "^#" && continue
            result="${result}/$line/"
        done < "$file"
    fi
    echo "$result"
}

# === 检查是否在列表中 ===
in_list() {
    cmd="$1"
    list="$2"
    case "$list" in
        *"/$cmd/"*) return 0 ;;
        *) return 1 ;;
    esac
}

# === 扫描目录列表，构建命令缓存 ===
scan_dirs_to_cache() {
    desc="$1"
    shift
    result=""
    for dir in "$@"; do
        if [ -d "$dir" ]; then
            for cmd in $(ls "$dir" 2>/dev/null); do
                result="${result}/$cmd/"
            done
        fi
    done
    count=$(echo "$result" | tr '/' ' ' | wc -w)
    log "$desc，共 $count 个条目"
    echo "$result"
}

# === 构建系统命令缓存 ===
build_system_cmd_cache() {
    sys_path="$(get_system_path)"
    dirs="$(echo "$sys_path" | tr ':' ' ')"
    scan_dirs_to_cache "系统命令缓存已建立" $dirs
}

# === 构建其他模块命令缓存 ===
build_foreign_cmd_cache() {
    dirs=""
    sys_path="$(get_system_path)"
    sys_dirs="$(echo "$sys_path" | tr ':' ' ')"
    for mod_dir in /data/adb/modules/*; do
        [ -d "$mod_dir" ] || continue
        [ "$mod_dir" = "$MODDIR" ] && continue
        [ -f "$mod_dir/disable" ] || [ -f "$mod_dir/remove" ] && continue
        [ -d "$mod_dir/system" ] || continue
        for sys_dir in $sys_dirs; do
            target="$mod_dir$sys_dir"
            [ -d "$target" ] && dirs="$dirs $target"
        done
    done
    scan_dirs_to_cache "其他模块命令缓存已建立" $dirs
}

# === 检查关键命令 ===
is_critical_cmd() {
    cmd="$1"
    for c in $CRITICAL_CMDS; do
        [ "$cmd" = "$c" ] && return 0
    done
    return 1
}

# === 检查 Termux 命令有效性 ===
is_termux_cmd_valid() {
    cmd="$1"
    target="$TERMUX_BIN_DIR/$cmd"
    [ -f "$target" ] || [ -L "$target" ] && [ -x "$target" ]
}

# === 生成主脚本内容 ===
generate_main_wrapper() {
    cat << 'EOF'
#!/system/bin/sh
# termux_path Wrapper v4.0

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
[ -z "$sdk_version" ] && sdk_version=0

if [ "$sdk_version" -ge 29 ]; then
    elf_class=$(dd if="$TARGET" bs=1 skip=4 count=1 2>/dev/null | od -A n -t d1 | tr -d ' ')
    case "$elf_class" in
        2) linker="linker64" ;;
        1) linker="linker" ;;
        *)
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
EOF
}

# === 确保主脚本存在 ===
ensure_main_wrapper() {
    whitelist_file="$1"
    for dir in "$MODULE_BIN_DIR" "$MODULE_BIN_DIR_OVERRIDE"; do
        if [ "$dir" = "$MODULE_BIN_DIR_OVERRIDE" ]; then
            [ -f "$whitelist_file" ] && [ -s "$whitelist_file" ] || continue
            mkdir -p "$dir"
        fi
        if [ ! -f "$dir/$WRAPPER_MAIN_NAME" ] || ! grep -q "# termux_path Wrapper v$WRAPPER_VERSION" "$dir/$WRAPPER_MAIN_NAME" 2>/dev/null; then
            generate_main_wrapper > "$dir/$WRAPPER_MAIN_NAME"
            chmod 755 "$dir/$WRAPPER_MAIN_NAME"
            chown root:root "$dir/$WRAPPER_MAIN_NAME"
            chcon u:object_r:system_file:s0 "$dir/$WRAPPER_MAIN_NAME"
            log "$(basename "$dir") 主脚本已更新到 v$WRAPPER_VERSION"
        fi
    done
}

# === 创建 wrapper 软链接 ===
create_wrapper() {
    cmd="$1"
    target_dir="$2"
    target="$target_dir/$cmd"

    if [ -L "$target" ]; then
        link_target="$(readlink "$target")"
        if [ "$link_target" = "$WRAPPER_MAIN_NAME" ] || [ "$link_target" = "./$WRAPPER_MAIN_NAME" ]; then
            return 0
        fi
    fi

    rm -f "$target"
    ln -s "$WRAPPER_MAIN_NAME" "$target"
    log "创建 wrapper 链接: $cmd (目录: $target_dir)"
    return 1
}

# === 扫描并创建 ===
scan_and_create() {
    whitelist="$1"
    blacklist="$2"
    system_cmds="$3"
    foreign_cmds="$4"

    total=0
    created=0
    skipped=0

    for f in "$TERMUX_BIN_DIR"/*; do
        [ -f "$f" ] || [ -L "$f" ] || continue
        [ -x "$f" ] || continue

        cmd="$(basename "$f")"
        total=$((total + 1))

        if in_list "$cmd" "$whitelist"; then
            create_wrapper "$cmd" "$MODULE_BIN_DIR_OVERRIDE"
            ret="$?"
            [ "$ret" -eq 1 ] && created=$((created + 1)) && echo "  强制覆盖(白名单): $cmd -> bin" >&2
            continue
        fi

        if in_list "$cmd" "$blacklist"; then
            skipped=$((skipped + 1))
            echo "  跳过黑名单命令: $cmd" >&2
            continue
        fi

        if in_list "$cmd" "$system_cmds"; then
            skipped=$((skipped + 1))
            echo "  跳过系统命令: $cmd" >&2
            continue
        fi

        if in_list "$cmd" "$foreign_cmds"; then
            skipped=$((skipped + 1))
            echo "  跳过其他模块命令: $cmd" >&2
            continue
        fi

        if is_critical_cmd "$cmd"; then
            skipped=$((skipped + 1))
            echo "  跳过关键命令: $cmd" >&2
            continue
        fi

        create_wrapper "$cmd" "$MODULE_BIN_DIR"
        ret="$?"
        [ "$ret" -eq 1 ] && created=$((created + 1)) && echo "  创建 wrapper: $cmd" >&2
    done

    echo "$total $created $skipped"
}

# === 检查是否是我们的 wrapper ===
is_our_wrapper() {
    file="$1"
    if [ -L "$file" ]; then
        target="$(readlink "$file")"
        [ "$target" = "$WRAPPER_MAIN_NAME" ] || [ "$target" = "./$WRAPPER_MAIN_NAME" ] && return 0
    fi
    return 1
}

# === 清理失效 wrapper ===
cleanup_invalid_wrappers() {
    whitelist="$1"
    blacklist="$2"
    foreign_cmds="$3"
    cleaned=0

    for target_dir in "$MODULE_BIN_DIR_OVERRIDE" "$MODULE_BIN_DIR"; do
        for wrapper in "$target_dir"/*; do
            [ -f "$wrapper" ] || [ -L "$wrapper" ] || continue
            [ "$(basename "$wrapper")" = "$WRAPPER_MAIN_NAME" ] && continue

            is_our_wrapper "$wrapper" || continue
            cmd="$(basename "$wrapper")"

            if [ "$target_dir" = "$MODULE_BIN_DIR_OVERRIDE" ]; then
                if [ ! -s "$WHITELIST_FILE" ] || ! in_list "$cmd" "$whitelist"; then
                    rm -f "$wrapper"
                    log "白名单变更，清理 wrapper: $cmd"
                    echo "  清理白名单移除: $cmd" >&2
                    cleaned=$((cleaned + 1))
                fi
                continue
            fi

            if in_list "$cmd" "$blacklist"; then
                rm -f "$wrapper"
                log "清理黑名单 wrapper: $cmd"
                echo "  清理黑名单命令: $cmd" >&2
                cleaned=$((cleaned + 1))
            elif in_list "$cmd" "$foreign_cmds"; then
                rm -f "$wrapper"
                log "其他模块已接管，清理 wrapper: $cmd"
                echo "  清理其他模块命令: $cmd" >&2
                cleaned=$((cleaned + 1))
            elif ! is_termux_cmd_valid "$cmd"; then
                rm -f "$wrapper"
                log "清理失效 wrapper: $cmd"
                echo "  清理已卸载命令: $cmd" >&2
                cleaned=$((cleaned + 1))
            fi
        done
    done

    if [ ! -s "$WHITELIST_FILE" ] && [ -d "$MODULE_BIN_DIR_OVERRIDE" ]; then
        rm -rf "$MODULE_BIN_DIR_OVERRIDE"
        log "白名单已清空，删除 bin 目录"
    fi

    echo "$cleaned"
}

# === 主同步流程 ===
sync_all() {
    log "========== 开始同步 =========="

    echo "正在加载白名单..." >&2
    whitelist="$(load_list "$WHITELIST_FILE")"
    echo "正在加载黑名单..." >&2
    blacklist="$(load_list "$BLACKLIST_FILE")"

    echo "正在扫描系统命令缓存..." >&2
    system_cmds="$(build_system_cmd_cache)"

    echo "正在扫描其他模块命令缓存..." >&2
    foreign_cmds="$(build_foreign_cmd_cache)"

    ensure_main_wrapper "$WHITELIST_FILE"

    if [ ! -d "$TERMUX_BIN_DIR" ]; then
        log "Termux 未安装"
        echo "错误: Termux 未安装" >&2
        return 1
    fi

    echo "正在扫描 Termux 命令..." >&2
    result="$(scan_and_create "$whitelist" "$blacklist" "$system_cmds" "$foreign_cmds")"
    set -- $result
    total="$1"
    created="$2"
    skipped="$3"

    echo "" >&2
    echo "正在清理失效 wrapper..." >&2
    cleaned="$(cleanup_invalid_wrappers "$whitelist" "$blacklist" "$foreign_cmds")"

    [ "$cleaned" -gt 0 ] && echo "  清理了 $cleaned 个失效 wrapper" >&2

    log "同步完成 - 总计:$total 新增:$created 跳过:$skipped 清理:$cleaned"
    log "========== 同步结束 =========="

    echo "$total $created $skipped $cleaned"
}

# === 开机服务入口 ===
run_service() {
    log "模块启动"
    init_env
    sync_all > /dev/null
    log "模块完成"
}

# === 手动扫描入口 ===
run_scan() {
    echo "termux_path - 手动扫描"
    echo "===================="

    init_env

    if [ ! -d "$TERMUX_BIN_DIR" ]; then
        echo "错误: Termux 未安装"
        return 1
    fi

    echo "Termux 目录: $TERMUX_BIN_DIR"
    echo "Wrapper 目录: $MODULE_BIN_DIR"
    echo "白名单文件: $WHITELIST_FILE"
    echo "黑名单文件: $BLACKLIST_FILE"
    echo ""

    result="$(sync_all)"
    set -- $result
    total="$1"
    created="$2"
    skipped="$3"
    cleaned="$4"

    echo ""
    echo "===================="
    echo "扫描完成!"
    echo "===================="
    echo "总计 Termux 命令: $total"
    echo "新增 wrapper: $created"
    echo "跳过 (系统/关键/黑名单/其他模块): $skipped"
    echo "清理失效 wrapper: $cleaned"
    echo ""
    echo "日志文件: $LOG_FILE"

    if [ "$created" -gt 0 ] || [ "$cleaned" -gt 0 ]; then
        echo ""
        echo "检测到 wrapper 变更，是否立即重启生效？"
        printf "5 秒后自动放弃，输入 Y 重启: "
        read -t 5 answer
        if [ "$answer" = "Y" ] || [ "$answer" = "y" ]; then
            echo "正在重启..."
            reboot
        else
            echo "已取消，变更将在下次开机时生效。"
        fi
    fi
}