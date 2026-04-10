# 🛠️ Utility Scripts

This project contains various scripts that I use to streamline my workflow, particularly for processing media files.

## 📂 Repository Structure

* **`video/`**: Video file manipulation (MKV extraction, keyframe generation, etc.).
* **`audio/`**: Audio processing (e.g., splitting FLAC files using .cue sheets).
* **`comics/`**: Image and document processing (e.g., converting CBR to CBZ).

## ⚙️ Prerequisites & Dependencies
Most of these scripts rely on open-source command-line tools. Make sure you have the following packages installed depending on the scripts you want to use:

* `ffmpeg` / `ffprobe` (General video/audio processing)
* `mkvtoolnix` (Tools like `mkvmerge` and `mkvextract`)
* `jq` (Command-line JSON processor)
* `scxvid` (Keyframe generation [Original .bat script](https://unanimated.github.io/scxvid.htm))<br>
On linux you must manualy compile [scxvid.c](https://github.com/soyokaze/SCXvid-standalone) : 
`
cc -o scxvid scxvid.c -lxvidcore
`

## General Usage
Before running a script for the first time, make sure it has execution permissions:

```bash
chmod +x path/to/script.sh
./path/to/script.sh