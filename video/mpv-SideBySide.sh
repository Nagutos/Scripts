#!/usr/bin/env zsh

# ==============================================================================
# Script: MPV Side-by-Side Comparator
# Description: Plays two videos side-by-side in a perfectly synced MPV instance.
# Requirements: mpv
# ==============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

show_help() {
    echo -e "${CYAN}Usage:${NC} $0 <video_1> <video_2>"
    echo -e "\n${BLUE}Description:${NC}"
    echo -e "  Launches MPV to compare two videos side-by-side (Split-Screen)."
    echo -e "  Play, pause, and seeking are perfectly synchronized because both"
    echo -e "  videos share the same playback engine."
    echo -e "\n${BLUE}Options:${NC}"
    echo -e "  -h, --help    Display this help message and exit"
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

if ! command -v mpv &> /dev/null; then
    echo -e "${RED}Error: 'mpv' is required but not installed.${NC}"
    exit 1
fi

if [[ $# -lt 2 ]]; then
    echo -e "${RED}Error: You must provide exactly two video files.${NC}"
    echo -e "Run '${CYAN}$0 --help${NC}' for more info."
    exit 1
fi

vid1="$1"
vid2="$2"

if [[ ! -f "$vid1" ]]; then echo -e "${RED}Error: File '$vid1' not found.${NC}"; exit 1; fi
if [[ ! -f "$vid2" ]]; then echo -e "${RED}Error: File '$vid2' not found.${NC}"; exit 1; fi

echo -e "${BLUE}>>> Launching Side-by-Side Comparison...${NC}"
echo -e "  ${CYAN}[Left]${NC}  ${vid1:t}"
echo -e "  ${CYAN}[Right]${NC} ${vid2:t}"
echo -e "\n${GREEN}Tip: Use SPACE to pause and '.' or ',' to go frame-by-frame on both videos simultaneously!${NC}"

# mpv charge la vidéo 1, ajoute la vidéo 2 en fichier externe, 
# puis utilise lavfi-complex pour les coller horizontalement (hstack).
# --pause permet de lancer MPV en pause pour avoir le temps de s'installer.
mpv "$vid1" --external-file="$vid2" --lavfi-complex="[vid1][vid2]hstack[vo]" --pause > /dev/null 2>&1