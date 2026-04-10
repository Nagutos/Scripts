#!/usr/bin/zsh

# ==============================================================================
# Script: Batch Keyframe Generator
# Description: Generates scxvid keyframe logs for one or multiple video files.
# Usage: ./script.zsh <video1> [video2] [video3] ... or ./script.zsh *.mp4
# ==============================================================================

# Check if at least one argument (video file) was provided
if [[ $# -eq 0 ]]; then
    echo "Error: No video files specified."
    echo "Usage: $0 <path_to_video_1> [path_to_video_2 ...]"
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
    ffmpeg -i "$video" -f yuv4mpegpipe -vf scale=640:360 -pix_fmt yuv420p -fps_mode drop - 2>/dev/null | /home/nagutos/Softwares/SCXvid-standalone/scxvid "$output_log"

    # Check the exit status of the previous pipeline to confirm success
    if [[ $? -eq 0 ]]; then
        echo "[SUCCESS] Keyframes generated for: $base_name"
    else
        echo "[ERROR] Failed to generate keyframes for: $video"
    fi

done

echo "============================================================"
echo "Batch processing completed."