#!/bin/zsh
set -eu
cd "${0:A:h:h}"
if (( $# < 1 || $# > 3 )); then
    print -u2 'Usage: Scripts/profile-headset.sh DEVICE_UDID [duration, default 30m] [output.trace]'
    exit 2
fi
headsetID=$1
traceDuration=${2:-30m}
traceOutput=${3:-build/Profiles/iris-$(date +%Y%m%d-%H%M%S).trace}
mkdir -p "${traceOutput:h}"
# Include WebContent/GPU processes: much of a browser's cost is outside its app process.
# Use default sampling settings so the profile itself adds less overhead.
xcrun xctrace record \
    --device "$headsetID" \
    --template 'RealityKit Trace' \
    --instrument 'Time Profiler' \
    --instrument 'Activity Monitor' \
    --instrument 'Thermal State' \
    --all-processes \
    --time-limit "$traceDuration" \
    --output "$traceOutput"
