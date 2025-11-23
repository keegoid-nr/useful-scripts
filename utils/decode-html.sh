#!/bin/bash
# shellcheck disable=SC2016
: '
A simple bash script to decode common HTML entities.
It can read from a file, standard input, or the system clipboard.
If input is from the clipboard, the decoded text is copied back.

Author : Keegan Mullaney
Company: New Relic
Email  : kmullaney@newrelic.com
Website: github.com/keegoid-nr/useful-scripts
License: Apache License 2.0

Usage:
  ./decode-html.sh [filename]
  ./decode-html.sh --clipboard
  cat [filename] | ./decode-html.sh


'

# Function to display usage and exit
usage() {
  echo "Usage: $0 [filename | --clipboard | -c]" >&2
  echo "Or pipe content to it: cat <filename> | $0" >&2
  exit 1
}

INPUT_STREAM=""
CLIPBOARD_MODE=false # Flag to track if we're using the clipboard

# Handle command-line arguments. Using a case statement for clarity.
case "$1" in
    --clipboard|-c)
        CLIPBOARD_MODE=true
        # Check for clipboard 'paste' tools and use the first one found.
        if command -v pbpaste &> /dev/null; then
            INPUT_STREAM=$(pbpaste)
        elif command -v xclip &> /dev/null; then
            INPUT_STREAM=$(xclip -o -selection clipboard)
        elif command -v xsel &> /dev/null; then
            INPUT_STREAM=$(xsel --clipboard --output)
        else
            echo "Error: No clipboard 'paste' tool found. Please install 'pbpaste', 'xclip', or 'xsel'." >&2
            exit 1
        fi
        ;;
    "")
        # No arguments provided.
        # Check if data is being piped in. If not, show usage.
        if [ -t 0 ]; then
            usage
        else
            # Read from standard input (pipe).
            INPUT_STREAM=$(cat)
        fi
        ;;
    *)
        # Default case: assume the argument is a filename.
        if [ ! -f "$1" ]; then
            echo "Error: File '$1' not found." >&2
            exit 1
        fi
        INPUT_STREAM=$(cat "$1")
        ;;
esac


# Use sed to replace the HTML entities. Store the result in a variable.
DECODED_OUTPUT=$(echo "$INPUT_STREAM" | sed \
    -e 's/&quot;/"/g'  \
    -e "s/&#39;/'/g"   \
    -e 's/&lt;/</g'     \
    -e 's/&gt;/>/g'     \
    -e 's/&amp;/&/g')

# If in clipboard mode, copy the output back to the clipboard.
# Otherwise, print to standard output as normal.
if [ "$CLIPBOARD_MODE" = true ]; then
    if command -v pbcopy &> /dev/null; then
        echo -n "$DECODED_OUTPUT" | pbcopy
    elif command -v xclip &> /dev/null; then
        echo -n "$DECODED_OUTPUT" | xclip -i -selection clipboard
    elif command -v xsel &> /dev/null; then
        echo -n "$DECODED_OUTPUT" | xsel --clipboard --input
    else
        # This should not happen if the paste command worked, but as a fallback, print the output.
        echo "Error: No clipboard 'copy' tool found, cannot copy result." >&2
        echo "$DECODED_OUTPUT"
        exit 1
    fi
    echo "Decoded text has been copied back to the clipboard." >&2
else
    echo "$DECODED_OUTPUT"
fi
