#!/usr/bin/env bash
#===============================================================================
#
#   MKVCleaner.sh
#
#   Nettoyage sélectif des pistes de fichiers Matroska (.mkv).
#
#   Sélection des pistes audio et sous-titres par langue, par nom de piste
#   (expression régulière), par codec ou par ID. Remux sans réencodage via
#   mkvmerge : la vidéo, les chapitres, les tags et les pièces jointes sont
#   préservés bit à bit sauf demande explicite contraire.
#
#   Les sélecteurs sont résolus fichier par fichier : les IDs de pistes
#   peuvent différer d'un épisode à l'autre, ce que le script gère.
#
#   Dépendances : mkvtoolnix (mkvmerge >= 9.0), jq
#
#   Auteur  : Maxime Ryckebusch
#   Version : 2.0.0
#   Licence : MIT
#
#===============================================================================

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly VERSION="2.0.0"

#===============================================================================
# Configuration
#===============================================================================
TARGETS=()          # dossiers et/ou fichiers passés en arguments positionnels
PATTERN="*.mkv"
OUT_DIR=""
RECURSIVE=0
DRY_RUN=0
ASSUME_YES=0
BACKUP=0
VERBOSE=0
FORCE=0
LIST_ONLY=0

# Sélecteurs (tableaux cumulatifs : chaque option peut être répétée)
KEEP_A_LANG=()  KEEP_A_NAME=()  KEEP_A_CODEC=()
DROP_A_LANG=()  DROP_A_NAME=()  DROP_A_CODEC=()
KEEP_S_LANG=()  KEEP_S_NAME=()  KEEP_S_CODEC=()
DROP_S_LANG=()  DROP_S_NAME=()  DROP_S_CODEC=()
DROP_IDS=()

NO_AUDIO=0
NO_SUBS=0
DROP_ATTACHMENTS=0
DROP_CHAPTERS=0
DROP_TAGS=0

DEFAULT_AUDIO=""
DEFAULT_SUB=""
NO_DEFAULT_SUB=0

# État interne
TMP_FILE=""
DEFAULT_FLAG_OPT="--default-track-flag"   # ajusté selon la version de mkvmerge

COUNT_TOTAL=0
COUNT_OK=0
COUNT_UNCHANGED=0
COUNT_DRY=0
COUNT_FAIL=0

#===============================================================================
# Journalisation
#===============================================================================
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_INFO=$'\033[1;34m'; C_OK=$'\033[1;32m'
    C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
else
    C_RESET='' C_INFO='' C_OK='' C_WARN='' C_ERR='' C_DIM='' C_BOLD=''
fi

