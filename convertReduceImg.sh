#!/bin/bash

################################################################################
# Script:	convertReduceImg.sh
# Description:	Converts and/or reduces images in a directory (recursively).
#		Converted files are written next to their source; optimization
#		without conversion rewrites the files in place, only when smaller.
# Usage:	bash ~/Documents/scripts/convertReduceImg.sh [directory]
# Author:	Pierre LAMOTTE
# Date:		05 JUL 2024
################################################################################

IMAGE_EXT_RE='\.(png|jpg|jpeg|heic|webp)$'

file_size() { stat -f%z "$1"; }
to_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
# jpg and jpeg are the same format
normalize_ext() { local e; e=$(to_lower "$1"); [[ "$e" == "jpeg" ]] && e="jpg"; printf '%s' "$e"; }

require() {
    command -v "$1" &>/dev/null && return 0
    echo "$1 could not be found. You can install it by running: brew install $2" >&2
    exit 1
}

# Keep $2 instead of $1 if it exists and is smaller; always remove $2 afterwards
keep_smallest() {
    local current="$1" candidate="$2"
    if [[ -s "$candidate" ]] && (( $(file_size "$candidate") < $(file_size "$current") )); then
        mv -f "$candidate" "$current"
    else
        rm -f "$candidate"
    fi
}

convert_file() {
    local src="$1" dest="$2"
    if magick "$src" "$dest" 2>/dev/null; then
        return 0
    fi
    # HEIC support depends on ImageMagick's build: fall back to macOS sips
    local fmt; fmt=$(normalize_ext "${dest##*.}")
    [[ "$fmt" == "jpg" ]] && fmt="jpeg"
    if [[ "$fmt" != "webp" ]] && sips -s format "$fmt" "$src" --out "$dest" &>/dev/null; then
        return 0
    fi
    echo "  Conversion failed: $src" >&2
    return 1
}

# Size target in bytes for one file ("" when no target)
target_bytes_for() {
    local file="$1"
    if [[ -n "$target_percent" ]]; then
        echo $(( $(file_size "$file") * target_percent / 100 ))
    elif [[ -n "$target_kb" ]]; then
        echo $(( target_kb * 1024 ))
    fi
}

optimize_jpg() {
    local file="$1" target="$2"
    local tmp="${file}.tmp_opt.jpg"
    cp "$file" "$tmp"
    if [[ -n "$target" ]]; then
        jpegoptim --quiet --strip-all --size="$(( target / 1024 ))k" "$tmp" >/dev/null
    else
        jpegoptim --quiet --strip-all --max="$min_quality" "$tmp" >/dev/null
    fi
    keep_smallest "$file" "$tmp"

    # guetzli (optional, very slow, needs quality >= 84): only when no hard target
    if [[ -z "$target" ]] && command -v guetzli &>/dev/null; then
        local q=$(( min_quality < 84 ? 84 : min_quality ))
        guetzli --quality "$q" "$file" "${file}.guetzli.jpg" 2>/dev/null
        keep_smallest "$file" "${file}.guetzli.jpg"
    fi
}

optimize_png() {
    local file="$1"
    local tmp="${file%.*}.tmp_quant.png"
    pngquant --force --skip-if-larger --strip --quality="${min_quality}-95" --output "$tmp" "$file" 2>/dev/null
    keep_smallest "$file" "$tmp"
    optipng -quiet -o2 -strip all "$file"
}

optimize_webp() {
    local source="$1" dest="$2" target="$3"
    local quality=90 tmp="${dest%.*}.tmp_webp.webp"
    cwebp -quiet -mt -q "$quality" "$source" -o "$tmp" || { rm -f "$tmp"; return 1; }
    if [[ -n "$target" ]]; then
        while (( $(file_size "$tmp") > target && quality - 5 >= min_quality )); do
            quality=$((quality - 5))
            cwebp -quiet -mt -q "$quality" "$source" -o "$tmp"
        done
        echo "  WebP quality: $quality% ($(( $(file_size "$tmp") / 1024 )) KB, target $(( target / 1024 )) KB)"
    fi
    if [[ "$source" -ef "$dest" ]]; then
        keep_smallest "$dest" "$tmp"
    else
        mv -f "$tmp" "$dest"
    fi
}

