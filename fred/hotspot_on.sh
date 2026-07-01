#!/usr/bin/env bash
###############################################################################
# Bring the FrED WiFi hotspot UP (on demand).
# The Pi becomes an access point at 10.42.0.1 and serves DHCP to your laptop.
# NOTE: while the hotspot is up, wlan0 is the AP, so the Pi's normal WiFi
# internet is paused. Run ./hotspot_off.sh to restore it.
###############################################################################
set -e
SSID="FrED_AP"
nmcli connection up "$SSID"
echo "Hotspot '$SSID' is UP."
echo "  Pi address : 10.42.0.1"
echo "  Next       : ./run_experiments.sh"