log()  { printf '%s[INFO]%s %s\n' "$C_INFO" "$C_RESET" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n' "$C_OK"   "$C_RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2; }
err()  { printf '%s[ERR ]%s %s\n' "$C_ERR"  "$C_RESET" "$*" >&2; }
dbg()  { ((VERBOSE)) && printf '       %s%s%s\n' "$C_DIM" "$*" "$C_RESET" || true; }
die()  { err "$*"; exit 1; }

cleanup() {
    local rc=$?
    [[ -n "$TMP_FILE" && -e "$TMP_FILE" ]] && rm -f -- "$TMP_FILE"
    exit "$rc"
}
trap cleanup EXIT
trap 'err "Interruption."; exit 130' INT TERM

#===============================================================================
# Aide
#===============================================================================
usage() {
    cat <<EOF
${C_BOLD}${SCRIPT_NAME} ${VERSION}${C_RESET} — nettoyage sélectif des pistes de fichiers MKV

${C_BOLD}USAGE${C_RESET}
    ${SCRIPT_NAME} [cibles...] [sélecteurs] [options]

    Une cible est un dossier ou un fichier .mkv. Plusieurs cibles peuvent être
    données, dans n'importe quel ordre par rapport aux options. Sans cible,
    le dossier courant (.) est utilisé.
    Pour une cible dont le nom commence par un tiret, la faire précéder de --.

${C_BOLD}SÉLECTEURS${C_RESET}
    Matrice type × critère. Toutes ces options sont ${C_BOLD}répétables${C_RESET} et cumulatives.

                    langue                 nom (regex)            codec (regex)
    audio  conserver  --keep-audio-lang      --keep-audio-name      --keep-audio-codec
           supprimer  --drop-audio-lang      --drop-audio-name      --drop-audio-codec
    s.-t.  conserver  --keep-sub-lang        --keep-sub-name        --keep-sub-codec
           supprimer  --drop-sub-lang        --drop-sub-name        --drop-sub-codec

    --drop-id <ids>       Supprime des pistes par ID absolu (ex. "2,5"). S'applique
                          à tous les types, y compris vidéo.
    --no-audio            Supprime toutes les pistes audio.
    --no-subs             Supprime toutes les pistes de sous-titres.

    <langue> = liste séparée par des virgules. Les codes ISO-639 à 2 et 3 lettres
               sont équivalents : "fr", "fre" et "fra" désignent la même chose.
    <regex>  = expression régulière POSIX étendue, insensible à la casse,
               appliquée au nom de la piste ou au nom du codec.

${C_BOLD}SÉMANTIQUE${C_RESET}
    Pour un type donné (audio ou sous-titres) :
      • sans sélecteur --keep-* : toutes les pistes sont candidates ;
      • avec au moins un --keep-* : seules les pistes correspondant à l'un des
        --keep-* sont candidates (liste blanche, les critères sont en OU) ;
      • les --drop-* retirent ensuite des candidates (les critères sont en OU).

${C_BOLD}MÉTADONNÉES${C_RESET}
    --default-audio <lang>  Marque « par défaut » la 1re piste audio conservée
                            de cette langue, et démarque les autres.
    --default-sub <lang>    Idem pour les sous-titres.
    --no-default-sub        Retire le drapeau « par défaut » de tous les s.-t.
    --drop-attachments      Supprime les pièces jointes (polices ASS).
    --drop-chapters         Supprime les chapitres.
    --drop-tags             Supprime les tags globaux et de pistes.

${C_BOLD}OPTIONS${C_RESET}
    -d, --dir <chemin>      Ajoute une cible (équivaut à un argument positionnel)
    -p, --pattern <glob>    Motif des fichiers                (défaut : *.mkv)
                            Ignoré pour les cibles qui sont des fichiers.
    -r, --recursive         Parcourt les sous-répertoires
    -o, --out-dir <chemin>  Écrit les résultats ici au lieu de remplacer
    -b, --backup            Conserve l'original en <fichier>.bak
    -l, --list              Inventaire des pistes, sans modification
    -n, --dry-run           Simulation détaillée, aucune écriture
    -y, --yes               Pas de confirmation
    -v, --verbose           Détaille la décision prise pour chaque piste
        --force             Autorise un résultat sans piste audio ou vidéo
    -h, --help              Cette aide
    -V, --version           Version

${C_BOLD}EXEMPLES${C_RESET}
    # Inventaire du dossier courant — toujours commencer par là
    ${SCRIPT_NAME} . -l

    # Inventaire d'un dossier dont le nom contient des espaces et des crochets
    ${SCRIPT_NAME} "../[ReinForce] Muv-Luv Alternative (BDRip 1080p)" -l

    # Supprimer les sous-titres français d'un dossier
    ${SCRIPT_NAME} "../[ReinForce] Muv-Luv Alternative" --drop-sub-lang fre -n

    # Plusieurs cibles, dossiers et fichiers mélangés
    ${SCRIPT_NAME} ./Saison01 ./Saison02 ./bonus.mkv --drop-sub-lang eng

    # Ne garder que l'audio japonais et les sous-titres français
    ${SCRIPT_NAME} . --keep-audio-lang jpn --keep-sub-lang fre -n

    # Supprimer les sous-titres nommés "Signs", "Songs" ou "Forced"
    ${SCRIPT_NAME} . --drop-sub-name '(signs|songs|forced)'

    # Nettoyage complet + repositionnement des drapeaux par défaut
    ${SCRIPT_NAME} ./Serie -r --keep-audio-lang fre,jpn --keep-sub-lang fre \\
                   --default-audio fre --default-sub fre --backup

${C_BOLD}CODES DE RETOUR${C_RESET}
    0 succès    1 au moins un échec    2 usage invalide    130 interruption
EOF
}

#===============================================================================
# Utilitaires
#===============================================================================

# Correspondance de motif insensible à la casse, sans polluer les `case` globaux.
regex_match() {
    local str="$1" re="$2" rc=0
    shopt -s nocasematch
    [[ "$str" =~ $re ]] || rc=1
    shopt -u nocasematch
    return $rc
}

# Normalise un code langue vers une forme canonique.
# Gère les paires bibliographiques/terminologiques ISO-639-2 (fre/fra, ger/deu…)
# et les codes ISO-639-1 (fr, de…), qui coexistent dans les MKV du monde réel.
lang_norm() {
    local l="${1,,}"
    l="${l%%-*}"          # "fr-FR" -> "fr"
    case "$l" in
        fr|fre|fra) echo "fre" ;;
        de|ger|deu) echo "ger" ;;
        nl|dut|nld) echo "dut" ;;
        zh|chi|zho) echo "chi" ;;
        cs|cze|ces) echo "cze" ;;
        el|gre|ell) echo "gre" ;;
        is|ice|isl) echo "ice" ;;
        ms|may|msa) echo "may" ;;
        fa|per|fas) echo "per" ;;
        ro|rum|ron) echo "rum" ;;
        sk|slo|slk) echo "slo" ;;
        cy|wel|cym) echo "wel" ;;
        hy|arm|hye) echo "arm" ;;
        eu|baq|eus) echo "baq" ;;
        my|bur|mya) echo "bur" ;;
        ka|geo|kat) echo "geo" ;;
        mk|mac|mkd) echo "mac" ;;
        bo|tib|bod) echo "tib" ;;
        sq|alb|sqi) echo "alb" ;;
        en|eng)     echo "eng" ;;
        es|spa)     echo "spa" ;;
        it|ita)     echo "ita" ;;
        ja|jpn)     echo "jpn" ;;
        ko|kor)     echo "kor" ;;
        pt|por)     echo "por" ;;
        ru|rus)     echo "rus" ;;
        pl|pol)     echo "pol" ;;
        ar|ara)     echo "ara" ;;
        tr|tur)     echo "tur" ;;
        sv|swe)     echo "swe" ;;
        da|dan)     echo "dan" ;;
        no|nor)     echo "nor" ;;
        fi|fin)     echo "fin" ;;
        hu|hun)     echo "hun" ;;
        he|heb)     echo "heb" ;;
        hi|hin)     echo "hin" ;;
        th|tha)     echo "tha" ;;
        vi|vie)     echo "vie" ;;
        uk|ukr)     echo "ukr" ;;
        bg|bul)     echo "bul" ;;
        hr|hrv)     echo "hrv" ;;
        sr|srp)     echo "srp" ;;
        sl|slv)     echo "slv" ;;
        ca|cat)     echo "cat" ;;
        id|ind)     echo "ind" ;;
        *)          echo "$l" ;;
    esac
}

