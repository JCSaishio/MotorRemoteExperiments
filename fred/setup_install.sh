#!/bin/bash
#
# setup_install.sh — one-shot installer for the FrED Motor Remote Experiments
# listener. Target: Raspberry Pi 4 running Raspberry Pi OS Bookworm.
#
# Mirrors the main fred-device installer:
#   1. Installs the system (apt) packages that must NOT come from pip on the Pi
#      — most importantly RPi.GPIO (python3-rpi.gpio) and the BLAS runtime numpy
#      links against. Pip-installing RPi.GPIO into a venv shadows the working
#      apt build and can stop the motor from being driven.
#   2. Creates a virtual environment  fred-venv  in this folder, built WITH
#      --system-site-packages so the apt RPi.GPIO is visible inside it.
#   3. Installs the remaining pure-Python / wheel packages from requirements.txt
#      INTO that venv (numpy, adafruit-blinka, adafruit-circuitpython-mcp3xxx,
#      spidev).
#   4. Enables the SPI interface (encoder + MCP3008 ADC).
#   5. Verifies that every library the program imports can actually be imported.
#
# Run it from inside this folder (with internet, hotspot OFF):
#     bash setup_install.sh
#
# Afterwards start the listener with:
#     bash start_experiments.sh
#   (or:  source fred-venv/bin/activate && python server.py )

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"
VENV_DIR="$PROJECT_DIR/fred-venv"

printf "\n=== FrED Motor Remote Experiments - Raspberry Pi 4 installer ===\n"
printf "Project folder: %s\n" "$PROJECT_DIR"

# ---------------------------------------------------------------------------
# 0. FrED_functions.py present?
# ---------------------------------------------------------------------------
if [ ! -f "$PROJECT_DIR/FrED_functions.py" ]; then
  printf "\nWARNING: FrED_functions.py is not in this folder. Copy it from your\n"
  printf "existing FrED project:  cp /path/to/FrED_functions.py \"%s/\"\n" "$PROJECT_DIR"
fi

# ---------------------------------------------------------------------------
# 1. System packages (apt)
# ---------------------------------------------------------------------------
printf "\n[1/5] Installing system packages with apt (sudo may prompt for your password)...\n"
sudo apt-get update
sudo apt-get install -y \
  python3-venv \
  python3-pip \
  python3-dev \
  python3-rpi.gpio \
  libatlas-base-dev

# python3-venv .............. lets us create the virtual environment
# python3-pip/dev ........... pip + headers for building any small wheels
# python3-rpi.gpio .......... GPIO access, prebuilt (do NOT pip-install this)
# libatlas-base-dev ......... BLAS runtime numpy links against

# ---------------------------------------------------------------------------
# 2. Virtual environment (fred-venv) that can see the apt RPi.GPIO
# ---------------------------------------------------------------------------
if [ ! -d "$VENV_DIR" ]; then
  printf "\n[2/5] Creating virtual environment 'fred-venv' (with system site packages)...\n"
  python3 -m venv --system-site-packages "$VENV_DIR"
else
  printf "\n[2/5] Virtual environment 'fred-venv' already exists - reusing it.\n"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

# ---------------------------------------------------------------------------
# 3. Python packages (pip) into the venv
# ---------------------------------------------------------------------------
printf "\n[3/5] Installing Python packages into fred-venv...\n"
python -m pip install --upgrade pip wheel
python -m pip install -r "$PROJECT_DIR/requirements.txt"

# ---------------------------------------------------------------------------
# 4. Enable SPI (encoder + MCP3008)
# ---------------------------------------------------------------------------
printf "\n[4/5] Enabling SPI interface...\n"
if command -v raspi-config >/dev/null 2>&1; then
  sudo raspi-config nonint do_spi 0 && printf "  SPI enabled.\n" \
    || printf "  Could not toggle SPI automatically; enable it via raspi-config if the encoder fails.\n"
else
  printf "  raspi-config not found; enable SPI manually if the encoder fails.\n"
fi

# ---------------------------------------------------------------------------
# 5. Verify every import the program uses actually works
# ---------------------------------------------------------------------------
printf "\n[5/5] Verifying imports...\n"
python - <<'PYCHECK'
import importlib, sys

checks = [
    ("numpy",                    "numpy"),
    ("socket",                   "socket (WiFi link, stdlib)"),
    ("RPi.GPIO",                 "RPi.GPIO (from apt)"),
    ("spidev",                   "spidev"),
    ("board",                    "Adafruit Blinka (board)"),
    ("busio",                    "Adafruit Blinka (busio)"),
    ("digitalio",                "Adafruit Blinka (digitalio)"),
    ("adafruit_mcp3xxx.mcp3008", "Adafruit MCP3xxx"),
]

failed = []
for module, label in checks:
    try:
        importlib.import_module(module)
        print(f"  OK   {label}")
    except Exception as exc:
        print(f"  FAIL {label}  ->  {exc}")
        failed.append(label)

if failed:
    print("\nSome libraries failed to import: " + ", ".join(failed))
    sys.exit(1)
print("\nAll required libraries import successfully.")
PYCHECK

printf "\n=== Done. ===\n"
printf "To run experiments:\n"
printf "    bash setup_hotspot.sh          # open the hotspot\n"
printf "    bash start_experiments.sh      # start the listener (Ctrl+C to stop)\n"
printf "    bash setup_hotspot.sh down     # close the hotspot when finished\n\n"
