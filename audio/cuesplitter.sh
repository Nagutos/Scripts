#!/usr/bin/zsh

# ==============================================================================
# Script: FLAC Cue Splitter
# Description: Splits FLAC audio files using associated .cue sheets.
#              Supports recursive subdirectory scanning.
# Requirements: ffcuesplitter
# ==============================================================================

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
GRAY='\033[0;37m'
NC='\033[0m'

# ==============================================================================
# Help Menu
# ==============================================================================
show_help() {
    echo -e "${CYAN}Usage:${NC} $0 [OPTIONS] [DIRECTORY...]"
    echo -e "\n${BLUE}Description:${NC}"
    echo -e "  Splits FLAC audio files into individual tracks using .cue sheets."
    echo -e "  Automatically navigates into subdirectories to ensure relative"
    echo -e "  paths inside .cue files resolve correctly."
    echo -e "  The original FLAC and CUE files are deleted after a successful split."
    echo -e "\n${BLUE}Options:${NC}"
    echo -e "  -h, --help    Display this help message and exit"
    echo -e "\n${BLUE}Examples:${NC}"
    echo -e "  $0               (Scans current directory and all subdirectories)"
    echo -e "  $0 ./MyMusic/    (Scans a specific directory recursively)"
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# ==============================================================================
# Dependency Check
# ==============================================================================
if ! command -v ffcuesplitter &> /dev/null; then
    echo -e "${RED}Error: 'ffcuesplitter' is not installed or not in PATH.${NC}"
    exit 1
fi

# ==============================================================================
# Main Processing Loop
# ==============================================================================
# If no arguments are passed, use the current directory (".")
search_dirs=("$@")
if [[ ${#search_dirs[@]} -eq 0 ]]; then
    search_dirs=(".")
fi

echo -e "${BLUE}>>> Starting CUE scanning...${NC}"
cues_found=0

for dir in "${search_dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
        echo -e "${RED}Warning: '$dir' is not a valid directory. Skipping...${NC}"
        continue
    fi

    # Zsh trick: **/*.cue(N.) recursively finds files, (N) prevents error if empty, (.) ensures it's a file
    for cue_path in "$dir"/**/*.cue(N.); do
        ((cues_found++))
        
        # Extract directory and filename from path
        cue_dir="${cue_path:h}"
        cue_file="${cue_path:t}"

        echo -e "\n${CYAN}Processing:${NC} $cue_path"

        # Enter the directory of the .cue file to resolve relative audio paths safely
        pushd "$cue_dir" > /dev/null

        # Run the extraction command (-del handles the cleanup automatically)
        ffcuesplitter -i "$cue_file" -f flac -ce UTF-8 -del > /dev/null 2>&1

        # Check if the command was successful
        if [[ $? -eq 0 ]]; then
            echo -e "  ${GREEN}[+] Successfully split & cleaned:${NC} $cue_dir"
        else
            echo -e "  ${RED}[!] Failed to split:${NC} $cue_file"
        fi

        # Return to the original directory before the next loop iteration
        popd > /dev/null
    done
done

# Final recap
if [[ $cues_found -eq 0 ]]; then
     echo -e "\n${GRAY}[-] No .cue files found in the specified directories.${NC}"
else
     echo -e "\n${GREEN}Finished processing $cues_found .cue file(s).${NC}"
fi