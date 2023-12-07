#!/bin/bash

# Re-encode videos to a target size in MB. Supports individual files or batch processing of a directory.
# Example:
#    ./converter.sh video.mp4 15

# Default values
VIDEO_CODEC="libx264"
AUDIO_CODEC="aac"
PASSES=2
FRAMERATE=""
RESOLUTION=""

# Input validation
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <input_file_or_directory> <target_size_in_MB> [-v video_codec] [-a audio_codec] [-p passes] [-f framerate] [-r resolution]"
    exit 1
fi

# Parsing optional arguments for codecs, passes, framerate, and resolution
while [[ "$#" -gt 2 ]]; do
    case $1 in
        -v) VIDEO_CODEC="$2"; shift ;;
        -a) AUDIO_CODEC="$2"; shift ;;
        -p) PASSES="$2"; shift ;;
        -f) FRAMERATE="$2"; shift ;;
        -r) RESOLUTION="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

INPUT_PATH="$1"
T_SIZE="$2"

if [ ! -e "$INPUT_PATH" ]; then
    echo "Error: Specified input path '$INPUT_PATH' does not exist!"
    exit 1
fi

if ! [[ "$T_SIZE" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "Error: Invalid target size! Please provide a valid number."
    exit 1
fi

# Function to process a single video file
process_video() {
    local INPUT_FILE="$1"
    T_FILE="${INPUT_FILE%.*}-$T_SIZE""MB.mp4"

    echo "Processing: $INPUT_FILE"

    # Original duration in seconds
    O_DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$INPUT_FILE")

    # Original audio rate
    O_ARATE=$(ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of csv=p=0 "$INPUT_FILE")

    # Original audio rate in KiB/s
    O_ARATE=$(awk -v arate="$O_ARATE" 'BEGIN { printf "%.0f", (arate / 1024) }')

    # Minimum possible size based on audio bitrate and duration
    T_MINSIZE=$(awk -v arate="$O_ARATE" -v duration="$O_DUR" 'BEGIN { printf "%.2f", ( (arate * duration) / 8192 ) }')

    # Check if the target size is acceptable
    IS_MINSIZE=$(awk -v size="$T_SIZE" -v minsize="$T_MINSIZE" 'BEGIN { print (minsize < size) }')

    # Error message if size is too small
    if [[ $IS_MINSIZE -eq 0 ]]; then
        echo "Error: Target size ${T_SIZE}MB is too small for file $INPUT_FILE!"
        echo "Try values larger than ${T_MINSIZE}MB"
        return
    fi

    # Set target audio bitrate
    T_ARATE=$O_ARATE

    # Calculate target video rate
    T_VRATE=$(awk -v size="$T_SIZE" -v duration="$O_DUR" -v audio_rate="$O_ARATE" 'BEGIN { print  ( ( size * 8192.0 ) / ( 1.048576 * duration ) - audio_rate) }')

    # Construct ffmpeg command
    CMD="ffmpeg -y -i "$INPUT_FILE" -c:v $VIDEO_CODEC -b:v "$T_VRATE"k"

    # Add optional framerate and resolution parameters
    [ ! -z "$FRAMERATE" ] && CMD="$CMD -r $FRAMERATE"
    [ ! -z "$RESOLUTION" ] && CMD="$CMD -s $RESOLUTION"

    if [[ $PASSES -eq 1 ]]; then
        CMD="$CMD -c:a $AUDIO_CODEC -b:a "$T_ARATE"k "$T_FILE""
        eval "$CMD"
    else
        CMD="$CMD -pass 1 -an -f mp4 /dev/null && ffmpeg -i "$INPUT_FILE" -c:v $VIDEO_CODEC -b:v "$T_VRATE"k -pass 2 -c:a $AUDIO_CODEC -b:a "$T_ARATE"k "$T_FILE""
        eval "$CMD"
    fi

    echo "Processed $INPUT_FILE -> $T_FILE"
}

# If the input path is a directory, process all mp4 files within it
if [ -d "$INPUT_PATH" ]; then
    for video_file in "$INPUT_PATH"/*.mp4; do
        process_video "$video_file"
    done
else
    process_video "$INPUT_PATH"
fi

echo "Conversão concluída com sucesso!"
