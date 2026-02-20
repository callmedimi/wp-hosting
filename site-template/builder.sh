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
# Smarter search for Tailwind CLI
TAILWIND_CLI=""
POSSIBLE_PATHS=(
    "/shared/node_modules/.bin/tailwindcss"
    "/shared/node_modules/tailwindcss/lib/cli.js"
    "/shared/node_modules/tailwindcss/bin/tailwindcss"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        TAILWIND_CLI="$path"
        break
    fi
done

if [ -f "/var/www/html/input.css" ]; then
    if [ -n "$TAILWIND_CLI" ]; then
        echo "🚀 Starting Tailwind watcher (Offline Mode)..."
        echo "   CLI found at: $TAILWIND_CLI"
        echo "   Target: $OUTPUT_PATH"
        
        # Check if it's a JS file or binary
        if [[ "$TAILWIND_CLI" == *.js ]]; then
            node "$TAILWIND_CLI" -i /var/www/html/input.css -o "$OUTPUT_PATH" --watch --poll
        else
            "$TAILWIND_CLI" -i /var/www/html/input.css -o "$OUTPUT_PATH" --watch --poll
        fi
    else
        echo "❌ ERROR: tailwind cli not found in shared node_modules."
        echo "Checked: ${POSSIBLE_PATHS[*]}"
        tail -f /dev/null
    fi
else
    echo "⚠️ No input.css found. Create one to start Tailwind compilation."
    tail -f /dev/null
fi