process_type() {
    local src_type="$1" dest_type="$2"
    local files=() file
    while IFS= read -r -d '' file; do
        [[ "$(normalize_ext "${file##*.}")" == "$(normalize_ext "$src_type")" ]] && files+=("$file")
    done < <(find "$directory" -type f -print0 | grep -zEi "$IMAGE_EXT_RE")

    local total=${#files[@]} count=0
    for file in "${files[@]}"; do
        count=$((count + 1))
        local dest="$file" before
        before=$(file_size "$file")

        if [[ "$(normalize_ext "${file##*.}")" != "$(normalize_ext "$dest_type")" ]]; then
            dest="${file%.*}.$dest_type"
            if [[ "$dest_type" == "webp" && "$optimize_choice" =~ ^[yY] ]]; then
                optimize_webp "$file" "$dest" "$(target_bytes_for "$file")" || continue
                echo "[$count/$total] $file -> $dest ($((before / 1024)) KB -> $(( $(file_size "$dest") / 1024 )) KB)"
                continue
            fi
            convert_file "$file" "$dest" || continue
        fi

        if [[ "$optimize_choice" =~ ^[yY] ]]; then
            case "$(normalize_ext "$dest_type")" in
                jpg) optimize_jpg "$dest" "$(target_bytes_for "$file")" ;;
                png) optimize_png "$dest" ;;
                webp) optimize_webp "$dest" "$dest" "$(target_bytes_for "$file")" ;;
            esac
        fi
        echo "[$count/$total] $dest ($((before / 1024)) KB -> $(( $(file_size "$dest") / 1024 )) KB)"
    done
}

# Directory: argument, or ask (current directory by default)
directory="$1"
if [[ -z "$directory" ]]; then
    read -rp "Enter the directory to analyze (default is current directory): " directory
fi
directory="${directory:-.}"
directory="${directory/#\~/$HOME}"
if [[ ! -d "$directory" ]]; then
    echo "The directory does not exist: $directory" >&2
    exit 1
fi

image_types=$(find "$directory" -type f | grep -Eio "$IMAGE_EXT_RE" | tr '[:upper:]' '[:lower:]' | sed 's/^\.//; s/^jpeg$/jpg/' | sort | uniq -c)
if [[ -z "$image_types" ]]; then
    echo "No image types found in the directory."
    exit 1
fi
echo "Available image types in the directory:"
echo "$image_types"

read -rp "Enter the image types to process (comma-separated, e.g., jpg,png or 'all' for all types): " selected_types
selected_types=$(to_lower "${selected_types:-all}")
if [[ "$selected_types" == "all" ]]; then
    selected_types=$(echo "$image_types" | awk '{print $2}' | paste -sd, -)
fi
IFS=',' read -ra types <<<"${selected_types// /}"

read -rp "Do you want to convert the images? (y/n): " convert_choice
target_type=""
if [[ "$convert_choice" =~ ^[yY] ]]; then
    read -rp "Enter the target conversion type (webp, png, jpg): " target_type
    target_type=$(normalize_ext "$target_type")
    case "$target_type" in
        webp|png|jpg) ;;
        *) echo "Unsupported target type: $target_type" >&2; exit 1 ;;
    esac
    require magick imagemagick
fi

read -rp "Do you want to optimize the image size? (y/n): " optimize_choice
target_kb=""
target_percent=""
min_quality=85
if [[ "$optimize_choice" =~ ^[yY] ]]; then
    read -rp "Enter the target size per image (e.g., 100KB or 80% of each file, empty for none): " target_size
    if [[ "$target_size" == *% ]]; then
        target_percent="${target_size%\%}"
        [[ "$target_percent" =~ ^[0-9]+$ ]] || { echo "Invalid percentage: $target_size" >&2; exit 1; }
    elif [[ -n "$target_size" ]]; then
        target_kb="${target_size//[^0-9]/}"
        [[ "$target_kb" =~ ^[0-9]+$ ]] || { echo "Invalid target size: $target_size" >&2; exit 1; }
    fi

    read -rp "Minimum quality accepted (40-95, default 85): " min_quality
    min_quality="${min_quality//[^0-9]/}"
    min_quality="${min_quality:-85}"
    (( min_quality < 40 )) && min_quality=40
    (( min_quality > 95 )) && min_quality=95

    for t in "${types[@]}"; do
        case "$(normalize_ext "${target_type:-$t}")" in
            jpg) require jpegoptim jpegoptim ;;
            png) require pngquant pngquant; require optipng optipng ;;
            webp) require cwebp webp ;;
        esac
    done
fi

for type in "${types[@]}"; do
    [[ -z "$type" ]] && continue
    echo "== Processing .$type files"
    process_type "$type" "${target_type:-$(normalize_ext "$type")}"
done

echo "All operations completed."
