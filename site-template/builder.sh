#!/bin/sh
# ------------------------------------------------------------------------------
# WP-HOSTING BUILDER SCRIPT (ALL THEMES MODE)
# ------------------------------------------------------------------------------

# 1. Harvest per-page configs
if [ -f "/var/www/html/config-harvester.js" ]; then
    echo "🔍 Harvesting per-page Tailwind configs..."
    node /var/www/html/config-harvester.js || echo "❌ Harvester failed."
fi

# 2. Setup Master Output and Symlinks for All Themes
MASTER_OUT="/var/www/html/wp-content/tailwind-all.css"
touch "$MASTER_OUT"
chmod 777 "$MASTER_OUT"

echo "🔗 Linking master CSS to all themes..."
for theme in /var/www/html/wp-content/themes/*; do
    if [ -d "$theme" ]; then
        # Create a symlink named output.css in every theme folder
        ln -sf "$MASTER_OUT" "$theme/output.css"
        echo "   -> Linked to $(basename "$theme")"
    fi
done

# 3. Search for Tailwind CLI
TAILWIND_CLI=""
if [ -f "/shared/node_modules/.bin/tailwindcss" ]; then
    TAILWIND_CLI="/shared/node_modules/.bin/tailwindcss"
elif [ -f "/shared/node_modules/tailwindcss/lib/cli.js" ]; then
    TAILWIND_CLI="/shared/node_modules/tailwindcss/lib/cli.js"
elif [ -f "/shared/node_modules/tailwindcss/bin/tailwindcss" ]; then
    TAILWIND_CLI="/shared/node_modules/tailwindcss/bin/tailwindcss"
fi

# 4. Starting the Watcher
if [ -f "/var/www/html/input.css" ]; then
    if [ -n "$TAILWIND_CLI" ]; then
        echo "🚀 Starting Tailwind watcher (Global Mode)..."
        echo "   Master Output: $MASTER_OUT"
        
        # Use node if it's a JS file, otherwise run directly
        case "$TAILWIND_CLI" in
            *.js) node "$TAILWIND_CLI" -i /var/www/html/input.css -o "$MASTER_OUT" --watch --poll ;;
            *) "$TAILWIND_CLI" -i /var/www/html/input.css -o "$MASTER_OUT" --watch --poll ;;
        esac
    else
        echo "❌ ERROR: tailwind cli not found in /shared/node_modules"
        tail -f /dev/null
    fi
else
    echo "⚠️ No input.css found in /var/www/html/. Please create one."
    tail -f /dev/null
fi
