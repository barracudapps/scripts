#!/bin/bash

################################################################################
# Script:        compressVideo.sh
# Description:   Compress video files in a directory (H.264, or H.265 with
#                Apple hardware encoding). The user can resize the videos and
#                remove the audio track. Originals are moved to an "originals"
#                sub-folder, except when the compressed file is not smaller.
# Usage:         bash ~/Documents/scripts/compressVideo.sh [directory]
# Author:        Pierre LAMOTTE
# Date:          18 SEPT 2024
################################################################################

shopt -s nullglob

# Vérifier que ffmpeg est installé
if ! command -v ffmpeg &> /dev/null; then
    echo "ffmpeg could not be found. Please install it to proceed."
    echo "You can install ffmpeg by running: brew install ffmpeg"
    exit 1
fi

to_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
human_size() { du -h "$1" | cut -f1 | tr -d ' '; }

# Dossier à analyser : argument, sinon demandé (dossier courant par défaut)
input_directory="$1"
if [[ -z "$input_directory" ]]; then
    read -rp "Enter the directory to analyze (default is current directory): " input_directory
fi
input_directory="${input_directory:-.}"
input_directory="${input_directory/#\~/$HOME}"
if [[ ! -d "$input_directory" ]]; then
    echo "The directory does not exist: $input_directory" >&2
    exit 1
fi

# Lister les vidéos du dossier (non récursif, comme le traitement) et leurs extensions
videos=()
for f in "$input_directory"/*; do
    [[ -f "$f" ]] || continue
    [[ "$f" == *_compressed.* ]] && continue
    if file --brief --mime-type "$f" | grep -q '^video/'; then
        videos+=("$f")
    fi
done

if [[ ${#videos[@]} -eq 0 ]]; then
    echo "No video files found in $input_directory."
    exit 0
fi

echo "Available video types in the directory:"
for f in "${videos[@]}"; do to_lower "${f##*.}"; echo; done | sort | uniq -c

# Demande à l'utilisateur de sélectionner les types de vidéos à traiter
read -rp "Enter the video types to process (comma-separated extensions, e.g., mp4,mov or 'all'): " selected_types
selected_types=$(to_lower "${selected_types:-all}")
selected_types="${selected_types// /}"

# Codec : H.264 (compatible partout) ou H.265 matériel (Apple Silicon, plus petit)
read -rp "Codec: [1] H.264 (max compatibility, default) [2] H.265 hardware (smaller, Apple devices): " codec_choice

read -rp "Do you want to resize the videos? (y/n): " resize_videos
if [[ "$resize_videos" =~ ^[yY] ]]; then
    read -rp "Enter the target width (e.g., 1920 for 1080p or 1280 for 720p): " target_width
    if ! [[ "$target_width" =~ ^[0-9]+$ ]]; then
        echo "Invalid width: $target_width" >&2
        exit 1
    fi
fi

read -rp "Do you want to remove the audio track from the videos? (y/n): " remove_audio

originals_folder="$input_directory/originals"

compress_video() {
    local input_file="$1"
    local output_file="${input_file%.*}_compressed.mp4"
    local cmd=(ffmpeg -hide_banner -loglevel error -stats -nostdin -y -i "$input_file")

    if [[ "$codec_choice" == "2" ]]; then
        cmd+=(-c:v hevc_videotoolbox -q:v 55 -tag:v hvc1)
    else
        cmd+=(-c:v libx264 -crf 23 -preset fast -pix_fmt yuv420p)
    fi

    if [[ "$resize_videos" =~ ^[yY] ]]; then
        # Never upscale: keep the original width if it is already smaller
        cmd+=(-vf "scale='min($target_width,iw)':-2")
    fi

    if [[ "$remove_audio" =~ ^[yY] ]]; then
        cmd+=(-an)
    else
        cmd+=(-c:a aac -b:a 128k)
    fi

    cmd+=(-movflags +faststart "$output_file")

    echo "Compressing: $input_file"
    if ! "${cmd[@]}"; then
        echo "Compression failed for $input_file" >&2
        rm -f "$output_file"
        return 1
    fi

    if (( $(stat -f%z "$output_file") >= $(stat -f%z "$input_file") )); then
        echo "No gain for $input_file ($(human_size "$input_file") -> $(human_size "$output_file")): original kept, output removed."
        rm -f "$output_file"
        return 0
    fi

    echo "Compression completed: $(human_size "$input_file") -> $(human_size "$output_file")"
    mkdir -p "$originals_folder"
    mv "$input_file" "$originals_folder/"
    echo "Moved original file to $originals_folder"
}

IFS=',' read -ra types_array <<< "$selected_types"
for video_file in "${videos[@]}"; do
    ext=$(to_lower "${video_file##*.}")
    if [[ "$selected_types" != "all" ]]; then
        match=false
        for t in "${types_array[@]}"; do
            [[ "$ext" == "${t#.}" ]] && match=true
        done
        $match || continue
    fi
    compress_video "$video_file"
done

echo "All videos processed."
