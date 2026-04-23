#!/usr/bin/zsh

# ==============================================================================
# Script: CBR to CBZ Converter
# Description: Converts .cbr (RAR) archives to .cbz (ZIP) archives.
# ==============================================================================

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

# ==============================================================================
# Security: Cleanup on unexpected exit (Ctrl+C, etc.)
# ==============================================================================
trap 'echo -e "\n${RED}[!] Process interrupted. Cleaning up temporary files...${NC}"; [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ] && rm -rf "$tmp_dir"; exit 1' INT TERM HUP

# ==============================================================================
# Help Menu
# ==============================================================================
show_help() {
    echo -e "${CYAN}Usage:${NC} $0 [OPTIONS] <file1.cbr> [file2.cbr ...]"
    echo -e "\n${BLUE}Description:${NC}"
    echo -e "  Converts .cbr (RAR-based) comic archives to .cbz (ZIP-based) archives."
    echo -e "  This process ensures maximum compatibility with e-readers."
    echo -e "\n${BLUE}Options:${NC}"
    echo -e "  -h, --help    Display this help message and exit"
    echo -e "\n${BLUE}Requirements:${NC}"
    echo -e "  p7zip (7z) must be installed."
    echo -e "\n${BLUE}Examples:${NC}"
    echo -e "  $0 \"Spider-Man 01.cbr\""
    echo -e "  $0 *.cbr"
}

# Catch help flags BEFORE any other checks
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# ==============================================================================
# Dependency & Argument Checks
# ==============================================================================
if ! command -v 7z &> /dev/null; then
    echo -e "${RED}Error: '7z' is not installed. Please install p7zip.${NC}"
    exit 1
fi

# We can now redirect the user to the --help flag if they make a mistake
if [[ $# -eq 0 ]]; then
    echo -e "${RED}Error: No CBR files specified.${NC}"
    echo -e "Run '${CYAN}$0 --help${NC}' for more information."
    exit 1
fi

# ==============================================================================
# Main Processing Loop
# ==============================================================================
for cbr in "$@"; do
    # Ensure the file exists and has a .cbr extension
    if [[ ! -f "$cbr" ]]; then
        echo -e "${RED}Warning: '$cbr' not found. Skipping...${NC}"
        continue
    fi

    # Get base name and define output name
    base="${cbr:r}"
    cbz="${base}.cbz"

    ### Security: Prevent overwriting existing CBZ files
    if [[ -f "$cbz" ]]; then
        echo -e "${YELLOW}Warning: Destination file '${cbz:t}' already exists. Skipping to prevent overwrite...${NC}"
        continue
    fi

    echo -e "\n${BLUE}>>> Processing:${NC} ${cbr:t}"

    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/cbr2cbz_XXXXXX")

    ### Security: Ensure the temp dir was actually created
    if [[ ! -d "$tmp_dir" ]]; then
        echo -e "${RED}Critical Error: Failed to create temporary directory. Aborting for this file.${NC}"
        continue
    fi

    echo -e "  ${CYAN}[1/3]${NC} Extracting archive..."
    7z x "$cbr" -o"$tmp_dir" -y > /dev/null

    if [[ $? -ne 0 ]]; then
        echo -e "  ${RED}[!] Extraction failed for $cbr${NC}"
        rm -rf "$tmp_dir"
        continue
    fi

    echo -e "  ${CYAN}[2/3]${NC} Compressing to CBZ..."
    7z a -tzip "$cbz" "$tmp_dir/"* -mx=9 > /dev/null

    if [[ $? -ne 0 ]]; then
        echo -e "  ${RED}[!] Compression failed. Removing incomplete CBZ...${NC}"
        rm -f "$cbz"
        rm -rf "$tmp_dir"
        continue
    fi

    ### Security: Test the integrity of the newly created CBZ archive
    echo -e "  ${CYAN}[3/3]${NC} Verifying archive integrity..."
    7z t "$cbz" > /dev/null

    if [[ $? -eq 0 ]]; then
        echo -e "  ${GREEN}[+] Successfully created:${NC} ${cbz:t}"
    else
        echo -e "  ${RED}[!] Compression failed for $cbz${NC}"
        rm -f "$cbz"
    fi

    rm -rf "$tmp_dir"
    tmp_dir=""
done

echo -e "\n${GREEN}Conversion process finished.${NC}"