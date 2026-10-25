#!/usr/bin/env bash
# Renders one tools/record.gd scenario to an MP4, gently: memory-capped (killed instead of freezing
# the PC), low priority, few rendering threads, frames deleted after encoding.
# Run scenarios ONE AT A TIME.
#   tools/render_video.sh <lanes|climb|descend|cliffs|fight> <out_dir>
set -euo pipefail
cd "$(dirname "$0")/.."
scenario="$1"
out="$2"
frames="$out/frames_$scenario"
rm -rf "$frames"
mkdir -p "$frames"
cap=(systemd-run --user --scope -q -p MemoryMax=2G -p CPUQuota=300%)

"${cap[@]}" env -u DRI_PRIME LP_NUM_THREADS=2 nice -n 10 \
	xvfb-run -a -s "-screen 0 1280x720x24" \
	godot --path . --rendering-driver opengl3 -s res://tools/record.gd -- "$scenario" "$frames" 2>&1 \
	| grep -E 'frames|SCRIPT ERROR|ERROR' || true

"${cap[@]}" nice -n 10 ffmpeg -y -loglevel error -threads 2 -framerate 30 -i "$frames/f%04d.png" \
	-pix_fmt yuv420p -vf "scale=960:-2" "$out/$scenario.mp4"
rm -rf "$frames"
ls -la "$out/$scenario.mp4"
