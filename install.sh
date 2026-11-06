#!/usr/bin/env bash
# DeepSeek 鲸鱼娘「大肥鱼」桌宠 —— Dux shell 插件一键安装 / 交互式配置
#
#   curl -fsSL https://raw.githubusercontent.com/maxlen727/deepseek-chan-dux-plugin/main/install.sh | bash
#   ./install.sh                 在仓库里运行：把这个目录链接成插件（git pull 即更新）
#   ./install.sh --configure     只重新走一遍配置
#   ./install.sh --yes           不提问，全部用默认值（AI 先不配）
#   ./install.sh --uninstall [--purge]   卸载；--purge 连配置、聊天记录、待办一起删
set -euo pipefail

REPO_URL="https://github.com/maxlen727/deepseek-chan-dux-plugin.git"
ASSET_REPO="https://github.com/PC2005-cloud/dsh-pet.git"
PLUGIN_ID="duxPet"
ANIM_COUNT=114

CFG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
if [[ -d "$CFG_HOME/dms" ]]; then
    DMS_DIR="$CFG_HOME/dms"
elif [[ -d "$CFG_HOME/DankMaterialShell" ]]; then
    DMS_DIR="$CFG_HOME/DankMaterialShell"
else
    DMS_DIR="$CFG_HOME/dms"
fi
PLUGIN_DIR="$DMS_DIR/plugins/$PLUGIN_ID"
PET_CFG_DIR="$CFG_HOME/dux-pet"
PET_CFG="$PET_CFG_DIR/config.json"
KEY_FILE="$PET_CFG_DIR/api-key"
CLONE_DIR="$DATA_HOME/deepseek-chan-dux-plugin"

ASSUME_YES=0
MODE=install
PURGE=0
NO_RESTART=0
for arg in "$@"; do
    case "$arg" in
    -y | --yes) ASSUME_YES=1 ;;
    --configure) MODE=configure ;;
    --uninstall) MODE=uninstall ;;
    --purge) PURGE=1 ;;
    --no-restart) NO_RESTART=1 ;;
    -h | --help)
        sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "不认识的参数：$arg（--help 看用法）" >&2
        exit 2
        ;;
    esac
done

# ------------------------------------------------------------------ 输出与提问

