# 🎬 Video Scripts

This folder contains utilities for processing and analyzing video files.

## 📜 Available Scripts

### 1. `MKVExtract.sh`
An interactive batch tool to extract tracks (Audio, Subtitles) and attachments (Fonts) from `.mkv` files.
* **Key Feature:** Automatically detects audio delay using `ffprobe` and appends the delay value to the extracted filename.
* **Filtering:** Allows targeting specific languages (e.g., `jpn`, `eng`, `fre`, `etc...`).
* **Usage:** Run the script from inside the folder containing the `.mkv` files.

### 2. `Keyframes.sh`
Generates keyframe log files (`_keyframes.log`) for one or multiple videos using `scxvid` and `ffmpeg`.
* **Key Feature:** Supports batch processing with error handling.
* **Configuration:** The `scxvid` binary is auto-detected from `PATH`. Otherwise set it explicitly:
  `SCXVID=/path/to/scxvid ./Keyframes.sh *.mp4`
* **Usage:**
  * Single file: `./Keyframes.sh my_video.mp4`
  * Multiple files: `./Keyframes.sh video1.mp4 video2.mkv`
  * Wildcards: `./Keyframes.sh *.mp4`

### 3. `encode.sh`
A flexible video/audio encoder wrapping custom `x265`/`x264` builds and `ffmpeg`.
* **Inputs:** Standard media files or VapourSynth scripts (`.vpy`, piped through `vspipe`).
* **Configuration:** Encoder paths default to `~/Softwares/...` and can be overridden via the
  `X265_PATH` / `X264_PATH` environment variables.
* **Usage:**
  * x265 video: `./encode.sh -v input.mkv`
  * x264 video (animation profile): `./encode.sh -V input.mkv`
  * Audio Opus / FLAC: `./encode.sh -a input.mkv` / `./encode.sh -A input.mkv`
  * Combined (video + audio): `./encode.sh -av input.vpy`
  * Full options: `./encode.sh --help`

### 4. `mpv-SideBySide.sh`
Plays two videos side-by-side in a single, perfectly synchronized MPV instance (split-screen).
* **Key Feature:** Play, pause and seeking stay in sync because both videos share one playback engine.
* **Usage:** `./mpv-SideBySide.sh video_1.mkv video_2.mkv`

## 📦 Required Dependencies
* `mkvtoolnix` (mkvmerge, mkvextract) — for `MKVExtract.sh`
* `ffmpeg` / `ffprobe` — most scripts
* `jq` — for `MKVExtract.sh`
* `scxvid` — for `Keyframes.sh` *(set the `SCXVID` env var if not in `PATH`)*
* `x265` / `x264` / `vspipe` — for `encode.sh`
* `mpv` — for `mpv-SideBySide.sh`
