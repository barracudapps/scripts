#!/bin/bash

################################################################################
# Script:       recursivePdf.sh
# Description:  Converts all .doc, .docx, or .odt files in a specified directory
#               to PDF format. Optionally combines the resulting PDF files.
# Usage:        sh ~/Documents/scripts/recursivePdf.sh
# Author:       Pierre LAMOTTE
# Date:         29 MAY 2024
################################################################################

# Variables
LIBRE_OFFICE="/Applications/LibreOffice.app/Contents/MacOS/soffice"

# Ask the user for the path of the directory where the files are located
read -p "Enter the path of the directory containing the files to be converted: " input_folder

# Ask the user if they want to delete the original files after conversion
read -p "Do you want to delete the original files after conversion? (yes/no): " delete_originals

# Recursive function to process folders and sub-folders
process_folder() {
    local folder="$1"

    # Iterate over all Word files in the directory
    for file in "$folder"/*.docx "$folder"/*.doc "$folder"/*.odt; do
        if [[ -f "$file" ]]; then
            # Convert the Word file to PDF
            echo "Converting $file to PDF..."
            "$LIBRE_OFFICE" --headless --convert-to pdf "$file" --outdir "$folder"

            # Check if the PDF conversion was successful
            if [[ -f "${file%.*}.pdf" ]]; then
                if [[ "$delete_originals" == "yes" ]]; then
                    # Delete the Word file once the conversion is successful
                    echo "PDF conversion successful. Deleting $file..."
                    rm "$file"
                else
                    echo "PDF conversion successful. Keeping the original file: $file"
                fi
            else
                echo "Error converting $file to PDF. The PDF file was not created."
            fi
        fi
    done

    # Iterate over sub-directories
    for subdir in "$folder"/*; do
        if [[ -d "$subdir" ]]; then
            process_folder "$subdir"
        fi
    done
}

# Check if the specified directory exists
if [[ ! -d "$input_folder" ]]; then
    echo "The specified directory does not exist: $input_folder"
    exit 1
fi

# Start processing the specified directory recursively
process_folder "$input_folder"

echo "PDF conversion completed."

# Ask the user if they want to combine the PDF files
read -p "Do you want to combine the PDF files? (yes/no): " combine_response

if [[ "$combine_response" == "yes" ]]; then
    # Ask the user for the output file name
    read -p "Enter the name of the combined PDF file: " combined_pdf_file

    # Combine PDF files using Ghostscript (gs)
    gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile="$input_folder/$combined_pdf_file" "$input_folder"/*.pdf

    echo "PDF files combined into $input_folder/$combined_pdf_file"
fi

echo "Script completed."
