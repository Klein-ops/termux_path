#!/system/bin/sh
# termux_path 公共函数库
# POSIX sh 兼容

# === 动态获取模块根目录 ===
MODDIR=${0%/*}
[ -z "$MODDIR" ] && MODDIR="."

# === 常量 ===
TERMUX_BIN_DIR="/data/data/com.termux/files/usr/bin"
MODULE_BIN_DIR="$MODDIR/system/xbin"
LOG_FILE="/data/local/tmp/termux_path.log"
WRAPPER_VERSION="2.0"
CRITICAL_CMDS="su mount umount reboot shutdown init kernel recovery magisk magiskpolicy resetprop"
BLACKLIST_FILE="$MODDIR/blacklist"

# 主脚本文件名
WRAPPER_MAIN_NAME="wrapper_main.sh"
WRAPPER_MAIN_SRC="$MODULE_BIN_DIR/$WRAPPER_MAIN_NAME"

# 系统命令缓存
SYSTEM_CMDS_CACHE=""
# 黑名单缓存
BLACKLIST=""

# === 初始化环境（精细化权限设置）===
init_env() {
    mkdir -p "$MODULE_BIN_DIR"
    chmod 755 "$MODDIR" "$MODDIR/system" "$MODULE_BIN_DIR" 2>/dev/null
    chown -R root:root "$MODDIR" 2>/dev/null

    if [ -d "/data/data/com.termux" ]; then
        restorecon -R /data/data/com.termux 2>/dev/null
        
        chmod 755 /data/data/com.termux 2>/dev/null
        chmod 755 /data/data/com.termux/files 2>/dev/null
        chmod -R 755 /data/data/com.termux/files/usr 2>/dev/null
        
        mkdir -p /data/data/com.termux/files/usr/tmp
        chmod 1777 /data/data/com.termux/files/usr/tmp 2>/dev/null
        
        log "Termux 权限已精细修复"
    fi
}

# === 日志 ===
log() {
    echo "$(date '+%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
    chmod 644 "$LOG_FILE" 2>/dev/null
}

# === 动态获取系统默认 PATH ===
get_system_path() {
    sys_path=$(env -i /system/bin/sh -c 'echo $PATH' 2>/dev/null)
    if [ -n "$sys_path" ]; then
        echo "$sys_path"
    else
        echo "/sbin:/system/sbin:/system/bin:/system/xbin:/vendor/bin:/vendor/xbin"
    fi
}

# === 加载黑名单 ===
load_blacklist() {
    BLACKLIST=""
    if [ -f "$BLACKLIST_FILE" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            [ -z "$line" ] && continue
            echo "$line" | grep -q "^#" && continue
            BLACKLIST="$BLACKLIST $line"
        done < "$BLACKLIST_FILE"
    fi
}

# === 检查是否在黑名单中 ===
is_blacklisted() {
    cmd="$1"
    case " $BLACKLIST " in
        *" $cmd "*) return 0 ;;
        *) return 1 ;;
    esac
}

# === 一次性扫描系统所有命令缓存 ===
build_system_cmd_cache() {
    SYSTEM_CMDS_CACHE=""
    sys_path=$(get_system_path)
    dirs=$(echo "$sys_path" | tr ':' ' ')
    for dir in $dirs; do
        if [ -d "$dir" ]; then
            for cmd in $(ls "$dir" 2>/dev/null); do
                SYSTEM_CMDS_CACHE="$SYSTEM_CMDS_CACHE $cmd"
            done
        fi
    done
    log "系统命令缓存已建立"
}

# === 检查是否是我们的 wrapper（仅软链接）===
is_our_wrapper() {
    file="$1"
    if [ -L "$file" ]; then
        target=$(readlink "$file")
        [ "$target" = "$WRAPPER_MAIN_NAME" ] || [ "$target" = "./$WRAPPER_MAIN_NAME" ] && return 0
    fi
    return 1
}

# === 检查是否系统命令 ===
is_system_cmd() {
    cmd="$1"
    case " $SYSTEM_CMDS_CACHE " in
        *" $cmd "*) return 0 ;;
        *) return 1 ;;
    esac
}

# === 检查是否关键命令 ===
is_critical_cmd() {
    cmd="$1"
    for c in $CRITICAL_CMDS; do
        [ "$cmd" = "$c" ] && return 0
    done
    return 1
}

# === 检查 Termux 命令是否有效 ===
is_termux_cmd_valid() {
    cmd="$1"
    target="$TERMUX_BIN_DIR/$cmd"
    [ -f "$target" ] || [ -L "$target" ] && [ -x "$target" ]
}

# === 生成主脚本内容 ===
generate_main_wrapper() {
    cat << EOF
#!/system/bin/sh
# termux_path Wrapper v$WRAPPER_VERSION

CMD=\$(basename "\$0")
PREFIX="/data/data/com.termux/files/usr"
TARGET="\$PREFIX/bin/\$CMD"

if [ ! -f "\$TARGET" ]; then
    echo "错误: Termux 中未安装命令 '\$CMD'" >&2
    exit 127
fi

if [ ! -x "\$TARGET" ]; then
    echo "错误: 权限不足，无法执行 '\$CMD'" >&2
    exit 126
fi

export HOME="\$PREFIX/home"
export TMPDIR="\$PREFIX/tmp"
export PREFIX="\$PREFIX"
[ -n "\$LD_LIBRARY_PATH" ] && export LD_LIBRARY_PATH="\$PREFIX/lib:\$LD_LIBRARY_PATH" || export LD_LIBRARY_PATH="\$PREFIX/lib"
export PATH="\$PREFIX/bin:\$PATH"

[ ! -d "\$PREFIX/tmp" ] && mkdir -p "\$PREFIX/tmp" 2>/dev/null

exec "\$TARGET" "\$@"
EOF
}

# === 确保主脚本存在且版本正确 ===
ensure_main_wrapper() {
    if [ ! -f "$WRAPPER_MAIN_SRC" ] || ! grep -q "# termux_path Wrapper v$WRAPPER_VERSION" "$WRAPPER_MAIN_SRC" 2>/dev/null; then
        generate_main_wrapper > "$WRAPPER_MAIN_SRC"
        chmod 755 "$WRAPPER_MAIN_SRC"
        chown root:root "$WRAPPER_MAIN_SRC" 2>/dev/null
        chcon u:object_r:system_file:s0 "$WRAPPER_MAIN_SRC" 2>/dev/null
        log "主脚本已生成/更新到 v$WRAPPER_VERSION"
        echo "  主脚本已更新到 v$WRAPPER_VERSION" >&2
    fi
}

# === 创建单个 wrapper（软链接，相对路径）===
create_wrapper() {
    cmd="$1"
    target="$MODULE_BIN_DIR/$cmd"

    ensure_main_wrapper

    if [ -L "$target" ]; then
        link_target=$(readlink "$target")
        if [ "$link_target" = "$WRAPPER_MAIN_NAME" ] || [ "$link_target" = "./$WRAPPER_MAIN_NAME" ]; then
            return 0
        fi
    fi

    rm -f "$target"
    ln -s "$WRAPPER_MAIN_NAME" "$target"
    log "创建 wrapper 链接: $cmd"
    return 1
}

# === 扫描 Termux 并创建软链接 ===
scan_and_create() {
    total=0
    created=0
    skipped=0

    for f in "$TERMUX_BIN_DIR"/*; do
        [ -f "$f" ] || [ -L "$f" ] || continue
        [ -x "$f" ] || continue

        cmd=$(basename "$f")
        total=$((total + 1))

        if is_system_cmd "$cmd"; then
            skipped=$((skipped + 1))
            echo "  跳过系统命令: $cmd" >&2
            continue
        fi

        if is_critical_cmd "$cmd"; then
            skipped=$((skipped + 1))
            echo "  跳过关键命令: $cmd" >&2
            continue
        fi

        if is_blacklisted "$cmd"; then
            skipped=$((skipped + 1))
            echo "  跳过黑名单命令: $cmd" >&2
            continue
        fi

        create_wrapper "$cmd"
        ret=$?
        [ $ret -eq 1 ] && created=$((created + 1)) && echo "  创建 wrapper: $cmd" >&2
    done

    echo "$total $created $skipped"
}

# === 清理失效 wrapper ===
cleanup_invalid_wrappers() {
    cleaned=0
    for wrapper in "$MODULE_BIN_DIR"/*; do
        [ -f "$wrapper" ] || [ -L "$wrapper" ] || continue
        [ "$(basename "$wrapper")" = "$WRAPPER_MAIN_NAME" ] && continue

        is_our_wrapper "$wrapper" || continue
        cmd=$(basename "$wrapper")

        if is_blacklisted "$cmd"; then
            rm -f "$wrapper"
            log "清理黑名单 wrapper: $cmd"
            cleaned=$((cleaned + 1))
            continue
        fi

        if ! is_termux_cmd_valid "$cmd"; then
            rm -f "$wrapper"
            log "清理失效 wrapper: $cmd"
            cleaned=$((cleaned + 1))
        fi
    done
    echo "$cleaned"
}

# === 主同步流程 ===
sync_all() {
    log "========== 开始同步 =========="
    echo "正在加载黑名单..." >&2
    load_blacklist
    echo "正在扫描系统命令缓存..." >&2
    build_system_cmd_cache
    echo "正在扫描 Termux 命令..." >&2

    ensure_main_wrapper

    if [ ! -d "$TERMUX_BIN_DIR" ]; then
        log "Termux 未安装"
        echo "错误: Termux 未安装" >&2
        return 1
    fi

    result=$(scan_and_create)
    set -- $result
    total=$1
    created=$2
    skipped=$3

    echo "" >&2
    echo "正在清理失效 wrapper..." >&2
    cleaned=$(cleanup_invalid_wrappers)

    [ $cleaned -gt 0 ] && echo "  清理了 $cleaned 个失效 wrapper" >&2

    log "同步完成 - 总计:$total 新增:$created 跳过:$skipped 清理:$cleaned"
    log "========== 同步结束 =========="

    echo "$total $created $skipped $cleaned"
}

# === 开机服务入口 ===
run_service() {
    log "模块启动"
    sync_all > /dev/null
    log "模块完成"
}

# === 手动扫描入口 ===
run_scan() {
    echo "termux_path - 手动扫描"
    echo "===================="

    if [ ! -d "$TERMUX_BIN_DIR" ]; then
        echo "错误: Termux 未安装"
        return 1
    fi

    echo "Termux 目录: $TERMUX_BIN_DIR"
    echo "Wrapper 目录: $MODULE_BIN_DIR"
    echo "黑名单文件: $BLACKLIST_FILE"
    echo ""

    result=$(sync_all)
    set -- $result

    echo ""
    echo "===================="
    echo "扫描完成!"
    echo "===================="
    echo "总计 Termux 命令: $1"
    echo "新增 wrapper: $2"
    echo "跳过 (系统/关键/黑名单): $3"
    echo "清理失效 wrapper: $4"
    echo ""
    echo "日志文件: $LOG_FILE"
}