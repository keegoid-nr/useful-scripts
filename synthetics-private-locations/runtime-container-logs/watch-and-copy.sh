#!/bin/bash

# Default Settings
IMAGE_NAME="newrelic/synthetics-node-browser-runtime"
DEST_BASE="./captured_outputs"
CHECK_INTERVAL=1 # Seconds to wait to ensure file size is stable

# Function to display usage
usage() {
    echo "Usage: $0 [-i image_name] [-d destination_path] [-t check_interval_seconds] [-h]"
    echo ""
    echo "  -i  Docker image name to monitor (default: $IMAGE_NAME)"
    echo "  -d  Destination base directory (default: $DEST_BASE)"
    echo "  -t  Seconds to wait for file stability (default: $CHECK_INTERVAL)"
    echo "  -h  Show this help message"
    exit 1
}

# Parse input arguments
while getopts "i:d:t:h" opt; do
    case $opt in
        i) IMAGE_NAME="$OPTARG" ;;
        d) DEST_BASE="$OPTARG" ;;
        t) CHECK_INTERVAL="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Ensure Docker is installed/running
if ! command -v docker &> /dev/null; then
    echo "Error: 'docker' command not found."
    exit 1
fi

# Cleanup background jobs on exit
trap 'kill $(jobs -p) 2>/dev/null' EXIT

echo "Monitoring for New Relic runtime containers..."

