#!/usr/bin/env bash
###############################################################################
# FrED one-time installer (Raspberry Pi 4, Debian 12 Bookworm)
#
# Run this ONCE, while the Pi still has its normal internet connection
# (before you ever bring the hotspot up):
#
#     cd fred
#     chmod +x *.sh
#     ./install.sh
#
# It:
#   1) creates a Python virtual environment (.venv) that inherits the
#      system hardware packages already used by motor_control.py,
#   2) installs fred/requirements.txt into it,
#   3) creates the WiFi hotspot connection profile (autoconnect OFF, so it
#      never comes up on its own and never disturbs the Pi's normal use).
###############################################################################
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# ---- hotspot settings (change if you like) ----
SSID="FrED_AP"
PASS="fred12345"
IFACE="wlan0"

echo "=== [1/3] Checking for FrED_functions.py ==="
if [ ! -f "$HERE/FrED_functions.py" ]; then
  echo "  WARNING: FrED_functions.py is not in this folder."
  echo "  Copy it here from your existing FrED motor project, e.g.:"
  echo "      cp /path/to/your/project/FrED_functions.py \"$HERE/\""
  echo "  (experiment_runner.py imports it at runtime.)"
else
  echo "  Found FrED_functions.py"
fi

echo "=== [2/3] Creating virtual environment (.venv) ==="
if [ ! -d "$HERE/.venv" ]; then
  python3 -m venv --system-site-packages "$HERE/.venv"
fi
"$HERE/.venv/bin/pip" install --upgrade pip
"$HERE/.venv/bin/pip" install -r "$HERE/requirements.txt"
echo "  venv ready at $HERE/.venv"

echo "=== [3/3] Creating hotspot profile '$SSID' (autoconnect OFF) ==="
if nmcli -g NAME connection show | grep -qx "$SSID"; then
  echo "  Profile '$SSID' already exists - leaving it as is."
else
  nmcli connection add type wifi ifname "$IFACE" con-name "$SSID" \
        autoconnect no ssid "$SSID"
  nmcli connection modify "$SSID" \
        802-11-wireless.mode ap \
        802-11-wireless.band bg \
        ipv4.method shared
  nmcli connection modify "$SSID" \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "$PASS"
  echo "  Created. SSID='$SSID'  password='$PASS'"
fi

echo
echo "Install complete."
echo "  Start experiments : ./hotspot_on.sh   then   ./run_experiments.sh"
echo "  When finished     : Ctrl+C the listener, then ./hotspot_off.sh"
