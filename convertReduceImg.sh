#!/bin/bash

################################################################################
# Script:	convertReduceImg.sh
# Description:	Converts and/or reduces images in the current directory.
# Usage:	sh ~/Documents/scripts/convertReduceImg.sh
# Author:	Pierre LAMOTTE
# Date:		05 JUL 2024
################################################################################

# Fonction pour lister les types de fichiers image présents dans le dossier
list_image_types() {
    find "$1" -type f | grep -Eo '\.(png|jpg|jpeg|heic|webp)$' | sed 's/.*\.//' | sort | uniq
}

# Fonction pour convertir et optimiser les images
convert_and_optimize() {
    local src_dir="$1"
    local src_type="$2"
    local dest_type="$3"
    local optimize="$4"
    local target_size="$5"
    local min_quality="$6"

    local files=($(find "$src_dir" -type f -iname "*.$src_type"))
    local total_files=${#files[@]}
    local count=0

    for file in "${files[@]}"; do
        ((count++))
        local base_name=$(basename "$file" .$src_type)
        local dest_file="$src_dir/${base_name}.${dest_type}"

        # Conversion
        if [ "$src_type" != "$dest_type" ]; then
            echo "Converting $file to $dest_file"
            magick convert "$file" "$dest_file"
        else
            dest_file="$file"
        fi

        # Optimization
        if [ "$optimize" = "y" ]; then
            if [ "$dest_type" = "jpg" ] || [ "$dest_type" = "jpeg" ]; then
                # Try different JPEG optimization tools and keep the smallest file
                local smallest_file=""
                local smallest_size=999999999999 # Large initial value

                # guetzli
                guetzli "$dest_file" "$dest_file".guetzli
                size_guetzli=$(stat -c%s "$dest_file".guetzli)
                if [ $size_guetzli -lt $smallest_size ]; then
                    smallest_file="$dest_file.guetzli"
                    smallest_size=$size_guetzli
                fi

                # jpegoptim
                jpegoptim --size=${target_size} "$dest_file"
                size_jpegoptim=$(stat -c%s "$dest_file")
                if [ $size_jpegoptim -lt $smallest_size ]; then
                    smallest_file="$dest_file"
                    smallest_size=$size_jpegoptim
                fi

                # Keep the smallest file
                mv "$smallest_file" "$dest_file"

            elif [ "$dest_type" = "png" ]; then
                # Try different PNG optimization tools and keep the smallest file
                local smallest_file=""
                local smallest_size=999999999999 # Large initial value

                # pngquant
                pngquant --force --ext .png --skip-if-larger --quality="$min_quality"-80 "$dest_file"
                size_pngquant=$(stat -c%s "${dest_file%.png}-fs8.png")
                if [ $size_pngquant -lt $smallest_size ]; then
                    smallest_file="${dest_file%.png}-fs8.png"
                    smallest_size=$size_pngquant
                fi

                # optipng
                optipng -o7 "$dest_file"
                size_optipng=$(stat -c%s "$dest_file")
                if [ $size_optipng -lt $smallest_size ]; then
                    smallest_file="$dest_file"
                    smallest_size=$size_optipng
                fi

                # Keep the smallest file
                mv "$smallest_file" "$dest_file"

            elif [ "$dest_type" = "webp" ]; then
                local quality=90
                local target_bytes=$((${target_size%KB} * 1024))

                cwebp -q $quality "$file" -o "$dest_file" -mt -exact

                local current_size=$(stat -f%z "$dest_file") # Utilisation de stat avec la syntaxe compatible avec macOS

                echo "Current size: $current_size bytes"
                echo "Target size: $target_bytes bytes"
                echo "Min. quality: $min_quality %"

                while ((current_size > target_bytes)) && ((quality > min_quality)); do
                    echo "Quality: $quality %"
                    quality=$((quality - 5))
                    cwebp -q $quality "$file" -o "$dest_file" -mt -exact
                    current_size=$(stat -f%z "$dest_file") # Réactualiser la taille du fichier compressé
                done

                # if [ $current_size -gt $target_bytes ]; then
                #     echo "Applying lossless compression to $dest_file"
                #     cwebp -lossless "$file" -o "$dest_file"
                # fi
            fi
        fi

        echo "Processed $count/$total_files files."
    done
}

# Vérifier que les outils nécessaires sont installés
for cmd in magick guetzli jpegoptim optipng cwebp pngquant; do
    if ! command -v $cmd &>/dev/null; then
        echo "$cmd could not be found. Please install it to proceed."
        if [ "$cmd" = "magick" ]; then
            echo "You can install ImageMagick by running: brew install imagemagick"
        elif [ "$cmd" = "guetzli" ]; then
            echo "You can install guetzli by running: brew install guetzli"
        elif [ "$cmd" = "jpegoptim" ]; then
            echo "You can install jpegoptim by running: brew install jpegoptim"
        elif [ "$cmd" = "optipng" ]; then
            echo "You can install optipng by running: brew install optipng"
        elif [ "$cmd" = "cwebp" ]; then
            echo "You can install cwebp by running: brew install webp"
        elif [ "$cmd" = "pngquant" ]; then
            echo "You can install pngquant by running: brew install pngquant"
        fi
        exit 1
    fi
done

# Demander le dossier, utiliser le dossier courant si aucun n'est spécifié
read -rp "Enter the directory to analyze (default is current directory): " directory
directory=${directory:-$(pwd)}

# Vérifier que le dossier existe
if [ ! -d "$directory" ]; then
    echo "The directory does not exist."
    exit 1
fi

# Lister les types de fichiers image disponibles
image_types=$(list_image_types "$directory")

# Vérifier s'il y a des types d'image détectés
if [ -z "$image_types" ]; then
    echo "No image types found in the directory."
    exit 1
fi

echo "Available image types in the directory:"
echo "$image_types"

# Demander à l'utilisateur de sélectionner les types de fichiers
read -rp "Enter the image types to process (comma-separated, e.g., jpg,png or 'all' for all types): " selected_types

# Si l'utilisateur choisit 'all', sélectionner tous les types disponibles
if [ "$selected_types" = "all" ]; then
    selected_types=$(echo $image_types | tr '\n' ',')
fi

IFS=',' read -ra types <<<"$selected_types"

# Demander si l'utilisateur souhaite effectuer une conversion
read -rp "Do you want to convert the images? (y/n): " convert_choice

if [ "$convert_choice" = "y" ]; then
    echo "Available conversion options: webp, png, jpg"
    read -rp "Enter the target conversion type: " target_type
else
    target_type=""
fi

# Demander si l'utilisateur souhaite optimiser les fichiers
read -rp "Do you want to optimize the image size? (y/n): " optimize_choice

if [ "$optimize_choice" = "y" ]; then
    read -rp "Enter the target size (e.g., 100KB or 80%): " target_size

    # Vérifier si la taille cible est en pourcentage et la convertir en KB si nécessaire
    if [[ "$target_size" == *%* ]]; then
        target_percentage=${target_size%\%*}
        total_size=$(du -sk "$directory" | cut -f1)
        
        if [[ "$selected_types" =~ "" ]]; then
            num_files=$(find "$directory" -type f -iname "*.$selected_types" | wc -l)
        else
            num_files=$(find "$directory" -type f | grep -Eo '\.(png|jpg|jpeg|heic|webp)$' | wc -l)
        fi
        target_size=$(echo "scale=2; ($total_size * $target_percentage / 100) / $num_files" | bc | awk -F. '{print $1}')
    else
        target_size=${target_size//[^0-9]/} # Supprimer les caractères non numériques
    fi

    # Vérifier si la taille cible est un nombre valide
    if ! [[ "$target_size" =~ ^[0-9]+$ ]]; then
        echo "Invalid target size $target_size. Please enter a valid size (e.g., 100KB or 80%)."
        exit 1
    fi

else
    target_size=""
    min_quality=""
fi

# Demander si l'utilisateur accepte une réduction de qualité
read -rp "Do you accept to reduce the image quality ? (y/n): " quality_choice

if [ "$quality_choice" = "y" ]; then
    read -rp "Enter the minimum quality percentage (< 90): " min_quality
    min_quality=${min_quality//[^0-9]/} # Supprimer les caractères non numériques

    # Vérifier si la taille cible est un nombre valide
    if ! [[ "$min_quality" =~ ^[0-9]+$ ]]; then
        echo "Invalid quality definition. Please enter a valid amount (< 90)."
        exit 1
    fi

    if ((min_quality > 89)); then
        min_quality=80
    fi

else
    min_quality=85
fi

# Traitement des fichiers
for type in "${types[@]}"; do
    if [ "$convert_choice" = "y" ]; then
        convert_and_optimize "$directory" "$type" "$target_type" "$optimize_choice" "$target_size" "$min_quality"
    else
        convert_and_optimize "$directory" "$type" "$type" "$optimize_choice" "$target_size" "$min_quality"
    fi
done

echo "All operations completed."
