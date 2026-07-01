#!/usr/bin/env bash
###############################################################################
# Bring the FrED WiFi hotspot DOWN and restore the Pi's normal networking.
###############################################################################
set -e
SSID="FrED_AP"
nmcli connection down "$SSID" || true
echo "Hotspot '$SSID' is DOWN. Pi is back to normal networking."
