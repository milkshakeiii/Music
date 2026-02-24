# Video Generation Process

FFmpeg path: `C:\Users\User\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe`

## Visualizer Rotation (6 segments)

Divide track duration by 6 to get segment length.

| Segment | Visualizer | Filter |
|---------|-----------|--------|
| 1 | showcqt | `[0:a]showcqt=s=1920x1080:fps=30[v]` |
| 2 | showspectrum | `[0:a]showspectrum=s=1920x1080:mode=combined:color=intensity:slide=scroll:scale=cbrt[v]` |
| 3 | vectorscope | `[0:a]avectorscope=s=1920x1080:mode=lissajous_xy:rate=30:draw=line[v]` |
| 4 | showfreqs | `[0:a]showfreqs=s=1920x1080:mode=bar:fscale=log,fps=30[v]` |
| 5 | showvolume | `[0:a]showvolume=w=1920:h=100:rate=30[vol];[vol]pad=1920:1080:0:(1080-ih)/2:black[v]` |
| 6 | ahistogram | `[0:a]ahistogram=s=1920x1080:rate=30[v]` |

## Steps

### 1. Render each segment

For each segment, run (in parallel):

```
ffmpeg -ss <start> -t <segment_length> -i input.wav -filter_complex "<filter>" -map "[v]" -map 0:a -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 192k -shortest -y seg<N>.mp4
```

For the last segment, omit `-t` so it runs to the end.

### 2. Create concat list

```
file 'seg1.mp4'
file 'seg2.mp4'
file 'seg3.mp4'
file 'seg4.mp4'
file 'seg5.mp4'
file 'seg6.mp4'
```

### 3. Combine with original audio

Use the original WAV as audio source (not the segment audio) to avoid glitches at transitions:

```
ffmpeg -f concat -safe 0 -i concat.txt -i input.wav -map 0:v -map 1:a -c:v libx264 -pix_fmt yuv420p -r 30 -c:a aac -b:a 192k -shortest -y output.mp4
```

### 4. (Optional) Add lyrics overlay

Create an ASS subtitle file (`lyrics.ass`) with three styles for multilingual lyrics:

```ass
[Script Info]
Title: Lyrics
ScriptType: v4.00+
WrapStyle: 0
ScaledBorderAndShadow: yes
YCbCr Matrix: None
PlayResX: 1920
PlayResY: 1080

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Chinese,Microsoft YaHei,72,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,3,0,8,10,10,10,1
Style: Pinyin,Microsoft YaHei,40,&H00CCCCCC,&H000000FF,&H00000000,&H80000000,0,1,0,0,100,100,0,0,1,2,0,8,10,10,10,1
Style: English,Microsoft YaHei,36,&H0099CCFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,2,0,8,10,10,10,1
```

Style notes:
- Alignment `8` = top-center
- MarginV controls vertical position from top (Chinese=280, Pinyin=200, English=130)
- Chinese: white, bold, size 72 with 3px outline
- Pinyin: light gray, italic, size 40 with 2px outline
- English: light blue (#99CCFF), size 36 with 2px outline

Each lyric line gets three Dialogue entries (one per style) with the same start/end time:

```ass
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:20.00,0:00:48.00,Chinese,,0,0,280,,独坐幽篁里
Dialogue: 0,0:00:20.00,0:00:48.00,Pinyin,,0,0,200,,Dú zuò yōu huáng lǐ
Dialogue: 0,0:00:20.00,0:00:48.00,English,,0,0,130,,Alone I sit amid the secluded bamboo
```

Then render with a 50% dim overlay + ASS burn-in:

```
ffmpeg -i output.mp4 -filter_complex "[0:v]colorlevels=rimax=0.5:gimax=0.5:bimax=0.5,ass='lyrics.ass'[v]" -map "[v]" -map 0:a -c:v libx264 -pix_fmt yuv420p -r 30 -c:a copy -shortest -y output_lyrics.mp4
```

- `colorlevels=rimax=0.5:gimax=0.5:bimax=0.5` dims the video to 50%
- The ASS path must use forward slashes and escape the colon: `C\:/Users/...`
- Audio is copied (`-c:a copy`) since only the video is being re-encoded

## Important notes

- Always use `-pix_fmt yuv420p` — Windows media player can't play yuv444p
- showfreqs outputs at 25fps by default — must append `,fps=30` to the filter
- showvolume max height is 900 — use `pad` to center it in 1080p frame, not `scale`
- Always use original WAV as audio source in the final combine step to avoid audio glitches at segment boundaries
- All segments should be rendered at 30fps for consistency
