#!/usr/bin/env bash
# 2026-11-07 18:45 UTC - light-triggered snapshot + clip, alert via ntfy (9046unix)

CAM=/dev/v4l/by-id/usb-Vimicro_corp._Lenovo_EasyCamera-video-index0   # built-in camera
OUT=/mnt/data/cam
ON="${ON:-60}"          # brightness (YAVG) at or above this = light on
OFF="${OFF:-45}"        # below this = dark again, re-arm
BRIGHT="${BRIGHT:-100}" # below this the scene counts as dim -> use enhanced capture
CHECK="${CHECK:-60}"    # seconds between checks
CLIP="${CLIP:-10}"      # clip length in seconds
REPEAT="${REPEAT:-60}"  # while light stays on: save a fresh snapshot this often (seconds)

yavg(){ ffmpeg -nostdin -hide_banner -loglevel error -f v4l2 -i "$CAM" -ss 2 -frames:v 1 \
          -vf "signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" -f null - 2>/dev/null \
        | grep -o 'YAVG=[0-9.]*' | tail -1 | cut -d= -f2 | cut -d. -f1; }
sense_mode(){ v4l2-ctl -d "$CAM" -c brightness=0 2>/dev/null; }
snap(){ if [ "$1" = dim ]; then
          v4l2-ctl -d "$CAM" -c brightness=10 2>/dev/null
          ffmpeg -nostdin -hide_banner -loglevel error -f v4l2 -i "$CAM" -ss 3 -t 1 \
                 -vf "tmix=frames=20,eq=contrast=1.4:gamma=1.3" -update 1 -y "$2"
        else
          ffmpeg -nostdin -hide_banner -loglevel error -f v4l2 -i "$CAM" -ss 2 -frames:v 1 -y "$2"
        fi; sense_mode; }
clip(){ if [ "$1" = dim ]; then
          v4l2-ctl -d "$CAM" -c brightness=10 2>/dev/null
          ffmpeg -nostdin -hide_banner -loglevel error -f v4l2 -i "$CAM" -ss 2 -t "$CLIP" \
                 -vf "hqdn3d=4:3:6:4,eq=contrast=1.4:gamma=1.3" \
                 -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -y "$2"
        else
          ffmpeg -nostdin -hide_banner -loglevel error -f v4l2 -i "$CAM" -t "$CLIP" \
                 -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -y "$2"
        fi; sense_mode; }
mode_for(){ if [ "$1" -lt "$BRIGHT" ]; then echo dim; else echo bright; fi; }

sense_mode
armed=1; last=0
echo "$(date '+%F %T') lightcam started: ON=$ON OFF=$OFF BRIGHT=$BRIGHT CHECK=${CHECK}s CLIP=${CLIP}s REPEAT=${REPEAT}s"
while true; do
  y=$(yavg); y=${y:-0}
  now=$(date +%s)
  if [ "$armed" = 1 ] && [ "$y" -ge "$ON" ]; then
    # light just came on: full set (snapshot + clip)
    mode=$(mode_for "$y"); ts=$(date +%Y-%m-%d_%H%M%S); d="$OUT/$(date +%F)"; mkdir -p "$d"
    snap "$mode" "$d/$ts.jpg"
    clip "$mode" "$d/$ts.mp4"
    echo "$(date '+%F %T') LIGHT ON yavg=$y mode=$mode -> snap + clip saved $ts"
    armed=0; last=$now
  elif [ "$armed" = 0 ] && [ "$y" -lt "$OFF" ]; then
    echo "$(date '+%F %T') dark again yavg=$y -> re-armed"
    armed=1
  elif [ "$armed" = 0 ] && [ $((now - last)) -ge "$REPEAT" ]; then
    # light still on: one fresh snapshot
    mode=$(mode_for "$y"); ts=$(date +%Y-%m-%d_%H%M%S); d="$OUT/$(date +%F)"; mkdir -p "$d"
    snap "$mode" "$d/$ts.jpg"
    echo "$(date '+%F %T') still on yavg=$y -> snapshot saved $ts"
    last=$now
  fi
  sleep "$CHECK"
done
# 2026-11-07 19:05 UTC - dim scenes now use enhanced capture (brightness 10 + frame averaging + contrast) and a built-in clip; normal captures when bright; reset sensing brightness afterwards
# 2026-11-07 19:20 UTC - dropped Logitech (built-in only); added a snapshot every REPEAT seconds while the light stays on (low priority); simplified file names
# 2026-11-09 03:02 UTC - removed ntfy (TOPIC/NTFY/send/curl; fd pulls the files and alerts instead); -nostdin on every ffmpeg call for systemd; same capture logic and file names
# 2026-11-09 03:55 UTC - moved into the scripts repo (9046Unix/lightcam.sh); lightcam.service runs it from there
