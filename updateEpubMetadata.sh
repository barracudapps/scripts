#!/bin/bash

################################################################################
# Script:       updateEpubMetadata.sh
# Description:  Updates the author and title metadata of EPUB files based on
#               their filenames. Author and title/subtitle information is
#               extracted from the filename format:
#               [Author(s)] Title - Subtitle.epub   (subtitle optional)
#               The updated copy is written next to the original as
#               <name>_updated.epub (the original is never modified).
# Usage:        bash updateEpubMetadata.sh [file.epub]
# Author:       Pierre LAMOTTE
# Date:         02 OCT 2024
################################################################################

shopt -s nullglob nocaseglob

# Check if necessary tools are installed
for tool in xmlstarlet zip unzip; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Required tool '$tool' is not installed (brew install $tool)." >&2
        exit 1
    fi
done

# Set encoding to avoid "illegal byte sequence" errors
export LC_ALL=en_US.UTF-8

DC_NS="http://purl.org/dc/elements/1.1/"
OPF_NS="http://www.idpf.org/2007/opf"

# Extract metadata from the filename (sets the globals "authors" and "title")
extract_metadata() {
    local name
    name=$(basename "$1")
    name="${name%.[eE][pP][uU][bB]}"

    authors=""
    if [[ "$name" =~ ^\[([^]]*)\][[:space:]]*(.*)$ ]]; then
        authors="${BASH_REMATCH[1]}"
        name="${BASH_REMATCH[2]}"
    fi

    # Title before the last " - ", subtitle after it (if present)
    if [[ "$name" == *" - "* ]]; then
        title="${name% - *}: ${name##* - }"
    else
        title="$name"
    fi
}

update_epub_metadata() {
    local epub_file="$1"
    local output_file="${epub_file%.*}_updated.epub"
    local output_abs temp_dir

    extract_metadata "$epub_file"
    if [[ -z "$title" ]]; then
        echo "Unable to extract a title from the filename." >&2
        return 1
    fi
    echo "  Author(s): ${authors:-(unchanged)}"
    echo "  Title:     $title"

    output_abs="$(cd "$(dirname "$output_file")" && pwd)/$(basename "$output_file")"
    temp_dir=$(mktemp -d)
    rewrite_epub "$epub_file" "$output_abs" "$temp_dir"
    local status=$?
    rm -rf "$temp_dir"
    [[ $status -eq 0 ]] && echo "  Output file: $output_file"
    return $status
}

# Unzip, edit the OPF metadata and zip again into output_abs
rewrite_epub() {
    local epub_file="$1" output_abs="$2" temp_dir="$3" opf_rel opf_file

    unzip -q "$epub_file" -d "$temp_dir" || return 1

    # The OPF path is declared in META-INF/container.xml
    opf_rel=$(xmlstarlet sel -N c="urn:oasis:names:tc:opendocument:xmlns:container" \
        -t -v "//c:rootfile[1]/@full-path" "$temp_dir/META-INF/container.xml" 2>/dev/null)
    opf_file="$temp_dir/$opf_rel"
    [[ -n "$opf_rel" && -f "$opf_file" ]] || opf_file=$(find "$temp_dir" -name "*.opf" | head -n 1)

    if [[ -z "$opf_file" || ! -f "$opf_file" ]]; then
        echo "Error: Unable to locate the .opf file in the EPUB." >&2
        return 1
    fi

    # Title: update the first dc:title, or create it if missing
    if xmlstarlet sel -N dc="$DC_NS" -t -v "count(//dc:title)" "$opf_file" | grep -qv '^0$'; then
        xmlstarlet ed -L -N dc="$DC_NS" -u "(//dc:title)[1]" -v "$title" "$opf_file"
    else
        xmlstarlet ed -L -N dc="$DC_NS" -N opf="$OPF_NS" \
            -s "//opf:metadata" -t elem -n "dc:title" -v "$title" "$opf_file"
    fi

    # Authors: keep a single dc:creator holding the bracketed value
    if [[ -n "$authors" ]]; then
        if xmlstarlet sel -N dc="$DC_NS" -t -v "count(//dc:creator)" "$opf_file" | grep -qv '^0$'; then
            xmlstarlet ed -L -N dc="$DC_NS" \
                -d "(//dc:creator)[position() > 1]" \
                -u "(//dc:creator)[1]" -v "$authors" "$opf_file"
        else
            xmlstarlet ed -L -N dc="$DC_NS" -N opf="$OPF_NS" \
                -s "//opf:metadata" -t elem -n "dc:creator" -v "$authors" "$opf_file"
        fi
    fi

    # Repackage: "mimetype" must be the first entry and stored uncompressed (EPUB spec)
    rm -f "$output_abs"
    (
        cd "$temp_dir" || exit 1
        zip -q -X -0 "$output_abs" mimetype &&
            zip -q -X -9 -r "$output_abs" . -x mimetype -x '.DS_Store' -x '__MACOSX/*'
    )
}

# Files to process: argument, or ask the user
if [[ -n "$1" ]]; then
    epub_files=("$@")
else
    echo "Do you want to update metadata for:"
    echo "1. A single EPUB file"
    echo "2. All EPUB files in the current directory"
    read -rp "Enter your choice (1-2): " file_choice

    if [[ "$file_choice" == "1" ]]; then
        read -rp "Enter the relative path of the EPUB file to update: " epub_file
        epub_files=("${epub_file/#\~/$HOME}")
    else
        epub_files=()
        for f in *.epub; do
            [[ "$f" == *_updated.epub ]] || epub_files+=("$f")
        done
    fi
fi

if [[ ${#epub_files[@]} -eq 0 ]]; then
    echo "No EPUB files found." >&2
    exit 1
fi

failed=0
for epub_file in "${epub_files[@]}"; do
    if [[ ! -f "$epub_file" ]]; then
        echo "The specified file does not exist: $epub_file" >&2
        failed=$((failed + 1))
        continue
    fi
    echo "Updating metadata for: $epub_file"
    if ! update_epub_metadata "$epub_file"; then
        echo "Failed to update metadata for $epub_file." >&2
        failed=$((failed + 1))
    fi
done

echo "All files processed ($failed failure(s)). Script completed."
[[ $failed -eq 0 ]]
