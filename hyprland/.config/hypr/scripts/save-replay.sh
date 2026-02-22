#!/bin/bash

# Attempt to tell OBS to save the replay buffer
if obs-cmd replay save; then
    # If successful, trigger a notification with the OBS icon
    notify-send -a "OBS Studio" -i obs-studio -t 3000 -u normal "Replay Saved" "Your replay buffer was successfully saved!"
else
    # If it fails (e.g., OBS is closed or buffer isn't active)
    notify-send -a "OBS Studio" -i dialog-error -t 4000 -u critical "Replay Failed" "Could not save replay. Is OBS running and the buffer active?"
fi
