#!/usr/bin/env zsh

# --- CONFIGURATION DES CHEMINS ---
X265_PATH="$HOME/Softwares/x265-aMod-Djatom"
X264_PATH="$HOME/Softwares/x264-aMod-Dajtom"

# --- COULEURS ---
GREEN='\033[0;32m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
RED='\033[0;31m'
NC='\033[0m'

# --- FONCTIONS D'ENCODAGE ---

encode_video_x265() {
    local input=$1
    local output="${input:r}_x265.mkv"
    echo -e "${BLUE}>>> Encoding Video (x265):${NC} $input"
    
    if [[ "${input:e}" == "vpy" ]]; then
        vspipe -y "$input" - | $X265_PATH --y4m --preset veryslow --crf 17 --colorprim bt709 --transfer bt709 --colormatrix bt709 --aq-mode 3 --aq-strength 0.8 --psy-rd 1.20 --psy-rdoq 0.10 --output-depth 10 -o "$output" -
    else
        ffmpeg -i "$input" -loglevel error -f yuv4mpegpipe - | $X265_PATH --y4m --preset veryslow --crf 17 --colorprim bt709 --transfer bt709 --colormatrix bt709 --aq-mode 3 --aq-strength 0.8 --psy-rd 1.20 --psy-rdoq 0.10 --output-depth 10 -o "$output" -
    fi
}

encode_video_x264() {
    local input=$1
    local output="${input:r}_x264.mkv"
    echo -e "${BLUE}>>> Encoding Video (x264):${NC} $input"
    
    if [[ "${input:e}" == "vpy" ]]; then
        vspipe -y "$input" - | $X264_PATH --y4m --tune animation --preset veryslow --crf 17 --colorprim bt709 --transfer bt709 --colormatrix bt709 --aq-mode 3 --aq-strength 0.8 --fps 24000/1001 --psy-rd 0.90:0.15 --output-depth 10 -o "$output" -
    else
        ffmpeg -i "$input" -loglevel error -f yuv4mpegpipe - | $X264_PATH --y4m --tune animation --preset veryslow --crf 17 --colorprim bt709 --transfer bt709 --colormatrix bt709 --aq-mode 3 --aq-strength 0.8 --fps 24000/1001 --psy-rd 0.90:0.15 --output-depth 10 -o "$output" -
    fi
}

encode_audio_opus() {
    local input=$1
    local output="${input:r}.opus"
    echo -e "${CYAN}>>> Encoding Audio (Opus 192k):${NC} $input"
    ffmpeg -i "$input" -map 0:a:0 -c:a libopus -b:a 192k "$output" -y
}

encode_audio_flac() {
    local input=$1
    local output="${input:r}.flac"
    echo -e "${CYAN}>>> Encoding Audio (FLAC Lossless):${NC} $input"
    ffmpeg -i "$input" -map 0:a:0 -c:a flac "$output" -y
}

# --- PARSEUR DE COMMANDES ---

show_help() {
    echo -e "${BLUE}Usage:${NC} enco [options] <fichier_ou_script.vpy>"
    echo -e "\n${CYAN}Options Vidéo:${NC}"
    echo "  -v, --x265    Encoder en x265 (Profil Djatom)"
    echo "  -V, --x264    Encoder en x264 (Profil Djatom Animation)"
    echo -e "\n${CYAN}Options Audio:${NC}"
    echo "  -a, --opus    Encoder l'audio en Opus"
    echo "  -A, --flac    Encoder l'audio en FLAC"
    echo -e "\n${CYAN}Raccourcis pratiques:${NC}"
    echo "  -av ou -va    Fait la vidéo x265 ET l'audio Opus"
    echo "  -aV ou -Va    Fait la vidéo x264 ET l'audio Opus"
}

# Initialisation des variables
do_x265=false
do_x264=false
do_opus=false
do_flac=false
file=""

# Analyse intelligente des arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--x265) do_x265=true ;;
        -V|--x264) do_x264=true ;;
        -a|--opus) do_opus=true ;;
        -A|--flac) do_flac=true ;;
        
        # --- Raccourcis combinés ---
        -av|-va)   do_x265=true; do_opus=true ;;
        -aV|-Va)   do_x264=true; do_opus=true ;;
        -Av|-vA)   do_x265=true; do_flac=true ;;
        -AV|-VA)   do_x264=true; do_flac=true ;;
        
        -h|--help) show_help; exit 0 ;;
        -*) echo -e "${RED}Option non reconnue : $1${NC}"; exit 1 ;;
        *) file="$1" ;;
    esac
    shift # Passe à l'argument suivant
done

# Vérification finale
if [[ -z "$file" ]]; then
    echo -e "${RED}Erreur : Aucun fichier spécifié.${NC}"
    show_help
    exit 1
fi

if [[ ! -f "$file" ]]; then
    echo -e "${RED}Erreur : Le fichier '$file' n'existe pas.${NC}"
    exit 1
fi

# Exécution des tâches
[[ "$do_x265" == true ]] && encode_video_x265 "$file"
[[ "$do_x264" == true ]] && encode_video_x264 "$file"
[[ "$do_opus" == true ]] && encode_audio_opus "$file"
[[ "$do_flac" == true ]] && encode_audio_flac "$file"

echo -e "\n${GREEN}Terminé !${NC}"