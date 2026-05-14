#!/usr/bin/env bash
# This script is used as a template and local fallback for kiosk startup logic.
# The installers overwrite it with the resolved Pi user's home directory and
# chosen Chromium binary before wiring it into systemd.

set -euo pipefail

echo "Run ./setup.sh or ./setup-precomf.sh to install the kiosk launcher with Pi-specific settings."
exit 1
