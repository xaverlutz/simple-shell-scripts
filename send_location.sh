#!/bin/zsh

# Script to get city coordinates and send location to iOS Simulator
# Usage: ./send_location.sh "City Name" [device_id]
# Example: ./send_location.sh "New York"
# Example: ./send_location.sh "Paris" "iPhone 15 Pro"

set -e

# Check if city name is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 \"City Name\" [device_id]"
    echo "Example: $0 \"New York\""
    echo "Example: $0 \"Paris\" \"iPhone 15 Pro\""
    exit 1
fi

CITY_NAME="$1"
DEVICE_ID="$2"

# Function to get coordinates from OpenStreetMap Nominatim API
get_coordinates() {
    local city="$1"
    local encoded_city=$(echo "$city" | sed 's/ /%20/g')
    local url="https://nominatim.openstreetmap.org/search?q=${encoded_city}&format=json&limit=1"

    echo "🔍 Looking up coordinates for: $city" >&2

    local response=$(curl -s "$url")

    if [ -z "$response" ] || [ "$response" = "[]" ]; then
        echo "❌ Error: City '$city' not found" >&2
        exit 1
    fi

    # Parse JSON response using python (available on macOS by default)
    local coordinates=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if len(data) > 0:
        print(f\"{data[0]['lat']},{data[0]['lon']}\")
    else:
        print('')
except:
    print('')
")

    if [ -z "$coordinates" ]; then
        echo "❌ Error: Could not extract coordinates from response" >&2
        exit 1
    fi

    local lat=$(echo "$coordinates" | cut -d',' -f1)
    local lon=$(echo "$coordinates" | cut -d',' -f2)

    echo "📍 Found coordinates: $lat, $lon" >&2
    echo "$coordinates"
}

# Function to get the default booted simulator if no device specified
get_booted_simulator() {
    local booted_device=$(xcrun simctl list devices | grep "Booted" | head -1 | sed -n 's/.*(\([^)]*\)).*/\1/p')

    if [ -z "$booted_device" ]; then
        echo "❌ Error: No booted simulator found. Please boot a simulator first."
        exit 1
    fi

    echo "$booted_device"
}

# Function to send location to simulator
send_location_to_simulator() {
    local coordinates="$1"
    local device="$2"
    local lat=$(echo "$coordinates" | cut -d',' -f1)
    local lon=$(echo "$coordinates" | cut -d',' -f2)

    echo "📱 Sending location to simulator: $device"

    if [ -n "$device" ]; then
        # Try to find device by name first
        local device_uuid=$(xcrun simctl list devices | grep "$device" | grep "Booted" | sed -n 's/.*(\([^)]*\)).*/\1/p' | head -1)

        if [ -z "$device_uuid" ]; then
            # If not found by name, assume it's a UUID
            device_uuid="$device"
        fi

        xcrun simctl location "$device_uuid" set "$lat","$lon"
    else
        # Use booted simulator
        local booted_uuid=$(get_booted_simulator)
        xcrun simctl location "$booted_uuid" set "$lat","$lon"
    fi

    echo "✅ Location set successfully: $lat, $lon"
}

# Main execution
main() {
    echo "🌍 City Location to iOS Simulator"
    echo "================================"

    # Get coordinates first
    local coordinates=$(get_coordinates "$CITY_NAME")

    # Send to simulator
    send_location_to_simulator "$coordinates" "$DEVICE_ID"

    echo "🎉 Done! The simulator should now show the location of $CITY_NAME"
}

# Run main function
main