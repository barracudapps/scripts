#!/bin/bash

################################################################################
# Script:        compressVideo.sh
# Description:   Compress video files in a directory. The user can choose to
#                remove the audio track during compression.
# Usage:         sh ~/Documents/scripts/compressVideo.sh
# Author:        Pierre LAMOTTE
# Date:          18 SEPT 2024
################################################################################

# Vérifier que ffmpeg est installé
if ! command -v ffmpeg &> /dev/null; then
    echo "ffmpeg could not be found. Please install it to proceed."
    echo "You can install ffmpeg by running: brew install ffmpeg"
    exit 1
fi

# Demander à l'utilisateur le dossier à analyser (ou utiliser le dossier courant)
echo "Enter the directory to analyze (default is current directory): "
read input_directory
input_directory="${input_directory:-.}"

# Récupérer tous les types de fichiers vidéo présents dans le répertoire
video_types=$(find "$input_directory" -type f -exec bash -c 'file --mime-type "$1"' _ {} \; | grep -Eo 'video/[^;]+' | cut -d '/' -f2 | sort | uniq)

echo "Available video types in the directory:"
echo "$video_types"

# Demande à l'utilisateur de sélectionner les types de vidéos à traiter
echo "Enter the video types to process (comma-separated, e.g., mp4,mkv or 'all' for all types): "
read selected_types
selected_types="${selected_types,,}"  # Convertir en minuscules

# Demande si l'utilisateur souhaite redimensionner les vidéos
echo "Do you want to resize the videos? (y/n): "
read resize_videos

if [ "$resize_videos" = "y" ]; then
    echo "Enter the target width (e.g., 1920 for 1080p or 1280 for 720p): "
    read target_width
fi

# Demande si l'utilisateur souhaite supprimer la piste audio
echo "Do you want to remove the audio track from the videos? (y/n): "
read remove_audio

# Créer le sous-dossier "originals" pour déplacer les fichiers originaux
originals_folder="$input_directory/originals"
mkdir -p "$originals_folder"

# Fonction pour compresser les vidéos
compress_video() {
    local input_file="$1"
    local output_file="${input_file%.*}_compressed.${input_file##*.}"
    
    # Options de compression de base
    ffmpeg_cmd="ffmpeg -i \"$input_file\" -c:v libx264 -crf 23 -preset fast"
    
    # Redimensionnement si nécessaire
    if [ "$resize_videos" = "y" ]; then
        ffmpeg_cmd="$ffmpeg_cmd -vf scale=$target_width:-2"
    fi
    
    # Suppression de la piste audio si nécessaire
    if [ "$remove_audio" = "y" ]; then
        ffmpeg_cmd="$ffmpeg_cmd -an"
    fi
    
    # Ajouter le chemin de sortie
    ffmpeg_cmd="$ffmpeg_cmd \"$output_file\""
    
    # Exécuter la commande
    echo "Compressing: $input_file"
    eval $ffmpeg_cmd
    
    # Vérifier si la compression a réussi
    if [ $? -eq 0 ]; then
        echo "Compression completed for $input_file"
        
        # Déplacer le fichier original dans le sous-dossier "originals"
        mv "$input_file" "$originals_folder"
        echo "Moved original file to $originals_folder"
    else
        echo "Compression failed for $input_file"
    fi
}

# Trouver et compresser les fichiers vidéo
if [ "$selected_types" = "all" ]; then
    for video_file in "$input_directory"/*; do
        if file --mime-type "$video_file" | grep -q "video/"; then
            compress_video "$video_file"
        fi
    done
else
    IFS=',' read -ra types_array <<< "$selected_types"
    for ext in "${types_array[@]}"; do
        for video_file in "$input_directory"/*."$ext"; do
            if [ -f "$video_file" ]; then
                compress_video "$video_file"
            fi
        done
    done
fi
