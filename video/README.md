# 🎬 Video Scripts

This folder contains utilities for processing and analyzing video files.

## 📜 Available Scripts

### 1. `mkv_extractor.sh`
An interactive batch tool to extract tracks (Audio, Subtitles) and attachments (Fonts) from `.mkv` files.
* **Key Feature:** Automatically detects audio delay using `ffprobe` and appends the delay value to the extracted filename.
* **Filtering:** Allows targeting specific languages (e.g., `jpn`, `eng`, `fre`, `etc...`).
* **Usage:** Run the script in video folder.

### 2. `batch_keyframes.sh`
Generates keyframe log files (`_keyframes.log`) for one or multiple videos using `scxvid` and `ffmpeg`.
* **Key Feature:** Supports batch processing with error handling. 
* **Usage:** 
  * Single file: `./batch_keyframes.sh my_video.mp4`
  * Multiple files: `./batch_keyframes.sh video1.mp4 video2.mkv`
  * Wildcards: `./batch_keyframes.sh *.mp4`

## 📦 Required Dependencies
* `mkvtoolnix` (mkvmerge, mkvextract)
* `ffmpeg` / `ffprobe`
* `jq`
* `scxvid` *(Note: Check and adjust the path to the scxvid executable inside the script if necessary)*