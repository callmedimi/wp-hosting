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

# 3. Find Theme Directory (where output.css should live)
THEME_DIR=$(find /var/www/html/wp-content/themes -maxdepth 1 -mindepth 1 -type d | head -n 1)
if [ -z "$THEME_DIR" ]; then
    echo "⚠️ No theme found in wp-content/themes. Falling back to site root."
    OUTPUT_PATH="/var/www/html/output.css"
else
    OUTPUT_PATH="$THEME_DIR/output.css"
fi

# 4. Start Tailwind Watcher (Offline Mode)
# Use the direct JS file to avoid issues with missing symlinks in .bin
TAILWIND_CLI="/shared/node_modules/tailwindcss/lib/cli.js"

if [ -f "/var/www/html/input.css" ]; then
    if [ -f "$TAILWIND_CLI" ]; then
        echo "🚀 Starting Tailwind watcher (Offline Mode)..."
        echo "   Target: $OUTPUT_PATH"
        # Run using node directly
        node "$TAILWIND_CLI" -i /var/www/html/input.css -o "$OUTPUT_PATH" --watch --poll
    else
        echo "❌ ERROR: tailwind cli not found at $TAILWIND_CLI"
        echo "Please ensure you sideloaded node_modules to /shared/node_modules"
        tail -f /dev/null
    fi
else
    echo "⚠️ No input.css found. Create one to start Tailwind compilation."
    tail -f /dev/null
fi
