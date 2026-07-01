#!/bin/bash
#
# start_experiments.sh — start the FrED experiment listener inside fred-venv.
#
# Usage (from inside this folder):
#     bash start_experiments.sh
#
# It activates fred-venv (created by setup_install.sh) and runs server.py, which
# waits for the laptop app, runs the experiments on the motor, and sends the
# data back. Press Ctrl+C to stop. Make sure the hotspot is up first:
#     bash setup_hotspot.sh

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"
VENV_DIR="$PROJECT_DIR/fred-venv"

if [ ! -d "$VENV_DIR" ]; then
  printf "\nERROR: fred-venv not found.\n"
  printf "Run the installer first:  bash setup_install.sh\n\n"
  exit 1
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

printf "\nStarting FrED experiment listener (server.py)...\n"
python server.py