if [[ -t 1 ]]; then
    B=$'\e[1m' DIM=$'\e[2m' G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' C=$'\e[36m' N=$'\e[0m'
else
    B="" DIM="" G="" Y="" R="" C="" N=""
fi
step() { printf '\n%s==>%s %s%s%s\n' "$C" "$N" "$B" "$*" "$N"; }
ok() { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die() {
    printf '%s✗ %s%s\n' "$R" "$*" "$N" >&2
    exit 1
}

# curl | bash 时 stdin 是管道，提问从终端读
TTY=/dev/tty
NO_TTY=0
if [[ $ASSUME_YES -eq 0 ]] && ! { : <"$TTY"; } 2>/dev/null; then
    NO_TTY=1
    ASSUME_YES=1
fi

# ask 变量名 "问题" "默认值"
ask() {
    local __var=$1 prompt=$2 def=${3-} ans
    if [[ $ASSUME_YES -eq 1 ]]; then
        printf -v "$__var" '%s' "$def"
        return
    fi
    if [[ -n $def ]]; then
        read -r -p "  $prompt ${DIM}[$def]${N} " ans <"$TTY" || ans=""
    else
        read -r -p "  $prompt " ans <"$TTY" || ans=""
    fi
    printf -v "$__var" '%s' "${ans:-$def}"
}

# ask_secret 变量名 "问题"（不回显）
ask_secret() {
    local __var=$1 prompt=$2 ans=""
    if [[ $ASSUME_YES -eq 0 ]]; then
        read -r -s -p "  $prompt " ans <"$TTY" || ans=""
        echo
    fi
    printf -v "$__var" '%s' "$ans"
}

# yes_no "问题" y|n（默认）→ 返回 0 = 是
yes_no() {
    local prompt=$1 def=${2:-y} ans hint
    [[ $def == y ]] && hint="Y/n" || hint="y/N"
    if [[ $ASSUME_YES -eq 1 ]]; then
        [[ $def == y ]]
        return
    fi
    read -r -p "  $prompt ${DIM}[$hint]${N} " ans <"$TTY" || ans=""
    ans=${ans:-$def}
    [[ $ans == [yY]* ]]
}

# choose 变量名 "问题" 默认序号 选项...（选项写成 "值|说明"）
choose() {
    local __var=$1 prompt=$2 def=$3
    shift 3
    local i=1 opt
    if [[ $ASSUME_YES -eq 0 ]]; then
        echo "  $prompt"
        for opt in "$@"; do
            printf '    %s%d)%s %s\n' "$B" "$i" "$N" "${opt#*|}"
            i=$((i + 1))
        done
    fi
    local pick
    while true; do
        ask pick "选择" "$def"
        if [[ $pick =~ ^[0-9]+$ ]] && ((pick >= 1 && pick <= $#)); then
            break
        fi
        warn "请输入 1-$#"
    done
    opt=${!pick}
    printf -v "$__var" '%s' "${opt%%|*}"
}

json_str() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\t'/\\t}
    printf '"%s"' "$s"
}

have() { command -v "$1" >/dev/null 2>&1; }

# 只留数字，空了就用默认值
num() {
    local v=${1//[^0-9]/}
    printf '%s' "${v:-$2}"
}

dms_ipc() { dms ipc call "$@" 2>/dev/null; }

# dms_has 正则 参数...：dms ipc 输出里有没有匹配的行（不用管道，避开 pipefail + grep -q 的 SIGPIPE）
dms_has() {
    local re=$1 out
    shift
    out=$(dms_ipc "$@" || true)
    grep -qE "$re" <<<"$out"
}

shell_running() { dms_ipc plugin-scan status >/dev/null; }

# ------------------------------------------------------------------ 卸载

uninstall() {
    step "卸载"
    if have dms && shell_running; then
        dms_ipc plugins disable "$PLUGIN_ID" >/dev/null && ok "已在 Dux shell 里停用插件"
    fi
    if [[ -L $PLUGIN_DIR ]]; then
        rm "$PLUGIN_DIR" && ok "删除链接 $PLUGIN_DIR"
    elif [[ -d $PLUGIN_DIR ]]; then
        rm -rf "$PLUGIN_DIR" && ok "删除 $PLUGIN_DIR"
    fi
    [[ -d $CLONE_DIR ]] && rm -rf "$CLONE_DIR" && ok "删除 $CLONE_DIR"
    if [[ $PURGE -eq 1 ]]; then
        rm -rf "$PET_CFG_DIR" && ok "删除配置 $PET_CFG_DIR"
        rm -f "$STATE_HOME"/quickshell/by-shell/*/duxPet-*.json 2>/dev/null && ok "删除聊天记录和待办"
    else
        echo "  配置、聊天记录和待办保留着（加 --purge 一起删）"
    fi
    warn "桌面上如果加过「小窝」小组件，到 设置 → 桌面小组件 里删掉"
    if have dms && shell_running && [[ $NO_RESTART -eq 0 ]] && yes_no "重启 Dux shell 让宠物立刻消失？" y; then
        dms restart >/dev/null 2>&1 || true
    fi
    echo
    ok "卸载完成"
}

# ------------------------------------------------------------------ 依赖

check_deps() {
    step "检查依赖"
    local missing=()
    have git || missing+=(git)
    have ffmpeg || missing+=(ffmpeg)
    have dms || missing+=("dms（Dux shell）")
    if ((${#missing[@]})); then
        die "缺少：${missing[*]}。Arch：sudo pacman -S git ffmpeg"
    fi
    ok "git、ffmpeg、dms 都在"
    have curl || warn "没有 curl：跳过 API Key 连通性测试"
    have notify-send || warn "没有 notify-send（libnotify）：待办到期不会弹系统通知"
    if ! shell_running; then
        warn "Dux shell 好像没在运行；装完后启动它，插件会自动加载"
    fi
}

check_ffmpeg() {
    # 先存下来再 grep：grep -q 提前退出会让 ffmpeg 吃 SIGPIPE，pipefail 下整条判失败
    local dec enc
    dec=$(ffmpeg -hide_banner -decoders 2>/dev/null || true)
    enc=$(ffmpeg -hide_banner -encoders 2>/dev/null || true)
    [[ $dec == *libvpx-vp9* ]] || die "ffmpeg 不带 libvpx 解码器（转换透明素材需要它）"
    [[ $enc == *libwebp_anim* ]] || die "ffmpeg 不带 libwebp 编码器（转换透明素材需要它）"
}

# ------------------------------------------------------------------ 插件本体

SCRIPT_DIR=""
if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi

install_plugin() {
    step "安装插件"
    local src
    if [[ -n $SCRIPT_DIR && -f $SCRIPT_DIR/plugin.json ]] && grep -q "\"id\": *\"$PLUGIN_ID\"" "$SCRIPT_DIR/plugin.json"; then
        src=$SCRIPT_DIR
        ok "使用当前仓库：$src"
    else
        if [[ -d $CLONE_DIR/.git ]]; then
            git -C "$CLONE_DIR" pull --ff-only -q && ok "已更新 $CLONE_DIR"
        else
            mkdir -p "$(dirname "$CLONE_DIR")"
            git clone -q --depth 1 "$REPO_URL" "$CLONE_DIR" && ok "已下载到 $CLONE_DIR"
        fi
        src=$CLONE_DIR
    fi
    mkdir -p "$(dirname "$PLUGIN_DIR")"
    if [[ -e $PLUGIN_DIR && ! -L $PLUGIN_DIR ]]; then
        local bak="$PLUGIN_DIR.bak-$(date +%Y%m%d%H%M%S)"
        # 备份放到插件目录外面，免得被当成另一个插件扫到
        bak="$DMS_DIR/$(basename "$bak")"
        mv "$PLUGIN_DIR" "$bak"
        warn "原来的 $PLUGIN_DIR 已挪到 $bak"
    fi
    ln -sfn "$src" "$PLUGIN_DIR"
    ok "链接 $PLUGIN_DIR → $src"
    PLUGIN_SRC=$src
}

install_assets() {
    step "准备动画素材"
    local anim="$PLUGIN_SRC/assets/anim"
    local have_n
    have_n=0
    [[ -d $anim ]] && have_n=$(find "$anim" -maxdepth 1 -name '*.webp' | wc -l)
    if ((have_n >= ANIM_COUNT)); then
        ok "已有 $have_n 段动画，跳过"
        return
    fi
    check_ffmpeg
    local tmp
    tmp=$(mktemp -d)
    echo "  从 dsh-pet 下载原始素材（约 56MB）…"
    if ! git clone -q --depth 1 --filter=blob:none --sparse "$ASSET_REPO" "$tmp/dsh-pet" 2>"$tmp/git.log" ||
        ! git -C "$tmp/dsh-pet" sparse-checkout set dsh-pet/assets/webm 2>>"$tmp/git.log"; then
        cat "$tmp/git.log" >&2
        rm -rf "$tmp"
        die "下载素材失败（网络问题？可以稍后重新运行）"
    fi
    ok "下载完成"
    echo "  转换成透明动画 WebP（$(nproc) 线程，大约一两分钟）…"
    bash "$PLUGIN_SRC/tools/convert-assets.sh" "$tmp/dsh-pet/dsh-pet/assets/webm" "$anim" >/dev/null
    rm -rf "$tmp"
    have_n=$(find "$anim" -maxdepth 1 -name '*.webp' | wc -l)
    ((have_n >= ANIM_COUNT)) || die "只转出了 $have_n 段动画，应该有 $ANIM_COUNT 段"
    ok "$have_n 段动画就绪（$(du -sh "$anim" | cut -f1)）"
}

# ------------------------------------------------------------------ 交互式配置

test_key() {
    local base=$1 key=$2 code
    have curl || return 0
    code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' -H "Authorization: Bearer $key" "${base%/}/models" || echo 000)
    case $code in
    200) ok "API Key 可用" ;;
    401 | 403) warn "接口返回 $code：Key 好像不对，装完可以重新运行 ./install.sh --configure" ;;
    000) warn "连不上 $base（网络问题？），先照样保存" ;;
    *) warn "接口返回 $code，先照样保存" ;;
    esac
}

configure() {
    step "配置宠物"
    if [[ -f $PET_CFG ]] && ! yes_no "已经有配置了（$PET_CFG），重新配置？" n; then
        ok "保留现有配置"
        return
    fi
    echo "  ${DIM}直接回车 = 用方括号里的默认值；以后在 设置 → 插件 → DeepSeek-chan Desktop Pet 里也能改${N}"
    echo

    local name size ground
    ask name "宠物叫什么名字？" "大肥鱼"
    ask size "宠物大小（px，150-600）？" "300"
    ask ground "地面离屏幕底边多高（底部有 dock 就填 dock 高度）？" "0"
    echo

    local provider base model need_key=1 bal_provider="off"
    choose provider "AI 对话 / 碎碎念用哪家？" 1 \
        "deepseek|DeepSeek（推荐，原汁原味）" \
        "openrouter|OpenRouter" \
        "siliconflow|硅基流动" \
        "ollama|本地 Ollama（不需要 Key）" \
        "custom|其他 OpenAI 兼容接口" \
        "none|先不配（用内置台词，以后再说）"
    case $provider in
    deepseek) base="https://api.deepseek.com" model="deepseek-chat" bal_provider=deepseek ;;
    openrouter) base="https://openrouter.ai/api/v1" model="deepseek/deepseek-chat" bal_provider=openrouter ;;
    siliconflow) base="https://api.siliconflow.cn/v1" model="deepseek-ai/DeepSeek-V3" bal_provider=siliconflow ;;
    ollama) base="http://localhost:11434/v1" model="qwen2.5:7b" need_key=0 ;;
    custom) base="" model="" ;;
    none) base="" model="" need_key=0 ;;
    esac
    local key_ref=""
    if [[ $provider != none ]]; then
        if [[ $provider == custom ]]; then
            while [[ -z $base ]]; do ask base "接口地址（到 /v1 为止）？" ""; done
        else
            ask base "接口地址？" "$base"
        fi
        ask model "模型名？" "$model"
        if [[ $need_key -eq 1 ]]; then
            local key=""
            if [[ $provider == deepseek && -n ${DEEPSEEK_API_KEY:-} ]] && yes_no "检测到环境变量 DEEPSEEK_API_KEY，直接用它？" y; then
                key=$DEEPSEEK_API_KEY
            else
                ask_secret key "API Key（输入时不显示，留空 = 以后再填）："
            fi
            if [[ -n $key ]]; then
                mkdir -p "$PET_CFG_DIR"
                (umask 077 && printf '%s\n' "$key" >"$KEY_FILE")
                chmod 600 "$KEY_FILE"
                key_ref="file:$KEY_FILE"
                ok "Key 存进 $KEY_FILE（权限 600），配置里只记文件路径"
                test_key "$base" "$key"
            else
                warn "没填 Key：先用内置台词"
            fi
        fi
    fi
    echo

    local whisper whisper_on=true
    ask whisper "多久碎碎念一句（秒，0 = 不说）？" "300"
    [[ $whisper == 0 ]] && whisper_on=false whisper=300

    local bal_auto=false bal_full=""
    if [[ $bal_provider != off && -n $key_ref ]]; then
        if yes_no "定时报余额（按剩余多少播 6 档钱袋动画）？" y; then
            bal_auto=true
        fi
        if [[ $bal_provider != openrouter ]]; then
            ask bal_full "平时一次充多少算「满」（元，用来算已用比例）？" "20"
        fi
    fi

    local multi="single" screens=""
    local n_out
    local outs
    outs=$(niri msg outputs 2>/dev/null || true)
    n_out=$(grep -c '^Output' <<<"$outs" || true)
    if [[ ${n_out:-0} -gt 1 ]]; then
        echo
        choose multi "检测到 $n_out 块屏，宠物怎么养？" 1 \
            "single|一只宠物，可以走到/甩到相邻屏" \
            "perScreen|每块屏各一只"
    fi

    mkdir -p "$PET_CFG_DIR"
    {
        echo "{"
        echo "  \"petName\": $(json_str "$name"),"
        echo "  \"petSize\": $(num "$size" 300),"
        echo "  \"groundOffset\": $(num "$ground" 0),"
        echo "  \"aiBaseUrl\": $(json_str "$base"),"
        echo "  \"aiModel\": $(json_str "$model"),"
        echo "  \"aiApiKey\": $(json_str "$key_ref"),"
        echo "  \"whisperEnabled\": $whisper_on,"
        echo "  \"whisperIntervalSec\": $(num "$whisper" 300),"
        echo "  \"balanceProvider\": $(json_str "$bal_provider"),"
        echo "  \"balanceAuto\": $bal_auto,"
        echo "  \"balanceFull\": $(json_str "$bal_full"),"
        echo "  \"multiScreen\": $(json_str "$multi"),"
        echo "  \"petScreens\": $(json_str "$screens")"
        echo "}"
    } >"$PET_CFG.tmp"
    mv "$PET_CFG.tmp" "$PET_CFG"
    ok "配置写到 $PET_CFG（改这个文件会实时生效）"

    # 在设置界面里填过的值优先级更高，提醒一下
    if grep -qs '"duxPet"' "$DMS_DIR/settings.json" "$DMS_DIR/plugin_settings.json"; then
        warn "如果以前在 设置 里填过同一项，那边的值优先；想让这里生效就把那边清空"
    fi
}

# ------------------------------------------------------------------ 启用

enable_plugin() {
    step "启用"
    if ! shell_running; then
        warn "Dux shell 没在运行：启动后执行 dms ipc call plugins enable $PLUGIN_ID"
        return
    fi
    local was_loaded=0
    dms_has "^$PLUGIN_ID[[:space:]]+loaded" plugin-scan list && was_loaded=1
    dms_ipc plugin-scan scan >/dev/null
    local i
    for i in $(seq 1 20); do
        dms_has "^$PLUGIN_ID" plugin-scan list && break
        sleep 0.5
    done
    dms_has "^$PLUGIN_ID" plugin-scan list || die "Dux shell 没扫到插件，看看 $PLUGIN_DIR/plugin.json 在不在"
    if [[ $was_loaded -eq 1 ]]; then
        # 已加载的插件改了 QML 只有重启 shell 才生效
        if [[ $NO_RESTART -eq 0 ]] && yes_no "插件之前就在运行，重启 Dux shell 让新版本生效？" y; then
            dms restart >/dev/null 2>&1 || true
            for i in $(seq 1 40); do
                dms_ipc "$PLUGIN_ID" state >/dev/null && break
                sleep 0.5
            done
        fi
    else
        dms_ipc plugins enable "$PLUGIN_ID" >/dev/null || true
    fi
    for i in $(seq 1 20); do
        dms_has '"mode"' "$PLUGIN_ID" state && break
        sleep 0.5
    done
    if dms_has '"mode"' "$PLUGIN_ID" state; then
        ok "宠物已经出现在屏幕上了"
        dms_ipc "$PLUGIN_ID" say "主人好！我是$(sed -n 's/.*"petName": *"\([^"]*\)".*/\1/p' "$PET_CFG" 2>/dev/null | head -1)～" >/dev/null || true
    else
        warn "没等到宠物出现，可以执行 dms restart 再看看"
    fi
}

offer_house() {
    shell_running || return 0
    echo
    echo "  桌面「小窝」是可选的：一个桌面小组件，左键把宠物叫回来，中键让它睡觉/起来。"
    if yes_no "现在打开设置去添加小窝？（在列表里选 DeepSeek-chan Desktop Pet）" n; then
        dms_ipc settings openWith desktop_widgets >/dev/null || true
    fi
}

summary() {
    local SELF="$0"
    [[ -n $SCRIPT_DIR ]] || SELF="bash $PLUGIN_SRC/install.sh"
    step "装好了"
    cat <<EOF
  ${B}玩法${N}：点它 Q 弹一下 · 拖着甩出去 · 右键菜单里聊天 / 待办 / 查余额 / 睡觉
  ${B}设置${N}：设置 → 插件 → DeepSeek-chan Desktop Pet，或者直接改 $PET_CFG
  ${B}命令${N}：dms ipc call $PLUGIN_ID say "你好"   ·   dms ipc call $PLUGIN_ID todoAdd "18:30 开会"
  ${B}更新${N}：重新运行这个脚本（或在仓库里 git pull 后 dms restart）
  ${B}卸载${N}：$SELF --uninstall [--purge]
EOF
}

# ------------------------------------------------------------------ main

printf '%s🐋 DeepSeek 鲸鱼娘桌宠 · Dux shell 插件%s\n' "$B" "$N"
[[ $NO_TTY -eq 1 ]] && warn "没有可交互的终端，全部使用默认值（之后可以运行 install.sh --configure 重新配置）"
case $MODE in
uninstall)
    uninstall
    ;;
configure)
    configure
    ;;
install)
    check_deps
    install_plugin
    install_assets
    configure
    enable_plugin
    offer_house
    summary
    ;;
esac
