#!/bin/bash
#
# setup_hotspot.sh — turn this Raspberry Pi into a self-contained WiFi hotspot
# (access point) so the laptop can connect and run motor experiments, with no
# router or university network.
#
# Uses NetworkManager (nmcli), the default on Raspberry Pi OS Bookworm. The
# hotspot has a FIXED address (192.168.4.1) and runs a small DHCP server for the
# laptop. The profile is created with autoconnect OFF, so it only comes up when
# you ask — the Pi stays free for its other uses the rest of the time.
#
#   SSID:      FrED_AP
#   Password:  fred12345
#   Pi IP:     192.168.4.1   (the laptop connects to this, port 5001)
#
# Usage (run on the Pi):
#     bash setup_hotspot.sh          # create + start the hotspot
#     bash setup_hotspot.sh down     # stop the hotspot (restore normal WiFi)
#     bash setup_hotspot.sh status   # show the hotspot state and Pi IPs
#
# NOTE: while the Pi is a hotspot, its built-in WiFi is the access point and is
# NOT connected to the internet. That is expected and makes the link reliable.

set -euo pipefail

# --- These MUST match DEFAULT_HOST/DEFAULT_PORT in laptop/comm_client.py ----- #
SSID="FrED_AP"
PASSWORD="fred12345"
CON_NAME="FrED_AP"
IFACE="wlan0"
PI_IP="192.168.4.1"
PORT="5001"
# --------------------------------------------------------------------------- #

ACTION="${1:-up}"

if ! command -v nmcli >/dev/null 2>&1; then
  cat <<'MSG'
ERROR: nmcli (NetworkManager) was not found.

This script needs NetworkManager, the default on Raspberry Pi OS Bookworm.
On an older Raspberry Pi OS, enable it:  sudo raspi-config -> Advanced Options
-> Network Config -> NetworkManager, then reboot and re-run this script.
MSG
  exit 1
fi

show_status() {
  printf "\n--- Hotspot status ---\n"
  nmcli -t -f NAME,TYPE,DEVICE connection show --active | grep -i wifi || true
  printf "\nThis Pi's IP address(es):\n"
  hostname -I || true
  printf "\nLaptop should connect to:  %s   (port %s)\n\n" "$PI_IP" "$PORT"
}

case "$ACTION" in
  down|stop)
    printf "Stopping hotspot '%s'...\n" "$CON_NAME"
    sudo nmcli connection down "$CON_NAME" 2>/dev/null || true
    printf "Hotspot stopped. NetworkManager will reconnect to your normal WiFi.\n"
    exit 0
    ;;
  status)
    show_status
    exit 0
    ;;
  up|start|"")
    : # fall through
    ;;
  *)
    printf "Unknown option '%s'. Use: up | down | status\n" "$ACTION"
    exit 1
    ;;
esac

printf "\n=== Configuring FrED experiments WiFi hotspot ===\n"
printf "SSID: %s    Password: %s    Pi IP: %s\n\n" "$SSID" "$PASSWORD" "$PI_IP"

# Create the connection profile if it does not already exist (autoconnect OFF).
if ! nmcli -t -f NAME connection show | grep -qx "$CON_NAME"; then
  printf "Creating connection profile '%s'...\n" "$CON_NAME"
  sudo nmcli connection add type wifi ifname "$IFACE" con-name "$CON_NAME" \
    autoconnect no ssid "$SSID"
fi

# (Re)apply the access-point settings every run so it stays consistent.
sudo nmcli connection modify "$CON_NAME" \
  802-11-wireless.mode ap \
  802-11-wireless.band bg \
  ipv4.method shared \
  ipv4.addresses "${PI_IP}/24" \
  wifi-sec.key-mgmt wpa-psk \
  wifi-sec.psk "$PASSWORD"

printf "Starting hotspot...\n"
sudo nmcli connection up "$CON_NAME"

show_status

printf "Hotspot is up. On the laptop:\n"
printf "  1) Connect to WiFi '%s' (password '%s').\n" "$SSID" "$PASSWORD"
printf "  2) Run the app:  python app.py  (host %s, port %s).\n" "$PI_IP" "$PORT"
printf "\nTo stop the hotspot later:  bash setup_hotspot.sh down\n\n"
