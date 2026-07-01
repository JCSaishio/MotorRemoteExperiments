#!/usr/bin/env bash
###############################################################################
# FrED one-time installer (Raspberry Pi 4, Debian 12 Bookworm) - plug & play.
#
# Run ONCE, while the Pi still has internet (before ./hotspot_on.sh):
#
#     cd fred
#     bash install.sh
#
# It:
#   1) checks FrED_functions.py is present,
#   2) enables the SPI interface (needed for the encoder + MCP3008),
#   3) installs all required Python libraries for the SYSTEM python3 (the same
#      interpreter that runs motor_control.py and that run_experiments.sh uses),
#   4) creates the WiFi hotspot profile (autoconnect OFF, so it never comes up
#      on its own and never disturbs the Pi's normal use).
###############################################################################
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# ---- hotspot settings (change if you like) ----
SSID="FrED_AP"
PASS="fred12345"
IFACE="wlan0"

PY="$(command -v python3 || command -v python)"
echo "Using interpreter: $PY"

echo "=== [1/4] Checking for FrED_functions.py ==="
if [ ! -f "$HERE/FrED_functions.py" ]; then
  echo "  WARNING: FrED_functions.py is not in this folder. Copy it from your"
  echo "  existing FrED project:  cp /path/to/FrED_functions.py \"$HERE/\""
else
  echo "  Found FrED_functions.py"
fi

echo "=== [2/4] Enabling SPI interface ==="
if command -v raspi-config >/dev/null 2>&1; then
  sudo raspi-config nonint do_spi 0 && echo "  SPI enabled." || echo "  Could not toggle SPI (enable it manually via raspi-config if needed)."
else
  echo "  raspi-config not found; skipping (enable SPI manually if the encoder fails)."
fi

echo "=== [3/4] Installing Python libraries for $PY ==="
# These provide the modules used by experiment_runner.py / FrED_functions.py:
#   board/busio/digitalio -> Adafruit-Blinka
#   adafruit_mcp3xxx       -> adafruit-circuitpython-mcp3xxx
#   RPi.GPIO, spidev, numpy
PKGS="Adafruit-Blinka adafruit-circuitpython-mcp3xxx RPi.GPIO spidev numpy"
# Bookworm marks the system env "externally managed"; try the flags that work,
# in order, so a fresh Pi installs cleanly and an existing one just updates.
if   "$PY" -m pip install --upgrade --break-system-packages $PKGS 2>/dev/null; then
  echo "  Installed (system, --break-system-packages)."
elif "$PY" -m pip install --upgrade --user $PKGS 2>/dev/null; then
  echo "  Installed (user site)."
elif "$PY" -m pip install --upgrade $PKGS; then
  echo "  Installed."
else
  echo "  WARNING: pip install failed. If motor_control.py already runs, the"
  echo "  libraries are present and you can ignore this."
fi

echo "=== [4/4] Creating hotspot profile '$SSID' (autoconnect OFF) ==="
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
echo "  Start experiments : bash hotspot_on.sh   then   bash run_experiments.sh"
echo "  When finished     : Ctrl+C the listener, then bash hotspot_off.sh"
