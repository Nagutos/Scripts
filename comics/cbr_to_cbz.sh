#!/usr/bin/zsh

# ==============================================================================
# Script: CBR to CBZ Converter
# Description: Converts .cbr (RAR) archives to .cbz (ZIP) archives.
# ==============================================================================

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

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
    tmp_dir="tmp_${base:t}"

    echo -e "\n${BLUE}>>> Processing:${NC} ${cbr:t}"

    mkdir -p "$tmp_dir"

    echo -e "  ${CYAN}[1/2]${NC} Extracting archive..."
    7z x "$cbr" -o"$tmp_dir" -y > /dev/null

    if [[ $? -ne 0 ]]; then
        echo -e "  ${RED}[!] Extraction failed for $cbr${NC}"
        rm -rf "$tmp_dir"
        continue
    fi

    echo -e "  ${CYAN}[2/2]${NC} Compressing to CBZ..."
    7z a -tzip "$cbz" "./$tmp_dir/*" -mx=9 > /dev/null

    if [[ $? -eq 0 ]]; then
        echo -e "  ${GREEN}[+] Successfully created:${NC} ${cbz:t}"
    else
        echo -e "  ${RED}[!] Compression failed for $cbz${NC}"
    fi

    rm -rf "$tmp_dir"
done

echo -e "\n${GREEN}Conversion process finished.${NC}"