# Vrai si la langue d'une piste ($1=language, $2=language_ietf) figure dans la
# liste séparée par virgules $3.
lang_in_list() {
    local track_lang="$1" track_ietf="$2" list="$3"
    local a b tok
    a="$(lang_norm "$track_lang")"
    b="$(lang_norm "${track_ietf:-$track_lang}")"
    local IFS=','
    for tok in $list; do
        [[ -z "$tok" ]] && continue
        tok="$(lang_norm "$tok")"
        [[ "$tok" == "$a" || "$tok" == "$b" ]] && return 0
    done
    return 1
}

join_by() { local IFS="$1"; shift; printf '%s' "$*"; }

#===============================================================================
# Analyse des arguments
#===============================================================================
need_value() { [[ -n "${2:-}" ]] || die "L'option $1 attend une valeur."; }

parse_args() {
    while (($# > 0)); do
        case "$1" in
            --keep-audio-lang)  need_value "$1" "${2:-}"; KEEP_A_LANG+=("$2");  shift ;;
            --keep-audio-name)  need_value "$1" "${2:-}"; KEEP_A_NAME+=("$2");  shift ;;
            --keep-audio-codec) need_value "$1" "${2:-}"; KEEP_A_CODEC+=("$2"); shift ;;
            --drop-audio-lang)  need_value "$1" "${2:-}"; DROP_A_LANG+=("$2");  shift ;;
            --drop-audio-name)  need_value "$1" "${2:-}"; DROP_A_NAME+=("$2");  shift ;;
            --drop-audio-codec) need_value "$1" "${2:-}"; DROP_A_CODEC+=("$2"); shift ;;
            --keep-sub-lang)    need_value "$1" "${2:-}"; KEEP_S_LANG+=("$2");  shift ;;
            --keep-sub-name)    need_value "$1" "${2:-}"; KEEP_S_NAME+=("$2");  shift ;;
            --keep-sub-codec)   need_value "$1" "${2:-}"; KEEP_S_CODEC+=("$2"); shift ;;
            --drop-sub-lang)    need_value "$1" "${2:-}"; DROP_S_LANG+=("$2");  shift ;;
            --drop-sub-name)    need_value "$1" "${2:-}"; DROP_S_NAME+=("$2");  shift ;;
            --drop-sub-codec)   need_value "$1" "${2:-}"; DROP_S_CODEC+=("$2"); shift ;;
            --drop-id)          need_value "$1" "${2:-}"; DROP_IDS+=("$2");     shift ;;

            --no-audio)         NO_AUDIO=1 ;;
            --no-subs|--no-subtitles) NO_SUBS=1 ;;
            --drop-attachments) DROP_ATTACHMENTS=1 ;;
            --drop-chapters)    DROP_CHAPTERS=1 ;;
            --drop-tags)        DROP_TAGS=1 ;;
            --default-audio)    need_value "$1" "${2:-}"; DEFAULT_AUDIO="$2"; shift ;;
            --default-sub)      need_value "$1" "${2:-}"; DEFAULT_SUB="$2";   shift ;;
            --no-default-sub)   NO_DEFAULT_SUB=1 ;;

            -d|--dir)           need_value "$1" "${2:-}"; TARGETS+=("$2"); shift ;;
            -p|--pattern)       need_value "$1" "${2:-}"; PATTERN="$2"; shift ;;
            -o|--out-dir)       need_value "$1" "${2:-}"; OUT_DIR="$2"; shift ;;
            -r|--recursive)     RECURSIVE=1 ;;
            -b|--backup)        BACKUP=1 ;;
            -l|--list)          LIST_ONLY=1 ;;
            -n|--dry-run)       DRY_RUN=1; VERBOSE=1 ;;
            -y|--yes)           ASSUME_YES=1 ;;
            -v|--verbose)       VERBOSE=1 ;;
            --force)            FORCE=1 ;;
            -h|--help)          usage; exit 0 ;;
            -V|--version)       printf '%s %s\n' "$SCRIPT_NAME" "$VERSION"; exit 0 ;;
            --)                 shift; TARGETS+=("$@"); break ;;
            -*)                 usage >&2; die "Option inconnue : $1" ;;
            *)                  TARGETS+=("$1") ;;
        esac
        shift
    done

    # Sans cible explicite, on travaille sur le dossier courant.
    (( ${#TARGETS[@]} > 0 )) || TARGETS=(".")

    local t
    for t in "${TARGETS[@]}"; do
        [[ -e "$t" ]] || die "Chemin introuvable : $t"
        [[ -d "$t" || -f "$t" ]] || die "Ni un dossier ni un fichier : $t"
    done

    if [[ -n "$OUT_DIR" ]]; then
        ((BACKUP)) && die "--backup est inutile avec --out-dir."
        mkdir -p -- "$OUT_DIR" || die "Impossible de créer : $OUT_DIR"
    fi

    local id
    for id in "${DROP_IDS[@]}"; do
        [[ "$id" =~ ^[0-9]+(,[0-9]+)*$ ]] || die "--drop-id attend des entiers : '$id'"
    done

    if ((LIST_ONLY == 0)) && ! has_any_selector; then
        usage >&2
        die "Aucun sélecteur fourni : le script ne saurait quoi faire."
    fi
}

has_any_selector() {
    ((NO_AUDIO || NO_SUBS || DROP_ATTACHMENTS || DROP_CHAPTERS || DROP_TAGS || NO_DEFAULT_SUB)) && return 0
    [[ -n "$DEFAULT_AUDIO$DEFAULT_SUB" ]] && return 0
    (( ${#KEEP_A_LANG[@]} + ${#KEEP_A_NAME[@]} + ${#KEEP_A_CODEC[@]} \
     + ${#DROP_A_LANG[@]} + ${#DROP_A_NAME[@]} + ${#DROP_A_CODEC[@]} \
     + ${#KEEP_S_LANG[@]} + ${#KEEP_S_NAME[@]} + ${#KEEP_S_CODEC[@]} \
     + ${#DROP_S_LANG[@]} + ${#DROP_S_NAME[@]} + ${#DROP_S_CODEC[@]} \
     + ${#DROP_IDS[@]} > 0 ))
}

#===============================================================================
# Dépendances
#===============================================================================
check_dependencies() {
    command -v mkvmerge >/dev/null 2>&1 || die \
"mkvmerge introuvable. Installe mkvtoolnix :
    Arch / CachyOS : sudo pacman -S mkvtoolnix-cli
    Debian/Ubuntu  : sudo apt install mkvtoolnix"
    command -v jq >/dev/null 2>&1 || die \
"jq introuvable (nécessaire pour analyser les pistes) :
    Arch / CachyOS : sudo pacman -S jq
    Debian/Ubuntu  : sudo apt install jq"

    # --default-track-flag remplace --default-track depuis mkvtoolnix 68.
    local ver major
    ver="$(mkvmerge --version | grep -oP 'v\K[0-9]+' | head -n1 || echo 0)"
    major="${ver:-0}"
    ((major >= 68)) || DEFAULT_FLAG_OPT="--default-track"
}

#===============================================================================
# Collecte des fichiers
#===============================================================================
collect_files() {
    local target f real
    local -a found=()
    local -A seen=()
    FILES=()

    for target in "${TARGETS[@]}"; do
        found=()
        if [[ -f "$target" ]]; then
            # Cible fichier : prise telle quelle, le motif ne s'applique pas.
            found=("$target")
        else
            local -a find_args=("$target")
            ((RECURSIVE)) || find_args+=(-maxdepth 1)
            find_args+=(-type f -name "$PATTERN" -print0)
            mapfile -d '' -t found < <(find "${find_args[@]}" | sort -z)
        fi

        # Déduplication sur le chemin canonique : deux cibles peuvent se recouvrir.
        for f in "${found[@]}"; do
            real="$(readlink -f -- "$f" 2>/dev/null || printf '%s' "$f")"
            [[ -n "${seen[$real]:-}" ]] && continue
            seen["$real"]=1
            FILES+=("$f")
        done
    done

    ((${#FILES[@]} > 0)) || die "Aucun fichier correspondant à '$PATTERN' dans : ${TARGETS[*]}"
}

#===============================================================================
# Sondage d'un fichier
#   Remplit : T_ID T_TYPE T_LANG T_IETF T_NAME T_CODEC T_DEFAULT T_FORCED
#             META_ATTACH META_CHAPTERS
#===============================================================================
probe_file() {
    local file="$1" json line
    T_ID=() T_TYPE=() T_LANG=() T_IETF=() T_NAME=() T_CODEC=() T_DEFAULT=() T_FORCED=()

    json="$(mkvmerge -J "$file" 2>/dev/null)" || return 1
    [[ -n "$json" ]] || return 1

    # Séparateur US (0x1F) et non tabulation : les caractères « blancs » dans IFS
    # sont fusionnés par `read`, ce qui décale les colonnes dès qu'un champ est
    # vide (piste sans track_name ou sans language_ietf, cas le plus courant).
    while IFS=$'\x1f' read -r id type lang ietf name codec def forced; do
        [[ -n "$id" ]] || continue
        T_ID+=("$id");     T_TYPE+=("$type");   T_LANG+=("$lang")
        T_IETF+=("$ietf"); T_NAME+=("$name");   T_CODEC+=("$codec")
        T_DEFAULT+=("$def"); T_FORCED+=("$forced")
    done < <(jq -r '
        def clean: gsub("[\t\r\n\u001f]"; " ");
        .tracks[] | [
            (.id | tostring),
            (.type // "unknown"),
            (.properties.language // "und"),
            (.properties.language_ietf // ""),
            ((.properties.track_name // "") | clean),
            ((.codec // "") | clean),
            (if .properties.default_track then "1" else "0" end),
            (if .properties.forced_track  then "1" else "0" end)
        ] | join("\u001f")' <<<"$json")

    META_ATTACH="$(jq -r '(.attachments // []) | length' <<<"$json")"
    META_CHAPTERS="$(jq -r '[(.chapters // [])[].num_entries] | add // 0' <<<"$json")"
    return 0
}

#===============================================================================
# Inventaire
#===============================================================================
list_tracks() {
    local file="$1" i
    printf '\n%s%s%s\n' "$C_BOLD" "${file##*/}" "$C_RESET"

    if ! probe_file "$file"; then
        err "  Lecture impossible (fichier corrompu ?)"
        return
    fi

    for i in "${!T_ID[@]}"; do
        local flags=""
        [[ "${T_DEFAULT[$i]}" == "1" ]] && flags+=" (défaut)"
        [[ "${T_FORCED[$i]}"  == "1" ]] && flags+=" (forcé)"
        printf '  ID %-3s %-10s [%-4s] %-28s %s%s%s\n' \
            "${T_ID[$i]}" "${T_TYPE[$i]}" "${T_LANG[$i]}" "${T_CODEC[$i]}" \
            "${T_NAME[$i]:-—}" "$C_DIM" "$flags$C_RESET"
    done
    printf '  %spièces jointes : %s   chapitres : %s%s\n' \
        "$C_DIM" "$META_ATTACH" "$META_CHAPTERS" "$C_RESET"
}

#===============================================================================
# Décision : la piste d'indice $1 doit-elle être conservée ?
#   Renvoie 0 = conserver, 1 = supprimer. Motif dans REASON.
#===============================================================================
should_keep() {
    local i="$1"
    local type="${T_TYPE[$i]}" id="${T_ID[$i]}" lang="${T_LANG[$i]}"
    local ietf="${T_IETF[$i]}" name="${T_NAME[$i]}" codec="${T_CODEC[$i]}"
    REASON=""

    # --- Suppression par ID absolu (tous types) ------------------------------
    local spec tok
    for spec in "${DROP_IDS[@]}"; do
        local IFS=','
        for tok in $spec; do
            if [[ "$tok" == "$id" ]]; then REASON="--drop-id $tok"; return 1; fi
        done
    done

    # --- Sélection des tableaux applicables au type --------------------------
    local -n keep_lang keep_name keep_codec drop_lang drop_name drop_codec
    case "$type" in
        audio)
            ((NO_AUDIO)) && { REASON="--no-audio"; return 1; }
            keep_lang=KEEP_A_LANG; keep_name=KEEP_A_NAME; keep_codec=KEEP_A_CODEC
            drop_lang=DROP_A_LANG; drop_name=DROP_A_NAME; drop_codec=DROP_A_CODEC
            ;;
        subtitles)
            ((NO_SUBS)) && { REASON="--no-subs"; return 1; }
            keep_lang=KEEP_S_LANG; keep_name=KEEP_S_NAME; keep_codec=KEEP_S_CODEC
            drop_lang=DROP_S_LANG; drop_name=DROP_S_NAME; drop_codec=DROP_S_CODEC
            ;;
        *)  # vidéo et autres : conservés sauf --drop-id, déjà traité
            REASON="type non ciblé"; return 0 ;;
    esac

    # --- Liste blanche (si au moins un --keep-* pour ce type) ----------------
    if (( ${#keep_lang[@]} + ${#keep_name[@]} + ${#keep_codec[@]} > 0 )); then
        local matched=0 s
        for s in "${keep_lang[@]}";  do lang_in_list "$lang" "$ietf" "$s" && { matched=1; break; }; done
        if ((!matched)); then
            for s in "${keep_name[@]}";  do regex_match "$name"  "$s" && { matched=1; break; }; done
        fi
        if ((!matched)); then
            for s in "${keep_codec[@]}"; do regex_match "$codec" "$s" && { matched=1; break; }; done
        fi
        if ((!matched)); then REASON="hors liste blanche"; return 1; fi
    fi

    # --- Liste noire ---------------------------------------------------------
    local s
    for s in "${drop_lang[@]}";  do lang_in_list "$lang" "$ietf" "$s" && { REASON="langue '$s'"; return 1; }; done
    for s in "${drop_name[@]}";  do regex_match "$name"  "$s" && { REASON="nom ~ /$s/";   return 1; }; done
    for s in "${drop_codec[@]}"; do regex_match "$codec" "$s" && { REASON="codec ~ /$s/"; return 1; }; done

    return 0
}

#===============================================================================
# Construction du plan de remux pour un fichier
#   Remplit MKV_ARGS et CHANGED
#===============================================================================
build_plan() {
    local i type
    local -a keep_v=() keep_a=() keep_s=() dropped=()
    local n_v=0 n_a=0 n_s=0

    for i in "${!T_ID[@]}"; do
        type="${T_TYPE[$i]}"
        case "$type" in
            video)     n_v=$((n_v + 1)) ;;
            audio)     n_a=$((n_a + 1)) ;;
            subtitles) n_s=$((n_s + 1)) ;;
        esac

        if should_keep "$i"; then
            case "$type" in
                video)     keep_v+=("${T_ID[$i]}") ;;
                audio)     keep_a+=("${T_ID[$i]}") ;;
                subtitles) keep_s+=("${T_ID[$i]}") ;;
            esac
            dbg "garder   ID ${T_ID[$i]} ${type} [${T_LANG[$i]}] ${T_NAME[$i]:-—}"
        else
            dropped+=("${T_ID[$i]}")
            dbg "SUPPRIMER ID ${T_ID[$i]} ${type} [${T_LANG[$i]}] ${T_NAME[$i]:-—}  → $REASON"
        fi
    done

    MKV_ARGS=()
    CHANGED=0
    (( ${#dropped[@]} > 0 )) && CHANGED=1

    # --- Pistes --------------------------------------------------------------
    if ((n_v > 0)); then
        if (( ${#keep_v[@]} == 0 )); then MKV_ARGS+=(--no-video)
        elif (( ${#keep_v[@]} != n_v )); then MKV_ARGS+=(--video-tracks "$(join_by , "${keep_v[@]}")"); fi
    fi
    if ((n_a > 0)); then
        if (( ${#keep_a[@]} == 0 )); then MKV_ARGS+=(--no-audio)
        elif (( ${#keep_a[@]} != n_a )); then MKV_ARGS+=(--audio-tracks "$(join_by , "${keep_a[@]}")"); fi
    fi
    if ((n_s > 0)); then
        if (( ${#keep_s[@]} == 0 )); then MKV_ARGS+=(--no-subtitles)
        elif (( ${#keep_s[@]} != n_s )); then MKV_ARGS+=(--subtitle-tracks "$(join_by , "${keep_s[@]}")"); fi
    fi

    # --- Garde-fou ------------------------------------------------------------
    if (( ${#keep_v[@]} == 0 && ${#keep_a[@]} == 0 )) && ((!FORCE)); then
        REASON="le résultat n'aurait ni vidéo ni audio (utiliser --force pour passer outre)"
        return 1
    fi

    # --- Éléments annexes -----------------------------------------------------
    if ((DROP_ATTACHMENTS)) && [[ "${META_ATTACH:-0}" != "0" ]]; then
        MKV_ARGS+=(--no-attachments); CHANGED=1
    fi
    if ((DROP_CHAPTERS)) && [[ "${META_CHAPTERS:-0}" != "0" ]]; then
        MKV_ARGS+=(--no-chapters); CHANGED=1
    fi
    if ((DROP_TAGS)); then
        MKV_ARGS+=(--no-global-tags --no-track-tags); CHANGED=1
    fi

    # --- Drapeaux « piste par défaut » ---------------------------------------
    apply_default_flags keep_a "$DEFAULT_AUDIO" 0
    apply_default_flags keep_s "$DEFAULT_SUB" "$NO_DEFAULT_SUB"

    return 0
}

# $1 = nom du tableau d'IDs conservés, $2 = langue cible, $3 = tout démarquer
apply_default_flags() {
    local -n kept="$1"
    local target="$2" clear_all="$3"
    [[ -n "$target" || "$clear_all" == "1" ]] || return 0
    (( ${#kept[@]} > 0 )) || return 0

    local id i chosen="" want cur
    if [[ -n "$target" ]]; then
        for id in "${kept[@]}"; do
            for i in "${!T_ID[@]}"; do
                if [[ "${T_ID[$i]}" == "$id" ]] \
                   && lang_in_list "${T_LANG[$i]}" "${T_IETF[$i]}" "$target"; then
                    chosen="$id"; break 2
                fi
            done
        done
        [[ -n "$chosen" ]] || warn "  Aucune piste conservée en '$target' pour le drapeau par défaut."
    fi

    for id in "${kept[@]}"; do
        want=0
        [[ "$id" == "$chosen" ]] && want=1
        cur=0
        for i in "${!T_ID[@]}"; do
            [[ "${T_ID[$i]}" == "$id" ]] && { cur="${T_DEFAULT[$i]}"; break; }
        done
        if [[ "$cur" != "$want" ]]; then
            MKV_ARGS+=("$DEFAULT_FLAG_OPT" "${id}:${want}")
            CHANGED=1
        fi
    done
}

#===============================================================================
# Traitement d'un fichier
#===============================================================================
process_file() {
    local src="$1"
    local base dest dir rc=0
    base="$(basename -- "$src")"

    if ! probe_file "$src"; then
        err "Analyse impossible : $base"
        COUNT_FAIL=$((COUNT_FAIL + 1))
        return
    fi

    ((VERBOSE)) && printf '\n%s%s%s\n' "$C_BOLD" "$base" "$C_RESET"

    if ! build_plan; then
        err "Ignoré — $base : $REASON"
        COUNT_FAIL=$((COUNT_FAIL + 1))
        return
    fi

    if ((CHANGED == 0)); then
        ((VERBOSE)) && dbg "aucune modification nécessaire"
        ((VERBOSE)) || printf '%s[ =  ]%s %s (inchangé)\n' "$C_DIM" "$C_RESET" "$base"
        COUNT_UNCHANGED=$((COUNT_UNCHANGED + 1))
        return
    fi

    if [[ -n "$OUT_DIR" ]]; then
        dest="${OUT_DIR%/}/${base}"
        [[ "$dest" -ef "$src" ]] && { err "Destination identique à la source : $base"
                                      COUNT_FAIL=$((COUNT_FAIL + 1)); return; }
        dir="${OUT_DIR%/}"
    else
        dest="$src"
        dir="$(dirname -- "$src")"
    fi
    TMP_FILE="${dir}/.${base}.remux.$$.tmp.mkv"

    if ((DRY_RUN)); then
        printf '       %s→ mkvmerge -o %q %s %q%s\n' \
            "$C_DIM" "$dest" "${MKV_ARGS[*]}" "$src" "$C_RESET"
        TMP_FILE=""
        COUNT_DRY=$((COUNT_DRY + 1))
        return
    fi

    # --- Remux (0 = succès, 1 = avertissements, >=2 = erreur) ----------------
    mkvmerge --quiet -o "$TMP_FILE" "${MKV_ARGS[@]}" "$src" || rc=$?
    if ((rc >= 2)); then
        err "Échec du remux ($rc) : $base"
        rm -f -- "$TMP_FILE"; TMP_FILE=""
        COUNT_FAIL=$((COUNT_FAIL + 1))
        return
    fi

    # --- Vérification --------------------------------------------------------
    if [[ ! -s "$TMP_FILE" ]] || ! mkvmerge -i "$TMP_FILE" >/dev/null 2>&1; then
        err "Sortie invalide, original intact : $base"
        rm -f -- "$TMP_FILE"; TMP_FILE=""
        COUNT_FAIL=$((COUNT_FAIL + 1))
        return
    fi

    # --- Mise en place -------------------------------------------------------
    touch -r "$src" -- "$TMP_FILE"

    if ((BACKUP)) && [[ -z "$OUT_DIR" ]]; then
        mv -f -- "$src" "${src}.bak" || {
            err "Sauvegarde impossible, abandon : $base"
            rm -f -- "$TMP_FILE"; TMP_FILE=""
            COUNT_FAIL=$((COUNT_FAIL + 1))
            return
        }
    fi

    mv -f -- "$TMP_FILE" "$dest"
    TMP_FILE=""
    ok "$base"
    COUNT_OK=$((COUNT_OK + 1))
}

#===============================================================================
# Confirmation et synthèse
#===============================================================================
confirm() {
    ((ASSUME_YES || DRY_RUN)) && return 0
    local mode answer
    if [[ -n "$OUT_DIR" ]]; then mode="écrits dans '$OUT_DIR'"
    elif ((BACKUP));      then mode="remplacés (originaux en .bak)"
    else                       mode="${C_WARN}remplacés sans sauvegarde${C_RESET}"
    fi
    printf '%s[ ?  ]%s %d fichier(s) seront analysés et %s. Continuer ? [o/N] ' \
        "$C_WARN" "$C_RESET" "${#FILES[@]}" "$mode"
    read -r answer
    [[ "$answer" =~ ^[oOyY]$ ]] || { log "Annulé."; exit 0; }
}

summary() {
    printf '\n%s──────── Synthèse ────────%s\n' "$C_INFO" "$C_RESET"
    printf '  Analysés   : %d\n' "$COUNT_TOTAL"
    ((COUNT_OK > 0))        && printf '  Remuxés    : %s%d%s\n' "$C_OK"  "$COUNT_OK" "$C_RESET"
    ((COUNT_DRY > 0))       && printf '  Simulés    : %d\n' "$COUNT_DRY"
    ((COUNT_UNCHANGED > 0)) && printf '  Inchangés  : %d\n' "$COUNT_UNCHANGED"
    ((COUNT_FAIL > 0))      && printf '  Échecs     : %s%d%s\n' "$C_ERR" "$COUNT_FAIL" "$C_RESET"
    ((COUNT_FAIL == 0))
}

#===============================================================================
# Point d'entrée
#===============================================================================
main() {
    parse_args "$@"
    check_dependencies
    collect_files
    COUNT_TOTAL=${#FILES[@]}

    if ((LIST_ONLY)); then
        log "$COUNT_TOTAL fichier(s) — cible(s) : ${TARGETS[*]}"
        local f
        for f in "${FILES[@]}"; do list_tracks "$f"; done
        printf '\n'
        return 0
    fi

    log "$COUNT_TOTAL fichier(s) — cible(s) : ${TARGETS[*]}"
    ((DRY_RUN)) && log "Mode simulation — aucune écriture"
    confirm

    local f
    for f in "${FILES[@]}"; do process_file "$f"; done

    summary
}

main "$@"