# 1. Listen for the 'start' event of any runtime container
docker events --filter "image=$IMAGE_NAME" --filter "event=start" --format '{{.Actor.ID}}' | while read -r CONTAINER_ID
do
    echo "--- Monitor Triggered (ID: ${CONTAINER_ID:0:12}) ---"
    
    # Run extraction in the background so we don't miss simultaneous jobs
    (
        # Extract runtime name from image (e.g., "newrelic/synthetics-node-browser-runtime" -> "synthetics-node-browser-runtime")
        RUNTIME_NAME="${IMAGE_NAME##*/}"
        INPUT_PATH="/app/${RUNTIME_NAME}/runtime/input-output/input"
        OUTPUT_PATH="/app/${RUNTIME_NAME}/runtime/input-output/output"

        # Prepare destination immediately
        RUN_ID=$(date +%Y%m%d_%H%M%S)_${CONTAINER_ID:0:6}
        DEST_DIR="$DEST_BASE/$RUN_ID"
        mkdir -p "$DEST_DIR/input"
        mkdir -p "$DEST_DIR/output"
        
        echo "Started monitoring $CONTAINER_ID -> $DEST_DIR"

        PREV_INPUT_SIZE=0
        PREV_OUTPUT_SIZE=0
        COPY_ATTEMPTED=false
        FIRST_CHECK=true
        
        # For extremely short-lived containers, attempt immediate copies before polling
        # Give the container a tiny moment to write files, then try copying
        sleep 0.05
        INPUT_SIZE=$(docker exec $CONTAINER_ID sh -c "du -sb '$INPUT_PATH' 2>/dev/null | cut -f1" 2>/dev/null || echo "0")
        OUTPUT_SIZE=$(docker exec $CONTAINER_ID sh -c "du -sb '$OUTPUT_PATH' 2>/dev/null | cut -f1" 2>/dev/null || echo "0")
        
        if [[ "$INPUT_SIZE" =~ ^[0-9]+$ ]] && [ "$INPUT_SIZE" -gt 0 ]; then
            if docker cp "$CONTAINER_ID:$INPUT_PATH/." "$DEST_DIR/input/" 2>/dev/null; then
                PREV_INPUT_SIZE=$INPUT_SIZE
                COPY_ATTEMPTED=true
                echo "Captured ${CONTAINER_ID:0:12} input: $INPUT_SIZE bytes"
            fi
        fi
        
        if [[ "$OUTPUT_SIZE" =~ ^[0-9]+$ ]] && [ "$OUTPUT_SIZE" -gt 0 ]; then
            if docker cp "$CONTAINER_ID:$OUTPUT_PATH/." "$DEST_DIR/output/" 2>/dev/null; then
                PREV_OUTPUT_SIZE=$OUTPUT_SIZE
                COPY_ATTEMPTED=true
                echo "Captured ${CONTAINER_ID:0:12} output: $OUTPUT_SIZE bytes"
            fi
        fi
        
        # Poll while container is running - use very short interval for short-lived containers
        while docker ps -q --no-trunc | grep -q "$CONTAINER_ID"; do
            # Check total size of both directories
            INPUT_SIZE=$(docker exec $CONTAINER_ID sh -c "du -sb '$INPUT_PATH' 2>/dev/null | cut -f1" 2>/dev/null || echo "0")
            OUTPUT_SIZE=$(docker exec $CONTAINER_ID sh -c "du -sb '$OUTPUT_PATH' 2>/dev/null | cut -f1" 2>/dev/null || echo "0")
            
            # Ensure sizes are valid integers
            if ! [[ "$INPUT_SIZE" =~ ^[0-9]+$ ]]; then
                INPUT_SIZE=0
            fi
            if ! [[ "$OUTPUT_SIZE" =~ ^[0-9]+$ ]]; then
                OUTPUT_SIZE=0
            fi
            
            # Mark first check as done
            if [ "$FIRST_CHECK" = true ]; then
                FIRST_CHECK=false
            fi
            
            # Copy input directory if it has grown
            if [ "$INPUT_SIZE" -gt "$PREV_INPUT_SIZE" ]; then
                if docker cp "$CONTAINER_ID:$INPUT_PATH/." "$DEST_DIR/input/" 2>/dev/null; then
                    PREV_INPUT_SIZE=$INPUT_SIZE
                    COPY_ATTEMPTED=true
                    echo "Captured ${CONTAINER_ID:0:12} input: $INPUT_SIZE bytes"
                fi
            fi
            
            # Copy output directory if it has grown
            if [ "$OUTPUT_SIZE" -gt "$PREV_OUTPUT_SIZE" ]; then
                if docker cp "$CONTAINER_ID:$OUTPUT_PATH/." "$DEST_DIR/output/" 2>/dev/null; then
                    PREV_OUTPUT_SIZE=$OUTPUT_SIZE
                    COPY_ATTEMPTED=true
                    echo "Captured ${CONTAINER_ID:0:12} output: $OUTPUT_SIZE bytes"
                fi
            fi
            
            # Very short sleep for rapid polling of short-lived containers
            sleep 0.1
        done
        
        # One final attempt to copy in case container just stopped
        # This races against --rm cleanup but might catch some cases
        if [ "$COPY_ATTEMPTED" = false ]; then
            echo "Container $CONTAINER_ID stopped before copy. Attempting final copy..."
            docker cp "$CONTAINER_ID:$INPUT_PATH/." "$DEST_DIR/input/" 2>/dev/null && echo "Final input copy succeeded!" || true
            docker cp "$CONTAINER_ID:$OUTPUT_PATH/." "$DEST_DIR/output/" 2>/dev/null && echo "Final output copy succeeded!" || echo "Final copy failed (--rm likely removed it)"
        else
            echo "Container $CONTAINER_ID stopped. Final sizes - input: $PREV_INPUT_SIZE bytes, output: $PREV_OUTPUT_SIZE bytes"
        fi
        
        # Check if we captured any actual files (not just empty directories)
        FILE_COUNT=$(find "$DEST_DIR" -type f | wc -l)
        
        if [ "$FILE_COUNT" -eq 0 ]; then
            # No files captured, clean up
            rm -rf "$DEST_DIR"
            echo "No files captured for ${CONTAINER_ID:0:12}"
        else
            # Remove .gitkeep placeholder files that have restrictive permissions
            find "$DEST_DIR" -name '.gitkeep' -delete 2>/dev/null
            
            # Create tar.gz archive of captured files
            ARCHIVE_NAME="${RUN_ID}.tar.gz"
            ARCHIVE_PATH="$DEST_BASE/$ARCHIVE_NAME"
            
            echo "Compressing captured files to $ARCHIVE_NAME..."
            if tar -czf "$ARCHIVE_PATH" -C "$DEST_BASE" "$RUN_ID" 2>/dev/null; then
                # Remove the uncompressed directory after successful compression
                rm -rf "$DEST_DIR"
                echo "Archive created: $ARCHIVE_PATH"
            else
                echo "Failed to create archive, keeping directory: $DEST_DIR"
            fi
        fi
    ) &
done