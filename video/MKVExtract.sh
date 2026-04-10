#!/bin/zsh

# ==============================================================================
# Colors for console output
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
PURPLE='\033[0;35m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# ==============================================================================
# Dependency Check
# ==============================================================================
if ! command -v mkvmerge &> /dev/null || ! command -v jq &> /dev/null || ! command -v ffprobe &> /dev/null; then
    echo -e "${RED}Error: mkvtoolnix, jq, and ffprobe are required to run this script.${NC}"
    exit 1
fi

# ==============================================================================
# User Configuration Prompts
# ==============================================================================
echo -e "${CYAN}=== MKV Extractor (with Delay Detection) ===${NC}"
echo -n "Extract Audio (y/n)? " && read -r want_audio
echo -n "Extract Subtitles (y/n)? " && read -r want_subs
echo -n "Extract Fonts (y/n)? " && read -r want_fonts
echo -n "Language Filter (e.g., jpn, fre) [Leave empty for ALL]: " && read -r target_lang

# Dictionary mapping codec IDs to file extensions
typeset -A ext_map
ext_map=(
    "A_AAC" "aac" "A_AC3" "ac3" "A_EAC3" "eac3" "A_FLAC" "flac" "A_OPUS" "opus"
    "S_TEXT/ASS" "ass" "S_TEXT/SSA" "ssa" "S_TEXT/UTF8" "srt" "S_HDMV/PGS" "sup"
)

# ==============================================================================
# Main Processing Loop
# ==============================================================================
for f in *.mkv; do
    # Skip if no mkv files are found (prevents literal '*.mkv' loop)
    [[ -e "$f" ]] || continue
    
    echo -e "\n${BLUE}>>> Analyzing: $f${NC}"
    base="${f%.mkv}"
    
    # Extract structural metadata as JSON
    json=$(mkvmerge -J "$f")
    
    # Counter for ffprobe stream indexing (audio streams only, starting at 0)
    audio_idx=0
    
    # --------------------------------------------------------------------------
    # 1. PROCESS TRACKS (AUDIO & SUBTITLES)
    # --------------------------------------------------------------------------
    track_args=()
    
    # Parse tracks: id | type | codec_id | language (default 'und') | track_name (default 'no_name')
    lines=(${(f)"$(echo "$json" | jq -r '.tracks[]? | "\(.id)|\(.type)|\(.properties.codec_id)|\(.properties.language // "und")|\(.properties.track_name // "no_name")"')"})
    
    for line in $lines; do
        parts=("${(@s/|/)line}")
        t_id=$parts[1]
        t_type=$parts[2]
        t_codec=$parts[3]
        t_lang=$parts[4]
        
        # Sanitize track name (replace spaces and slashes with underscores)
        t_name=${parts[5]//[ \/]/__}

        # --- Audio Delay Detection ---
        delay_tag=""
        if [[ "$t_type" == "audio" ]]; then
            # Fetch the first Presentation Time Stamp (PTS) using ffprobe
            first_pts=$(ffprobe -v error -select_streams "a:$audio_idx" -show_entries packet=pts_time -of compact=p=0:nk=1 "$f" | head -n 1)
            
            if [[ -n "$first_pts" && "$first_pts" != "0.000000" ]]; then
                # Convert seconds to integer milliseconds using awk for safe float math
                t_delay_ms=$(echo "$first_pts" | awk '{printf "%.0f", $1 * 1000}')
                [[ "$t_delay_ms" -ne 0 ]] && delay_tag="_DELAY_${t_delay_ms}ms"
            fi
            ((audio_idx++))
        fi

        # --- Filter out unwanted tracks ---
        [[ "$t_type" == "video" ]] && continue
        [[ "$t_type" == "audio" && "$want_audio" != "y" ]] && continue
        [[ "$t_type" == "subtitles" && "$want_subs" != "y" ]] && continue
        [[ -n "$target_lang" && "$t_lang" != "$target_lang" ]] && continue

        # --- Build extraction arguments ---
        ext=${ext_map[$t_codec]:-"dat"}
        out="${base}_${t_name}_${t_lang}${delay_tag}.${ext}"
        track_args+=("$t_id:$out")
    done

    # Execute batched track extraction
    if [[ ${#track_args[@]} -gt 0 ]]; then
        echo -e "  ${GREEN}[+]${NC} Extracting tracks..."
        mkvextract "$f" tracks "${track_args[@]}" > /dev/null
    else
        echo -e "  ${GRAY}[-]${NC} No tracks matched the filter criteria."
    fi

    # --------------------------------------------------------------------------
    # 2. PROCESS ATTACHMENTS (FONTS)
    # --------------------------------------------------------------------------
    if [[ "$want_fonts" == "y" ]]; then
        attach_args=()
        
        # Read attachments list safely
        while read -r font_line; do
            [[ -z "$font_line" ]] && continue
            f_id="${font_line%%|*}"
            f_name="${font_line#*|}"
            dest="./$f_name"

            if [[ ! -f "$dest" ]]; then
                echo -e "  ${PURPLE}[*]${NC} Queuing font: $f_name"
                attach_args+=("$f_id:$dest")
            else
                echo -e "  ${GRAY}[-]${NC} Font $f_name already exists locally."
            fi
        done <<< "$(echo "$json" | jq -r '.attachments[]? | "\(.id)|\(.file_name)"')"
        
        # Execute batched font extraction
        if [[ ${#attach_args[@]} -gt 0 ]]; then
            echo -e "  ${GREEN}[+]${NC} Extracting queued fonts..."
            mkvextract "$f" attachments "${attach_args[@]}" > /dev/null
        fi
    fi

done

echo -e "\n${GREEN}Extraction process successfully completed!${NC}"