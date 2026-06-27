#!/usr/bin/env zsh

# ==============================================================================
# Script: Batch Keyframe Generator
# Description: Generates scxvid keyframe logs for one or multiple video files.
# Usage: ./Keyframes.sh <video1> [video2] [video3] ... or ./Keyframes.sh *.mp4
# ==============================================================================

# Fail a pipeline if ANY stage fails (so a broken ffmpeg is caught, not just scxvid).
set -o pipefail

# Path to the scxvid binary. Override with: SCXVID=/path/to/scxvid ./Keyframes.sh ...
# Falls back to a 'scxvid' found in PATH, then to a sensible default location.
SCXVID="${SCXVID:-$(command -v scxvid 2>/dev/null || echo "$HOME/Softwares/SCXvid-standalone/scxvid")}"

# Check if at least one argument (video file) was provided
if [[ $# -eq 0 ]]; then
    echo "Error: No video files specified."
    echo "Usage: $0 <path_to_video_1> [path_to_video_2 ...]"
    exit 1
fi

# Verify required tooling is available
if ! command -v ffmpeg &> /dev/null; then
    echo "Error: 'ffmpeg' is required but not installed."
    exit 1
fi
if [[ ! -x "$SCXVID" ]]; then
    echo "Error: scxvid binary not found or not executable: '$SCXVID'"
    echo "Set the SCXVID environment variable to its location."
    exit 1
fi

# Iterate over all arguments passed to the script
for video in "$@"; do
    
    # Verify that the current argument is an existing regular file
    if [[ ! -f "$video" ]]; then
        echo "Warning: File '$video' not found. Skipping..."
        continue
    fi

    # Extract the base name of the file using Zsh parameter expansion modifiers:
    # ':t' (tail) extracts the filename, removing the directory path.
    # ':r' (root) removes the file extension.
    base_name="${video:t:r}"
    output_log="${base_name}_keyframes.log"

    echo "------------------------------------------------------------"
    echo "Processing video: $video"
    echo "Output log will be: $output_log"
    echo "------------------------------------------------------------"

    # Execute ffmpeg to decode and scale the video, piping the output to scxvid.
    if ffmpeg -i "$video" -f yuv4mpegpipe -vf scale=640:360 -pix_fmt yuv420p -fps_mode drop - 2>/dev/null | "$SCXVID" "$output_log"; then
        echo "[SUCCESS] Keyframes generated for: $base_name"
    else
        echo "[ERROR] Failed to generate keyframes for: $video"
    fi

done

echo "============================================================"
echo "Batch processing completed."