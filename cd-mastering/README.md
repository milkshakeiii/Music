# CD Compilation Mastering Process — "Silly Songs from SPACE"

How the 15 mixed-format WAVs were turned into consistent, car-friendly,
Red-Book-ready CD audio (July 2026). The whole process is automated in
[`master_cd.sh`](master_cd.sh) (run from Git Bash; needs ffmpeg with libsoxr):

```bash
./master_cd.sh <input_dir> <output_dir> [target_lufs] [max_lra]
./master_cd.sh . CD_master -12 8.5     # what was used for this disc
```

## The problem

The source tracks varied in every parameter:

- **Sample rate / bit depth**: mix of 44.1k & 48k, 24-bit int & 32-bit float
- **Loudness**: −10.6 to −20.4 LUFS integrated (a ~10 dB track-to-track spread)
- **True peaks**: several tracks over 0 dBTP (up to +5.2) — would clip at 16-bit
- **Dynamics**: loudness range (LRA) 5.7–13.7 LU; the dynamic tracks were mixed
  on headphones and their quiet passages sink under road noise in a car

## The chain (per track, single 32-bit-float pass, no intermediate files)

```
measure (EBU R128) → pre-gain → leveler → trim gain → 4× upsample → true-peak limiter → 44.1k downsample → dither → 16-bit WAV
```

1. **Measure** integrated loudness (LUFS), true peak (dBTP), and loudness range
   (LRA) with ffmpeg's `loudnorm` filter in analysis mode.
2. **Pre-gain** = target − measured LUFS (plain gain, transparent).
3. **Leveler** — dynamic-range reduction for car listening: `acompressor`,
   ratio 2:1, RMS detection, slow attack/release (250 ms / 1000 ms) so it rides
   whole passages instead of squashing transients. The threshold is
   auto-calibrated per track: start at −18 dBFS, re-measure LRA, step down 2 dB
   at a time until the track lands at ≤ 8.5 LU (floor −26 dBFS). Tracks already
   inside the LRA target are barely touched by the first threshold.
4. **Trim gain** — compression changes loudness, so a second measured gain
   brings the track back to exactly the target.
5. **True-peak limiter** — `alimiter`, ceiling −1 dBTP (0.891 linear), 5 ms
   lookahead, 100 ms release, **run at 176.4 kHz (4× oversampled)** so
   intersample peaks are actually caught, then downsampled back to 44.1 kHz.
   Both resamples use the SoX resampler (`soxr`).
6. **Dither** — TPDF high-passed (`triangular_hp`) dither applied exactly once,
   at the final float → 16-bit quantization. Everything upstream stays float.
7. **Verify** — every output re-measured (LUFS / dBTP / LRA) plus a total-length
   check against the 80-minute CD-R limit.

The exact ffmpeg filter chain (values substituted per track):

```
volume=<pregain>dB,
acompressor=threshold=<linear>:ratio=2:attack=250:release=1000:detection=rms,
volume=<trim>dB,
aresample=osr=176400:resampler=soxr,
alimiter=limit=0.891:attack=5:release=100:level=false,
aresample=osr=44100:osf=s16:resampler=soxr:dither_method=triangular_hp
```

(`level=false` on alimiter matters — its auto-gain is on by default and would
wreck the calibrated loudness.)

## Parameter choices

| Parameter | Value | Why |
|---|---|---|
| Loudness target | −12 LUFS | Hot-ish CD level for car use; −14 = streaming standard (gentler limiting), −10 = commercial-loud (audible squash) |
| Max LRA | 8.5 LU | Commercial masters run ~4–7; above ~9 quiet passages get lost over road noise |
| TP ceiling | −1.0 dBTP | Safety margin for cheap car-player DACs and lossy rips |
| Compressor | 2:1, 250/1000 ms, RMS | Slow "leveler" behavior — rides sections, leaves transients to the limiter |
| Dither | TPDF high-passed | Correct for 16-bit; noise pushed where ears are least sensitive |

## Results for this disc (July 2026)

All 15 tracks: −12.0 to −12.7 LUFS, true peaks ≤ −0.43 dBTP, LRA 3.4–7.5 LU,
total 47.9 min. Leveler threshold landed at −18 dBFS for every track except
15_Solution (−20, it started at 13.7 LU). 02_closertoyou ended ~0.6 dB quieter
than target — its peaks sat unusually high relative to its loudness, so the
limiter ate some makeup gain; left as-is rather than limit deeper.

## Gotchas / notes for next time

- Measure-then-gain (two `volume` stages from *measured* values) preserves
  dynamics exactly; avoid `loudnorm`'s dynamic mode for music — it gain-rides.
- The limiter is the only nonlinear stage; if a track needs > ~4–5 dB of peak
  reduction, consider a lower loudness target instead of deeper limiting.
- Burn as **Audio CD** (not data/MP3), on **CD-R** (not RW), at moderate speed
  (~16×). Windows Media Player Legacy works; CDBurnerXP allows gapless + CD-Text.
- Kunaki (kunaki.com, $2/disc, min 1) manufactures jewel-case CDs from these
  files as-is. Artwork JPGs *and* their editable HTML sources are in
  `artwork/` — edit the HTML, then re-render with headless Chrome at the exact
  size and convert, e.g.:
  `chrome --headless=new --screenshot=tray.png --window-size=1772,1385 tray.html`
  then `ffmpeg -i tray.png -pix_fmt yuvj444p -q:v 2 tray.jpg`
  (cover/inside: 1423×1411, tray: 1772×1385, disc: 1394×1394).
