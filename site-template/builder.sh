#!/bin/sh
# ------------------------------------------------------------------------------
# WP-HOSTING BUILDER SCRIPT
# Handles Tailwind & Lucide Assets
# ------------------------------------------------------------------------------

# 1. Harvest per-page configs
if [ -f "/var/www/html/config-harvester.js" ]; then
    echo "🔍 Harvesting per-page Tailwind configs..."
    node /var/www/html/config-harvester.js || echo "❌ Harvester failed."
else
    echo "⏭️ Skipping harvest (config-harvester.js not found in /var/www/html/)."
fi

# 2. Copy Lucide Assets (if available in shared volume)
if [ -f /shared/node_modules/lucide/dist/lucide-sprite.svg ] && [ ! -f /var/www/html/lucide-sprite.svg ]; then
    cp /shared/node_modules/lucide/dist/lucide-sprite.svg /var/www/html/
    echo "✅ Lucide sprite copied."
fi

if [ -f /shared/node_modules/lucide/dist/umd/lucide.min.js ] && [ ! -f /var/www/html/lucide.min.js ]; then
    cp /shared/node_modules/lucide/dist/umd/lucide.min.js /var/www/html/
    echo "✅ Lucide JS copied."
fi

# 3. Start Tailwind Watcher (Direct Path - No Internet!)
TAILWIND_BIN="/shared/node_modules/.bin/tailwindcss"
if [ -f "/var/www/html/input.css" ]; then
    if [ -f "$TAILWIND_BIN" ]; then
        echo "🚀 Starting Tailwind watcher (Offline Mode)..."
        "$TAILWIND_BIN" -i /var/www/html/input.css -o /var/www/html/output.css --watch --poll
    else
        echo "❌ ERROR: tailwindcss binary not found at $TAILWIND_BIN"
        echo "Please run Opt 10 or check shared_deps container."
        tail -f /dev/null
    fi
else
    echo "⚠️ No input.css found in /var/www/html/. Create one to start Tailwind compilation."
    echo "Waiting for assets..."
    tail -f /dev/null
fi
