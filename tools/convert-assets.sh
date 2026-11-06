#!/usr/bin/env bash
# 把 dsh-pet 的 VP9-alpha webm 素材转成 Qt AnimatedImage 能播的动画 WebP（保留透明）。
# Qt Multimedia 的 FFmpeg 后端用原生 vp9 解码器会丢 alpha，所以这里必须强制 libvpx-vp9 解码。
#
# 用法: tools/convert-assets.sh <dsh-pet 仓库里的 assets/webm 目录> [输出目录] [宽度] [fps]
set -euo pipefail

src=${1:?需要 webm 源目录}
out=${2:-"$(dirname "$0")/../assets/anim"}
width=${3:-360}
fps=${4:-15}
jobs=${JOBS:-$(nproc)}

mkdir -p "$out"

convert_one() {
    local f=$1 out=$2 width=$3 fps=$4
    local name dst
    name=$(basename "$f" .webm)
    dst="$out/$name.webp"
    [[ -s "$dst" && "$dst" -nt "$f" ]] && return 0
    ffmpeg -nostdin -hide_banner -loglevel error -y \
        -c:v libvpx-vp9 -i "$f" -an \
        -vf "fps=$fps,scale=$width:-2:flags=lanczos,format=yuva420p" \
        -c:v libwebp_anim -lossless 0 -quality 70 -compression_level 4 -loop 0 \
        "$dst.tmp.webp"
    mv "$dst.tmp.webp" "$dst"
    echo "ok  $name"
}
export -f convert_one

find "$src" -maxdepth 1 -name '*.webm' -print0 |
    xargs -0 -P "$jobs" -I{} bash -c 'convert_one "$@"' _ {} "$out" "$width" "$fps"

du -sh "$out"
