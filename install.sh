#!/usr/bin/env bash
# Install clipboard-image-paste into Hammerspoon
#
# Usage:
#   ./install.sh
#
# This script will:
#   1. Check that Hammerspoon is installed (if not, print an install hint and exit)
#   2. Append the contents of clipboard-image-paste.lua to ~/.hammerspoon/init.lua
#      (if that file already exists, it's backed up first as init.lua.bak.<timestamp>)
#   3. Restart Hammerspoon to load the new config
#
# Note: this script only touches your local ~/.hammerspoon/init.lua.
# It does not modify any other config or system settings, and it does not
# attempt to bypass or auto-click any system permission dialogs — you still
# need to manually approve Accessibility access in the System Settings
# window that will pop up.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNIPPET="$SCRIPT_DIR/clipboard-image-paste.lua"
HAMMERSPOON_DIR="$HOME/.hammerspoon"
INIT_LUA="$HAMMERSPOON_DIR/init.lua"

if ! [ -d "/Applications/Hammerspoon.app" ]; then
    echo "❌ Hammerspoon.app not found. Install it first:"
    echo "   brew install --cask hammerspoon"
    exit 1
fi

mkdir -p "$HAMMERSPOON_DIR"

if [ -f "$INIT_LUA" ]; then
    backup="$INIT_LUA.bak.$(date +%Y%m%d%H%M%S)"
    cp "$INIT_LUA" "$backup"
    echo "📦 Backed up existing config to: $backup"
fi

{
    echo ""
    echo "-- ===== clipboard-image-paste (installed $(date)) ====="
    cat "$SNIPPET"
} >> "$INIT_LUA"

echo "✅ Written to $INIT_LUA"
echo ""
echo "⚙️  Defaults to iTerm2 only. If you use a different terminal,"
echo "   edit the TARGET_APP variable in $INIT_LUA."
echo ""

osascript -e 'quit app "Hammerspoon"' >/dev/null 2>&1 || true
sleep 1
open -a Hammerspoon
echo "🔨 Hammerspoon restarted."
echo "   On first run, a system Accessibility permission dialog will appear —"
echo "   check the box for Hammerspoon to enable it."
