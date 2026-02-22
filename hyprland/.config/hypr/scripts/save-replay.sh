#!/bin/bash

# --- CONFIGURATION ---
OBS_DIR="$HOME/Captures" # Ensure this is your correct path
THUMB_PATH="/tmp/obs_replay_thumb.png"
SOUND_PATH="/usr/share/sounds/freedesktop/stereo/camera-shutter.oga"
# ---------------------

# 1. Ask Hyprland for BOTH the window class and the window title.
# We use sed to strip out the labels and leading spaces perfectly.
WINDOW_CLASS=$(hyprctl activewindow | grep -E '^[[:space:]]*class:' | sed 's/^[[:space:]]*class:[[:space:]]*//')
WINDOW_TITLE=$(hyprctl activewindow | grep -E '^[[:space:]]*title:' | sed 's/^[[:space:]]*title:[[:space:]]*//')

# 2. Decide which name to use. 
# If the class is a generic Wine/Proton/Steam wrapper, use the Title instead.
if [[ "$WINDOW_CLASS" == steam_app_* || "$WINDOW_CLASS" == "wine" || "$WINDOW_CLASS" == "gamescope" ]]; then
    RAW_NAME="$WINDOW_TITLE"
else
    RAW_NAME="$WINDOW_CLASS"
fi

# 3. Clean up the name for the Linux filesystem.
if [[ -z "$RAW_NAME" ]]; then
    GAME_NAME="Desktop"
else
    # Removes weird characters, colons, or slashes that break folder paths
    GAME_NAME=$(echo "$RAW_NAME" | sed 's/[^a-zA-Z0-9 -]/_/g')
fi

# 4. Create the game's subdirectory
TARGET_DIR="$OBS_DIR/$GAME_NAME"
mkdir -p "$TARGET_DIR"

# 5. Tell OBS to save the replay
if obs-cmd replay save; then
    
    sleep 0.5

    # 6. Find the newly saved video
    LATEST_REPLAY=$(find "$OBS_DIR" -maxdepth 1 -type f -iregex '.*\.\(mp4\|mkv\|mov\|flv\)$' -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" ")

    if [[ -n "$LATEST_REPLAY" && -f "$LATEST_REPLAY" ]]; then
        
        # 7. Move the clip into the game's folder
        FILE_NAME=$(basename "$LATEST_REPLAY")
        NEW_REPLAY_PATH="$TARGET_DIR/$FILE_NAME"
        mv "$LATEST_REPLAY" "$NEW_REPLAY_PATH"

        # 8. Generate Thumbnail
        rm -f "$THUMB_PATH"
        ffmpeg -y -i "$NEW_REPLAY_PATH" -vframes 1 "$THUMB_PATH" -loglevel error

        if [[ -f "$SOUND_PATH" ]]; then
            pw-play "$SOUND_PATH" &
        fi

        # 9. Send Notification
        if [[ -f "$THUMB_PATH" ]]; then
            notify-send -a "OBS Studio" -i "$THUMB_PATH" -t 4000 -u normal "Saved to: $GAME_NAME" "$FILE_NAME"
        else
            notify-send -a "OBS Studio" -i obs-studio -t 4000 -u normal "Saved to: $GAME_NAME" "$FILE_NAME (Thumbnail failed)"
        fi
        
    else
        notify-send -a "OBS Studio" -i obs-studio -t 4000 -u normal "Replay Saved" "Saved! (Couldn't locate new video to move)"
    fi

else
    notify-send -a "OBS Studio" -i dialog-error -t 4000 -u critical "Replay Failed" "Could not save replay. Is OBS running?"
fi