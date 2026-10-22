#!/usr/bin/env bash
# Assembles the Mirrorwing promo videos (landscape 1920x1080 + vertical
# 1080x1920) from lockstep-captured 30fps frames, overlay PNGs and the
# game's own music. See README.md in this folder for the capture step.
# Usage: FRAMES=<capture dir> GFX=<overlay dir> FF=<ffmpeg.exe> bash build.sh
set -euo pipefail
cd "$(dirname "$0")"
FRAMES=${FRAMES:?capture dir with L3/ L14/ L15/ L9/ L16/ daily/ editor/}
GFX=${GFX:?overlay dir from make_overlays.ps1}
FF=${FF:?path to ffmpeg.exe}
FP="$(dirname "$FF")/ffprobe.exe"
AUDIO="$(cd ../.. && pwd)/assets/audio"
OUT=${OUT:-../../store/promo}
WORK=$(mktemp -d)
mkdir -p "$OUT"
ENC=(-c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -r 30 -an)
XF=0.3   # crossfade between segments

# name  frame-dir  frames  caption#  (all start at the first captured frame)
SEGMENTS=(
  "g1 L3    105 1"
  "g2 L14   120 2"
  "g3 L15   105 3"
  "g4 L9    105 4"
  "g5 L16   105 5"
  "g6 daily 90  6"
)
EDITOR_CAP=7

dur() { "$FP" -v error -show_entries format=duration -of csv=p=0 "$1"; }
fadecap() { echo "format=rgba,fade=t=in:st=0.25:d=0.35:alpha=1"; }

card() { # out png seconds fade-from-black(0/1)
  local vf="format=yuv420p"
  [ "$4" = 1 ] && vf="fade=t=in:st=0:d=0.5,$vf"
  "$FF" -y -v error -loop 1 -framerate 30 -t "$3" -i "$GFX/$2" -vf "$vf" "${ENC[@]}" "$WORK/$1.mp4"
}

# Editor stop-motion list: 0.3s per placement, the last one held longer.
n=$(ls "$FRAMES/editor"/*.jpg | wc -l)
{ i=0; for f in "$FRAMES/editor"/*.jpg; do i=$((i+1)); echo "file '$(cygpath -m "$f")'"; [ $i -eq $n ] && echo "duration 0.9" || echo "duration 0.3"; done; echo "file '$(cygpath -m "$f")'"; } > "$WORK/editor_list.txt"

# ------------------------------------------------------------ landscape
card intro intro.png 2.5 1
card outro outro.png 3.2 0
for s in "${SEGMENTS[@]}"; do
  read -r name dir count cap <<<"$s"
  secs=$(awk "BEGIN{print $count/30}")
  "$FF" -y -v error -framerate 30 -i "$FRAMES/$dir/f%05d.jpg" -loop 1 -framerate 30 -t "$secs" -i "$GFX/cap$cap.png" \
    -filter_complex "[1]$(fadecap)[c];[0][c]overlay=0:0:shortest=1,format=yuv420p" \
    -frames:v "$count" "${ENC[@]}" "$WORK/$name.mp4"
done
"$FF" -y -v error -f concat -safe 0 -i "$WORK/editor_list.txt" -loop 1 -framerate 30 -t 4.5 -i "$GFX/cap$EDITOR_CAP.png" \
  -filter_complex "[0]fps=30,scale=1920:1080,setsar=1[v];[1]$(fadecap)[c];[v][c]overlay=0:0:shortest=1,format=yuv420p" \
  "${ENC[@]}" "$WORK/g7.mp4"

chain() { # prefix  output
  local p=$1 outf=$2
  local order=(intro g1 g2 g3 g4 g5 g6 g7 outro)
  local trans=(fade wipeleft wipeleft wipeleft wipeleft wipeleft wipeleft fade)
  local inputs=() fc="" prev="[0:v]" offset=0 k outro_at=0
  for k in "${!order[@]}"; do inputs+=(-i "$WORK/${p}${order[$k]}.mp4"); done
  for ((k=1; k<${#order[@]}; k++)); do
    offset=$(awk "BEGIN{print $offset + $(dur "$WORK/${p}${order[$((k-1))]}.mp4") - $XF}")
    fc+="${prev}[$k:v]xfade=transition=${trans[$((k-1))]}:duration=$XF:offset=$offset[x$k];"
    prev="[x$k]"
    [ "${order[$k]}" = outro ] && outro_at=$offset
  done
  local total win_ms
  total=$(awk "BEGIN{print $offset + $(dur "$WORK/${p}outro.mp4")}")
  win_ms=$(awk "BEGIN{printf \"%d\", ($outro_at + 0.15) * 1000}")
  # Music: the game's own synthesized loop under gameplay, win jingle on the end card.
  fc+="[${#order[@]}:a]atrim=0:$outro_at,afade=t=in:st=0:d=0.4,afade=t=out:st=$(awk "BEGIN{print $outro_at-0.5}"):d=0.5[bed];"
  fc+="[$(( ${#order[@]} + 1 )):a]adelay=${win_ms}|${win_ms}[win];"
  fc+="[bed][win]amix=inputs=2:duration=longest:normalize=0,atrim=0:$total,afade=t=out:st=$(awk "BEGIN{print $total-0.6}"):d=0.6[a]"
  "$FF" -y -v error "${inputs[@]}" -stream_loop -1 -i "$AUDIO/music_2.wav" -i "$AUDIO/sfx_win.wav" \
    -filter_complex "$fc" -map "${prev}" -map "[a]" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -r 30 -movflags +faststart \
    -c:a aac -b:a 192k -ar 44100 -t "$total" "$outf"
  echo "$outf: $(dur "$outf")s"
}
chain "" "$OUT/mirrorwing-promo-1920x1080.mp4"

# ------------------------------------------------------------- vertical
card v_intro v_intro.png 2.5 1
card v_outro v_outro.png 3.2 0
vseg() { # name frame# fit(crop|fit) nframes input-args...
  local name=$1 frame=$2 fit=$3 nframes=$4; shift 4
  local limit=(); [ "$nframes" != 0 ] && limit=(-frames:v "$nframes")
  local square
  if [ "$fit" = crop ]; then square="scale=-2:1080,crop=1080:1080:300:0"; else square="scale=1080:-2,pad=1080:1080:0:(oh-ih)/2:black"; fi
  "$FF" -y -v error "$@" -i "$GFX/v_frame$frame.png" \
    -filter_complex "[0]fps=30,$square,setsar=1[g];[1]loop=-1:1,fps=30[bg];[bg][g]overlay=0:420:shortest=1,format=yuv420p" \
    "${limit[@]}" "${ENC[@]}" "$WORK/v_$name.mp4"
}
for s in "${SEGMENTS[@]}"; do
  read -r name dir count cap <<<"$s"
  vseg "$name" "$cap" crop "$count" -framerate 30 -i "$FRAMES/$dir/f%05d.jpg"
done
vseg g7 $EDITOR_CAP fit 0 -f concat -safe 0 -i "$WORK/editor_list.txt"
chain "v_" "$OUT/mirrorwing-promo-1080x1920.mp4"
rm -rf "$WORK"
