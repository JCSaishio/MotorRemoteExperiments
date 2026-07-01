#!/usr/bin/env bash
###############################################################################
# Start the FrED experiment listener.
#
# Runs with the SAME system Python that runs your validated motor_control.py,
# so the motor/encoder behave identically. (A venv is intentionally NOT used
# here: the hardware libraries — RPi.GPIO, Blinka, adafruit-mcp3xxx — are the
# system ones already proven to drive the motor.)
#
# Make sure you ran ./hotspot_on.sh first (bash hotspot_on.sh).
# Press Ctrl+C to stop the listener.
###############################################################################
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# Prefer python3; fall back to python. This is the interpreter that already
# runs motor_control.py successfully.
PY="$(command -v python3 || command -v python || true)"
if [ -z "$PY" ]; then
  echo "No python3/python found on PATH." >&2
  exit 1
fi

echo "Starting FrED listener with: $PY"
exec "$PY" "$HERE/server.py"
