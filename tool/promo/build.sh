#!/usr/bin/env bash
# Assembles the Wave Rush promo videos (landscape 1920x1080 + vertical
# 1080x1920) from lockstep-captured 30fps frames, overlay PNGs and the
# game's own music. Usage: bash build.sh
set -euo pipefail
cd "$(dirname "$0")"
FF="$(cat ../ffmpeg/ffpath.txt)"
FP="$(dirname "$FF")/ffprobe.exe"
LOCK=lock
GFX=gfx
AUDIO=/c/Users/Hi/.gemini/antigravity/scratch/wave-rush-app/assets/audio
OUT=out
mkdir -p seg "$OUT"
ENC=(-c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -r 30 -an)
XF=0.3   # crossfade length between segments

# Gameplay segments: name  frame-dir  start-frame  frame-count  caption#
SEGMENTS=(
  "g1 L3  15  120 1"
  "g2 L9  150 135 2"
  "g3 L5  180 90  3"
  "g4 L12 165 120 4"
)

# ------------------------------------------------------------ landscape
card() { # name png seconds fade-from-black(0/1)
  local vf="format=yuv420p"
  [ "$4" = 1 ] && vf="fade=t=in:st=0:d=0.5,$vf"
  "$FF" -y -v error -loop 1 -framerate 30 -t "$3" -i "$GFX/$2" -vf "$vf" "${ENC[@]}" "seg/$1.mp4"
}
card intro intro.png 2.5 1
card outro outro.png 3.2 0

for s in "${SEGMENTS[@]}"; do
  read -r name dir start count cap <<<"$s"
  secs=$(awk "BEGIN{print $count/30}")
  "$FF" -y -v error -framerate 30 -start_number "$start" -i "$LOCK/$dir/f%05d.jpg" \
    -loop 1 -framerate 30 -t "$secs" -i "$GFX/cap$cap.png" \
    -filter_complex "[1]format=rgba,fade=t=in:st=0.25:d=0.35:alpha=1[c];[0][c]overlay=0:0:shortest=1,format=yuv420p" \
    -frames:v "$count" "${ENC[@]}" "seg/$name.mp4"
done

# Editor: stop-motion, 0.3s per placement, last frame held longer.
n=$(ls "$LOCK/editor"/*.jpg | wc -l)
{ i=0; for f in "$LOCK/editor"/*.jpg; do i=$((i+1)); echo "file '$(cygpath -m "$(pwd)/$f")'"; if [ $i -eq $n ]; then echo "duration 0.9"; else echo "duration 0.3"; fi; done; echo "file '$(cygpath -m "$(pwd)/$f")'"; } > seg/editor_list.txt
"$FF" -y -v error -f concat -safe 0 -i seg/editor_list.txt -loop 1 -framerate 30 -t 4.5 -i "$GFX/cap5.png" \
  -filter_complex "[0]fps=30,scale=1920:1080,setsar=1[v];[1]format=rgba,fade=t=in:st=0.25:d=0.35:alpha=1[c];[v][c]overlay=0:0:shortest=1,format=yuv420p" \
  "${ENC[@]}" seg/g5.mp4
# Home screen menu (shows Endless / Skins buttons).
"$FF" -y -v error -framerate 30 -start_number 30 -i "$LOCK/home/f%05d.jpg" -loop 1 -framerate 30 -t 3 -i "$GFX/cap6.png" \
  -filter_complex "[1]format=rgba,fade=t=in:st=0.25:d=0.35:alpha=1[c];[0][c]overlay=0:0:shortest=1,format=yuv420p" \
  -frames:v 90 "${ENC[@]}" seg/g6.mp4

dur() { "$FP" -v error -show_entries format=duration -of csv=p=0 "$1"; }

# xfade chain over: intro g1..g6 outro
chain() { # prefix  output
  local p=$1 outf=$2
  local order=(intro g1 g2 g3 g4 g5 g6 outro)
  local trans=(fade wipeleft wipeleft wipeleft wipeleft wipeleft fade)
  local inputs=() fc="" prev="[0:v]" offset=0 k
  for k in "${!order[@]}"; do inputs+=(-i "seg/${p}${order[$k]}.mp4"); done
  for ((k=1; k<${#order[@]}; k++)); do
    offset=$(awk "BEGIN{print $offset + $(dur "seg/${p}${order[$((k-1))]}.mp4") - $XF}")
    fc+="${prev}[$k:v]xfade=transition=${trans[$((k-1))]}:duration=$XF:offset=$offset[x$k];"
    prev="[x$k]"
    [ "${order[$k]}" = outro ] && OUTRO_AT=$offset
  done
  local total
  total=$(awk "BEGIN{print $offset + $(dur "seg/${p}outro.mp4")}")
  # Music: the in-game track looped under gameplay, the win jingle on the
  # end card.
  local win_ms
  win_ms=$(awk "BEGIN{printf \"%d\", ($OUTRO_AT + 0.15) * 1000}")
  fc+="[${#order[@]}:a]atrim=0:$OUTRO_AT,afade=t=in:st=0:d=0.4,afade=t=out:st=$(awk "BEGIN{print $OUTRO_AT-0.5}"):d=0.5[bed];"
  fc+="[$(( ${#order[@]} + 1 )):a]adelay=${win_ms}|${win_ms}[win];"
  fc+="[bed][win]amix=inputs=2:duration=longest:normalize=0,atrim=0:$total,afade=t=out:st=$(awk "BEGIN{print $total-0.6}"):d=0.6[a]"
  "$FF" -y -v error "${inputs[@]}" -stream_loop -1 -i "$AUDIO/m_ig1.mp3" -i "$AUDIO/m_win.mp3" \
    -filter_complex "$fc" -map "${prev}" -map "[a]" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -r 30 -movflags +faststart \
    -c:a aac -b:a 192k -ar 44100 -t "$total" "$outf"
  echo "$outf: $(dur "$outf")s"
}
[ -f "$OUT/wave-rush-promo-1920x1080.mp4" ] || chain "" "$OUT/wave-rush-promo-1920x1080.mp4"

# ------------------------------------------------------------- vertical
card v_intro v_intro.png 2.5 1
card v_outro v_outro.png 3.2 0
vseg() { # name  input-args...  (gameplay crop: 1080x1080 square with the wave near the left third)
  local name=$1 frame=$2 fit=$3 nframes=$4; shift 4
  local limit=(); [ "$nframes" != 0 ] && limit=(-frames:v "$nframes")
  local square
  if [ "$fit" = crop ]; then square="scale=-2:1080,crop=1080:1080:300:0"; else square="scale=1080:-2,pad=1080:1080:0:(oh-ih)/2:black"; fi
  "$FF" -y -v error "$@" -i "$GFX/v_frame$frame.png" \
    -filter_complex "[0]fps=30,$square,setsar=1[g];[1]loop=-1:1,fps=30[bg];[bg][g]overlay=0:420:shortest=1,format=yuv420p" \
    "${limit[@]}" "${ENC[@]}" "seg/v_$name.mp4"
}
for s in "${SEGMENTS[@]}"; do
  read -r name dir start count cap <<<"$s"
  vseg "$name" "$cap" crop "$count" -framerate 30 -start_number "$start" -i "$LOCK/$dir/f%05d.jpg"
done
vseg g5 5 fit 0 -f concat -safe 0 -i seg/editor_list.txt
vseg g6 6 fit 90 -framerate 30 -start_number 30 -i "$LOCK/home/f%05d.jpg"
chain "v_" "$OUT/wave-rush-promo-1080x1920.mp4"
