#!/bin/bash
# master_cd.sh — batch-master a folder of WAVs into CD-ready 44.1kHz/16-bit files
# with consistent loudness, car-friendly dynamics, true-peak limiting, and dither.
#
# Usage (Git Bash):  ./master_cd.sh <input_dir> <output_dir> [target_lufs] [max_lra]
# Example:           ./master_cd.sh . CD_master -12 8.5
#
# Requires: ffmpeg (with libsoxr), awk. Processing chain per track (all in float,
# one pass, no intermediate files):
#   1. pre-gain to target LUFS (from a first measurement pass)
#   2. gentle 2:1 "leveler" compressor (slow attack/release, RMS detection);
#      threshold auto-calibrated per track until loudness range (LRA) <= max_lra
#   3. trim gain back to target (compression changes loudness)
#   4. upsample 4x (176.4k, soxr) -> lookahead limiter, ceiling -1 dBTP
#   5. downsample to 44.1k (soxr) + TPDF high-passed dither to 16-bit
# Ends with a verification pass printing LUFS / true peak / LRA / total minutes.

IN="${1:?usage: master_cd.sh <input_dir> <output_dir> [target_lufs] [max_lra]}"
OUTDIR="${2:?usage: master_cd.sh <input_dir> <output_dir> [target_lufs] [max_lra]}"
TARGET="${3:--12}"     # integrated loudness target, LUFS (-14 = streaming standard, -12 = hot-ish CD)
MAXLRA="${4:-8.5}"     # max loudness range, LU (~8-9 suits noisy car listening)
CEIL=0.891             # limiter ceiling, linear (0.891 = -1 dBTP)
THR_START=-18          # leveler threshold search start, dBFS
THR_FLOOR=-26          # deepest threshold before giving up (best effort)

mkdir -p "$OUTDIR" || exit 1

json_field() { # stream-in loudnorm json, extract field $1
  awk -v k="\"$1\"" '$1==k{gsub(/[",]/,"");print $3}'
}

measure_plain() { # file -> integrated LUFS
  ffmpeg -hide_banner -nostats -i "$1" -af loudnorm=print_format=json -f null - 2>&1 |
    json_field input_i
}

comp_chain() { # pregain_db thr_db -> leveler filter string
  local lin
  lin=$(awk -v d="$2" 'BEGIN{printf "%.6f", 10^(d/20)}')
  echo "volume=${1}dB,acompressor=threshold=${lin}:ratio=2:attack=250:release=1000:detection=rms"
}

measure_comp() { # file pregain_db thr_db -> "I LRA" after leveler
  ffmpeg -hide_banner -nostats -i "$1" -af "$(comp_chain "$2" "$3"),loudnorm=print_format=json" -f null - 2>&1 |
    awk '/"input_i"/{gsub(/[",]/,"");i=$3} /"input_lra"/{gsub(/[",]/,"");l=$3} END{print i, l}'
}

shopt -s nullglob
for f in "$IN"/*.wav; do
  base=$(basename "$f")
  [ -e "$OUTDIR/$base" ] && [ "$(cd "$IN" && pwd)" = "$(cd "$OUTDIR" && pwd)" ] && { echo "SKIP (in==out): $base"; continue; }

  i0=$(measure_plain "$f")
  [ -z "$i0" ] && { echo "MEASURE FAILED: $base"; continue; }
  g=$(awk -v t="$TARGET" -v i="$i0" 'BEGIN{printf "%.2f", t-i}')

  thr=$THR_START
  read -r mi mlra < <(measure_comp "$f" "$g" "$thr")
  while awk -v l="$mlra" -v m="$MAXLRA" 'BEGIN{exit !(l>m)}' && [ "$thr" -gt "$THR_FLOOR" ]; do
    thr=$((thr-2))
    read -r mi mlra < <(measure_comp "$f" "$g" "$thr")
  done

  trim=$(awk -v t="$TARGET" -v i="$mi" 'BEGIN{printf "%.2f", t-i}')

  ffmpeg -y -hide_banner -nostats -i "$f" \
    -af "$(comp_chain "$g" "$thr"),volume=${trim}dB,aresample=osr=176400:resampler=soxr,alimiter=limit=${CEIL}:attack=5:release=100:level=false,aresample=osr=44100:osf=s16:resampler=soxr:dither_method=triangular_hp" \
    -c:a pcm_s16le "$OUTDIR/$base" 2>&1 | grep -Ei "error|invalid"
  echo "RENDERED $base | src I ${i0} | pregain ${g} dB | thr ${thr} dB | post-comp I ${mi}, LRA ${mlra} | trim ${trim} dB"
done

echo "=== VERIFY ==="
total=0
for f in "$OUTDIR"/*.wav; do
  read -r vi vtp vlra < <(ffmpeg -hide_banner -nostats -i "$f" -af loudnorm=print_format=json -f null - 2>&1 |
    awk '/"input_i"/{gsub(/[",]/,"");i=$3} /"input_tp"/{gsub(/[",]/,"");t=$3} /"input_lra"/{gsub(/[",]/,"");l=$3} END{print i, t, l}')
  dur=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f")
  total=$(awk -v a="$total" -v b="$dur" 'BEGIN{printf "%.1f", a+b}')
  printf "%-45s I=%s LUFS  TP=%s dBTP  LRA=%s LU  dur=%.0fs\n" "$(basename "$f")" "$vi" "$vtp" "$vlra" "$dur"
done
awk -v s="$total" 'BEGIN{printf "TOTAL: %.1f min (CD-R limit: 80)\n", s/60}'
