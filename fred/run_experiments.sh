#!/usr/bin/env bash
###############################################################################
# Start the FrED experiment listener in the foreground.
# It waits for your laptop app to connect, runs the experiments, sends the
# data back, then waits for the next job. Press Ctrl+C to stop it completely.
#
# Make sure ./hotspot_on.sh has been run first.
###############################################################################
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

if [ ! -d "$HERE/.venv" ]; then
  echo "No .venv found - run ./install.sh first."
  exit 1
fi

exec "$HERE/.venv/bin/python" "$HERE/server.py"
